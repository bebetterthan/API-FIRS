<?php
/**
 * Test Database Connection and Logging
 * 
 * Script untuk test koneksi database dan fungsi logging
 * Run: php test_database_logging.php
 */

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/classes/DatabaseLogger.php';

// Load configuration
$config = require __DIR__ . '/config.php';

echo "=================================================\n";
echo "FIRS Database Logging - Connection Test\n";
echo "=================================================\n\n";

// Check if database logging is enabled
if (!$config['database']['logging_enabled']) {
    echo "❌ Database logging is DISABLED\n";
    echo "   Set DB_LOGGING_ENABLED=true in .env file\n";
    exit(1);
}

echo "✅ Database logging is ENABLED\n\n";

// Display connection info
echo "Connection Information:\n";
echo "  Driver   : " . $config['database']['driver'] . "\n";
echo "  Host     : " . $config['database']['host'] . "\n";
echo "  Port     : " . $config['database']['port'] . "\n";
echo "  Database : " . $config['database']['database'] . "\n";
echo "  Username : " . $config['database']['username'] . "\n";
echo "  Password : " . str_repeat('*', strlen($config['database']['password'])) . "\n\n";

// Check PHP extensions
echo "PHP Extensions Check:\n";
$extensions = [
    'pdo' => extension_loaded('pdo'),
    'pdo_sqlsrv' => extension_loaded('pdo_sqlsrv'),
    'sqlsrv' => extension_loaded('sqlsrv'),
];

foreach ($extensions as $ext => $loaded) {
    $status = $loaded ? '✅ Loaded' : '❌ Not loaded';
    echo "  $ext: $status\n";
}
echo "\n";

// Test database connection
echo "Testing Database Connection...\n";
try {
    $dbLogger = new \FIRS\DatabaseLogger($config);
    
    if ($dbLogger->testConnection()) {
        echo "✅ Database connection successful!\n\n";
    } else {
        echo "❌ Database connection failed!\n";
        echo "   Check your credentials and network connectivity.\n";
        exit(1);
    }
} catch (Exception $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
    exit(1);
}

// Test inserting success log
echo "Testing Success Log Insert...\n";
$testSuccessLog = [
    'timestamp' => date('Y-m-d H:i:s'),
    'type' => 'SUCCESS',
    'irn' => 'TEST-IRN-' . time(),
    'business_id' => 'TEST-BUSINESS-001',
    'supplier' => 'Test Supplier Ltd',
    'customer' => 'Test Customer Inc',
    'amount' => 1500.75,
    'currency' => 'NGN',
    'http_code' => 200,
    'files' => 'test.json,test.txt,test.png',
];

if ($dbLogger->logSuccess($testSuccessLog)) {
    echo "✅ Success log inserted successfully!\n\n";
} else {
    echo "❌ Failed to insert success log\n";
    echo "   Check database permissions and table structure.\n\n";
}

// Test inserting error log
echo "Testing Error Log Insert...\n";
$testErrorLog = [
    'timestamp' => date('Y-m-d H:i:s'),
    'type' => 'ERROR',
    'error_type' => 'test_error',
    'irn' => 'TEST-IRN-ERROR-' . time(),
    'business_id' => 'TEST-BUSINESS-002',
    'supplier' => 'Test Supplier Ltd',
    'customer' => 'Test Customer Inc',
    'amount' => 2500.50,
    'currency' => 'NGN',
    'http_code' => 400,
    'error' => 'This is a test error message',
    'context' => 'testing',
];

if ($dbLogger->logError($testErrorLog)) {
    echo "✅ Error log inserted successfully!\n\n";
} else {
    echo "❌ Failed to insert error log\n";
    echo "   Check database permissions and table structure.\n\n";
}

// Test retrieving recent logs
echo "Testing Log Retrieval...\n";
$recentSuccess = $dbLogger->getRecentLogs('success', 5);
$recentErrors = $dbLogger->getRecentLogs('error', 5);

echo "  Recent success logs: " . count($recentSuccess) . " records\n";
echo "  Recent error logs: " . count($recentErrors) . " records\n\n";

// Test statistics
echo "Testing Statistics...\n";
$stats = $dbLogger->getStatistics();
echo "  Date: " . $stats['date'] . "\n";
echo "  Success count: " . $stats['success_count'] . "\n";
echo "  Error count: " . $stats['error_count'] . "\n";
echo "  Total count: " . $stats['total_count'] . "\n\n";

echo "=================================================\n";
echo "✅ All tests completed successfully!\n";
echo "=================================================\n";
echo "\nYou can now use database logging in production.\n";
echo "Monitor logs with SQL queries in database/README.md\n\n";
