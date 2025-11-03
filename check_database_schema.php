<?php
/**
 * Check Database Schema - Verify New Columns Exist
 */

require_once __DIR__ . '/vendor/autoload.php';

$config = require __DIR__ . '/config.php';

echo "========================================\n";
echo "CHECK DATABASE SCHEMA\n";
echo "========================================\n\n";

echo "Database: {$config['database']['host']}:{$config['database']['port']}\n";
echo "Name: {$config['database']['database']}\n";
echo "Table: {$config['database']['tables']['error_logs']}\n\n";

try {
    $dsn = "odbc:Driver={SQL Server};Server={$config['database']['host']},{$config['database']['port']};Database={$config['database']['database']};TrustServerCertificate=yes";
    $pdo = new PDO($dsn, $config['database']['username'], $config['database']['password']);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    echo "✅ Connection successful\n\n";
    
    // Check table columns
    $query = "SELECT 
        COLUMN_NAME,
        DATA_TYPE,
        CHARACTER_MAXIMUM_LENGTH,
        IS_NULLABLE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = ?
    ORDER BY ORDINAL_POSITION";
    
    $stmt = $pdo->prepare($query);
    $stmt->execute([$config['database']['tables']['error_logs']]);
    $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    echo "Table Structure for '{$config['database']['tables']['error_logs']}':\n";
    echo "========================================\n\n";
    
    $newFields = ['nama_file', 'handler', 'detailed_message', 'public_message'];
    $foundNewFields = [];
    
    foreach ($columns as $column) {
        $name = $column['COLUMN_NAME'];
        $type = $column['DATA_TYPE'];
        $length = $column['CHARACTER_MAXIMUM_LENGTH'] ?? '';
        $nullable = $column['IS_NULLABLE'] === 'YES' ? 'NULL' : 'NOT NULL';
        
        $isNew = in_array($name, $newFields);
        $marker = $isNew ? '🆕' : '  ';
        
        if ($isNew) {
            $foundNewFields[] = $name;
        }
        
        $lengthStr = $length !== '' ? "($length)" : '';
        echo "$marker $name - $type$lengthStr - $nullable\n";
    }
    
    echo "\n========================================\n";
    echo "New Fields Status:\n";
    echo "========================================\n\n";
    
    foreach ($newFields as $field) {
        if (in_array($field, $foundNewFields)) {
            echo "✅ $field - EXISTS\n";
        } else {
            echo "❌ $field - MISSING\n";
        }
    }
    
    if (count($foundNewFields) === count($newFields)) {
        echo "\n✅ All new fields are present!\n";
        echo "   Database schema is up to date.\n\n";
    } else {
        echo "\n⚠️  Some fields are missing!\n";
        echo "   Please run migration script:\n";
        echo "   database/database_update.sql\n\n";
    }
    
    // Show migration script location
    echo "========================================\n";
    echo "Migration Script Location:\n";
    echo "========================================\n\n";
    echo "File: database/database_update.sql\n";
    echo "Run this script in Azure Data Studio or SSMS to add missing columns.\n\n";
    
} catch (Exception $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
    exit(1);
}
