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

        $this->writeLog($this->successLogFile, $logEntry);
    }

    /**
     * Log error from API response (optimized for MS SQL Server storage)
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
        // Compact error details - combine error_message and error_details
        $fullErrorMsg = $errorMessage;
        if ($errorDetails) {
            if (is_array($errorDetails)) {
                $fullErrorMsg .= ' | ' . json_encode($errorDetails, JSON_UNESCAPED_SLASHES);
            } else {
                $fullErrorMsg .= ' | ' . $errorDetails;
            }
        }

        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'type' => 'ERROR',
            'error_type' => $errorType ?? 'unknown',
            'irn' => $irn,
            'business_id' => $requestPayload['business_id'] ?? 'N/A',
            'supplier' => $this->truncate($requestPayload['accounting_supplier_party']['party_name'] ?? 'N/A', 100),
            'customer' => $this->truncate($requestPayload['accounting_customer_party']['party_name'] ?? 'N/A', 100),
            'amount' => $requestPayload['legal_monetary_total']['payable_amount'] ?? 0,
            'currency' => $requestPayload['document_currency_code'] ?? 'NGN',
            'http_code' => $httpCode,
            'error' => $this->truncate($fullErrorMsg, 500), // Limit error message to 500 chars
        ];

        $this->writeLog($this->errorLogFile, $logEntry);
    }

    /**
     * Log exception during processing (optimized for MS SQL Server storage)
     * 
     * @param string $irn Original IRN
     * @param \Exception $exception Exception object
     * @param string $context Context where error occurred
     * @param array|null $additionalContext Additional context data
     * @return void
     */
    public function logException(string $irn, \Exception $exception, string $context = 'processing', ?array $additionalContext = null): void {
        // Compact exception info - combine file:line with message
        $exceptionInfo = basename($exception->getFile()) . ':' . $exception->getLine() . ' - ' . $exception->getMessage();
        if ($additionalContext) {
            $exceptionInfo .= ' | ' . json_encode($additionalContext, JSON_UNESCAPED_SLASHES);
        }

        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'type' => 'EXCEPTION',
            'error_type' => 'exception',
            'irn' => $irn,
            'context' => $context,
            'http_code' => $exception->getCode() ?: 500,
            'error' => $this->truncate($exceptionInfo, 500),
        ];

        $this->writeLog($this->errorLogFile, $logEntry);
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
