-- ================================================================-- ================================================================

-- FIRS API Logging - Useful Queries-- FIRS API Logging - Useful Queries

-- Database: firststaging-- Database: firststaging

-- Simplified Structure - Essential Fields Only-- Simplified Structure - Essential Fields Only

-- ================================================================-- ================================================================



USE [firsstaging];USE [firststaging];

GOGO



-- ================================================================-- ================================================================

-- 1. RECENT LOGS-- 1. RECENT LOGS

-- ================================================================-- ================================================================



-- Get last 50 success logs-- Get last 50 success logs

SELECT TOP 50 SELECT TOP 50 

    id,    id,

    timestamp,    timestamp,

    irn,    irn,

    status,    status,

    created_at    created_at

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

ORDER BY created_at DESC;ORDER BY created_at DESC;



-- Get last 50 error logs-- Get last 50 error logs

SELECT TOP 50 SELECT TOP 50 

    id,    id,

    timestamp,    timestamp,

    irn,    irn,

    http_code,    http_code,

    error_type,    error_type,

    error_message,    error_message,

    error_details,    error_details,

    created_at    created_at

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

ORDER BY created_at DESC;ORDER BY created_at DESC;



-- ================================================================-- ================================================================

-- 2. DAILY STATISTICS-- 2. DAILY STATISTICS

-- ================================================================-- ================================================================



-- Success logs count by date-- Success logs count by date

SELECT SELECT 

    CAST(timestamp AS DATE) as log_date,    CAST(timestamp AS DATE) as log_date,

    COUNT(*) as total_success,    COUNT(*) as total_success,

    COUNT(DISTINCT irn) as unique_invoices,    COUNT(DISTINCT irn) as unique_invoices,

    MIN(timestamp) as first_log,    MIN(timestamp) as first_log,

    MAX(timestamp) as last_log    MAX(timestamp) as last_log

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

WHERE timestamp >= DATEADD(day, -7, GETDATE())WHERE timestamp >= DATEADD(day, -7, GETDATE())

GROUP BY CAST(timestamp AS DATE)GROUP BY CAST(timestamp AS DATE)

ORDER BY log_date DESC;ORDER BY log_date DESC;



-- Error logs count by date-- Error logs count by date

SELECT SELECT 

    CAST(timestamp AS DATE) as log_date,    CAST(timestamp AS DATE) as log_date,

    COUNT(*) as total_errors,    COUNT(*) as total_errors,

    COUNT(DISTINCT error_type) as unique_error_types,    COUNT(DISTINCT error_type) as unique_error_types,

    COUNT(DISTINCT http_code) as unique_http_codes    COUNT(DISTINCT http_code) as unique_http_codes

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE timestamp >= DATEADD(day, -7, GETDATE())WHERE timestamp >= DATEADD(day, -7, GETDATE())

GROUP BY CAST(timestamp AS DATE)GROUP BY CAST(timestamp AS DATE)

ORDER BY log_date DESC;ORDER BY log_date DESC;



-- Combined daily statistics-- Combined daily statistics

SELECT SELECT 

    log_date,    log_date,

    ISNULL(success_count, 0) as success_count,    ISNULL(success_count, 0) as success_count,

    ISNULL(error_count, 0) as error_count,    ISNULL(error_count, 0) as error_count,

    ISNULL(success_count, 0) + ISNULL(error_count, 0) as total_count,    ISNULL(success_count, 0) + ISNULL(error_count, 0) as total_count,

    CASE     CASE 

        WHEN ISNULL(success_count, 0) + ISNULL(error_count, 0) > 0         WHEN ISNULL(success_count, 0) + ISNULL(error_count, 0) > 0 

        THEN CAST(ISNULL(success_count, 0) * 100.0 / (ISNULL(success_count, 0) + ISNULL(error_count, 0)) AS DECIMAL(5,2))        THEN CAST(ISNULL(success_count, 0) * 100.0 / (ISNULL(success_count, 0) + ISNULL(error_count, 0)) AS DECIMAL(5,2))

        ELSE 0         ELSE 0 

    END as success_rate    END as success_rate

FROM (FROM (

    SELECT CAST(timestamp AS DATE) as log_date, COUNT(*) as success_count    SELECT CAST(timestamp AS DATE) as log_date, COUNT(*) as success_count

    FROM dbo.firs_success_logs    FROM dbo.firs_success_logs

    WHERE timestamp >= DATEADD(day, -30, GETDATE())    WHERE timestamp >= DATEADD(day, -30, GETDATE())

    GROUP BY CAST(timestamp AS DATE)    GROUP BY CAST(timestamp AS DATE)

) s) s

FULL OUTER JOIN (FULL OUTER JOIN (

    SELECT CAST(timestamp AS DATE) as log_date, COUNT(*) as error_count    SELECT CAST(timestamp AS DATE) as log_date, COUNT(*) as error_count

    FROM dbo.firs_error_logs    FROM dbo.firs_error_logs

    WHERE timestamp >= DATEADD(day, -30, GETDATE())    WHERE timestamp >= DATEADD(day, -30, GETDATE())

    GROUP BY CAST(timestamp AS DATE)    GROUP BY CAST(timestamp AS DATE)

) e ON s.log_date = e.log_date) e ON s.log_date = e.log_date

ORDER BY log_date DESC;ORDER BY log_date DESC;



-- ================================================================-- ================================================================

-- 3. ERROR ANALYSIS-- 3. ERROR ANALYSIS

-- ================================================================-- ================================================================



-- Error count by type-- Error count by type

SELECT SELECT 

    error_type,    error_type,

    COUNT(*) as error_count,    COUNT(*) as error_count,

    COUNT(DISTINCT http_code) as unique_http_codes,    COUNT(DISTINCT http_code) as unique_http_codes,

    MIN(timestamp) as first_occurrence,    MIN(timestamp) as first_occurrence,

    MAX(timestamp) as last_occurrence,    MAX(timestamp) as last_occurrence,

    DATEDIFF(hour, MIN(timestamp), MAX(timestamp)) as span_hours    DATEDIFF(hour, MIN(timestamp), MAX(timestamp)) as span_hours

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE error_type IS NOT NULLWHERE error_type IS NOT NULL

GROUP BY error_typeGROUP BY error_type

ORDER BY error_count DESC;ORDER BY error_count DESC;



-- Most common errors (last 7 days)-- Most common errors (last 7 days)

SELECT TOP 20SELECT TOP 20

    error_type,    error_type,

    http_code,    http_code,

    LEFT(error_message, 100) as error_sample,    LEFT(error_message, 100) as error_sample,

    COUNT(*) as occurrence_count,    COUNT(*) as occurrence_count,

    COUNT(DISTINCT irn) as affected_invoices,    COUNT(DISTINCT irn) as affected_invoices,

    MAX(timestamp) as last_seen    MAX(timestamp) as last_seen

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE timestamp >= DATEADD(day, -7, GETDATE())WHERE timestamp >= DATEADD(day, -7, GETDATE())

GROUP BY error_type, http_code, LEFT(error_message, 100)GROUP BY error_type, http_code, LEFT(error_message, 100)

ORDER BY occurrence_count DESC;ORDER BY occurrence_count DESC;



-- Errors by HTTP status code-- Errors by HTTP status code

SELECT SELECT 

    http_code,    http_code,

    COUNT(*) as error_count,    COUNT(*) as error_count,

    COUNT(DISTINCT error_type) as unique_error_types,    COUNT(DISTINCT error_type) as unique_error_types,

    COUNT(DISTINCT irn) as affected_invoices,    COUNT(DISTINCT irn) as affected_invoices,

    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) as percentage    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) as percentage

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE timestamp >= DATEADD(day, -7, GETDATE())WHERE timestamp >= DATEADD(day, -7, GETDATE())

    AND http_code IS NOT NULL    AND http_code IS NOT NULL

GROUP BY http_codeGROUP BY http_code

ORDER BY error_count DESC;ORDER BY error_count DESC;



-- ================================================================-- ================================================================

-- 4. INVOICE ANALYSIS-- 4. INVOICE ANALYSIS

-- ================================================================-- ================================================================



-- Top invoices by status-- Top invoices by status

SELECT TOP 20SELECT TOP 20

    irn,    irn,

    status,    status,

    COUNT(*) as log_count,    COUNT(*) as log_count,

    MIN(timestamp) as first_logged,    MIN(timestamp) as first_logged,

    MAX(timestamp) as last_logged    MAX(timestamp) as last_logged

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

WHERE irn IS NOT NULLWHERE irn IS NOT NULL

GROUP BY irn, statusGROUP BY irn, status

ORDER BY log_count DESC;ORDER BY log_count DESC;



-- Invoice processing timeline (success vs errors)-- Invoice processing timeline (success vs errors)

SELECT SELECT 

    irn,    irn,

    success_count,    success_count,

    error_count,    error_count,

    CASE     CASE 

        WHEN success_count > 0 THEN 'Success'        WHEN success_count > 0 THEN 'Success'

        ELSE 'Failed'        ELSE 'Failed'

    END as final_status,    END as final_status,

    first_attempt,    first_attempt,

    last_attempt,    last_attempt,

    DATEDIFF(minute, first_attempt, last_attempt) as processing_time_minutes    DATEDIFF(minute, first_attempt, last_attempt) as processing_time_minutes

FROM (FROM (

    SELECT     SELECT 

        ISNULL(s.irn, e.irn) as irn,        ISNULL(s.irn, e.irn) as irn,

        ISNULL(s.success_count, 0) as success_count,        ISNULL(s.success_count, 0) as success_count,

        ISNULL(e.error_count, 0) as error_count,        ISNULL(e.error_count, 0) as error_count,

        CASE         CASE 

            WHEN s.first_attempt < e.first_attempt OR e.first_attempt IS NULL THEN s.first_attempt            WHEN s.first_attempt < e.first_attempt OR e.first_attempt IS NULL THEN s.first_attempt

            ELSE e.first_attempt            ELSE e.first_attempt

        END as first_attempt,        END as first_attempt,

        CASE         CASE 

            WHEN s.last_attempt > e.last_attempt OR e.last_attempt IS NULL THEN s.last_attempt            WHEN s.last_attempt > e.last_attempt OR e.last_attempt IS NULL THEN s.last_attempt

            ELSE e.last_attempt            ELSE e.last_attempt

        END as last_attempt        END as last_attempt

    FROM (    FROM (

        SELECT         SELECT 

            irn,            irn,

            COUNT(*) as success_count,            COUNT(*) as success_count,

            MIN(timestamp) as first_attempt,            MIN(timestamp) as first_attempt,

            MAX(timestamp) as last_attempt            MAX(timestamp) as last_attempt

        FROM dbo.firs_success_logs        FROM dbo.firs_success_logs

        WHERE timestamp >= DATEADD(day, -7, GETDATE())        WHERE timestamp >= DATEADD(day, -7, GETDATE())

            AND irn IS NOT NULL            AND irn IS NOT NULL

        GROUP BY irn        GROUP BY irn

    ) s    ) s

    FULL OUTER JOIN (    FULL OUTER JOIN (

        SELECT         SELECT 

            irn,            irn,

            COUNT(*) as error_count,            COUNT(*) as error_count,

            MIN(timestamp) as first_attempt,            MIN(timestamp) as first_attempt,

            MAX(timestamp) as last_attempt            MAX(timestamp) as last_attempt

        FROM dbo.firs_error_logs        FROM dbo.firs_error_logs

        WHERE timestamp >= DATEADD(day, -7, GETDATE())        WHERE timestamp >= DATEADD(day, -7, GETDATE())

            AND irn IS NOT NULL            AND irn IS NOT NULL

        GROUP BY irn        GROUP BY irn

    ) e ON s.irn = e.irn    ) e ON s.irn = e.irn

) combined) combined

WHERE irn IS NOT NULLWHERE irn IS NOT NULL

ORDER BY last_attempt DESC;ORDER BY last_attempt DESC;



-- ================================================================-- ================================================================

-- 5. HOURLY PATTERNS-- 5. HOURLY PATTERNS

-- ================================================================-- ================================================================



-- Success log volume by hour-- Success log volume by hour

SELECT SELECT 

    DATEPART(hour, timestamp) as hour_of_day,    DATEPART(hour, timestamp) as hour_of_day,

    COUNT(*) as log_count,    COUNT(*) as log_count,

    COUNT(DISTINCT irn) as unique_invoices,    COUNT(DISTINCT irn) as unique_invoices,

    MIN(timestamp) as earliest_log,    MIN(timestamp) as earliest_log,

    MAX(timestamp) as latest_log    MAX(timestamp) as latest_log

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

WHERE timestamp >= DATEADD(day, -7, GETDATE())WHERE timestamp >= DATEADD(day, -7, GETDATE())

GROUP BY DATEPART(hour, timestamp)GROUP BY DATEPART(hour, timestamp)

ORDER BY hour_of_day;ORDER BY hour_of_day;



-- Error patterns by hour-- Error patterns by hour

SELECT SELECT 

    DATEPART(hour, timestamp) as hour_of_day,    DATEPART(hour, timestamp) as hour_of_day,

    COUNT(*) as error_count,    COUNT(*) as error_count,

    COUNT(DISTINCT error_type) as unique_error_types,    COUNT(DISTINCT error_type) as unique_error_types,

    COUNT(DISTINCT http_code) as unique_http_codes,    COUNT(DISTINCT http_code) as unique_http_codes,

    COUNT(DISTINCT irn) as affected_invoices    COUNT(DISTINCT irn) as affected_invoices

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE timestamp >= DATEADD(day, -7, GETDATE())WHERE timestamp >= DATEADD(day, -7, GETDATE())

GROUP BY DATEPART(hour, timestamp)GROUP BY DATEPART(hour, timestamp)

ORDER BY hour_of_day;ORDER BY hour_of_day;



-- Combined hourly activity (success vs errors)-- Combined hourly activity (success vs errors)

SELECT SELECT 

    hour_of_day,    hour_of_day,

    ISNULL(success_count, 0) as success_count,    ISNULL(success_count, 0) as success_count,

    ISNULL(error_count, 0) as error_count,    ISNULL(error_count, 0) as error_count,

    ISNULL(success_count, 0) + ISNULL(error_count, 0) as total_activity,    ISNULL(success_count, 0) + ISNULL(error_count, 0) as total_activity,

    CASE     CASE 

        WHEN ISNULL(success_count, 0) + ISNULL(error_count, 0) > 0         WHEN ISNULL(success_count, 0) + ISNULL(error_count, 0) > 0 

        THEN CAST(ISNULL(success_count, 0) * 100.0 / (ISNULL(success_count, 0) + ISNULL(error_count, 0)) AS DECIMAL(5,2))        THEN CAST(ISNULL(success_count, 0) * 100.0 / (ISNULL(success_count, 0) + ISNULL(error_count, 0)) AS DECIMAL(5,2))

        ELSE 0         ELSE 0 

    END as success_rate_pct    END as success_rate_pct

FROM (FROM (

    SELECT DATEPART(hour, timestamp) as hour_of_day, COUNT(*) as success_count    SELECT DATEPART(hour, timestamp) as hour_of_day, COUNT(*) as success_count

    FROM dbo.firs_success_logs    FROM dbo.firs_success_logs

    WHERE timestamp >= DATEADD(day, -7, GETDATE())    WHERE timestamp >= DATEADD(day, -7, GETDATE())

    GROUP BY DATEPART(hour, timestamp)    GROUP BY DATEPART(hour, timestamp)

) s) s

FULL OUTER JOIN (FULL OUTER JOIN (

    SELECT DATEPART(hour, timestamp) as hour_of_day, COUNT(*) as error_count    SELECT DATEPART(hour, timestamp) as hour_of_day, COUNT(*) as error_count

    FROM dbo.firs_error_logs    FROM dbo.firs_error_logs

    WHERE timestamp >= DATEADD(day, -7, GETDATE())    WHERE timestamp >= DATEADD(day, -7, GETDATE())

    GROUP BY DATEPART(hour, timestamp)    GROUP BY DATEPART(hour, timestamp)

) e ON s.hour_of_day = e.hour_of_day) e ON s.hour_of_day = e.hour_of_day

ORDER BY hour_of_day;ORDER BY hour_of_day;



-- ================================================================-- ================================================================

-- 6. SEARCH SPECIFIC RECORDS-- 6. SEARCH SPECIFIC RECORDS

-- ================================================================-- ================================================================



-- Find all logs by IRN (success and errors)-- Find all logs by IRN (success and errors)

DECLARE @SearchIRN VARCHAR(255) = 'YOUR-IRN-HERE';DECLARE @SearchIRN VARCHAR(255) = 'YOUR-IRN-HERE';



SELECT SELECT 

    'Success' as log_type,    'Success' as log_type,

    id,    id,

    timestamp,    timestamp,

    irn,    irn,

    status,    status,

    NULL as http_code,    NULL as http_code,

    NULL as error_type,    NULL as error_type,

    NULL as error_message,    NULL as error_message,

    created_at    created_at

FROM dbo.firs_success_logs FROM dbo.firs_success_logs 

WHERE irn = @SearchIRNWHERE irn = @SearchIRN

UNION ALLUNION ALL

SELECT SELECT 

    'Error' as log_type,    'Error' as log_type,

    id,    id,

    timestamp,    timestamp,

    irn,    irn,

    NULL as status,    NULL as status,

    http_code,    http_code,

    error_type,    error_type,

    error_message,    error_message,

    created_at    created_at

FROM dbo.firs_error_logs FROM dbo.firs_error_logs 

WHERE irn = @SearchIRNWHERE irn = @SearchIRN

ORDER BY timestamp DESC;ORDER BY timestamp DESC;



-- Find logs by partial IRN match-- Find logs by partial IRN match

DECLARE @SearchPattern VARCHAR(255) = '%PATTERN%';DECLARE @SearchPattern VARCHAR(255) = '%PATTERN%';



SELECT 'Success' as log_type, timestamp, irn, statusSELECT 'Success' as log_type, timestamp, irn, status

FROM dbo.firs_success_logs FROM dbo.firs_success_logs 

WHERE irn LIKE @SearchPatternWHERE irn LIKE @SearchPattern

UNION ALLUNION ALL

SELECT 'Error' as log_type, timestamp, irn, error_messageSELECT 'Error' as log_type, timestamp, irn, error_message

FROM dbo.firs_error_logs FROM dbo.firs_error_logs 

WHERE irn LIKE @SearchPatternWHERE irn LIKE @SearchPattern

ORDER BY timestamp DESC;ORDER BY timestamp DESC;



-- Search errors by message content-- Search errors by message content

SELECT SELECT 

    id,    id,

    timestamp,    timestamp,

    irn,    irn,

    http_code,    http_code,

    error_type,    error_type,

    error_message,    error_message,

    created_at    created_at

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE error_message LIKE '%SEARCH_TERM%'WHERE error_message LIKE '%SEARCH_TERM%'

    OR error_details LIKE '%SEARCH_TERM%'    OR error_details LIKE '%SEARCH_TERM%'

ORDER BY timestamp DESC;ORDER BY timestamp DESC;



-- ================================================================-- ================================================================

-- 7. PERFORMANCE MONITORING-- 7. PERFORMANCE MONITORING

-- ================================================================-- ================================================================



-- Table sizes-- Table sizes

SELECT SELECT 

    t.name AS table_name,    t.name AS table_name,

    p.rows AS row_count,    p.rows AS row_count,

    SUM(a.total_pages) * 8 AS total_space_kb,    SUM(a.total_pages) * 8 AS total_space_kb,

    SUM(a.used_pages) * 8 AS used_space_kb,    SUM(a.used_pages) * 8 AS used_space_kb,

    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS unused_space_kb    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS unused_space_kb

FROM sys.tables tFROM sys.tables t

INNER JOIN sys.indexes i ON t.object_id = i.object_idINNER JOIN sys.indexes i ON t.object_id = i.object_id

INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_idINNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id

INNER JOIN sys.allocation_units a ON p.partition_id = a.container_idINNER JOIN sys.allocation_units a ON p.partition_id = a.container_id

WHERE t.name IN ('firs_success_logs', 'firs_error_logs')WHERE t.name IN ('firs_success_logs', 'firs_error_logs')

GROUP BY t.name, p.rowsGROUP BY t.name, p.rows

ORDER BY row_count DESC;ORDER BY row_count DESC;



-- Database growth trend (last 30 days)-- Database growth trend (last 30 days)

SELECT SELECT 

    CAST(created_at AS DATE) as date,    CAST(created_at AS DATE) as date,

    COUNT(*) as records_added,    COUNT(*) as records_added,

    SUM(COUNT(*)) OVER (ORDER BY CAST(created_at AS DATE)) as cumulative_count    SUM(COUNT(*)) OVER (ORDER BY CAST(created_at AS DATE)) as cumulative_count

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

WHERE created_at >= DATEADD(day, -30, GETDATE())WHERE created_at >= DATEADD(day, -30, GETDATE())

GROUP BY CAST(created_at AS DATE)GROUP BY CAST(created_at AS DATE)

ORDER BY date;ORDER BY date;



-- ================================================================-- ================================================================

-- 8. DATA RETENTION & CLEANUP-- 8. DATA RETENTION & CLEANUP

-- ================================================================-- ================================================================



-- Count records by age-- Count records by age

SELECT SELECT 

    'Success Logs' as table_name,    'Success Logs' as table_name,

    COUNT(CASE WHEN timestamp >= DATEADD(day, -7, GETDATE()) THEN 1 END) as last_7_days,    COUNT(CASE WHEN timestamp >= DATEADD(day, -7, GETDATE()) THEN 1 END) as last_7_days,

    COUNT(CASE WHEN timestamp >= DATEADD(day, -30, GETDATE()) THEN 1 END) as last_30_days,    COUNT(CASE WHEN timestamp >= DATEADD(day, -30, GETDATE()) THEN 1 END) as last_30_days,

    COUNT(CASE WHEN timestamp >= DATEADD(day, -90, GETDATE()) THEN 1 END) as last_90_days,    COUNT(CASE WHEN timestamp >= DATEADD(day, -90, GETDATE()) THEN 1 END) as last_90_days,

    COUNT(CASE WHEN timestamp < DATEADD(day, -90, GETDATE()) THEN 1 END) as older_than_90_days,    COUNT(CASE WHEN timestamp < DATEADD(day, -90, GETDATE()) THEN 1 END) as older_than_90_days,

    COUNT(*) as total_records    COUNT(*) as total_records

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

UNION ALLUNION ALL

SELECT SELECT 

    'Error Logs' as table_name,    'Error Logs' as table_name,

    COUNT(CASE WHEN timestamp >= DATEADD(day, -7, GETDATE()) THEN 1 END) as last_7_days,    COUNT(CASE WHEN timestamp >= DATEADD(day, -7, GETDATE()) THEN 1 END) as last_7_days,

    COUNT(CASE WHEN timestamp >= DATEADD(day, -30, GETDATE()) THEN 1 END) as last_30_days,    COUNT(CASE WHEN timestamp >= DATEADD(day, -30, GETDATE()) THEN 1 END) as last_30_days,

    COUNT(CASE WHEN timestamp >= DATEADD(day, -90, GETDATE()) THEN 1 END) as last_90_days,    COUNT(CASE WHEN timestamp >= DATEADD(day, -90, GETDATE()) THEN 1 END) as last_90_days,

    COUNT(CASE WHEN timestamp < DATEADD(day, -90, GETDATE()) THEN 1 END) as older_than_90_days,    COUNT(CASE WHEN timestamp < DATEADD(day, -90, GETDATE()) THEN 1 END) as older_than_90_days,

    COUNT(*) as total_records    COUNT(*) as total_records

FROM dbo.firs_error_logs;FROM dbo.firs_error_logs;



-- Archive old logs to backup table (older than 90 days)-- Archive old logs to backup table (older than 90 days)

-- Step 1: Create archive tables (run once)-- Step 1: Create archive tables (run once)

/*/*

SELECT * INTO dbo.firs_success_logs_archive FROM dbo.firs_success_logs WHERE 1=0;SELECT * INTO dbo.firs_success_logs_archive FROM dbo.firs_success_logs WHERE 1=0;

SELECT * INTO dbo.firs_error_logs_archive FROM dbo.firs_error_logs WHERE 1=0;SELECT * INTO dbo.firs_error_logs_archive FROM dbo.firs_error_logs WHERE 1=0;

*/*/



-- Step 2: Move old records to archive-- Step 2: Move old records to archive

/*/*

INSERT INTO dbo.firs_success_logs_archiveINSERT INTO dbo.firs_success_logs_archive

SELECT * FROM dbo.firs_success_logsSELECT * FROM dbo.firs_success_logs

WHERE timestamp < DATEADD(day, -90, GETDATE());WHERE timestamp < DATEADD(day, -90, GETDATE());



INSERT INTO dbo.firs_error_logs_archiveINSERT INTO dbo.firs_error_logs_archive

SELECT * FROM dbo.firs_error_logsSELECT * FROM dbo.firs_error_logs

WHERE timestamp < DATEADD(day, -90, GETDATE());WHERE timestamp < DATEADD(day, -90, GETDATE());

*/*/



-- Step 3: Delete archived records-- Step 3: Delete archived records

/*/*

DELETE FROM dbo.firs_success_logsDELETE FROM dbo.firs_success_logs

WHERE timestamp < DATEADD(day, -90, GETDATE());WHERE timestamp < DATEADD(day, -90, GETDATE());



DELETE FROM dbo.firs_error_logsDELETE FROM dbo.firs_error_logs

WHERE timestamp < DATEADD(day, -90, GETDATE());WHERE timestamp < DATEADD(day, -90, GETDATE());

*/*/



-- ================================================================-- ================================================================

-- 9. MONITORING & HEALTH CHECKS-- 9. MONITORING & HEALTH CHECKS

-- ================================================================-- ================================================================



-- API Health Summary (Last 24 Hours)-- API Health Summary (Last 24 Hours)

SELECT SELECT 

    'Last 24 Hours' as time_period,    'Last 24 Hours' as time_period,

    (SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) as success_count,    (SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) as success_count,

    (SELECT COUNT(*) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) as error_count,    (SELECT COUNT(*) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) as error_count,

    (SELECT COUNT(DISTINCT error_type) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) as unique_errors,    (SELECT COUNT(DISTINCT error_type) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) as unique_errors,

    CASE     CASE 

        WHEN (SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) +         WHEN (SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) + 

             (SELECT COUNT(*) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) > 0             (SELECT COUNT(*) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) > 0

        THEN CAST((SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) * 100.0 /         THEN CAST((SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) * 100.0 / 

             ((SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) +              ((SELECT COUNT(*) FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE())) + 

              (SELECT COUNT(*) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE()))) AS DECIMAL(5,2))              (SELECT COUNT(*) FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -24, GETDATE()))) AS DECIMAL(5,2))

        ELSE 0        ELSE 0

    END as success_rate_pct;    END as success_rate_pct;



-- Recent activity summary (Last hour)-- Recent activity summary (Last hour)

SELECT SELECT 

    'Last Hour' as time_window,    'Last Hour' as time_window,

    COUNT(*) as total_logs,    COUNT(*) as total_logs,

    MIN(timestamp) as earliest_log,    MIN(timestamp) as earliest_log,

    MAX(timestamp) as latest_log,    MAX(timestamp) as latest_log,

    COUNT(DISTINCT irn) as unique_invoices    COUNT(DISTINCT irn) as unique_invoices

FROM (FROM (

    SELECT timestamp, irn FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -1, GETDATE())    SELECT timestamp, irn FROM dbo.firs_success_logs WHERE timestamp >= DATEADD(hour, -1, GETDATE())

    UNION ALL    UNION ALL

    SELECT timestamp, irn FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -1, GETDATE())    SELECT timestamp, irn FROM dbo.firs_error_logs WHERE timestamp >= DATEADD(hour, -1, GETDATE())

) combined;) combined;



-- Critical errors (HTTP 500+) in last 24 hours-- Critical errors (HTTP 500+) in last 24 hours

SELECT SELECT 

    timestamp,    timestamp,

    irn,    irn,

    http_code,    http_code,

    error_type,    error_type,

    error_message,    error_message,

    DATEDIFF(minute, timestamp, GETDATE()) as minutes_ago    DATEDIFF(minute, timestamp, GETDATE()) as minutes_ago

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE timestamp >= DATEADD(hour, -24, GETDATE())WHERE timestamp >= DATEADD(hour, -24, GETDATE())

    AND http_code >= 500    AND http_code >= 500

ORDER BY timestamp DESC;ORDER BY timestamp DESC;



-- ================================================================-- ================================================================

-- 10. EXPORT QUERIES-- 10. EXPORT QUERIES

-- ================================================================-- ================================================================



-- Export today's success logs-- Export today's success logs

SELECT SELECT 

    id,    id,

    FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss') as timestamp,    FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss') as timestamp,

    irn,    irn,

    status,    status,

    FORMAT(created_at, 'yyyy-MM-dd HH:mm:ss') as created_at    FORMAT(created_at, 'yyyy-MM-dd HH:mm:ss') as created_at

FROM dbo.firs_success_logsFROM dbo.firs_success_logs

WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)

ORDER BY timestamp DESC;ORDER BY timestamp DESC;



-- Export today's error logs-- Export today's error logs

SELECT SELECT 

    id,    id,

    FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss') as timestamp,    FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss') as timestamp,

    irn,    irn,

    http_code,    http_code,

    error_type,    error_type,

    error_message,    error_message,

    error_details,    error_details,

    FORMAT(created_at, 'yyyy-MM-dd HH:mm:ss') as created_at    FORMAT(created_at, 'yyyy-MM-dd HH:mm:ss') as created_at

FROM dbo.firs_error_logsFROM dbo.firs_error_logs

WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)

ORDER BY timestamp DESC;ORDER BY timestamp DESC;



-- BCP Export Commands (Run from command line)-- BCP Export Commands (Run from command line)

/*/*

# Export success logs# Export success logs

bcp "SELECT id, FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss'), irn, status FROM firststaging.dbo.firs_success_logs WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)" queryout "success_logs.csv" -c -t"," -S 34.65.240.209 -U sqlserver -P YourPasswordbcp "SELECT id, FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss'), irn, status FROM firststaging.dbo.firs_success_logs WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)" queryout "success_logs.csv" -c -t"," -S 34.65.240.209 -U sqlserver -P YourPassword



# Export error logs# Export error logs

bcp "SELECT id, FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss'), irn, http_code, error_type, error_message FROM firststaging.dbo.firs_error_logs WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)" queryout "error_logs.csv" -c -t"," -S 34.65.240.209 -U sqlserver -P YourPasswordbcp "SELECT id, FORMAT(timestamp, 'yyyy-MM-dd HH:mm:ss'), irn, http_code, error_type, error_message FROM firststaging.dbo.firs_error_logs WHERE CAST(timestamp AS DATE) = CAST(GETDATE() AS DATE)" queryout "error_logs.csv" -c -t"," -S 34.65.240.209 -U sqlserver -P YourPassword

*/*/



-- ================================================================-- ================================================================

PRINT '================================================================';PRINT '================================================================';

PRINT 'FIRS API Logging Queries - Simplified Structure';PRINT 'FIRS API Logging Queries - Simplified Structure';

PRINT '================================================================';PRINT '================================================================';

PRINT 'Query templates loaded successfully!';PRINT 'Query templates loaded successfully!';

PRINT 'Replace placeholder values (YOUR-IRN-HERE, SEARCH_TERM, etc.)';PRINT 'Replace placeholder values (YOUR-IRN-HERE, SEARCH_TERM, etc.)';

PRINT 'Uncomment DELETE/INSERT statements before executing cleanup queries';PRINT 'Uncomment DELETE/INSERT statements before executing cleanup queries';

PRINT '================================================================';PRINT '================================================================';

GOGO

