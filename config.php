<?php

function loadEnv($filePath = __DIR__ . '/.env') {
    if (!file_exists($filePath)) {
        throw new Exception('.env file not found at: ' . $filePath);
    }
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) {
            continue;
        }
        if (strpos($line, '=') !== false) {
            list($key, $value) = explode('=', $line, 2);
            $key = trim($key);
            $value = trim($value);
            $value = trim($value, '"\'');
            if (!array_key_exists($key, $_ENV)) {
                $_ENV[$key] = $value;
                putenv("$key=$value");
            }
        }
    }
}

loadEnv();

function env($key, $default = null) {
    return $_ENV[$key] ?? getenv($key) ?: $default;
}

return [
    'app' => [
        'name' => 'FIRS E-Invoice API Processor',
        'version' => '1.0.0',
        'env' => env('APP_ENV', 'production'),
        'debug' => env('APP_DEBUG', 'false') === 'true',
        'timezone' => env('TIMEZONE', 'Africa/Lagos'),
        'url' => env('APP_URL', 'https://eivc-k6z6d.ondigitalocean.app'),
    ],
    'api' => [
        'version' => env('API_VERSION', 'v1'),
        'key' => env('API_KEY'),
        'secret' => env('API_SECRET'),
        'prefix' => '/api/v1',
    ],
    'security' => [
        'crypto_keys_file' => env('CRYPTO_KEYS_FILE', './storage/crypto_keys.txt'),
        'max_upload_size' => (int) env('MAX_UPLOAD_SIZE', 102400),
        'allowed_ips' => explode(',', env('ALLOWED_IPS', '*')),
    ],
    'rate_limit' => [
        'enabled' => env('RATE_LIMIT_ENABLED', 'true') === 'true',
        'per_minute' => (int) env('RATE_LIMIT_PER_MINUTE', 100),
        'per_ip' => (int) env('RATE_LIMIT_PER_IP', 60),
    ],
    'sftp' => [
        'enabled' => env('SFTP_ENABLED', 'false') === 'true',
        'host' => env('SFTP_HOST'),
        'port' => (int) env('SFTP_PORT', 22),
        'username' => env('SFTP_USERNAME'),
        'password' => env('SFTP_PASSWORD'),
        'root_path' => env('SFTP_ROOT_PATH', '/firs-invoices'),
        'paths' => [
            'incoming' => '/incoming',
            'processing' => '/processing',
            'completed' => '/completed',
            'failed' => '/failed',
            'qrcodes' => '/qrcodes',
        ],
    ],
    'firs_api' => [
        'enabled' => env('FIRS_API_ENABLED', 'false') === 'true',
        'url' => env('FIRS_API_URL'),
        'key' => env('FIRS_API_KEY'),
        'timeout' => (int) env('FIRS_API_TIMEOUT', 30),
        'endpoints' => [
            'validate_irn' => '/invoice/validate-irn',
            'submit' => '/invoice/submit',
            'status' => '/invoice/status',
        ],
    ],
    'paths' => [
        'storage' => __DIR__ . '/' . ltrim(env('STORAGE_PATH', './storage'), './'),
        'output' => env('OUTPUT_PATH', '/www/wwwroot/sftp/user_data'),
        'logs' => __DIR__ . '/' . ltrim(env('LOGS_PATH', './logs'), './'),
        'json' => env('OUTPUT_PATH', '/www/wwwroot/sftp/user_data') . '/json',
        'encrypted' => env('OUTPUT_PATH', '/www/wwwroot/sftp/user_data') . '/QR/QR_txt',
        'qrcodes' => env('OUTPUT_PATH', '/www/wwwroot/sftp/user_data') . '/QR/QR_img',
        'sftp_cache' => __DIR__ . '/storage/sftp_cache',
        'crypto_keys' => __DIR__ . '/storage/crypto_keys.txt',
        'hsn_codes' => __DIR__ . '/storage/hsn_codes.json',
        'invoice_index' => __DIR__ . '/storage/invoice_index.json',
    ],
    'logging' => [
        'level' => env('LOG_LEVEL', 'info'),
        'file' => __DIR__ . '/logs/app.log',
        'sftp_sync_log' => __DIR__ . '/logs/sftp_sync.log',
        'error_log' => __DIR__ . '/logs/error.log',
        'processing_log' => __DIR__ . '/logs/processing.log',
    ],
    'qr' => [
        'size' => 300,
        'error_correction' => 'M',
        'format' => 'png',
        'margin' => 4,
    ],
    'validation' => [
        'max_invoice_lines' => 1000,
        'tax_tolerance' => 0.01,
        'standard_vat_rate' => 7.5,
        'required_fields' => 52,
        'tin_pattern' => '/^(TIN-[0-9]{8}-[0-9]{4}|DONT HAVE)$/i',
        'phone_prefix' => '+234',
        'country_code' => 'NG',
    ],
    'nigeria' => [
        'currency' => 'NGN',
        'country_code' => 'NG',
        'tax_authority' => 'FIRS',
        'phone_prefix' => '+234',
        'invoice_types' => [
            '380' => 'Commercial Invoice',
            '381' => 'Credit Note',
            '384' => 'Corrected Invoice',
        ],
        'tax_categories' => [
            'S' => 'Standard Rate (7.5%)',
            'Z' => 'Zero Rated',
            'E' => 'Exempt',
            'L' => 'Local Sales Tax',
        ],
    ],
];
