-- ================================================================
-- Migration Script: Add Observability Fields to firs_error_logs
-- Description: Adds handler, detailed_message, and public_message columns
-- Target: Existing firs_error_logs table
-- Date: 2025-11-04
-- ================================================================

USE [firsstaging];
GO

-- Check if table exists
IF OBJECT_ID('dbo.firs_error_logs', 'U') IS NULL
BEGIN
    PRINT 'ERROR: Table firs_error_logs does not exist. Please run create_logging_tables.sql first.';
    RETURN;
END
GO

-- ================================================================
-- Add new columns for enhanced observability
-- ================================================================

-- Add nama_file column (original JSON filename)
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'nama_file'
)
BEGIN
    ALTER TABLE dbo.firs_error_logs
    ADD nama_file VARCHAR(500) NULL;
    
    PRINT 'Added column: nama_file';
END
ELSE
BEGIN
    PRINT 'Column nama_file already exists, skipping...';
END
GO

-- Add handler column (context/location where error occurred)
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'handler'
)
BEGIN
    ALTER TABLE dbo.firs_error_logs
    ADD handler VARCHAR(255) NULL;
    
    PRINT 'Added column: handler';
END
ELSE
BEGIN
    PRINT 'Column handler already exists, skipping...';
END
GO-- Add detailed_message column (technical error details)
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'detailed_message'
)
BEGIN
    ALTER TABLE dbo.firs_error_logs
    ADD detailed_message NVARCHAR(MAX) NULL;

    PRINT 'Added column: detailed_message';
END
ELSE
BEGIN
    PRINT 'Column detailed_message already exists, skipping...';
END
GO

-- Add public_message column (user-facing error message)
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'firs_error_logs' AND COLUMN_NAME = 'public_message'
)
BEGIN
    ALTER TABLE dbo.firs_error_logs
    ADD public_message NVARCHAR(1000) NULL;

    PRINT 'Added column: public_message';
END
ELSE
BEGIN
    PRINT 'Column public_message already exists, skipping...';
END
GO

-- ================================================================
-- Add indexes for new columns
-- ================================================================

-- Add index on nama_file for filtering by JSON filename
IF NOT EXISTS (
    SELECT * FROM sys.indexes 
    WHERE name = 'IX_error_nama_file' AND object_id = OBJECT_ID('dbo.firs_error_logs')
)
BEGIN
    CREATE INDEX IX_error_nama_file ON dbo.firs_error_logs(nama_file);
    PRINT 'Created index: IX_error_nama_file';
END
ELSE
BEGIN
    PRINT 'Index IX_error_nama_file already exists, skipping...';
END
GO

-- Add index on handler for filtering by error location
IF NOT EXISTS (
    SELECT * FROM sys.indexes 
    WHERE name = 'IX_error_handler' AND object_id = OBJECT_ID('dbo.firs_error_logs')
)
BEGIN
    CREATE INDEX IX_error_handler ON dbo.firs_error_logs(handler);
    PRINT 'Created index: IX_error_handler';
END
ELSE
BEGIN
    PRINT 'Index IX_error_handler already exists, skipping...';
END
GO-- ================================================================
-- Migrate existing data (optional)
-- ================================================================

-- Update existing records to populate new fields from old error_message column
-- This is optional and can be commented out if not needed
/*
UPDATE dbo.firs_error_logs
SET
    handler = 'unknown',
    detailed_message = error_message,
    public_message = 'An error occurred. Please contact support.'
WHERE handler IS NULL;

PRINT 'Migrated existing error records';
*/

-- ================================================================
-- Verification
-- ================================================================

-- Display updated table structure
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'firs_error_logs'
ORDER BY ORDINAL_POSITION;

-- Display indexes
SELECT
    i.name AS index_name,
    c.name AS column_name,
    i.type_desc
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID('dbo.firs_error_logs')
ORDER BY i.name, ic.key_ordinal;

PRINT 'Migration completed successfully!';
GO
