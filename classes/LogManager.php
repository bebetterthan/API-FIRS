<?php
namespace FIRS;

/**
 * LogManager - Handles structured logging for API responses
 * Logs success and error details from FIRS API calls
 * Supports dual logging: file-based and database
 */
class LogManager {
    private $config;
    private $successLogFile;
    private $errorLogFile;
    private $databaseLogger;
    private $dbLoggingEnabled;

    public function __construct($config) {
        $this->config = $config;
        $this->successLogFile = $this->config['logging']['api_success_log'];
        $this->errorLogFile = $this->config['logging']['api_error_log'];
        $this->dbLoggingEnabled = $this->config['logging']['database_enabled'] ?? false;

        // Ensure log directory exists
        $logDir = dirname($this->successLogFile);
        if (!is_dir($logDir)) {
            mkdir($logDir, 0755, true);
        }

        // Initialize database logger if enabled
        if ($this->dbLoggingEnabled) {
            try {
                $this->databaseLogger = new DatabaseLogger($config);
            } catch (\Exception $e) {
                error_log("LogManager: Failed to initialize DatabaseLogger - " . $e->getMessage());
                $this->databaseLogger = null;
            }
        }
    }

    /**
     * Log successful API response (optimized for MS SQL Server storage)
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
        // Compact log entry optimized for database storage
        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'type' => 'SUCCESS',
            'irn' => $irn,
            'business_id' => $invoiceData['business_id'] ?? 'N/A',
            'supplier' => $this->truncate($invoiceData['accounting_supplier_party']['party_name'] ?? 'N/A', 100),
            'customer' => $this->truncate($invoiceData['accounting_customer_party']['party_name'] ?? 'N/A', 100),
            'amount' => $invoiceData['legal_monetary_total']['payable_amount'] ?? 0,
            'currency' => $invoiceData['document_currency_code'] ?? 'NGN',
            'http_code' => $apiResponse['http_code'] ?? 200,
            'files' => implode(',', array_map(fn($f) => basename($f), $files)), // json.txt,encrypted.txt,qr.png
        ];

        // Write to file log
        $this->writeLog($this->successLogFile, $logEntry);

        // Write to database if enabled (simplified structure)
        if ($this->databaseLogger) {
            $dbLogEntry = [
                'timestamp' => $logEntry['timestamp'],
                'irn' => $irn,
                'status' => 'SUCCESS',
            ];
            $this->databaseLogger->logSuccess($dbLogEntry);
        }
    }

    /**
     * Log error from API response (enhanced with observability fields)
     *
     * @param string $irn Original IRN
     * @param int $httpCode HTTP status code
     * @param string $publicMessage User-facing error message (safe for client display)
     * @param string|null $detailedMessage Technical error message (for internal debugging)
     * @param string|null $handler Context/location where error occurred (e.g., class::method)
     * @param array|null $errorDetails Additional error details
     * @param array|null $requestPayload Original request payload (optional)
     * @param string|null $errorType Type of error (validation, api, processing, etc)
     * @param string|null $sourceFile Original source JSON filename
     * @return void
     */
    public function logError(
        string $irn,
        int $httpCode,
        string $publicMessage,
        ?string $detailedMessage = null,
        ?string $handler = null,
        ?array $errorDetails = null,
        ?array $requestPayload = null,
        ?string $errorType = null,
        ?string $sourceFile = null
    ): void {
        $timestamp = date('Y-m-d H:i:s');
        
        // Enhanced log entry with observability fields
        $logEntry = [
            'timestamp' => $timestamp,
            'type' => 'ERROR',
            'error_type' => $errorType ?? 'unknown',
            'http_code' => $httpCode,
            'irn' => $irn,
            'source_file' => $sourceFile ?? 'N/A',
            
            // --- NEW: Enhanced Observability Fields ---
            'handler' => $handler ?? 'unknown',
            'detailed_message' => $this->truncate($detailedMessage ?? $publicMessage, 1000),
            'public_message' => $this->truncate($publicMessage, 500),
            
            // --- Request Context ---
            'business_id' => $requestPayload['business_id'] ?? 'N/A',
            'supplier' => $this->truncate($requestPayload['accounting_supplier_party']['party_name'] ?? 'N/A', 100),
            'customer' => $this->truncate($requestPayload['accounting_customer_party']['party_name'] ?? 'N/A', 100),
            'amount' => $requestPayload['legal_monetary_total']['payable_amount'] ?? 0,
            'currency' => $requestPayload['document_currency_code'] ?? 'NGN',
        ];        // Write to file log
        $this->writeLog($this->errorLogFile, $logEntry);

        // Write to database if enabled (with enhanced fields)
        if ($this->databaseLogger) {
            $dbLogEntry = [
                'timestamp' => $timestamp,
                'irn' => $irn,
                'source_file' => $sourceFile,
                'http_code' => $httpCode,
                'error_type' => $errorType ?? 'unknown',
                'handler' => $handler,
                'detailed_message' => $detailedMessage,
                'public_message' => $publicMessage,
                'error_details' => $errorDetails ? json_encode($errorDetails, JSON_UNESCAPED_SLASHES) : null,
            ];
            $this->databaseLogger->logError($dbLogEntry);
        }
    }

    /**
     * Log exception during processing (enhanced with observability fields)
     *
     * @param string $irn Original IRN
     * @param \Exception $exception Exception object
     * @param string $handler Context/handler where error occurred (e.g., class::method)
     * @param string|null $publicMessage User-facing error message (if null, generates generic message)
     * @param array|null $additionalContext Additional context data
     * @param string|null $sourceFile Original source JSON filename
     * @return void
     */
    public function logException(
        string $irn,
        \Exception $exception,
        string $handler = 'unknown',
        ?string $publicMessage = null,
        ?array $additionalContext = null,
        ?string $sourceFile = null
    ): void {
        $timestamp = date('Y-m-d H:i:s');

        // Build detailed technical message with full stack trace context
        $detailedMessage = sprintf(
            "Exception: %s in %s:%d | Message: %s",
            get_class($exception),
            $exception->getFile(),
            $exception->getLine(),
            $exception->getMessage()
        );

        if ($additionalContext) {
            $detailedMessage .= ' | Context: ' . json_encode($additionalContext, JSON_UNESCAPED_SLASHES);
        }

        // Generate safe public message if not provided
        if (!$publicMessage) {
            $publicMessage = 'Terjadi kesalahan internal. Silakan coba lagi atau hubungi administrator.';
        }

        $logEntry = [
            'timestamp' => $timestamp,
            'type' => 'EXCEPTION',
            'error_type' => 'exception',
            'http_code' => $exception->getCode() ?: 500,
            'irn' => $irn,
            'source_file' => $sourceFile ?? 'N/A',

            // --- Enhanced Observability Fields ---
            'handler' => $handler,
            'detailed_message' => $this->truncate($detailedMessage, 1000),
            'public_message' => $this->truncate($publicMessage, 500),

            // --- Request Context (minimal for exceptions) ---
            'business_id' => 'N/A',
            'supplier' => 'N/A',
            'customer' => 'N/A',
            'amount' => 0,
            'currency' => 'NGN',
        ];

        // Write to file log
        $this->writeLog($this->errorLogFile, $logEntry);

        // Write to database if enabled (with enhanced fields)
        if ($this->databaseLogger) {
            $dbLogEntry = [
                'timestamp' => $timestamp,
                'irn' => $irn,
                'source_file' => $sourceFile,
                'http_code' => $exception->getCode() ?: 500,
                'error_type' => 'exception',
                'handler' => $handler,
                'detailed_message' => $detailedMessage,
                'public_message' => $publicMessage,
                'error_details' => json_encode([
                    'exception_class' => get_class($exception),
                    'file' => $exception->getFile(),
                    'line' => $exception->getLine(),
                    'trace' => $exception->getTraceAsString(),
                    'additional' => $additionalContext,
                ], JSON_UNESCAPED_SLASHES),
            ];
            $this->databaseLogger->logError($dbLogEntry);
        }
    }

    /**
     * Truncate string to specified length with ellipsis
     *
     * @param string $str String to truncate
     * @param int $length Maximum length
     * @return string Truncated string
     */
    private function truncate(string $str, int $length): string {
        if (strlen($str) <= $length) {
            return $str;
        }
        return substr($str, 0, $length - 3) . '...';
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
     * @param string|null $date Date in Y-m-d format (default: today)
     * @return array Statistics for success and error logs
     */
    public function getStatistics(?string $date = null): array {
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
