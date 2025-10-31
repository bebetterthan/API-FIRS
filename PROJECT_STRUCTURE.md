# FIRS API - Clean Project Structure

## 📁 Essential Files Only

```
API FIRS/
├── 📄 Core Application
│   ├── index.php                          # Main API endpoint
│   ├── config.php                         # Configuration (DB, API, paths)
│   ├── .env                               # Environment variables (DB credentials)
│   ├── .env.example                       # Template untuk .env
│   └── .htaccess                          # Apache rewrite rules
│
├── 📂 classes/                            # Core PHP Classes
│   ├── ConfigCache.php                    # Configuration caching
│   ├── CryptoService.php                  # Encryption/decryption
│   ├── DatabaseLogger.php                 # Database logging (MSSQL)
│   ├── FileManager.php                    # File operations
│   ├── FIRSAPIClient.php                  # FIRS API client
│   ├── HSNCodeProvider.php                # HSN code validation
│   ├── InvoiceManager.php                 # Invoice management
│   ├── IRNProcessor.php                   # IRN processing
│   ├── LogManager.php                     # Dual logging (file + DB)
│   ├── QRGenerator.php                    # QR code generation
│   ├── ResponseBuilder.php                # API response builder
│   ├── Router.php                         # API routing
│   ├── SearchEngine.php                   # Search functionality
│   ├── SFTPManager.php                    # SFTP operations
│   └── Validator.php                      # Input validation
│
├── 📂 database/                           # Database Scripts
│   ├── check_config.php                   # Verify DB configuration
│   ├── create_logging_tables.sql          # Create log tables (simplified)
│   └── useful_queries.sql                 # Monitoring & analysis queries
│
├── 📂 logs/                               # Log Files
│   ├── .gitkeep                           # Keep folder in git
│   ├── api_success.log                    # Success logs (JSON)
│   └── api_error.log                      # Error logs (JSON)
│
├── 📂 output/                             # Generated Files
│   ├── QR/                                # QR codes output
│   └── qrcodes/                           # Alternative QR path
│
├── 📂 storage/                            # Data Storage
│   ├── crypto_keys.txt                    # Encryption keys (gitignored)
│   ├── crypto_keys.txt.example            # Template for keys
│   ├── hsn_codes.json                     # HSN code database
│   ├── invoice_index.json                 # Invoice index
│   ├── encrypted/                         # Encrypted invoice data
│   └── sftp_cache/                        # SFTP cache
│       ├── pending/                       # Pending files
│       └── processed/                     # Processed files
│
├── 📂 vendor/                             # Composer Dependencies
│   └── (auto-generated, don't edit)
│
├── 🧪 Test Scripts
│   ├── test_database_logging.php          # Test DB connection & logging
│   ├── test_process_json_files.ps1        # PowerShell batch processor
│   └── test_process_json_files.sh         # Bash batch processor
│
├── 📖 Documentation
│   ├── README.md                          # Main documentation
│   └── TEST_SCRIPTS_DATABASE_LOGGING.md   # Test script usage guide
│
└── ⚙️ Configuration Files
    ├── composer.json                      # PHP dependencies
    ├── composer.lock                      # Locked versions
    ├── .gitignore                         # Git ignore rules
    └── sample_invoice.json                # Sample invoice format
```

## ✅ Cleaned Files (Removed)

**Removed Setup Scripts:**
- ❌ `install_sqlsrv_extension.ps1` - No longer needed after setup
- ❌ `setup_database_logging.ps1` - No longer needed after setup

**Removed Test Scripts:**
- ❌ `test_odbc_connection.php` - Replaced by test_database_logging.php
- ❌ `test_pdo_sqlsrv.php` - Replaced by test_database_logging.php

**Removed Documentation:**
- ❌ `DATABASE_SETUP_COMPLETE.md` - Outdated, replaced by README.md

**Removed Backups:**
- ❌ `logs/api_error.log.backup` - Not needed in version control
- ❌ `logs/api_success.log.backup` - Not needed in version control

## 🚀 Quick Start

### 1. Configuration
```bash
# Copy environment file
cp .env.example .env

# Edit database credentials
nano .env
```

### 2. Database Setup
```bash
# Test connection
php database/check_config.php

# Create tables (via SSMS or sqlcmd)
sqlcmd -S 34.65.240.209 -U sqlserver -d firststaging -i database/create_logging_tables.sql
```

### 3. Test Database Logging
```bash
# Run test script
php test_database_logging.php
```

### 4. Process JSON Files (Batch)
```powershell
# PowerShell (Windows)
$env:JSON_DIR=".\storage"
.\test_process_json_files.ps1
```

```bash
# Bash (Linux)
export JSON_DIR="./storage"
bash test_process_json_files.sh
```

## 📊 Database Structure (Simplified)

### Success Logs
```sql
CREATE TABLE firs_success_logs (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME2 NOT NULL,
    irn VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at DATETIME2 DEFAULT GETDATE()
);
```

### Error Logs
```sql
CREATE TABLE firs_error_logs (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME2 NOT NULL,
    irn VARCHAR(255) NULL,
    http_code INT NULL,
    error_type VARCHAR(100) NULL,
    error_message NVARCHAR(MAX) NULL,
    error_details NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE()
);
```

## 🔍 Monitoring Queries

```sql
-- Recent logs
SELECT TOP 10 * FROM firs_success_logs ORDER BY timestamp DESC;
SELECT TOP 10 * FROM firs_error_logs ORDER BY timestamp DESC;

-- API Health (24 hours)
-- See database/useful_queries.sql for complete query
```

## 📝 API Endpoints

```
POST /api/v1/invoice/sign
POST /api/v1/invoice/cancel
GET  /api/v1/invoice/{irn}
GET  /api/v1/invoices
POST /api/v1/qr/generate
GET  /api/v1/hsn/{code}
```

## 🔐 Security

- ✅ `.env` file is gitignored
- ✅ `crypto_keys.txt` is gitignored
- ✅ SFTP credentials in .env only
- ✅ Database passwords encrypted in .env
- ✅ API keys secured with X-API-KEY and X-API-SECRET

## 📦 Dependencies (Composer)

```json
{
    "chillerlan/php-qrcode": "QR code generation",
    "league/flysystem-sftp-v3": "SFTP operations",
    "phpseclib/phpseclib": "SSH/SFTP security"
}
```

## 🎯 File Sizes (Optimized)

```
Config:        ~6 KB (config.php)
Classes:       ~50 KB total (14 files)
Database:      ~18 KB (3 SQL files)
Tests:         ~67 KB (3 test scripts)
Documentation: ~5 KB (2 MD files)
```

## 🛠️ Maintenance

### Clear Old Logs (Database)
```sql
-- See database/useful_queries.sql
-- Section 8: Data Retention & Cleanup
```

### Clear Old Logs (Files)
```bash
# Clear logs older than 30 days
find ./logs -name "*.log" -mtime +30 -delete
```

### Backup Database Logs
```bash
# Export to CSV (see useful_queries.sql Section 10)
```

---

**Project cleaned and optimized! ✨**
- Essential files only
- Professional structure
- Ready for production
- Easy to maintain
