<?php
/**
 * Run Database Migration - Add New Columns
 */

require_once __DIR__ . '/vendor/autoload.php';

$config = require __DIR__ . '/config.php';

echo "========================================\n";
echo "DATABASE MIGRATION\n";
echo "========================================\n\n";

echo "Target: {$config['database']['host']}:{$config['database']['port']}\n";
echo "Database: {$config['database']['database']}\n";
echo "Table: {$config['database']['tables']['error_logs']}\n\n";

try {
    $dsn = "odbc:Driver={SQL Server};Server={$config['database']['host']},{$config['database']['port']};Database={$config['database']['database']};TrustServerCertificate=yes";
    $pdo = new PDO($dsn, $config['database']['username'], $config['database']['password']);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    echo "✅ Connection successful\n\n";
    
    echo "Running migration...\n\n";
    
    // Add nama_file column
    echo "[1/4] Adding nama_file column...\n";
    try {
        $pdo->exec("
            IF NOT EXISTS (
                SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'nama_file'
            )
            BEGIN
                ALTER TABLE dbo.firs_error_logs ADD nama_file VARCHAR(500) NULL;
                PRINT 'Added column: nama_file';
            END
        ");
        echo "  ✅ nama_file column added/verified\n";
    } catch (Exception $e) {
        echo "  ⚠️  Warning: " . $e->getMessage() . "\n";
    }
    
    // Add handler column
    echo "[2/4] Adding handler column...\n";
    try {
        $pdo->exec("
            IF NOT EXISTS (
                SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'handler'
            )
            BEGIN
                ALTER TABLE dbo.firs_error_logs ADD handler VARCHAR(255) NULL;
                PRINT 'Added column: handler';
            END
        ");
        echo "  ✅ handler column added/verified\n";
    } catch (Exception $e) {
        echo "  ⚠️  Warning: " . $e->getMessage() . "\n";
    }
    
    // Add detailed_message column
    echo "[3/4] Adding detailed_message column...\n";
    try {
        $pdo->exec("
            IF NOT EXISTS (
                SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'detailed_message'
            )
            BEGIN
                ALTER TABLE dbo.firs_error_logs ADD detailed_message NVARCHAR(MAX) NULL;
                PRINT 'Added column: detailed_message';
            END
        ");
        echo "  ✅ detailed_message column added/verified\n";
    } catch (Exception $e) {
        echo "  ⚠️  Warning: " . $e->getMessage() . "\n";
    }
    
    // Add public_message column
    echo "[4/4] Adding public_message column...\n";
    try {
        $pdo->exec("
            IF NOT EXISTS (
                SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'public_message'
            )
            BEGIN
                ALTER TABLE dbo.firs_error_logs ADD public_message NVARCHAR(1000) NULL;
                PRINT 'Added column: public_message';
            END
        ");
        echo "  ✅ public_message column added/verified\n";
    } catch (Exception $e) {
        echo "  ⚠️  Warning: " . $e->getMessage() . "\n";
    }
    
    echo "\n";
    echo "Creating indexes...\n\n";
    
    // Create index on nama_file
    echo "[1/2] Creating index on nama_file...\n";
    try {
        $pdo->exec("
            IF NOT EXISTS (
                SELECT * FROM sys.indexes 
                WHERE name = 'IX_error_nama_file' AND object_id = OBJECT_ID('dbo.firs_error_logs')
            )
            BEGIN
                CREATE INDEX IX_error_nama_file ON dbo.firs_error_logs(nama_file);
            END
        ");
        echo "  ✅ Index IX_error_nama_file created/verified\n";
    } catch (Exception $e) {
        echo "  ⚠️  Warning: " . $e->getMessage() . "\n";
    }
    
    // Create index on handler
    echo "[2/2] Creating index on handler...\n";
    try {
        $pdo->exec("
            IF NOT EXISTS (
                SELECT * FROM sys.indexes 
                WHERE name = 'IX_error_handler' AND object_id = OBJECT_ID('dbo.firs_error_logs')
            )
            BEGIN
                CREATE INDEX IX_error_handler ON dbo.firs_error_logs(handler);
            END
        ");
        echo "  ✅ Index IX_error_handler created/verified\n";
    } catch (Exception $e) {
        echo "  ⚠️  Warning: " . $e->getMessage() . "\n";
    }
    
    echo "\n========================================\n";
    echo "✅ MIGRATION COMPLETED!\n";
    echo "========================================\n\n";
    
    // Verify schema
    echo "Verifying updated schema...\n\n";
    
    $query = "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
              FROM INFORMATION_SCHEMA.COLUMNS
              WHERE TABLE_NAME = 'firs_error_logs'
              ORDER BY ORDINAL_POSITION";
    
    $stmt = $pdo->query($query);
    $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    $newFields = ['nama_file', 'handler', 'detailed_message', 'public_message'];
    $foundFields = [];
    
    foreach ($columns as $col) {
        if (in_array($col['COLUMN_NAME'], $newFields)) {
            $foundFields[] = $col['COLUMN_NAME'];
            echo "  ✅ {$col['COLUMN_NAME']} - {$col['DATA_TYPE']}\n";
        }
    }
    
    echo "\n";
    
    if (count($foundFields) === count($newFields)) {
        echo "✅ All new fields are present!\n";
        echo "   Database is ready for enhanced logging.\n\n";
    } else {
        echo "⚠️  Some fields are missing:\n";
        foreach (array_diff($newFields, $foundFields) as $missing) {
            echo "   - $missing\n";
        }
        echo "\n";
    }
    
} catch (Exception $e) {
    echo "❌ Migration failed: " . $e->getMessage() . "\n";
    exit(1);
}
