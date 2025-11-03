<?php
namespace FIRS;

/**
 * DatabaseLogger - Handles logging to MS SQL Server database
 * Stores success and error logs in database tables
 */
class DatabaseLogger {
    private $config;
    private $connection;
    private $successTable;
    private $errorTable;
    private $enabled;

    public function __construct($config) {
        $this->config = $config;
        $this->enabled = $config['database']['logging_enabled'] ?? false;

        if (!$this->enabled) {
            return;
        }

        $this->successTable = $config['database']['tables']['success_logs'];
        $this->errorTable = $config['database']['tables']['error_logs'];

        try {
            $this->connect();
        } catch (\Exception $e) {
            error_log("DatabaseLogger: Failed to connect to database - " . $e->getMessage());
            $this->enabled = false;
        }
    }

    /**
     * Establish connection to MS SQL Server
     *
     * @throws \Exception if connection fails
     */
    private function connect(): void {
        $host = $this->config['database']['host'];
        $port = $this->config['database']['port'];
        $database = $this->config['database']['database'];
        $username = $this->config['database']['username'];
        $password = $this->config['database']['password'];
        $driver = $this->config['database']['driver'];

        try {
            if ($driver === 'sqlsrv') {
                // Using SQL Server extension
                $connectionInfo = [
                    "Database" => $database,
                    "UID" => $username,
                    "PWD" => $password,
                    "CharacterSet" => "UTF-8",
                    "ReturnDatesAsStrings" => true,
                ];

                $serverName = $host . "," . $port;
                $this->connection = sqlsrv_connect($serverName, $connectionInfo);

                if ($this->connection === false) {
                    $errors = sqlsrv_errors();
                    throw new \Exception("SQLSRV Connection failed: " . json_encode($errors));
                }
            } elseif ($driver === 'odbc') {
                // Using PDO with ODBC Driver for SQL Server
                $dsn = "odbc:Driver={SQL Server};Server={$host},{$port};Database={$database};TrustServerCertificate=yes";
                $this->connection = new \PDO($dsn, $username, $password);
                $this->connection->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
            } else {
                // Using PDO with SQLSRV driver
                $dsn = "sqlsrv:Server={$host},{$port};Database={$database}";
                $this->connection = new \PDO($dsn, $username, $password);
                $this->connection->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
            }
        } catch (\Exception $e) {
            throw new \Exception("Database connection failed: " . $e->getMessage());
        }
    }

    /**
     * Log successful API response to database
     *
     * @param array $logData Log entry data
     * @return bool Success status
     */
    public function logSuccess(array $logData): bool {
        if (!$this->enabled || !$this->connection) {
            return false;
        }

        try {
            $sql = "INSERT INTO {$this->successTable} (
                timestamp, irn, status, created_at
            ) VALUES (?, ?, ?, GETDATE())";

            $params = [
                $logData['timestamp'] ?? date('Y-m-d H:i:s'),
                $logData['irn'] ?? '',
                $logData['status'] ?? 'SUCCESS',
            ];

            return $this->executeQuery($sql, $params);
        } catch (\Exception $e) {
            error_log("DatabaseLogger::logSuccess failed: " . $e->getMessage());
            return false;
        }
    }

    /**
     * Log error to database (enhanced with observability fields)
     *
     * @param array $logData Log entry data
     * @return bool Success status
     */
    public function logError(array $logData): bool {
        if (!$this->enabled || !$this->connection) {
            return false;
        }

        try {
            $sql = "INSERT INTO {$this->errorTable} (
                timestamp, irn, source_file, http_code, error_type, handler, detailed_message, public_message, error_details, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, GETDATE())";

            $params = [
                $logData['timestamp'] ?? date('Y-m-d H:i:s'),
                $logData['irn'] ?? '',
                $logData['source_file'] ?? null,
                $logData['http_code'] ?? 500,
                $logData['error_type'] ?? 'unknown',
                $logData['handler'] ?? 'unknown',
                $logData['detailed_message'] ?? null,
                $logData['public_message'] ?? null,
                $logData['error_details'] ?? null,
            ];

            return $this->executeQuery($sql, $params);
        } catch (\Exception $e) {
            error_log("DatabaseLogger::logError failed: " . $e->getMessage());
            return false;
        }
    }

    /**
     * Execute SQL query with parameters
     *
     * @param string $sql SQL query
     * @param array $params Query parameters
     * @return bool Success status
     */
    private function executeQuery(string $sql, array $params): bool {
        $driver = $this->config['database']['driver'];

        try {
            if ($driver === 'sqlsrv') {
                $stmt = sqlsrv_query($this->connection, $sql, $params);
                if ($stmt === false) {
                    $errors = sqlsrv_errors();
                    throw new \Exception("Query failed: " . json_encode($errors));
                }
                sqlsrv_free_stmt($stmt);
                return true;
            } else {
                // PDO (both pdo and odbc drivers)
                $stmt = $this->connection->prepare($sql);
                return $stmt->execute($params);
            }
        } catch (\Exception $e) {
            error_log("DatabaseLogger::executeQuery failed: " . $e->getMessage());
            return false;
        }
    }

    /**
     * Get recent logs from database
     *
     * @param string $type 'success' or 'error'
     * @param int $limit Number of entries to retrieve
     * @return array Array of log entries
     */
    public function getRecentLogs(string $type = 'success', int $limit = 100): array {
        if (!$this->enabled || !$this->connection) {
            return [];
        }

        $table = $type === 'success' ? $this->successTable : $this->errorTable;
        $driver = $this->config['database']['driver'];

        try {
            $sql = "SELECT TOP {$limit} * FROM {$table} ORDER BY created_at DESC";

            if ($driver === 'sqlsrv') {
                $stmt = sqlsrv_query($this->connection, $sql);
                if ($stmt === false) {
                    return [];
                }

                $results = [];
                while ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
                    $results[] = $row;
                }
                sqlsrv_free_stmt($stmt);
                return $results;
            } else {
                // PDO
                $stmt = $this->connection->query($sql);
                return $stmt->fetchAll(\PDO::FETCH_ASSOC);
            }
        } catch (\Exception $e) {
            error_log("DatabaseLogger::getRecentLogs failed: " . $e->getMessage());
            return [];
        }
    }

    /**
     * Get log statistics from database
     *
     * @param string|null $date Date in Y-m-d format (default: today)
     * @return array Statistics for success and error logs
     */
    public function getStatistics(?string $date = null): array {
        if (!$this->enabled || !$this->connection) {
            return [
                'date' => $date ?? date('Y-m-d'),
                'success_count' => 0,
                'error_count' => 0,
                'total_count' => 0,
            ];
        }

        if (!$date) {
            $date = date('Y-m-d');
        }

        $driver = $this->config['database']['driver'];
        $stats = [
            'date' => $date,
            'success_count' => 0,
            'error_count' => 0,
            'total_count' => 0,
        ];

        try {
            // Count success logs
            $sql = "SELECT COUNT(*) as count FROM {$this->successTable}
                    WHERE CONVERT(date, timestamp) = ?";
            $count = $this->queryCount($sql, [$date], $driver);
            $stats['success_count'] = $count;

            // Count error logs
            $sql = "SELECT COUNT(*) as count FROM {$this->errorTable}
                    WHERE CONVERT(date, timestamp) = ?";
            $count = $this->queryCount($sql, [$date], $driver);
            $stats['error_count'] = $count;

            $stats['total_count'] = $stats['success_count'] + $stats['error_count'];

            return $stats;
        } catch (\Exception $e) {
            error_log("DatabaseLogger::getStatistics failed: " . $e->getMessage());
            return $stats;
        }
    }

    /**
     * Execute count query
     *
     * @param string $sql SQL query
     * @param array $params Query parameters
     * @param string $driver Database driver
     * @return int Count result
     */
    private function queryCount(string $sql, array $params, string $driver): int {
        if ($driver === 'sqlsrv') {
            $stmt = sqlsrv_query($this->connection, $sql, $params);
            if ($stmt === false) {
                return 0;
            }
            $row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
            sqlsrv_free_stmt($stmt);
            return (int) ($row['count'] ?? 0);
        } else {
            // PDO
            $stmt = $this->connection->prepare($sql);
            $stmt->execute($params);
            $row = $stmt->fetch(\PDO::FETCH_ASSOC);
            return (int) ($row['count'] ?? 0);
        }
    }

    /**
     * Test database connection
     *
     * @return bool Connection status
     */
    public function testConnection(): bool {
        if (!$this->enabled) {
            return false;
        }

        try {
            $driver = $this->config['database']['driver'];

            if ($driver === 'sqlsrv') {
                $sql = "SELECT 1 as test";
                $stmt = sqlsrv_query($this->connection, $sql);
                if ($stmt === false) {
                    return false;
                }
                sqlsrv_free_stmt($stmt);
                return true;
            } else {
                // PDO
                $this->connection->query("SELECT 1");
                return true;
            }
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Close database connection
     */
    public function __destruct() {
        if ($this->connection) {
            $driver = $this->config['database']['driver'] ?? 'pdo';
            if ($driver === 'sqlsrv') {
                sqlsrv_close($this->connection);
            } else {
                $this->connection = null;
            }
        }
    }
}
