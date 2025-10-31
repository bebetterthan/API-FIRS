# Test Scripts - Database Logging Integration

Kedua test script (PowerShell dan Bash) sekarang sudah terintegrasi dengan database logging MSSQL.

## ✨ Fitur

- **Dual Logging**: Log disimpan ke file JSON dan database MSSQL secara bersamaan
- **Auto Configuration**: Membaca konfigurasi database dari file `.env`
- **Silent Failure**: Jika database logging gagal, script tetap melanjutkan proses tanpa error
- **Simplified Structure**: Hanya menyimpan field essential ke database

## 📋 Struktur Log Database

### Success Logs
```sql
INSERT INTO firs_success_logs (timestamp, irn, status)
```

### Error Logs
```sql
INSERT INTO firs_error_logs (timestamp, irn, http_code, error_type, error_message, error_details)
```

## 🚀 Cara Penggunaan

### 1. Pastikan Database Sudah Dikonfigurasi

File `.env` harus berisi:
```env
DB_LOGGING_ENABLED=true
DB_DRIVER=odbc
DB_HOST=34.65.240.209
DB_PORT=1433
DB_DATABASE=firsstaging
DB_USERNAME=sqlserver
DB_PASSWORD=YourPassword
```

### 2. Jalankan Test Script

**PowerShell:**
```powershell
# Set environment variables
$env:JSON_DIR = ".\storage"
$env:PROCESS_MODE = "pipeline"

# Run script
.\test_process_json_files.ps1
```

**Bash:**
```bash
# Set environment variables
export JSON_DIR="./storage"
export PROCESS_MODE="pipeline"

# Run script
bash test_process_json_files.sh
```

## 📊 Verifikasi Log di Database

### Cek Recent Error Logs
```sql
SELECT TOP 10 
    timestamp, irn, http_code, error_type, error_message
FROM firs_error_logs 
ORDER BY timestamp DESC;
```

### Cek Recent Success Logs
```sql
SELECT TOP 10 
    timestamp, irn, status
FROM firs_success_logs 
ORDER BY timestamp DESC;
```

### Statistik Error by Type
```sql
SELECT 
    error_type, 
    COUNT(*) as total,
    MIN(timestamp) as first_error,
    MAX(timestamp) as last_error
FROM firs_error_logs
WHERE timestamp >= DATEADD(day, -7, GETDATE())
GROUP BY error_type
ORDER BY total DESC;
```

## 🔧 Troubleshooting

### PowerShell Script
- Memerlukan System.Data.Odbc assembly (built-in di .NET)
- Menggunakan ODBC Driver "SQL Server" (built-in Windows)
- Jika database logging gagal, akan muncul warning kuning tapi script tetap berjalan

### Bash Script
- Memerlukan PHP dengan extension pdo_odbc
- Menggunakan temporary PHP script untuk koneksi database
- Error database di-suppress agar tidak mengganggu proses utama

## 📝 Log Format

### File Log (JSON)
Log file tetap menyimpan struktur lengkap dengan semua detail invoice, file paths, dll.

### Database Log (Simplified)
Database hanya menyimpan field essential untuk monitoring dan analisis.

**Success:**
- `timestamp`: Waktu log
- `irn`: Invoice Reference Number
- `status`: Status message (SUCCESS)

**Error:**
- `timestamp`: Waktu log
- `irn`: Invoice Reference Number (jika ada)
- `http_code`: HTTP status code
- `error_type`: Kategori error (api_error, validation_error, dll)
- `error_message`: Pesan error singkat
- `error_details`: Detail tambahan dalam format JSON

## 🎯 Best Practices

1. **Monitor Database Size**: Log database bisa bertambah cepat, gunakan retention policy
2. **Index Maintenance**: Pastikan index pada `timestamp` dan `irn` tetap optimal
3. **Backup Logs**: Backup tabel log secara berkala
4. **Clean Old Logs**: Hapus log lama secara periodik (contoh: > 90 hari)

### Contoh Query Cleanup
```sql
-- Hapus log success lebih dari 90 hari
DELETE FROM firs_success_logs 
WHERE timestamp < DATEADD(day, -90, GETDATE());

-- Hapus log error lebih dari 90 hari
DELETE FROM firs_error_logs 
WHERE timestamp < DATEADD(day, -90, GETDATE());
```

## 📈 Monitoring Dashboard

Gunakan query berikut untuk monitoring real-time:

```sql
-- API Health Last 24 Hours
SELECT 
    CAST(timestamp AS DATE) as date,
    DATEPART(hour, timestamp) as hour,
    COUNT(*) as total_requests,
    (SELECT COUNT(*) FROM firs_success_logs s 
     WHERE CAST(s.timestamp AS DATE) = CAST(e.timestamp AS DATE) 
     AND DATEPART(hour, s.timestamp) = DATEPART(hour, e.timestamp)) as success_count
FROM firs_error_logs e
WHERE timestamp >= DATEADD(hour, -24, GETDATE())
GROUP BY CAST(timestamp AS DATE), DATEPART(hour, timestamp)
ORDER BY date DESC, hour DESC;
```

## ⚡ Performance Tips

1. Script PowerShell lebih cepat di Windows karena native ODBC support
2. Bash script menggunakan PHP subprocess, sedikit lebih lambat tapi lebih portable
3. Database logging dilakukan asynchronous (tidak blocking main process)
4. Jika DB connection gagal, log tetap tersimpan di file

## 🔐 Security Notes

- Password database tidak pernah di-log ke file
- Connection string di-encrypt di memory
- Error message di-truncate (max 500 chars) untuk mencegah data leak
- Sensitive data (customer info, amounts) tidak disimpan ke database, hanya ke file log
