-- ================================================================
-- FIRS API Logging Database Schema - Simplified Structure
-- Database: firsstaging
-- Created: 2025-10-31
-- Updated: 2025-10-31 (Simplified to essential fields only)
-- Description: Lightweight tables for storing FIRS API logs
-- ================================================================

USE [firsstaging];
GO

-- ================================================================
-- Table: firs_success_logs
-- Description: Stores successful API responses (essential fields only)
-- Columns:
--   - id: Auto-increment primary key
--   - timestamp: Log timestamp from application
--   - irn: Invoice Reference Number
--   - status: Status message (e.g., 'SUCCESS')
--   - created_at: Record creation timestamp
-- ================================================================
IF OBJECT_ID('dbo.firs_success_logs', 'U') IS NOT NULL
    DROP TABLE dbo.firs_success_logs;
GO

CREATE TABLE dbo.firs_success_logs (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME2 NOT NULL,
    irn VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'SUCCESS',
    created_at DATETIME2 DEFAULT GETDATE(),
    INDEX IX_success_timestamp (timestamp),
    INDEX IX_success_irn (irn),
    INDEX IX_success_created_at (created_at)
);
GO

-- ================================================================
-- Table: firs_error_logs
-- Description: Stores error responses and exceptions (essential fields only)
-- Columns:
--   - id: Auto-increment primary key
--   - timestamp: Log timestamp from application
--   - irn: Invoice Reference Number (nullable)
--   - http_code: HTTP status code (nullable)
--   - error_type: Error category (nullable, e.g., 'api_error', 'validation_error')
--   - error_message: Brief error message (nullable)
--   - error_details: Additional context in JSON format (nullable)
--   - created_at: Record creation timestamp
-- ================================================================
IF OBJECT_ID('dbo.firs_error_logs', 'U') IS NOT NULL
    DROP TABLE dbo.firs_error_logs;
GO

CREATE TABLE dbo.firs_error_logs (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME2 NOT NULL,
    irn VARCHAR(255) NULL,
    http_code INT NULL,
    error_type VARCHAR(100) NULL,
    error_message NVARCHAR(MAX) NULL,
    error_details NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    INDEX IX_error_timestamp (timestamp),
    INDEX IX_error_irn (irn),
    INDEX IX_error_type (error_type),
    INDEX IX_error_http_code (http_code),
    INDEX IX_error_created_at (created_at)
);
GO

-- ================================================================
-- Verification Queries
-- ================================================================

-- Verify tables were created
SELECT 
    TABLE_NAME,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = t.TABLE_NAME) as column_count,
    (SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.' + t.TABLE_NAME) AND index_id > 0) as index_count
FROM INFORMATION_SCHEMA.TABLES t
WHERE TABLE_NAME IN ('firs_success_logs', 'firs_error_logs')
ORDER BY TABLE_NAME;

-- View table structure
-- SELECT 
--     TABLE_NAME,
--     COLUMN_NAME,
--     DATA_TYPE,
--     CHARACTER_MAXIMUM_LENGTH,
--     IS_NULLABLE,
--     COLUMN_DEFAULT
-- FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_NAME IN ('firs_success_logs', 'firs_error_logs')
-- ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- ================================================================
-- Sample Monitoring Queries
-- ================================================================

-- Recent success logs (Last 10)
-- SELECT TOP 10 
--     id,
--     timestamp,
--     irn,
--     status,
--     created_at
-- FROM dbo.firs_success_logs
-- ORDER BY created_at DESC;

-- Recent error logs (Last 10)
-- SELECT TOP 10 
--     id,
--     timestamp,
--     irn,
--     http_code,
--     error_type,
--     error_message,
--     created_at
-- FROM dbo.firs_error_logs
-- ORDER BY created_at DESC;

-- Daily log summary (Last 7 days)
-- SELECT 
--     CAST(timestamp AS DATE) as log_date,
--     COUNT(*) as success_count,
--     COUNT(DISTINCT irn) as unique_invoices
-- FROM dbo.firs_success_logs
-- WHERE timestamp >= DATEADD(day, -7, GETDATE())
-- GROUP BY CAST(timestamp AS DATE)
-- ORDER BY log_date DESC;

-- Error statistics by type (Last 7 days)
-- SELECT 
--     error_type,
--     COUNT(*) as error_count,
--     COUNT(DISTINCT irn) as affected_invoices,
--     MAX(timestamp) as last_occurrence
-- FROM dbo.firs_error_logs
-- WHERE timestamp >= DATEADD(day, -7, GETDATE())
--     AND error_type IS NOT NULL
-- GROUP BY error_type
-- ORDER BY error_count DESC;

-- ================================================================
PRINT '================================================================';
PRINT 'FIRS API Logging Tables Created Successfully!';
PRINT '================================================================';
PRINT 'Tables Created:';
PRINT '  - dbo.firs_success_logs (simplified structure)';
PRINT '  - dbo.firs_error_logs (simplified structure)';
PRINT '';
PRINT 'Features:';
PRINT '  - Essential fields only for optimal performance';
PRINT '  - Indexed on timestamp, irn, and error_type';
PRINT '  - Support for NULL values in error logs';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Configure database settings in .env file';
PRINT '  2. Run test_database_logging.php to verify connection';
PRINT '  3. Use queries in useful_queries.sql for monitoring';
PRINT '================================================================';
GO
