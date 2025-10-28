<?php
namespace FIRS;

class Router {
    private $config;
    private $routes = [];
    private $responseBuilder;

    public function __construct($config) {
        $this->config = $config;
        $this->responseBuilder = new ResponseBuilder($config);
        $this->registerRoutes();
    }

    private function registerRoutes(): void {
        $prefix = $this->config['api']['prefix'];
        $this->post("{$prefix}/invoice/validate-irn", 'validateIRN');
        $this->post("{$prefix}/invoice/validate", 'validateInvoice');
        $this->post("{$prefix}/invoice/sign", 'signInvoice');
        $this->get("{$prefix}/invoice/download/{irn}", 'downloadFile');
        $this->get("{$prefix}/invoice/confirm", 'confirmStatus');
        $this->post("{$prefix}/invoice/update", 'updateInvoice');
        $this->get("{$prefix}/invoice/search", 'searchInvoices');
        $this->get("{$prefix}/invoice/hsn-codes", 'getHSNCodes');
        $this->get("{$prefix}/invoice/new-request", 'getInvoiceTemplate');
        $this->get("{$prefix}/system/health", 'healthCheck');
        $this->get('/api/transmitting/health', 'healthCheck');
    }

    private function get(string $path, string $handler): void {
        $this->routes['GET'][$path] = $handler;
    }

    private function post(string $path, string $handler): void {
        $this->routes['POST'][$path] = $handler;
    }

    public function dispatch(): void {
        if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
            $this->responseBuilder->handleOptions();
        }
        $method = $_SERVER['REQUEST_METHOD'];
        $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
        $handler = $this->findRoute($method, $path);
        if (!$handler) {
            $this->responseBuilder->notFound('Endpoint', $path);
        }
        call_user_func([$this, $handler['method']], $handler['params']);
    }

    private function findRoute(string $method, string $path): ?array {
        if (!isset($this->routes[$method])) {
            return null;
        }
        foreach ($this->routes[$method] as $route => $handler) {
            $params = $this->matchRoute($route, $path);
            if ($params !== false) {
                return ['method' => $handler, 'params' => $params];
            }
        }
        return null;
    }

    private function matchRoute(string $route, string $path): bool|array {
        $pattern = preg_replace('/\{([a-zA-Z0-9_]+)\}/', '([^/]+)', $route);
        $pattern = '#^' . $pattern . '$#';
        if (preg_match($pattern, $path, $matches)) {
            array_shift($matches);
            preg_match_all('/\{([a-zA-Z0-9_]+)\}/', $route, $paramNames);
            $params = [];
            foreach ($paramNames[1] as $index => $name) {
                $params[$name] = $matches[$index] ?? null;
            }
            return $params;
        }
        return false;
    }

    protected function getJsonBody(): ?array {
        $input = file_get_contents('php://input');
        if (empty($input)) {
            return null;
        }
        $data = json_decode($input, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            $this->responseBuilder->error('Invalid JSON in request body', 'INVALID_JSON', null, 400);
        }
        return $data;
    }

    protected function getQuery(string $key, $default = null) {
        return $_GET[$key] ?? $default;
    }

    protected function validateIRN(array $params): void {
        require_once __DIR__ . '/Validator.php';
        $body = $this->getJsonBody();
        $validator = new Validator($this->config);
        $result = $validator->validateIRNQuick($body);
        if ($result['valid']) {
            $this->responseBuilder->success($result, 'IRN validation successful');
        } else {
            $this->responseBuilder->validationError($result['errors'], 'IRN validation failed');
        }
    }

    protected function validateInvoice(array $params): void {
        require_once __DIR__ . '/Validator.php';
        $body = $this->getJsonBody();
        $validator = new Validator($this->config);
        $result = $validator->validateFull($body);
        if ($result['valid']) {
            $message = !empty($result['warnings']) ? 'Validation passed with warnings' : 'Validation successful';
            $this->responseBuilder->success($result, $message);
        } else {
            $this->responseBuilder->validationError($result['errors'], 'Validation failed');
        }
    }

    protected function signInvoice(array $params): void {
        $startTime = microtime(true);
        $timings = [];

        require_once __DIR__ . '/Validator.php';
        require_once __DIR__ . '/IRNProcessor.php';
        require_once __DIR__ . '/CryptoService.php';
        require_once __DIR__ . '/QRGenerator.php';
        require_once __DIR__ . '/FileManager.php';
        require_once __DIR__ . '/InvoiceManager.php';
        require_once __DIR__ . '/FIRSAPIClient.php';
        require_once __DIR__ . '/LogManager.php';
        $body = $this->getJsonBody();

        $stepStart = microtime(true);
        $validator = new Validator($this->config);
        $validation = $validator->validateFull($body);
        if (!$validation['valid']) {
            $this->responseBuilder->validationError($validation['errors'], 'Validation failed');
        }
        $timings['validation'] = round((microtime(true) - $stepStart) * 1000, 2);

        try {
            $stepStart = microtime(true);
            $irnProcessor = new IRNProcessor($this->config);
            $irn = $irnProcessor->extractIRN($body);
            $signedIRN = $irnProcessor->formatSignedIRN($irn);
            $timings['irn_processing'] = round((microtime(true) - $stepStart) * 1000, 2);

            $stepStart = microtime(true);
            $invoiceManager = new InvoiceManager($this->config);
            if ($invoiceManager->isDuplicate($irn)) {
                $this->responseBuilder->error('Invoice with this IRN already exists', 'DUPLICATE_IRN', null, 409);
            }
            $timings['duplicate_check'] = round((microtime(true) - $stepStart) * 1000, 2);

            $fileManager = new FileManager($this->config);

            // Save JSON with signedIRN (includes timestamp) as filename
            $stepStart = microtime(true);
            $jsonFile = $fileManager->saveInvoiceJSON($signedIRN, $body);
            $timings['save_json'] = round((microtime(true) - $stepStart) * 1000, 2);

            $savedInvoiceData = json_decode(file_get_contents($jsonFile), true);

            $stepStart = microtime(true);
            $crypto = new CryptoService($this->config);
            $encryptedData = $crypto->encryptIRN($irn, $signedIRN);
            $timings['encryption'] = round((microtime(true) - $stepStart) * 1000, 2);

            // Save Base64 encrypted data with signedIRN as filename
            $stepStart = microtime(true);
            $encryptedFile = $fileManager->saveEncryptedData($irn, $signedIRN, $encryptedData, $savedInvoiceData);
            $timings['save_base64'] = round((microtime(true) - $stepStart) * 1000, 2);

            $base64DataFromFile = file_get_contents($encryptedFile);

            $stepStart = microtime(true);
            $qrGenerator = new QRGenerator($this->config);
            // Generate QR with signedIRN as filename
            $qrFile = $qrGenerator->generate($base64DataFromFile, $signedIRN);
            $timings['qr_generation'] = round((microtime(true) - $stepStart) * 1000, 2);

            $stepStart = microtime(true);
            $invoiceManager->createInvoiceRecord($irn, $signedIRN, $body, $encryptedFile, $qrFile);
            $timings['save_record'] = round((microtime(true) - $stepStart) * 1000, 2);

            // Initialize LogManager for API response logging
            $logManager = new LogManager($this->config);

            $firsResponse = null;
            if ($this->config['firs_api']['enabled']) {
                $stepStart = microtime(true);
                $firsClient = new FIRSAPIClient($this->config);
                
                try {
                    $firsResponse = $firsClient->submitInvoice($body);
                    $timings['firs_api'] = round((microtime(true) - $stepStart) * 1000, 2);
                    
                    $totalTime = round((microtime(true) - $startTime) * 1000, 2);
                    
                    // Log success to api_success.log with detailed information
                    $logManager->logSuccess(
                        $irn, 
                        $signedIRN, 
                        [
                            'json' => $jsonFile,
                            'encrypted' => $encryptedFile,
                            'qr_code' => $qrFile,
                        ], 
                        $firsResponse,
                        $body, // Invoice data for details
                        [
                            'total_time_ms' => $totalTime,
                            'breakdown' => $timings,
                        ]
                    );
                    
                    error_log(sprintf('[FIRS API SUCCESS] Invoice %s submitted successfully', $irn));
                } catch (\Exception $apiException) {
                    $timings['firs_api'] = round((microtime(true) - $stepStart) * 1000, 2);
                    
                    // Log error to api_error.log with detailed information
                    $logManager->logException(
                        $irn, 
                        $apiException, 
                        'firs_api_submission',
                        [
                            'endpoint' => '/api/v1/invoice/sign',
                            'http_code' => $apiException->getCode(),
                            'files_created' => [
                                'json' => basename($jsonFile),
                                'encrypted' => basename($encryptedFile),
                                'qr_code' => basename($qrFile),
                            ],
                        ]
                    );
                    
                    error_log(sprintf('[FIRS API ERROR] Invoice %s failed: %s', $irn, $apiException->getMessage()));
                    
                    // Continue processing even if FIRS API fails
                    $firsResponse = [
                        'status' => 'error',
                        'message' => $apiException->getMessage(),
                    ];
                }
            } else {
                // Log local success (FIRS API disabled)
                $totalTime = round((microtime(true) - $startTime) * 1000, 2);
                $logManager->logSuccess(
                    $irn, 
                    $signedIRN, 
                    [
                        'json' => $jsonFile,
                        'encrypted' => $encryptedFile,
                        'qr_code' => $qrFile,
                    ], 
                    ['status' => 'disabled', 'message' => 'FIRS API integration disabled'],
                    $body,
                    [
                        'total_time_ms' => $totalTime,
                        'breakdown' => $timings,
                    ]
                );
            }

            $totalTime = round((microtime(true) - $startTime) * 1000, 2);

            $responseData = [
                'irn' => $irn,
                'irn_signed' => $signedIRN,
                'encrypted_data' => $encryptedData,
                'files' => [
                    'json' => $jsonFile,
                    'encrypted' => $encryptedFile,
                    'qr_code' => $qrFile,
                ],
                'performance' => [
                    'total_time_ms' => $totalTime,
                    'timings' => $timings,
                ],
            ];
            if ($firsResponse && isset($firsResponse['status']) && $firsResponse['status'] !== 'disabled') {
                $responseData['firs_api_response'] = $firsResponse;
            }
            $this->responseBuilder->success($responseData, 'Invoice signed successfully');
        } catch (\Exception $e) {
            // Log processing error
            require_once __DIR__ . '/LogManager.php';
            $logManager = new LogManager($this->config);
            
            // Try to extract IRN from body if available
            $errorIRN = 'unknown';
            try {
                $errorBody = $this->getJsonBody();
                $errorIRN = $errorBody['irn'] ?? 'unknown';
            } catch (\Exception $ex) {
                // Ignore if can't get body
            }
            
            $logManager->logException(
                $errorIRN,
                $e,
                'invoice_processing',
                [
                    'error_stage' => 'general_processing',
                    'error_code' => $e->getCode(),
                ]
            );
            
            $this->responseBuilder->error($e->getMessage(), 'PROCESSING_ERROR', $e->getTrace(), 500);
        }
    }

    protected function downloadFile(array $params): void {
        require_once __DIR__ . '/FileManager.php';
        $irn = $params['irn'] ?? null;
        $type = $this->getQuery('type', 'qr');
        if (!$irn) {
            $this->responseBuilder->error('IRN parameter is required', 'MISSING_PARAMETER', null, 400);
        }
        try {
            $fileManager = new FileManager($this->config);
            $fileManager->downloadFile($irn, $type);
        } catch (\Exception $e) {
            $this->responseBuilder->error($e->getMessage(), 'FILE_NOT_FOUND', null, 404);
        }
    }

    protected function confirmStatus(array $params): void {
        require_once __DIR__ . '/InvoiceManager.php';
        $irn = $this->getQuery('irn');
        $businessId = $this->getQuery('business_id');
        if (!$irn) {
            $this->responseBuilder->error('IRN parameter is required', 'MISSING_PARAMETER', null, 400);
        }
        try {
            $invoiceManager = new InvoiceManager($this->config);
            $status = $invoiceManager->getInvoiceStatus($irn, $businessId);
            $this->responseBuilder->success($status, 'Status retrieved successfully');
        } catch (\Exception $e) {
            $this->responseBuilder->notFound('Invoice', $irn);
        }
    }

    protected function updateInvoice(array $params): void {
        $this->responseBuilder->error('Update endpoint not yet implemented', 'NOT_IMPLEMENTED', null, 501);
    }

    protected function searchInvoices(array $params): void {
        require_once __DIR__ . '/SearchEngine.php';
        $searchEngine = new SearchEngine($this->config);
        $results = $searchEngine->search($_GET);
        $this->responseBuilder->success($results, 'Search completed');
    }

    protected function getHSNCodes(array $params): void {
        require_once __DIR__ . '/HSNCodeProvider.php';
        $provider = new HSNCodeProvider($this->config);
        $results = $provider->search($_GET);
        $this->responseBuilder->success($results, 'HSN codes retrieved');
    }

    protected function getInvoiceTemplate(array $params): void {
        $templateType = $this->getQuery('template_type', 'standard');
        $format = $this->getQuery('format', 'json');
        $template = $this->generateTemplate($templateType);
        $this->responseBuilder->success($template, 'Template generated');
    }

    protected function healthCheck(array $params): void {
        $detailed = $this->getQuery('detailed', 'false') === 'true';
        $health = [
            'status' => 'healthy',
            'timestamp' => date('Y-m-d\TH:i:s\Z'),
            'version' => $this->config['app']['version'],
            'environment' => $this->config['app']['env'],
        ];
        if ($detailed) {
            $health['checks'] = [
                'php_version' => PHP_VERSION,
                'openssl' => extension_loaded('openssl'),
                'gd' => extension_loaded('gd'),
                'json' => extension_loaded('json'),
                'crypto_keys_exists' => file_exists($this->config['paths']['crypto_keys']),
                'storage_writable' => is_writable($this->config['paths']['storage']),
            ];
        }
        $this->responseBuilder->success($health, 'System healthy');
    }

    private function generateTemplate(string $type): array {
        return [
            'irn' => 'TEMPLATE-IRN-' . date('Ymd'),
            'business_id' => '00000000-0000-0000-0000-000000000000',
            'issue_date' => date('Y-m-d'),
            'due_date' => date('Y-m-d', strtotime('+30 days')),
            'invoice_type_code' => '380',
            'document_currency_code' => 'NGN',
            'note' => 'Sample invoice template',
        ];
    }
}
