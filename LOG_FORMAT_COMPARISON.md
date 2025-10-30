# 📊 Perbandingan Format Log - Optimasi untuk MS SQL Server

## ❌ **FORMAT LAMA (Terlalu Panjang)**

### Success Log (Panjang: ~800-1200 karakter)
```json
{
  "timestamp": "2025-10-28 19:15:58",
  "type": "SUCCESS",
  "irn": "PFTEST20251028191545-TEST001-20251028",
  "irn_signed": "PFTEST20251028191545-TEST001-20251028.1761653757",
  "invoice_details": {
    "business_id": "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
    "issue_date": "2025-10-23",
    "supplier": "PF-DEV COMPANY NAME VERY LONG",
    "customer": "EURO MEGA ATLANTIC NIGERIA LTD. North Branch Office",
    "total_amount": "59850",
    "currency": "NGN",
    "payment_status": "PAID"
  },
  "files_created": {
    "json": {
      "filename": "PFTEST20251028191545-TEST001-20251028.1761653757.json",
      "path": "C:/www/wwwroot/sftp/user_data/PFTEST20251028191545-TEST001-20251028.1761653757.json",
      "size_bytes": 1024,
      "size_kb": 1.0
    },
    "encrypted": {
      "filename": "PFTEST20251028191545-TEST001-20251028.1761653757.txt",
      "path": "C:/www/wwwroot/sftp/user_data/QR/QR_txt/PFTEST20251028191545-TEST001-20251028.1761653757.txt",
      "size_bytes": 345,
      "size_kb": 0.34
    },
    "qr_code": {
      "filename": "PFTEST20251028191545-TEST001-20251028.1761653757.png",
      "path": "C:/www/wwwroot/sftp/user_data/QR/QR_img/PFTEST20251028191545-TEST001-20251028.1761653757.png",
      "size_bytes": 3829,
      "size_kb": 3.74
    }
  },
  "api_response": {
    "status": "success",
    "http_code": 200,
    "data": {
      "message": "Invoice processed successfully"
    }
  },
  "performance": {
    "validation": 12.5,
    "irn_processing": 3.2,
    "duplicate_check": 5.1,
    "save_json": 8.3,
    "total": 156.8
  }
}
```

### Error Log (Panjang: ~600-900 karakter)
```json
{
  "timestamp": "2025-10-30 23:35:33",
  "type": "ERROR",
  "error_type": "api_error",
  "irn": "PFTEST-20251030234021-001",
  "http_code": 400,
  "error_message": "Unknown error",
  "error_details": {
    "code": "INVALID_FORMAT",
    "description": "API call failed",
    "validation_errors": [
      "Field 'tax_amount' is required",
      "Field 'taxable_amount' must be numeric"
    ]
  },
  "request_summary": {
    "business_id": "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
    "issue_date": "2025-10-30",
    "total_amount": "1075",
    "currency": "NGN",
    "supplier": "PF-DEV COMPANY NAME VERY LONG",
    "customer": "TEST CUSTOMER PS1 BRANCH OFFICE NORTH"
  }
}
```

---

## ✅ **FORMAT BARU (Ringkas & Informatif)**

### Success Log (Panjang: ~250-350 karakter - **Hemat 70%**)
```json
{
  "timestamp": "2025-10-28 19:15:58",
  "type": "SUCCESS",
  "irn": "PFTEST20251028191545-TEST001-20251028",
  "business_id": "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
  "supplier": "PF-DEV COMPANY NAME VERY LONG",
  "customer": "EURO MEGA ATLANTIC NIGERIA LTD. North Branch Office",
  "amount": 59850,
  "currency": "NGN",
  "http_code": 200,
  "files": "PFTEST.json,PFTEST.txt,PFTEST.png",
  "process_time": "156.8ms"
}
```

### Error Log (Panjang: ~300-400 karakter - **Hemat 60%**)
```json
{
  "timestamp": "2025-10-30 23:35:33",
  "type": "ERROR",
  "error_type": "api_error",
  "irn": "PFTEST-20251030234021-001",
  "business_id": "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
  "supplier": "PF-DEV COMPANY NAME VERY LONG",
  "customer": "TEST CUSTOMER PS1 BRANCH OFFICE NORTH",
  "amount": 1075,
  "currency": "NGN",
  "http_code": 400,
  "error": "Unknown error | {\"code\":\"INVALID_FORMAT\",\"description\":\"API call failed\",\"validation_errors\":[\"Field 'tax_amount' is required\"]}"
}
```

---

## 📈 **Keuntungan Format Baru:**

### 1. **Ukuran Database Lebih Efisien**
- ❌ Lama: ~1000 bytes per log
- ✅ Baru: ~300 bytes per log
- 💾 **Hemat Storage: 70%**

### 2. **Query Database Lebih Cepat**
- Kolom flat (tidak nested) → index lebih efisien
- VARCHAR field lebih pendek → scan lebih cepat
- JSON parsing minimal → query performance meningkat

### 3. **MS SQL Server Table Structure Suggestion**
```sql
CREATE TABLE api_success_logs (
    id BIGINT PRIMARY KEY IDENTITY(1,1),
    timestamp DATETIME2 NOT NULL,
    type VARCHAR(20) NOT NULL,
    irn VARCHAR(100) NOT NULL,
    business_id VARCHAR(50),
    supplier VARCHAR(100),
    customer VARCHAR(100),
    amount DECIMAL(18,2),
    currency VARCHAR(10),
    http_code INT,
    files VARCHAR(255),
    process_time VARCHAR(20),
    INDEX idx_timestamp (timestamp),
    INDEX idx_irn (irn),
    INDEX idx_business_id (business_id)
);

CREATE TABLE api_error_logs (
    id BIGINT PRIMARY KEY IDENTITY(1,1),
    timestamp DATETIME2 NOT NULL,
    type VARCHAR(20) NOT NULL,
    error_type VARCHAR(50) NOT NULL,
    irn VARCHAR(100),
    business_id VARCHAR(50),
    supplier VARCHAR(100),
    customer VARCHAR(100),
    amount DECIMAL(18,2),
    currency VARCHAR(10),
    http_code INT,
    error VARCHAR(500),
    INDEX idx_timestamp (timestamp),
    INDEX idx_irn (irn),
    INDEX idx_error_type (error_type)
);
```

### 4. **Tetap Informatif**
- ✅ Timestamp untuk tracking waktu
- ✅ IRN untuk identifikasi invoice
- ✅ Business ID untuk filter per business
- ✅ Supplier & Customer (truncated ke 100 char)
- ✅ Amount & Currency untuk monitoring nilai
- ✅ HTTP Code untuk monitoring status
- ✅ Files created (comma-separated list)
- ✅ Process time untuk performance monitoring
- ✅ Error detail lengkap (gabungan message + details)

### 5. **Mudah Di-Import ke Database**
```powershell
# PowerShell script untuk import ke MS SQL Server
$logs = Get-Content "api_success.log" | ForEach-Object {
    $json = $_ | ConvertFrom-Json
    @{
        timestamp = $json.timestamp
        type = $json.type
        irn = $json.irn
        business_id = $json.business_id
        supplier = $json.supplier
        customer = $json.customer
        amount = $json.amount
        currency = $json.currency
        http_code = $json.http_code
        files = $json.files
        process_time = $json.process_time
    }
}

# Bulk insert ke SQL Server
$logs | ForEach-Object {
    Invoke-Sqlcmd -Query "INSERT INTO api_success_logs ..." -ServerInstance "localhost" -Database "FIRS_API"
}
```

---

## 🎯 **Fitur Khusus:**

### 1. **Auto-Truncate Long Text**
- Supplier/Customer name: Max 100 karakter
- Error message: Max 500 karakter
- Jika lebih panjang → otomatis di-truncate dengan "..."

### 2. **Compact File List**
- Bukan full path, hanya filename
- Comma-separated: `file1.json,file2.txt,file3.png`
- Hemat space tapi tetap informatif

### 3. **Combined Error Info**
- Error message + error details digabung dengan separator "|"
- Format: `message | {"details":"..."}` 
- Mudah di-parse jika perlu detail lengkap

### 4. **Performance Metrics**
- Hanya simpan total time (ms)
- Tidak perlu detail per-step (hemat space)

---

## 📊 **Estimasi Storage untuk 1 Tahun:**

### Format Lama:
- 1000 bytes × 10,000 requests/day × 365 days = **3.65 GB/year**

### Format Baru:
- 300 bytes × 10,000 requests/day × 365 days = **1.09 GB/year**

**💾 Penghematan: 2.56 GB/year (70%)**

---

## ✅ **Status Implementasi:**
- ✅ LogManager.php diupdate
- ✅ Success log format optimized
- ✅ Error log format optimized
- ✅ Exception log format optimized
- ✅ Truncate helper function added
- ⏳ Ready untuk testing & push to GitHub
