<?php
namespace FIRS;

/**
 * LogManager - Handles structured logging for API responses
 * Logs success and error details from FIRS API calls
 */
class LogManager {
    private $config;
    private $successLogFile;
    private $errorLogFile;

    public function __construct($config) {
        $this->config = $config;
        $this->successLogFile = $this->config['logging']['api_success_log'];
        $this->errorLogFile = $this->config['logging']['api_error_log'];
        
        // Ensure log directory exists
        $logDir = dirname($this->successLogFile);
        if (!is_dir($logDir)) {
            mkdir($logDir, 0755, true);
        }
    }

    /**
     * Log successful API response
     * 
     * @param string $irn Original IRN
     * @param string $signedIRN Signed IRN with timestamp
     * @param array $files Files created (json, encrypted, qr_code)
     * @param array|null $apiResponse FIRS API response data
     * @param array|null $invoiceData Original invoice data for details
     * @param array|null $timings Performance timings
     * @return void
     */
    public function logSuccess(string $irn, string $signedIRN, array $files, ?array $apiResponse = null, ?array $invoiceData = null, ?array $timings = null): void {
        // Get file sizes
        $fileSizes = [];
        foreach ($files as $type => $path) {
            if (file_exists($path)) {
                $fileSizes[$type] = [
                    'path' => $path,
                    'filename' => basename($path),
                    'size_bytes' => filesize($path),
                    'size_kb' => round(filesize($path) / 1024, 2),
                ];
            }
        }

        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'type' => 'SUCCESS',
            'irn' => $irn,
            'irn_signed' => $signedIRN,
            'invoice_details' => $invoiceData ? [
                'business_id' => $invoiceData['business_id'] ?? 'N/A',
                'issue_date' => $invoiceData['issue_date'] ?? 'N/A',
                'supplier' => $invoiceData['accounting_supplier_party']['party_name'] ?? 'N/A',
                'customer' => $invoiceData['accounting_customer_party']['party_name'] ?? 'N/A',
                'total_amount' => $invoiceData['legal_monetary_total']['payable_amount'] ?? 'N/A',
                'currency' => $invoiceData['document_currency_code'] ?? 'N/A',
                'payment_status' => $invoiceData['payment_status'] ?? 'N/A',
            ] : null,
            'files_created' => $fileSizes,
            'api_response' => $apiResponse ? [
                'status' => $apiResponse['status'] ?? 'N/A',
                'http_code' => $apiResponse['http_code'] ?? 'N/A',
                'data' => $apiResponse['data'] ?? null,
            ] : null,
            'performance' => $timings,
        ];

        $this->writeLog($this->successLogFile, $logEntry);
    }

    /**
     * Log error from API response
     * 
     * @param string $irn Original IRN
     * @param int $httpCode HTTP status code
     * @param string $errorMessage Error message
     * @param array|null $errorDetails Additional error details
     * @param array|null $requestPayload Original request payload (optional)
     * @param string|null $errorType Type of error (validation, api, processing, etc)
     * @return void
     */
    public function logError(string $irn, int $httpCode, string $errorMessage, ?array $errorDetails = null, ?array $requestPayload = null, ?string $errorType = null): void {
        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'type' => 'ERROR',
            'error_type' => $errorType ?? 'unknown',
            'irn' => $irn,
            'http_code' => $httpCode,
            'error_message' => $errorMessage,
            'error_details' => $errorDetails,
            'request_summary' => $requestPayload ? [
                'business_id' => $requestPayload['business_id'] ?? 'N/A',
                'issue_date' => $requestPayload['issue_date'] ?? 'N/A',
                'total_amount' => $requestPayload['legal_monetary_total']['payable_amount'] ?? 'N/A',
                'currency' => $requestPayload['document_currency_code'] ?? 'N/A',
                'supplier' => $requestPayload['accounting_supplier_party']['party_name'] ?? 'N/A',
                'customer' => $requestPayload['accounting_customer_party']['party_name'] ?? 'N/A',
            ] : null,
        ];

        $this->writeLog($this->errorLogFile, $logEntry);
    }

    /**
     * Log exception during processing
     * 
     * @param string $irn Original IRN
     * @param \Exception $exception Exception object
     * @param string $context Context where error occurred
     * @param array|null $additionalContext Additional context data
     * @return void
     */
    public function logException(string $irn, \Exception $exception, string $context = 'processing', ?array $additionalContext = null): void {
        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'type' => 'EXCEPTION',
            'error_type' => 'exception',
            'irn' => $irn,
            'context' => $context,
            'exception' => [
                'message' => $exception->getMessage(),
                'code' => $exception->getCode(),
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => array_slice($exception->getTrace(), 0, 5), // First 5 stack frames
            ],
            'additional_context' => $additionalContext,
        ];

        $this->writeLog($this->errorLogFile, $logEntry);
    }

    /**
     * Write log entry to file
     * 
     * @param string $logFile Path to log file
     * @param array $logEntry Log entry data
     * @return void
     */
    private function writeLog(string $logFile, array $logEntry): void {
        $jsonLine = json_encode($logEntry, JSON_UNESCAPED_SLASHES) . PHP_EOL;
        file_put_contents($logFile, $jsonLine, FILE_APPEND | LOCK_EX);
    }

    /**
     * Get recent log entries
     * 
     * @param string $type 'success' or 'error'
     * @param int $limit Number of entries to retrieve
     * @return array Array of log entries
     */
    public function getRecentLogs(string $type = 'success', int $limit = 100): array {
        $logFile = $type === 'success' ? $this->successLogFile : $this->errorLogFile;
        
        if (!file_exists($logFile)) {
            return [];
        }

        $lines = file($logFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        $logs = [];

        // Get last N lines
        $lines = array_slice($lines, -$limit);

        foreach ($lines as $line) {
            $decoded = json_decode($line, true);
            if ($decoded) {
                $logs[] = $decoded;
            }
        }

        return array_reverse($logs);
    }

    /**
     * Get log statistics
     * 
     * @param string $date Date in Y-m-d format (default: today)
     * @return array Statistics for success and error logs
     */
    public function getStatistics(string $date = null): array {
        if (!$date) {
            $date = date('Y-m-d');
        }

        $stats = [
            'date' => $date,
            'success_count' => 0,
            'error_count' => 0,
            'total_count' => 0,
        ];

        // Count success logs
        if (file_exists($this->successLogFile)) {
            $lines = file($this->successLogFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (strpos($line, $date) !== false) {
                    $stats['success_count']++;
                }
            }
        }

        // Count error logs
        if (file_exists($this->errorLogFile)) {
            $lines = file($this->errorLogFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (strpos($line, $date) !== false) {
                    $stats['error_count']++;
                }
            }
        }

        $stats['total_count'] = $stats['success_count'] + $stats['error_count'];

        return $stats;
    }
}
