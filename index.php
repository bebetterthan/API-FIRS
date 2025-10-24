<?php

// Performance: Enable output compression
if (extension_loaded('zlib') && !ini_get('zlib.output_compression')) {
    ini_set('zlib.output_compression', '1');
    ini_set('zlib.output_compression_level', '6'); // Balance between speed and compression
}

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');


$config = require_once __DIR__ . '/config.php';


date_default_timezone_set($config['app']['timezone']);


ini_set('error_log', $config['logging']['error_log']);


ini_set('memory_limit', '256M');


if (!file_exists(__DIR__ . '/vendor/autoload.php')) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'status' => 'error',
        'error' => [
            'code' => 'DEPENDENCY_ERROR',
            'message' => 'Composer dependencies not installed. Please run: composer install',
        ],
    ]);
    exit;
}


require_once __DIR__ . '/vendor/autoload.php';


require_once __DIR__ . '/classes/ResponseBuilder.php';
require_once __DIR__ . '/classes/Router.php';


set_error_handler(function($errno, $errstr, $errfile, $errline) use ($config) {
    $responseBuilder = new \FIRS\ResponseBuilder($config);

    error_log("PHP Error [$errno]: $errstr in $errfile on line $errline");

    if ($config['app']['debug']) {
        $responseBuilder->error(
            'Internal server error: ' . $errstr,
            'INTERNAL_ERROR',
            [
                'file' => $errfile,
                'line' => $errline,
            ],
            500
        );
    } else {
        $responseBuilder->error('Internal server error', 'INTERNAL_ERROR', null, 500);
    }
});


set_exception_handler(function($exception) use ($config) {
    $responseBuilder = new \FIRS\ResponseBuilder($config);

    error_log("Uncaught Exception: " . $exception->getMessage() . "\n" . $exception->getTraceAsString());

    if ($config['app']['debug']) {
        $responseBuilder->error(
            $exception->getMessage(),
            'EXCEPTION',
            [
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
            ],
            500
        );
    } else {
        $responseBuilder->error('An unexpected error occurred', 'EXCEPTION', null, 500);
    }
});


function checkApiKey($config): void {
    $apiKey = null;


    if (isset($_SERVER['HTTP_X_API_KEY'])) {
        $apiKey = $_SERVER['HTTP_X_API_KEY'];
    }


    if (!$apiKey && isset($_SERVER['HTTP_AUTHORIZATION'])) {
        if (preg_match('/Bearer\s+(.*)$/i', $_SERVER['HTTP_AUTHORIZATION'], $matches)) {
            $apiKey = $matches[1];
        }
    }


    $publicEndpoints = [
        '/api/v1/system/health',
        '/api/transmitting/health',
        '/api/v1/invoice/hsn-codes',
    ];

    $requestUri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

    foreach ($publicEndpoints as $endpoint) {
        if (strpos($requestUri, $endpoint) !== false) {
            return;
        }
    }


    if (!$apiKey || $apiKey !== $config['api']['key']) {
        $responseBuilder = new \FIRS\ResponseBuilder($config);
        $responseBuilder->error('Invalid or missing API key', 'UNAUTHORIZED', null, 401);
    }
}


function checkRateLimit($config): void {
    if (!$config['rate_limit']['enabled']) {
        return;
    }

    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $key = 'ratelimit_' . $ip . '_' . date('YmdHi');
    $cacheFile = sys_get_temp_dir() . '/' . md5($key) . '.cache';

    $count = 0;
    if (file_exists($cacheFile)) {
        $count = (int) file_get_contents($cacheFile);
    }

    $count++;
    file_put_contents($cacheFile, $count);

    if ($count > $config['rate_limit']['per_minute']) {
        $responseBuilder = new \FIRS\ResponseBuilder($config);
        header('X-RateLimit-Limit: ' . $config['rate_limit']['per_minute']);
        header('X-RateLimit-Remaining: 0');
        header('X-RateLimit-Reset: ' . (time() + 60));
        $responseBuilder->error('Rate limit exceeded', 'RATE_LIMIT_EXCEEDED', null, 429);
    }

    header('X-RateLimit-Limit: ' . $config['rate_limit']['per_minute']);
    header('X-RateLimit-Remaining: ' . ($config['rate_limit']['per_minute'] - $count));
    header('X-RateLimit-Reset: ' . (time() + 60));
}


try {

    checkApiKey($config);
    checkRateLimit($config);


    $router = new \FIRS\Router($config);
    $router->dispatch();

} catch (\Exception $e) {

    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'status' => 'error',
        'error' => [
            'code' => 'FATAL_ERROR',
            'message' => $config['app']['debug'] ? $e->getMessage() : 'A fatal error occurred',
        ],
        'timestamp' => date('Y-m-d\TH:i:s\Z'),
    ]);
}
