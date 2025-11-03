# Enhanced Logging System - Observability Refactoring

## Ringkasan Perubahan

Sistem logging telah direfaktorisasi untuk meningkatkan **observability** dan **debugging capability** dengan menambahkan tiga field baru:

1. **`handler`** - Identifikasi lokasi kode tempat error terjadi (misalnya: `ClassName::methodName`)
2. **`detailed_message`** - Pesan error teknis lengkap untuk internal debugging
3. **`public_message`** - Pesan error yang aman untuk ditampilkan ke user/client

---

## Perubahan pada File

### 1. LogManager.php

#### Method `logError()` - Signature Baru:

```php
public function logError(
    string $irn,
    int $httpCode,
    string $publicMessage,              // WAJIB: User-facing message
    ?string $detailedMessage = null,    // OPSIONAL: Technical details
    ?string $handler = null,            // OPSIONAL: Context (class::method)
    ?array $errorDetails = null,
    ?array $requestPayload = null,
    ?string $errorType = null
): void
```

**Perubahan Utama:**
- Parameter `$publicMessage` sekarang WAJIB dan di posisi ke-3
- Menambahkan `$detailedMessage` (opsional) untuk detail teknis
- Menambahkan `$handler` (opsional) untuk context
- Parameter lama `$errorMessage` diganti menjadi `$publicMessage`

#### Method `logException()` - Signature Baru:

```php
public function logException(
    string $irn,
    \Exception $exception,
    string $handler = 'unknown',        // Handler/context
    ?string $publicMessage = null,      // User-facing message
    ?array $additionalContext = null
): void
```

**Perubahan Utama:**
- Parameter `$context` diganti menjadi `$handler` (lebih deskriptif)
- Menambahkan `$publicMessage` (opsional, default: generic message)
- Otomatis membuat `detailed_message` dari exception details

---

### 2. DatabaseLogger.php

#### Method `logError()` - Update Database Insert:

```php
public function logError(array $logData): bool
```

**Perubahan:**
- Menambahkan kolom `handler`, `detailed_message`, `public_message` pada INSERT statement
- Mendukung parameter baru dari LogManager

---

### 3. Database Schema

#### File: `create_logging_tables.sql`

Tabel `firs_error_logs` sekarang memiliki kolom tambahan:

```sql
CREATE TABLE dbo.firs_error_logs (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME2 NOT NULL,
    irn VARCHAR(255) NULL,
    http_code INT NULL,
    error_type VARCHAR(100) NULL,
    handler VARCHAR(255) NULL,              -- BARU
    detailed_message NVARCHAR(MAX) NULL,    -- BARU
    public_message NVARCHAR(1000) NULL,     -- BARU
    error_details NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    -- Indexes...
);
```

#### File: `migrate_add_observability_fields.sql`

Migration script untuk update database yang sudah ada:
- Menambahkan 3 kolom baru tanpa merusak data existing
- Menambahkan index pada kolom `handler`
- Aman untuk dijalankan multiple times (idempotent)

---

## Contoh Penggunaan

### Contoh 1: API Error dengan Context Lengkap

```php
try {
    $apiResponse = callExternalAPI($invoiceData);

    if ($apiResponse['status'] !== 'success') {
        $logManager->logError(
            irn: 'INV-2025-001',
            httpCode: 400,
            publicMessage: 'Pembayaran gagal karena dana tidak mencukupi.',
            detailedMessage: "Payment gateway rejected. API Response: {$apiResponse['message']} | Error Code: {$apiResponse['code']} | Trace ID: {$apiResponse['trace_id']}",
            handler: 'PaymentService::processPayment',
            errorDetails: ['api_response' => $apiResponse],
            requestPayload: $invoiceData,
            errorType: 'api_error'
        );
    }
} catch (\Exception $e) {
    // Exception handling otomatis
}
```

### Contoh 2: Validation Error

```php
$missingFields = ['supplier_name', 'customer_name'];

$logManager->logError(
    irn: 'INV-2025-002',
    httpCode: 422,
    publicMessage: 'Data invoice tidak lengkap. Harap periksa kembali formulir Anda.',
    detailedMessage: "Validation failed. Missing fields: " . implode(', ', $missingFields),
    handler: 'InvoiceValidator::validateRequired',
    errorType: 'validation_error'
);
```

### Contoh 3: Exception dengan Context

```php
try {
    $encrypted = encryptFile($filePath);
} catch (\Exception $e) {
    $logManager->logException(
        irn: 'INV-2025-003',
        exception: $e,
        handler: 'CryptoService::encryptInvoiceFile',
        publicMessage: 'Gagal mengenkripsi file invoice.',
        additionalContext: ['file_path' => $filePath, 'file_size' => filesize($filePath)]
    );
}
```

---

## Format Log Output Baru

### File Log (JSON):

```json
{
  "timestamp": "2025-11-04 10:30:45",
  "type": "ERROR",
  "error_type": "api_error",
  "http_code": 400,
  "irn": "INV-2025-001",
  "handler": "PaymentService::processPayment",
  "detailed_message": "Payment gateway rejected transaction. API Response: Insufficient Funds | Error Code: INSUF_FUNDS | Trace ID: TXN-xyz789",
  "public_message": "Pembayaran gagal karena dana tidak mencukupi.",
  "business_id": "BUS-123",
  "supplier": "PT Supplier Indonesia",
  "customer": "PT Customer Indonesia",
  "amount": 1500000,
  "currency": "IDR"
}
```

### Database Record:

| Column | Value |
|--------|-------|
| timestamp | 2025-11-04 10:30:45 |
| irn | INV-2025-001 |
| http_code | 400 |
| error_type | api_error |
| **handler** | **PaymentService::processPayment** |
| **detailed_message** | **Payment gateway rejected...** |
| **public_message** | **Pembayaran gagal karena...** |
| error_details | {"api_response": {...}} |

---

## Migration Steps

### Untuk Database yang Sudah Ada:

1. **Backup database terlebih dahulu**

2. **Jalankan migration script:**
   ```sql
   -- Di SQL Server Management Studio atau Azure Data Studio
   -- Buka file: database/migrate_add_observability_fields.sql
   -- Execute script
   ```

3. **Verifikasi kolom baru:**
   ```sql
   SELECT TOP 5 * FROM firs_error_logs
   ORDER BY created_at DESC;
   ```

### Untuk Database Baru:

1. **Jalankan schema creation:**
   ```sql
   -- Buka file: database/create_logging_tables.sql
   -- Execute script
   ```

---

## Breaking Changes & Backward Compatibility

### ⚠️ Breaking Changes:

1. **LogManager::logError()**
   - Parameter ke-3 sekarang adalah `$publicMessage` (WAJIB)
   - Parameter `$errorMessage` lama DIHAPUS

2. **LogManager::logException()**
   - Parameter `$context` diganti dengan `$handler`

### 🔄 Migration Path untuk Kode yang Ada:

#### Before (Old):
```php
$logManager->logError(
    $irn,
    $httpCode,
    $errorMessage,  // ❌ Parameter ini berubah
    $errorDetails,
    $requestPayload,
    $errorType
);
```

#### After (New):
```php
$logManager->logError(
    $irn,
    $httpCode,
    $errorMessage,      // ✅ Sekarang sebagai publicMessage
    $errorMessage,      // ✅ Duplicate sebagai detailedMessage (temporary)
    'UnknownHandler',   // ✅ Tambahkan handler
    $errorDetails,
    $requestPayload,
    $errorType
);
```

**Recommended:** Update semua pemanggilan untuk memanfaatkan field baru dengan benar.

---

## Query Examples

### 1. Cari Error Berdasarkan Handler:

```sql
SELECT TOP 10
    timestamp,
    irn,
    handler,
    public_message,
    detailed_message
FROM firs_error_logs
WHERE handler = 'PaymentService::processPayment'
ORDER BY timestamp DESC;
```

### 2. Analisis Error Type per Handler:

```sql
SELECT
    handler,
    error_type,
    COUNT(*) as error_count,
    MAX(timestamp) as last_occurrence
FROM firs_error_logs
WHERE timestamp >= DATEADD(day, -7, GETDATE())
GROUP BY handler, error_type
ORDER BY error_count DESC;
```

### 3. Public Messages yang Paling Sering Muncul:

```sql
SELECT TOP 10
    public_message,
    COUNT(*) as occurrence_count,
    MIN(timestamp) as first_seen,
    MAX(timestamp) as last_seen
FROM firs_error_logs
WHERE timestamp >= DATEADD(day, -30, GETDATE())
GROUP BY public_message
ORDER BY occurrence_count DESC;
```

---

## Benefits

### 🎯 Improved Observability:
- **Cepat identifikasi lokasi error** dengan field `handler`
- **Detail teknis lengkap** untuk debugging di `detailed_message`
- **Pesan user-friendly** siap pakai di `public_message`

### 🔍 Better Debugging:
- Stack trace dan error details terpisah dari public message
- Context data yang lebih kaya
- Mudah filter error berdasarkan module/class

### 🛡️ Security:
- Pesan internal tidak bocor ke client
- `public_message` sudah di-sanitize
- `detailed_message` hanya untuk internal team

### 📊 Analytics:
- Analisis error pattern per handler
- Track error frequency per module
- Monitoring error trends

---

## Testing

File example tersedia di: `examples/enhanced_logging_usage.php`

Jalankan testing:

```bash
cd "c:\Users\iroel\Documents\API FIRS"
php examples/enhanced_logging_usage.php
```

---

## Troubleshooting

### Issue: Error "Too few arguments to function logError()"

**Cause:** Kode lama masih menggunakan signature lama

**Solution:** Update pemanggilan function dengan menambahkan parameter `publicMessage`:

```php
// Temporary fix
$logManager->logError(
    $irn,
    $httpCode,
    $oldErrorMessage,           // Use as publicMessage
    $oldErrorMessage,           // Duplicate as detailedMessage
    'UpdateHandler::method',    // Add handler
    // ... rest of parameters
);
```

### Issue: Database error "Invalid column name 'handler'"

**Cause:** Database belum di-migrate

**Solution:** Jalankan migration script:
```sql
-- Run: database/migrate_add_observability_fields.sql
```

---

## Referensi File

- **LogManager.php** - Main logging class (refactored)
- **DatabaseLogger.php** - Database persistence (updated)
- **create_logging_tables.sql** - Fresh database schema
- **migrate_add_observability_fields.sql** - Migration for existing database
- **enhanced_logging_usage.php** - Usage examples

---

## Next Steps

1. ✅ Review dan test perubahan
2. ⚠️ Update semua pemanggilan `logError()` dan `logException()` di codebase
3. 🗄️ Jalankan database migration di environment yang sesuai
4. 📝 Update API documentation dengan format error baru
5. 🔄 Deploy ke staging untuk integration testing

---

Dokumen ini dibuat pada: **2025-11-04**
Versi: **2.0**
