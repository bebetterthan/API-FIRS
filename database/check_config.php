<?php
/**
 * Database Configuration Helper
 * 
 * Script untuk menampilkan dan validate konfigurasi database
 * Run: php database/check_config.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

// Load configuration
$config = require __DIR__ . '/../config.php';

echo "=================================================\n";
echo "FIRS API - Database Configuration\n";
echo "=================================================\n\n";

// Database Configuration
echo "Database Configuration:\n";
echo "  Logging Enabled : " . ($config['database']['logging_enabled'] ? 'YES' : 'NO') . "\n";
echo "  Driver          : " . $config['database']['driver'] . "\n";
echo "  Host            : " . $config['database']['host'] . "\n";
echo "  Port            : " . $config['database']['port'] . "\n";
echo "  Database        : " . $config['database']['database'] . "\n";
echo "  Username        : " . $config['database']['username'] . "\n";
echo "  Password        : " . (empty($config['database']['password']) ? '(not set)' : str_repeat('*', 10)) . "\n";
echo "\n";

echo "Table Names:\n";
echo "  Success Logs    : " . $config['database']['tables']['success_logs'] . "\n";
echo "  Error Logs      : " . $config['database']['tables']['error_logs'] . "\n";
echo "\n";

// PHP Extensions
echo "PHP Extensions:\n";
$extensions = [
    'PDO' => extension_loaded('pdo'),
    'PDO_SQLSRV' => extension_loaded('pdo_sqlsrv'),
    'SQLSRV' => extension_loaded('sqlsrv'),
];

$allLoaded = true;
foreach ($extensions as $ext => $loaded) {
    $status = $loaded ? '✅ Loaded' : '❌ Not loaded';
    echo "  $ext: $status\n";
    if (!$loaded && ($ext === 'PDO_SQLSRV' || $ext === 'SQLSRV')) {
        $allLoaded = false;
    }
}
echo "\n";

// Warnings
if (!$config['database']['logging_enabled']) {
    echo "⚠️  WARNING: Database logging is DISABLED\n";
    echo "   Set DB_LOGGING_ENABLED=true in .env to enable\n\n";
}

if (!$allLoaded) {
    echo "⚠️  WARNING: No SQL Server extension loaded\n";
    echo "   Install pdo_sqlsrv or sqlsrv extension\n";
    echo "   See database/README.md for installation instructions\n\n";
}

if ($config['database']['driver'] === 'pdo' && !extension_loaded('pdo_sqlsrv')) {
    echo "⚠️  WARNING: Driver is set to 'pdo' but pdo_sqlsrv is not loaded\n";
    echo "   Change DB_DRIVER to 'sqlsrv' or install pdo_sqlsrv extension\n\n";
}

if ($config['database']['driver'] === 'sqlsrv' && !extension_loaded('sqlsrv')) {
    echo "⚠️  WARNING: Driver is set to 'sqlsrv' but sqlsrv is not loaded\n";
    echo "   Change DB_DRIVER to 'pdo' or install sqlsrv extension\n\n";
}

if (empty($config['database']['password'])) {
    echo "⚠️  WARNING: Database password is not set\n";
    echo "   Set DB_PASSWORD in .env file\n\n";
}

// Recommendations
echo "Recommendations:\n";
if ($config['database']['driver'] === 'sqlsrv' && extension_loaded('pdo_sqlsrv')) {
    echo "  💡 Consider using 'pdo' driver (more stable and portable)\n";
    echo "     Set DB_DRIVER=pdo in .env\n";
}

if ($config['database']['logging_enabled'] && !$allLoaded) {
    echo "  💡 Install SQL Server PHP extension:\n";
    echo "     Windows: Download from Microsoft\n";
    echo "     Linux: sudo pecl install pdo_sqlsrv\n";
}

echo "\n";
echo "=================================================\n";
echo "Configuration check complete!\n";
echo "=================================================\n";
