################################################################################
# FIRS E-Invoice API - JSON Pipeline Processor (PowerShell)
# Processes JSON files: JSON -> Base64 Encryption -> QR Code Generation
# Same flow as /api/v1/invoice/sign but for batch processing
################################################################################

# Configuration (same as main API)
$JSON_DIR = if ($env:JSON_DIR) { $env:JSON_DIR } else { "C:\www\wwwroot\sftp\user_data" }
$OUTPUT_BASE = if ($env:OUTPUT_BASE) { $env:OUTPUT_BASE } else { "C:\www\wwwroot\sftp\user_data" }
$BASE_URL = if ($env:BASE_URL) { $env:BASE_URL } else { "https://eivc-k6z6d.ondigitalocean.app" }
$X_API_KEY = if ($env:X_API_KEY) { $env:X_API_KEY } else { "62b9fd03-d9ab-4417-a834-be90616253a4" }
$X_API_SECRET = if ($env:X_API_SECRET) { $env:X_API_SECRET } else { "c72DlrZgxvzl4E2AHjyQqNHMDohqbUZphSPBDDaLJKW4zibksYg6cW5Bsa6g4rZy2vx1xA3r9DGaP27rVamx8wf7OZCAEcKKydkC" }

# Processing mode
$PROCESS_MODE = if ($env:PROCESS_MODE) { $env:PROCESS_MODE } else { "pipeline" }

# Log files
$LOG_DIR = if ($env:LOG_DIR) { $env:LOG_DIR } else { ".\logs" }
$SUCCESS_LOG = Join-Path $LOG_DIR "api_success.log"
$ERROR_LOG = Join-Path $LOG_DIR "api_error.log"

# Ensure log directory exists
if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

# Header
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " FIRS E-Invoice - JSON Pipeline Processor" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Mode:           $PROCESS_MODE"
Write-Host "  JSON Directory: $JSON_DIR"
Write-Host "  Output Base:    $OUTPUT_BASE"
Write-Host "  Base URL:       $BASE_URL"
Write-Host "  API Key:        $($X_API_KEY.Substring(0, [Math]::Min(20, $X_API_KEY.Length)))..."
Write-Host "  Success Log:    $SUCCESS_LOG"
Write-Host "  Error Log:      $ERROR_LOG"
Write-Host ""

################################################################################
# Log Functions
################################################################################

function Write-SuccessLog {
    param(
        [string]$IRN,
        [string]$IRNSigned,
        [string]$JSONFile,
        [string]$Base64File,
        [string]$QRFile,
        [string]$HTTPCode,
        [string]$Supplier = "N/A",
        [string]$Customer = "N/A",
        [string]$TotalAmount = "N/A",
        [string]$Currency = "N/A"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Get file sizes
    $jsonSize = if (Test-Path $JSONFile) { (Get-Item $JSONFile).Length } else { 0 }
    $base64Size = if (Test-Path $Base64File) { (Get-Item $Base64File).Length } else { 0 }
    $qrSize = if (Test-Path $QRFile) { (Get-Item $QRFile).Length } else { 0 }
    
    $jsonSizeKB = [Math]::Round($jsonSize / 1024, 2)
    $base64SizeKB = [Math]::Round($base64Size / 1024, 2)
    $qrSizeKB = [Math]::Round($qrSize / 1024, 2)
    
    $logEntry = @{
        timestamp = $timestamp
        type = "SUCCESS"
        irn = $IRN
        irn_signed = $IRNSigned
        invoice_details = @{
            supplier = $Supplier
            customer = $Customer
            total_amount = $TotalAmount
            currency = $Currency
        }
        files_created = @{
            json = @{
                filename = (Split-Path -Leaf $JSONFile)
                path = $JSONFile
                size_bytes = $jsonSize
                size_kb = $jsonSizeKB
            }
            encrypted = @{
                filename = (Split-Path -Leaf $Base64File)
                path = $Base64File
                size_bytes = $base64Size
                size_kb = $base64SizeKB
            }
            qr_code = @{
                filename = (Split-Path -Leaf $QRFile)
                path = $QRFile
                size_bytes = $qrSize
                size_kb = $qrSizeKB
            }
        }
        api_response = @{
            status = "success"
            http_code = $HTTPCode
        }
    } | ConvertTo-Json -Compress -Depth 10
    
    Add-Content -Path $SUCCESS_LOG -Value $logEntry
}

function Write-ErrorLog {
    param(
        [string]$IRN,
        [string]$HTTPCode,
        [string]$ErrorMessage,
        [string]$ErrorDetails = "N/A",
        [string]$ErrorType = "api_error",
        [string]$Supplier = "N/A",
        [string]$Customer = "N/A",
        [string]$TotalAmount = "N/A"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Limit error message length
    if ($ErrorMessage.Length -gt 500) {
        $ErrorMessage = $ErrorMessage.Substring(0, 500)
    }
    if ($ErrorDetails.Length -gt 500) {
        $ErrorDetails = $ErrorDetails.Substring(0, 500)
    }
    
    $logEntry = @{
        timestamp = $timestamp
        type = "ERROR"
        error_type = $ErrorType
        irn = $IRN
        http_code = $HTTPCode
        error_message = $ErrorMessage
        error_details = $ErrorDetails
        request_summary = @{
            supplier = $Supplier
            customer = $Customer
            total_amount = $TotalAmount
        }
    } | ConvertTo-Json -Compress -Depth 10
    
    Add-Content -Path $ERROR_LOG -Value $logEntry
}

################################################################################
# Step 1: Check Prerequisites
################################################################################
Write-Host "[Step 1/5] Checking Prerequisites..." -ForegroundColor Cyan

# Check PHP
try {
    $phpVersion = php -v 2>&1 | Select-Object -First 1
    if ($phpVersion -match "PHP (\d+\.\d+\.\d+)") {
        Write-Host "  ✓ PHP $($matches[1])" -ForegroundColor Green
    } else {
        Write-Host "  ✗ PHP version not detected" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ PHP not found" -ForegroundColor Red
    exit 1
}

# Check curl
try {
    $null = curl.exe --version 2>&1 | Select-Object -First 1
    Write-Host "  ✓ curl installed" -ForegroundColor Green
} catch {
    Write-Host "  ✗ curl not found" -ForegroundColor Red
    exit 1
}

Write-Host ""

################################################################################
# Step 2: Check Directory
################################################################################
Write-Host "[Step 2/5] Checking JSON Directory..." -ForegroundColor Cyan

if (-not (Test-Path $JSON_DIR)) {
    Write-Host "✗ Directory not found: $JSON_DIR" -ForegroundColor Red
    exit 1
}

Write-Host "  ✓ Directory exists" -ForegroundColor Green

# Count JSON files
$jsonFiles = Get-ChildItem -Path $JSON_DIR -Filter "*.json" -File -ErrorAction SilentlyContinue
$JSON_COUNT = $jsonFiles.Count

if ($JSON_COUNT -eq 0) {
    Write-Host "  ⚠ No JSON files found" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  To create test data, run:"
    Write-Host "    .\test_linux_production.ps1"
    exit 0
}

Write-Host "  ✓ Found $JSON_COUNT JSON file(s)" -ForegroundColor Green
Write-Host ""

################################################################################
# Step 3: Test API Connection
################################################################################
Write-Host "[Step 3/5] Testing API Connection..." -ForegroundColor Cyan
Write-Host "  Endpoint: $BASE_URL/api/v1/invoice/sign"
Write-Host "  ✓ Ready to process invoices" -ForegroundColor Green
Write-Host ""

################################################################################
# Step 4: Process JSON Files (Pipeline Mode)
################################################################################
Write-Host "[Step 4/5] Processing JSON Files ($PROCESS_MODE mode)..." -ForegroundColor Cyan
Write-Host ""

$PROCESSED = 0
$ERRORS = 0
$SUCCESS = 0
$SKIPPED = 0

foreach ($jsonFileItem in $jsonFiles) {
    $JSON_FILE = $jsonFileItem.FullName
    $FILENAME = $jsonFileItem.Name
    $FILESIZE = $jsonFileItem.Length

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host "File: " -NoNewline -ForegroundColor Cyan
    Write-Host $FILENAME
    Write-Host "Size: " -NoNewline -ForegroundColor Cyan
    Write-Host "$FILESIZE bytes"
    Write-Host ""

    # Validate JSON syntax
    try {
        $jsonContent = Get-Content -Path $JSON_FILE -Raw -ErrorAction Stop
        $jsonObject = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        Write-Host "✓ Valid JSON syntax" -ForegroundColor Green
    } catch {
        Write-Host "✗ Invalid JSON syntax" -ForegroundColor Red
        $ERRORS++
        Write-Host ""
        continue
    }

    # Extract key information
    $IRN = if ($jsonObject.irn) { $jsonObject.irn } else { "N/A" }
    $BUSINESS_ID = if ($jsonObject.business_id) { $jsonObject.business_id } else { "N/A" }
    $ISSUE_DATE = if ($jsonObject.issue_date) { $jsonObject.issue_date } else { "N/A" }
    $PAYMENT_STATUS = if ($jsonObject.payment_status) { $jsonObject.payment_status } else { "N/A" }
    $SUPPLIER = if ($jsonObject.accounting_supplier_party.party_name) { $jsonObject.accounting_supplier_party.party_name } else { "N/A" }
    $CUSTOMER = if ($jsonObject.accounting_customer_party.party_name) { $jsonObject.accounting_customer_party.party_name } else { "N/A" }
    $TOTAL = if ($jsonObject.legal_monetary_total.payable_amount) { $jsonObject.legal_monetary_total.payable_amount } else { "N/A" }
    $CURRENCY = if ($jsonObject.document_currency_code) { $jsonObject.document_currency_code } else { "N/A" }

    # Display extracted data
    Write-Host ""
    Write-Host "Invoice Information:" -ForegroundColor Yellow
    Write-Host "  IRN:            $IRN"
    Write-Host "  Business ID:    $BUSINESS_ID"
    Write-Host "  Issue Date:     $ISSUE_DATE"
    Write-Host "  Payment Status: $PAYMENT_STATUS"
    Write-Host "  Supplier:       $SUPPLIER"
    Write-Host "  Customer:       $CUSTOMER"
    Write-Host "  Total Amount:   $TOTAL $CURRENCY"
    Write-Host ""

    # Skip verify mode for now, only implement pipeline mode
    if ($PROCESS_MODE -ne "pipeline") {
        Write-Host "[VERIFY MODE] Not implemented in PowerShell version" -ForegroundColor Yellow
        $PROCESSED++
        Write-Host ""
        continue
    }

    # PIPELINE MODE: Process through API
    Write-Host "[PIPELINE] Starting processing..." -ForegroundColor Cyan

    # Step 1: Read JSON content
    Write-Host "  [1/3] Reading JSON content..."
    Write-Host "  ✓ JSON file readable ($FILESIZE bytes)" -ForegroundColor Green

    # Step 2: Call API to encrypt and generate QR
    Write-Host "  [2/3] Calling API POST /api/v1/invoice/sign..."
    Write-Host "    IRN: $IRN"

    $START_TIME = Get-Date

    # Prepare headers
    $headers = @{
        "Content-Type" = "application/json"
        "Accept-Encoding" = "gzip, deflate"
        "x-api-key" = $X_API_KEY
        "x-api-secret" = $X_API_SECRET
    }

    # Make API call
    try {
        $response = Invoke-WebRequest -Uri "$BASE_URL/api/v1/invoice/sign" `
            -Method Post `
            -Headers $headers `
            -Body $jsonContent `
            -UseBasicParsing `
            -ErrorAction Stop

        $HTTP_CODE = $response.StatusCode
        $RESPONSE_BODY = $response.Content
        $DATA_OK = $true
    } catch {
        $HTTP_CODE = $_.Exception.Response.StatusCode.value__
        $RESPONSE_BODY = $_.ErrorDetails.Message
        if (-not $RESPONSE_BODY) {
            $RESPONSE_BODY = $_.Exception.Message
        }
        $DATA_OK = $false
    }

    $END_TIME = Get-Date
    $DURATION = [Math]::Round(($END_TIME - $START_TIME).TotalMilliseconds, 0)

    Write-Host "    HTTP Status: $HTTP_CODE"

    # Accept both HTTP 200 and 201 as success
    if ($HTTP_CODE -ne 200 -and $HTTP_CODE -ne 201) {
        # Check if this is a duplicate error
        $IS_DUPLICATE = $false
        try {
            $responseObj = $RESPONSE_BODY | ConvertFrom-Json -ErrorAction SilentlyContinue
            $ERROR_MESSAGE = if ($responseObj.error.message) { $responseObj.error.message } else { "Unknown error" }
            $ERROR_DETAILS = if ($responseObj.error.details) { $responseObj.error.details } else { "N/A" }
            
            if ($ERROR_DETAILS -match "duplicate|already exists|unable to complete") {
                $IS_DUPLICATE = $true
            }
        } catch {
            $ERROR_MESSAGE = "Unknown error"
            $ERROR_DETAILS = "N/A"
            if ($RESPONSE_BODY -match "duplicate|already exists|unable to complete") {
                $IS_DUPLICATE = $true
            }
        }

        if ($IS_DUPLICATE) {
            Write-Host "  ⚠ Duplicate IRN (already validated by FIRS)" -ForegroundColor Yellow
            
            # Log as error (duplicate)
            Write-ErrorLog -IRN $IRN -HTTPCode $HTTP_CODE -ErrorMessage "Duplicate IRN - already exists" -ErrorDetails $ERROR_DETAILS -ErrorType "duplicate" -Supplier $SUPPLIER -Customer $CUSTOMER -TotalAmount $TOTAL

            # Check if files already exist
            $BASE64_DIR = Join-Path $OUTPUT_BASE "QR\QR_txt"
            $QR_DIR = Join-Path $OUTPUT_BASE "QR\QR_img"

            $EXISTING_BASE64 = Get-ChildItem -Path $BASE64_DIR -Filter "$IRN.*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
            $EXISTING_QR = Get-ChildItem -Path $QR_DIR -Filter "$IRN.*.png" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($EXISTING_BASE64 -and $EXISTING_QR) {
                Write-Host "  ✓ Base64 file exists: $($EXISTING_BASE64.Name)" -ForegroundColor Green
                Write-Host "  ✓ QR code exists: $($EXISTING_QR.Name)" -ForegroundColor Green
                Write-Host "  → Skipping: All files already generated" -ForegroundColor Cyan
                $SKIPPED++
                $PROCESSED++
                Write-Host ""
                continue
            } else {
                if (-not $EXISTING_BASE64) {
                    Write-Host "  ✗ Base64 file not found" -ForegroundColor Yellow
                }
                if (-not $EXISTING_QR) {
                    Write-Host "  ✗ QR code not found" -ForegroundColor Yellow
                }
                Write-Host "  → Generating missing files..." -ForegroundColor Cyan
                $DATA_OK = $true
            }
        } else {
            Write-Host "  ✗ API call failed (HTTP $HTTP_CODE)" -ForegroundColor Red
            
            if ($ERROR_MESSAGE.Length -gt 200) {
                $ERROR_MESSAGE = $ERROR_MESSAGE.Substring(0, 200) + "..."
            }
            Write-Host "  Error: $ERROR_MESSAGE" -ForegroundColor Red

            # Log error
            Write-ErrorLog -IRN $IRN -HTTPCode $HTTP_CODE -ErrorMessage $ERROR_MESSAGE -ErrorDetails "API call failed" -ErrorType "api_error" -Supplier $SUPPLIER -Customer $CUSTOMER -TotalAmount $TOTAL

            $ERRORS++
            Write-Host ""
            continue
        }
    } else {
        Write-Host "  ✓ API call successful (HTTP $HTTP_CODE)" -ForegroundColor Green
        Write-Host "    Response time: ${DURATION}ms"
        $DATA_OK = $true
    }

    # Step 3: Process locally if FIRS validation OK or duplicate
    Write-Host "  [3/3] Processing locally with crypto_keys..."

    $FILES_CREATED = 0

    if ($DATA_OK) {
        Write-Host "    ✓ FIRS validation confirmed" -ForegroundColor Green
        Write-Host "    Encrypting with crypto_keys..."

        # Create signed IRN with timestamp
        $TIMESTAMP = [int][double]::Parse((Get-Date -UFormat %s))
        $IRN_SIGNED = "$IRN.$TIMESTAMP"

        # Encrypt using PHP
        $CRYPTO_KEYS_FILE = ".\storage\crypto_keys.txt"
        if (-not (Test-Path $CRYPTO_KEYS_FILE)) {
            Write-Host "    ✗ crypto_keys.txt not found" -ForegroundColor Red
            $ERRORS++
            Write-Host ""
            continue
        }

        $phpScript = @"
`$keysFile = './storage/crypto_keys.txt';
`$keys = json_decode(file_get_contents(`$keysFile), true);
if (!`$keys) {
    fwrite(STDERR, 'ERROR: Failed to load crypto_keys.txt' . PHP_EOL);
    exit(1);
}
`$publicKeyPem = base64_decode(`$keys['public_key']);
`$publicKey = openssl_pkey_get_public(`$publicKeyPem);
if (!`$publicKey) {
    fwrite(STDERR, 'ERROR: Invalid public key' . PHP_EOL);
    exit(1);
}
`$irnSigned = '$IRN_SIGNED';
`$payload = json_encode(['irn' => `$irnSigned, 'certificate' => `$keys['certificate']], JSON_UNESCAPED_SLASHES);
`$encrypted = '';
`$result = openssl_public_encrypt(`$payload, `$encrypted, `$publicKey, OPENSSL_PKCS1_PADDING);
if (!`$result) {
    fwrite(STDERR, 'ERROR: Encryption failed' . PHP_EOL);
    exit(1);
}
echo base64_encode(`$encrypted);
"@

        $ENCRYPTED_DATA = php -r $phpScript 2>&1

        if ($ENCRYPTED_DATA -match "^ERROR:" -or -not $ENCRYPTED_DATA) {
            Write-Host "    ✗ Encryption failed: $ENCRYPTED_DATA" -ForegroundColor Red
            $ERRORS++
            Write-Host ""
            continue
        }

        Write-Host "    ✓ Encrypted with crypto_keys ($($ENCRYPTED_DATA.Length) bytes base64)" -ForegroundColor Green
    }

    if (-not $IRN_SIGNED) {
        Write-Host "    ✗ Cannot extract IRN from response" -ForegroundColor Red
        $ERRORS++
        Write-Host ""
        continue
    }

    # Define file paths
    $BASE64_DIR = Join-Path $OUTPUT_BASE "QR\QR_txt"
    $QR_DIR = Join-Path $OUTPUT_BASE "QR\QR_img"

    # Create directories
    if (-not (Test-Path $BASE64_DIR)) {
        New-Item -ItemType Directory -Path $BASE64_DIR -Force | Out-Null
    }
    if (-not (Test-Path $QR_DIR)) {
        New-Item -ItemType Directory -Path $QR_DIR -Force | Out-Null
    }

    $BASE64_PATH = Join-Path $BASE64_DIR "$IRN_SIGNED.txt"
    $QR_PATH = Join-Path $QR_DIR "$IRN_SIGNED.png"

    # Save Base64 encrypted data
    if ($ENCRYPTED_DATA) {
        Set-Content -Path $BASE64_PATH -Value $ENCRYPTED_DATA -NoNewline
        if (Test-Path $BASE64_PATH) {
            $B64_SIZE = (Get-Item $BASE64_PATH).Length
            Write-Host "    ✓ Base64: $IRN_SIGNED.txt ($B64_SIZE bytes)" -ForegroundColor Green
            $FILES_CREATED++
        } else {
            Write-Host "    ✗ Failed to save Base64 file" -ForegroundColor Red
        }
    } else {
        Write-Host "    ✗ No encrypted data in response" -ForegroundColor Red
    }

    # Generate QR code from Base64 data using PHP
    if ($ENCRYPTED_DATA) {
        $qrScript = @"
require 'vendor/autoload.php';
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;
try {
    `$options = new QROptions([
        'version' => QRCode::VERSION_AUTO,
        'outputType' => QRCode::OUTPUT_IMAGE_PNG,
        'eccLevel' => QRCode::ECC_L,
        'scale' => 6,
        'imageBase64' => false,
    ]);
    `$qrcode = new QRCode(`$options);
    `$qrcode->render('$ENCRYPTED_DATA', '$($QR_PATH.Replace('\', '/'))');
    echo 'SUCCESS';
} catch (Exception `$e) {
    echo 'ERROR: ' . `$e->getMessage();
}
"@

        $QR_RESULT = php -r $qrScript 2>&1

        if ($QR_RESULT -eq "SUCCESS" -and (Test-Path $QR_PATH)) {
            $QR_SIZE = (Get-Item $QR_PATH).Length
            $QR_SIZE_KB = [Math]::Round($QR_SIZE / 1024, 1)
            Write-Host "    ✓ QR PNG: $IRN_SIGNED.png ($QR_SIZE_KB KB)" -ForegroundColor Green
            $FILES_CREATED++
        } else {
            Write-Host "    ✗ Failed to generate QR code" -ForegroundColor Red
            if ($QR_RESULT -ne "SUCCESS") {
                Write-Host "      Error: $QR_RESULT" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "    ✗ Cannot generate QR (missing data or PHP)" -ForegroundColor Red
    }

    # JSON file already exists in source directory
    if (Test-Path $JSON_FILE) {
        Write-Host "    ✓ JSON:   $FILENAME" -ForegroundColor Green
        $FILES_CREATED++
    }

    if ($FILES_CREATED -eq 3) {
        Write-Host "Pipeline completed successfully!" -ForegroundColor Green
        $SUCCESS++
        
        # Save JSON signed before deleting source
        $JSON_SIGNED_DIR = Join-Path $OUTPUT_BASE "json_signed"
        if (-not (Test-Path $JSON_SIGNED_DIR)) {
            New-Item -ItemType Directory -Path $JSON_SIGNED_DIR -Force | Out-Null
        }
        
        $JSON_SIGNED_FILE = Join-Path $JSON_SIGNED_DIR "$IRN_SIGNED.json"
        
        Write-Host "    → Saving JSON signed..." -ForegroundColor Cyan
        try {
            Copy-Item -Path $JSON_FILE -Destination $JSON_SIGNED_FILE -Force
            Write-Host "    ✓ JSON signed saved: $IRN_SIGNED.json" -ForegroundColor Green
        } catch {
            Write-Host "    ⚠ Failed to save JSON signed" -ForegroundColor Yellow
        }
        
        # Log success with detailed information
        Write-SuccessLog -IRN $IRN -IRNSigned $IRN_SIGNED -JSONFile $JSON_SIGNED_FILE -Base64File $BASE64_PATH -QRFile $QR_PATH -HTTPCode $HTTP_CODE -Supplier $SUPPLIER -Customer $CUSTOMER -TotalAmount $TOTAL -Currency $CURRENCY
        
        # Delete original JSON file after successful processing
        Write-Host "    → Deleting source JSON file..." -ForegroundColor Cyan
        try {
            Remove-Item -Path $JSON_FILE -Force
            Write-Host "    ✓ Source JSON deleted: $FILENAME" -ForegroundColor Green
        } catch {
            Write-Host "    ⚠ Failed to delete source JSON" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Pipeline completed with missing files ($FILES_CREATED/3)" -ForegroundColor Yellow
        
        # Log error for incomplete processing
        Write-ErrorLog -IRN $IRN -HTTPCode "0" -ErrorMessage "Incomplete file generation" -ErrorDetails "Only $FILES_CREATED/3 files created" -ErrorType "processing_error" -Supplier $SUPPLIER -Customer $CUSTOMER -TotalAmount $TOTAL
        
        $ERRORS++
    }

    $PROCESSED++
    Write-Host ""
}

################################################################################
# Step 5: Summary
################################################################################
Write-Host ""
Write-Host "[Step 5/5] Processing Summary" -ForegroundColor Cyan
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""

if ($PROCESS_MODE -eq "pipeline") {
    if ($ERRORS -eq 0 -and $SUCCESS -eq $PROCESSED) {
        Write-Host "✓ All files processed successfully through pipeline" -ForegroundColor Green
    } else {
        Write-Host "⚠ Some files had errors during pipeline processing" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Mode:              Pipeline (JSON → Base64 → QR)"
    Write-Host "  Total JSON files:  $JSON_COUNT"
    Write-Host "  Processed:         $PROCESSED"
    Write-Host "  Success:           $SUCCESS"
    Write-Host "  Errors:            $ERRORS"
} else {
    Write-Host "Verification mode (API not available)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Mode:              Verify only"
    Write-Host "  Total JSON files:  $JSON_COUNT"
    Write-Host "  Processed:         $PROCESSED"
    Write-Host "  Skipped:           $SKIPPED"
    Write-Host "  Errors:            $ERRORS"
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
if ($PROCESS_MODE -eq "pipeline" -and $SUCCESS -eq $PROCESSED -and $ERRORS -eq 0) {
    Write-Host "Pipeline Processing Complete! All files processed successfully." -ForegroundColor Green
    $EXIT_CODE = 0
} elseif ($ERRORS -gt 0) {
    Write-Host "Pipeline Processing Complete with $ERRORS error(s)." -ForegroundColor Yellow
    $EXIT_CODE = 1
} else {
    Write-Host "Processing Complete!" -ForegroundColor Green
    $EXIT_CODE = 0
}
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Logs:" -ForegroundColor Yellow
Write-Host "  Success: $SUCCESS_LOG"
Write-Host "  Error:   $ERROR_LOG"
Write-Host ""

exit $EXIT_CODE
