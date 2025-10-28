# FIRS E-Invoice API - Production Test Script (PowerShell)
# Tests invoice signing with 3-file generation (JSON, Base64, QR)

$ErrorActionPreference = "Stop"

$BASE_URL = if ($env:BASE_URL) { $env:BASE_URL } else { "http://localhost" }
$API_KEY = if ($env:API_KEY) { $env:API_KEY } else { "test-key" }
$API_SECRET = if ($env:API_SECRET) { $env:API_SECRET } else { "test-secret" }
$OUTPUT_PATH = "C:\www\wwwroot\sftp\user_data"

$TIMESTAMP = [int][double]::Parse((Get-Date -UFormat %s))
$IRN = "PFNL0001-9D3009-$(Get-Date -Format 'yyyyMMdd')"
$SIGNED_IRN = "$IRN.$TIMESTAMP"

Write-Host ""
Write-Host "FIRS E-Invoice API - Production Test" -ForegroundColor Cyan
Write-Host "IRN: $IRN | Signed: $SIGNED_IRN"
Write-Host ""

Write-Host "[1/4] Checking Prerequisites..." -ForegroundColor Cyan

# Check PHP
try {
    $null = php -v 2>&1 | Select-Object -First 1
    Write-Host "PHP OK" -ForegroundColor Green
} catch {
    Write-Host "PHP not found" -ForegroundColor Red
    exit 1
}

# Check curl
try {
    $null = curl.exe --version 2>&1 | Select-Object -First 1
    Write-Host "curl OK" -ForegroundColor Green
} catch {
    Write-Host "curl not found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/4] Verifying Folders..." -ForegroundColor Cyan

# Create directories
$folders = @(
    (Join-Path $OUTPUT_PATH "json"),
    (Join-Path $OUTPUT_PATH "QR\QR_txt"),
    (Join-Path $OUTPUT_PATH "QR\QR_img")
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

Write-Host "Folders OK" -ForegroundColor Green

Write-Host ""
Write-Host "[3/4] Signing Invoice..." -ForegroundColor Cyan

$CURRENT_DATE = Get-Date -Format "yyyy-MM-dd"
$CURRENT_TIME = Get-Date -Format "HH:mm:ss"
$DUE_DATE = (Get-Date).AddDays(30).ToString("yyyy-MM-dd")

$invoiceJson = @"
{
  "business_id": "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
  "irn": "$IRN",
  "payment_status": "PAID",
  "issue_date": "$CURRENT_DATE",
  "issue_time": "$CURRENT_TIME",
  "due_date": "$DUE_DATE",
  "invoice_type_code": "380",
  "document_currency_code": "NGN",
  "tax_currency_code": "NGN",
  "accounting_supplier_party": {
    "id": "971cdc76-8f01-4d5c-b48f-297126b1e69b",
    "postal_address_id": "cd9e1ba4-ae36-4ead-b44d-951c7042a4f0",
    "party_name": "PF-DEV",
    "tin": "16069538-0001",
    "email": "sys@primerafood-nigeria.com",
    "telephone": "+2342342532",
    "postal_address": {
      "street_name": "Plot 4-6, Block I, Industrial 1",
      "city_name": "Agbara",
      "postal_zone": "110123",
      "country": "NG"
    }
  },
  "accounting_customer_party": {
    "id": "971cdc76-8f01-4d5c-b48f-297126b1e69b",
    "postal_address_id": "cd9e1ba4-ae36-4ead-b44d-951c7042a4f0",
    "party_name": "TEST CUSTOMER",
    "tin": "12345678-0001",
    "email": "customer@example.com",
    "telephone": "+2341234567",
    "postal_address": {
      "street_name": "123 Test Street",
      "city_name": "Lagos",
      "postal_zone": "100001",
      "country": "NG"
    }
  },
  "invoice_lines": [
    {
      "id": 1,
      "invoiced_quantity": 10,
      "line_extension_amount": 1000.00,
      "item": {
        "description": "Test Product",
        "name": "Test Item",
        "sellers_item_identification": {
          "id": "ITEM001"
        },
        "classified_tax_category": {
          "id": "S",
          "percent": 7.5,
          "tax_scheme": {
            "id": "VAT"
          }
        }
      },
      "price": {
        "price_amount": 100.00
      }
    }
  ],
  "tax_total": [
    {
      "tax_amount": 75.00,
      "tax_subtotal": [
        {
          "taxable_amount": 1000.00,
          "tax_amount": 75.00,
          "tax_category": {
            "id": "S",
            "percent": 7.5,
            "tax_scheme": {
              "id": "VAT"
            }
          }
        }
      ]
    }
  ],
  "legal_monetary_total": {
    "line_extension_amount": 1000.00,
    "tax_exclusive_amount": 1000.00,
    "tax_inclusive_amount": 1075.00,
    "payable_amount": 1075.00
  }
}
"@

# Save to temp file
$TEMP_FILE = Join-Path $env:TEMP "firs_test_$PID.json"
Set-Content -Path $TEMP_FILE -Value $invoiceJson

# Make API call
try {
    $headers = @{
        "Content-Type" = "application/json"
        "x-api-key" = $API_KEY
        "x-api-secret" = $API_SECRET
    }

    $response = Invoke-WebRequest -Uri "$BASE_URL/api/v1/invoice/sign" `
        -Method Post `
        -Headers $headers `
        -InFile $TEMP_FILE `
        -UseBasicParsing `
        -ErrorAction Stop

    $HTTP_CODE = $response.StatusCode
    $BODY = $response.Content

    Remove-Item -Path $TEMP_FILE -Force -ErrorAction SilentlyContinue

    if ($HTTP_CODE -ne 200) {
        Write-Host "FAILED (HTTP $HTTP_CODE)" -ForegroundColor Red
        Write-Host $BODY
        exit 1
    }

    Write-Host "Signed OK (HTTP $HTTP_CODE)" -ForegroundColor Green

} catch {
    Remove-Item -Path $TEMP_FILE -Force -ErrorAction SilentlyContinue
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Parse response
try {
    $responseObj = $BODY | ConvertFrom-Json
    $JSON_FILE = $responseObj.data.files.json
    $BASE64_FILE = $responseObj.data.files.encrypted
    $QR_FILE = $responseObj.data.files.qr_code
} catch {
    Write-Host "Failed to parse response" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/4] Verifying Files..." -ForegroundColor Cyan

$FILES_OK = 0

# Check JSON file
if ($JSON_FILE -and (Test-Path $JSON_FILE)) {
    $JSON_SIZE = (Get-Item $JSON_FILE).Length
    Write-Host "JSON:   $(Split-Path -Leaf $JSON_FILE) ($JSON_SIZE bytes)" -ForegroundColor Green
    $FILES_OK++
} else {
    Write-Host "JSON NOT FOUND" -ForegroundColor Red
}

# Check Base64 file
if ($BASE64_FILE -and (Test-Path $BASE64_FILE)) {
    $B64_SIZE = (Get-Item $BASE64_FILE).Length
    Write-Host "Base64: $(Split-Path -Leaf $BASE64_FILE) ($B64_SIZE bytes)" -ForegroundColor Green
    $FILES_OK++
} else {
    Write-Host "Base64 NOT FOUND" -ForegroundColor Red
}

# Check QR file
if ($QR_FILE -and (Test-Path $QR_FILE)) {
    $QR_SIZE = (Get-Item $QR_FILE).Length
    $QR_SIZE_KB = [Math]::Round($QR_SIZE / 1024, 1)
    Write-Host "QR PNG: $(Split-Path -Leaf $QR_FILE) ($QR_SIZE_KB KB)" -ForegroundColor Green
    $FILES_OK++
} else {
    Write-Host "QR PNG NOT FOUND" -ForegroundColor Red
}

Write-Host ""
if ($FILES_OK -eq 3) {
    Write-Host "ALL TESTS PASSED (3/3 files created)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "TEST FAILED ($FILES_OK/3 files created)" -ForegroundColor Red
    exit 1
}
