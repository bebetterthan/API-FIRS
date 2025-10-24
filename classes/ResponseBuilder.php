<?php
namespace FIRS;


class ResponseBuilder {
    private $config;
    private $requestId;

    public function __construct($config = []) {
        $this->config = $config;
        $this->requestId = $this->generateRequestId();
    }


    private function generateRequestId(): string {
        return bin2hex(random_bytes(8));
    }


    public function success($data, $message = 'Success', $httpStatus = 200): void {
        $this->sendResponse([
            'status' => 'success',
            'message' => $message,
            'data' => $data,
            'timestamp' => date('Y-m-d\TH:i:s\Z'),
            'request_id' => $this->requestId,
        ], $httpStatus);
    }


    public function error($message, $code = 'ERROR', $details = null, $httpStatus = 500): void {
        $response = [
            'status' => 'error',
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
            'timestamp' => date('Y-m-d\TH:i:s\Z'),
            'request_id' => $this->requestId,
        ];


        if ($details && ($this->config['app']['debug'] ?? false)) {
            $response['error']['details'] = $details;
        }

        $this->sendResponse($response, $httpStatus);
    }


    public function validationError($errors, $message = 'Validation failed'): void {
        $this->sendResponse([
            'status' => 'invalid',
            'message' => $message,
            'errors' => $errors,
            'timestamp' => date('Y-m-d\TH:i:s\Z'),
            'request_id' => $this->requestId,
        ], 400);
    }


    public function notFound($resource = 'Resource', $identifier = null): void {
        $message = $identifier
            ? "{$resource} with identifier '{$identifier}' not found"
            : "{$resource} not found";

        $this->sendResponse([
            'status' => 'error',
            'error' => [
                'code' => 'NOT_FOUND',
                'message' => $message,
            ],
            'timestamp' => date('Y-m-d\TH:i:s\Z'),
            'request_id' => $this->requestId,
        ], 404);
    }


    private function sendResponse(array $data, int $httpStatus): void {
        http_response_code($httpStatus);


        header('Content-Type: application/json; charset=utf-8');
        header('X-Request-ID: ' . $this->requestId);


        $this->addCorsHeaders();

        echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
        exit;
    }


    private function addCorsHeaders(): void {
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, Authorization, X-API-Key');
        header('Access-Control-Max-Age: 86400');
    }


    public function handleOptions(): void {
        http_response_code(200);
        $this->addCorsHeaders();
        exit;
    }
}
