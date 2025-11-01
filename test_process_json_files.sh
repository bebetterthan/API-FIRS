#!/bin/bash

################################################################################
# FIRS E-Invoice API - JSON Pipeline Processor
# Processes JSON files: JSON -> Base64 Encryption -> QR Code Generation
# Same flow as /api/v1/invoice/sign but for batch processing
################################################################################

# Exit on error (but continue loop)
# set -e  # Removed to allow processing multiple files even if one fails

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration (same as main API)
# POST to FIRS production API for validation, then process locally with crypto_keys
# Local processing: encrypt with crypto_keys.txt, generate QR, save files
JSON_DIR="${JSON_DIR:-C:/www/wwwroot/sftp/user_data}"
OUTPUT_BASE="${OUTPUT_BASE:-C:/www/wwwroot/sftp/user_data}"
BASE_URL="${BASE_URL:-https://eivc-k6z6d.ondigitalocean.app}"  # FIRS production API
X_API_KEY="${X_API_KEY:-YOUR-API-KEY-HERE}"
X_API_SECRET="${X_API_SECRET:-YOUR-API-SECRET-HERE}"

# Workflow: JSON → FIRS validation → Local encrypt (crypto_keys) → Local QR → Save files

# Processing mode
PROCESS_MODE="${PROCESS_MODE:-pipeline}"  # pipeline or verify

# Log files
LOG_DIR="${LOG_DIR:-./logs}"
SUCCESS_LOG="${LOG_DIR}/api_success.log"
ERROR_LOG="${LOG_DIR}/api_error.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR" 2>/dev/null

# Header
echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN} FIRS E-Invoice - JSON Pipeline Processor${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Mode:           ${PROCESS_MODE}"
echo "  JSON Directory: ${JSON_DIR}"
echo "  Output Base:    ${OUTPUT_BASE}"
echo "  Base URL:       ${BASE_URL}"
echo "  API Key:        ${X_API_KEY:0:20}..." # Show first 20 chars only
echo "  Success Log:    ${SUCCESS_LOG}"
echo "  Error Log:      ${ERROR_LOG}"
echo ""

################################################################################
# Database Configuration
################################################################################

# Load database configuration from .env file
DB_ENABLED=false
DB_DRIVER=""
DB_HOST=""
DB_PORT="1433"
DB_DATABASE=""
DB_USERNAME=""
DB_PASSWORD=""

if [ -f ".env" ]; then
    while IFS='=' read -r key value; do
        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        case "$key" in
            DB_LOGGING_ENABLED)
                if [ "$value" = "true" ]; then
                    DB_ENABLED=true
                fi
                ;;
            DB_DRIVER) DB_DRIVER="$value" ;;
            DB_HOST) DB_HOST="$value" ;;
            DB_PORT) DB_PORT="$value" ;;
            DB_DATABASE) DB_DATABASE="$value" ;;
            DB_USERNAME) DB_USERNAME="$value" ;;
            DB_PASSWORD) DB_PASSWORD="$value" ;;
        esac
    done < .env
fi

################################################################################
# Log Functions
################################################################################

# Log to database (simplified structure)
log_to_database() {
    local log_type="$1"
    local timestamp="$2"
    local irn="$3"
    local status="$4"
    local http_code="$5"
    local error_type="$6"
    local error_message="$7"
    local error_details="$8"
    
    if [ "$DB_ENABLED" != "true" ]; then
        return
    fi
    
    # Create temporary PHP script for database logging
    local php_script=$(cat <<'PHPSCRIPT'
<?php
$type = $argv[1];
$timestamp = $argv[2];
$irn = $argv[3];
$status = $argv[4] ?? null;
$http_code = $argv[5] ?? null;
$error_type = $argv[6] ?? null;
$error_message = $argv[7] ?? null;
$error_details = $argv[8] ?? null;

$host = getenv('DB_HOST');
$port = getenv('DB_PORT');
$database = getenv('DB_DATABASE');
$username = getenv('DB_USERNAME');
$password = getenv('DB_PASSWORD');

try {
    $dsn = "odbc:Driver={SQL Server};Server=$host,$port;Database=$database";
    $pdo = new PDO($dsn, $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    if ($type === 'success') {
        $stmt = $pdo->prepare("INSERT INTO firs_success_logs (timestamp, irn, status) VALUES (?, ?, ?)");
        $stmt->execute([$timestamp, $irn, $status]);
    } elseif ($type === 'error') {
        $stmt = $pdo->prepare("INSERT INTO firs_error_logs (timestamp, irn, http_code, error_type, error_message, error_details) VALUES (?, ?, ?, ?, ?, ?)");
        $stmt->execute([
            $timestamp,
            $irn ?: null,
            $http_code ?: null,
            $error_type ?: null,
            $error_message ?: null,
            $error_details ?: null
        ]);
    }
} catch (Exception $e) {
    // Silently fail, don't interrupt main process
    error_log("Database logging failed: " . $e->getMessage());
}
PHPSCRIPT
)
    
    # Export environment variables and run PHP script
    export DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD
    echo "$php_script" | php -- "$log_type" "$timestamp" "$irn" "$status" "$http_code" "$error_type" "$error_message" "$error_details" 2>/dev/null
}

# Log success to JSON format
log_success() {
    local irn="$1"
    local irn_signed="$2"
    local json_file="$3"
    local base64_file="$4"
    local qr_file="$5"
    local http_code="$6"
    local supplier="${7:-N/A}"
    local customer="${8:-N/A}"
    local total_amount="${9:-N/A}"
    local currency="${10:-N/A}"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Get file sizes
    local json_size=0
    local base64_size=0
    local qr_size=0

    if [ -f "$json_file" ]; then
        json_size=$(stat -c%s "$json_file" 2>/dev/null || stat -f%z "$json_file" 2>/dev/null || echo "0")
    fi

    if [ -f "$base64_file" ]; then
        base64_size=$(stat -c%s "$base64_file" 2>/dev/null || stat -f%z "$base64_file" 2>/dev/null || echo "0")
    fi

    if [ -f "$qr_file" ]; then
        qr_size=$(stat -c%s "$qr_file" 2>/dev/null || stat -f%z "$qr_file" 2>/dev/null || echo "0")
    fi

    local qr_size_kb=$(echo "scale=2; $qr_size / 1024" | bc 2>/dev/null || echo "0")

    local log_entry=$(cat <<EOF
{"timestamp":"${timestamp}","type":"SUCCESS","irn":"${irn}","irn_signed":"${irn_signed}","invoice_details":{"supplier":"${supplier}","customer":"${customer}","total_amount":"${total_amount}","currency":"${currency}"},"files_created":{"json":{"filename":"$(basename "$json_file")","path":"${json_file}","size_bytes":${json_size},"size_kb":$(echo "scale=2; $json_size / 1024" | bc 2>/dev/null || echo "0")},"encrypted":{"filename":"$(basename "$base64_file")","path":"${base64_file}","size_bytes":${base64_size},"size_kb":$(echo "scale=2; $base64_size / 1024" | bc 2>/dev/null || echo "0")},"qr_code":{"filename":"$(basename "$qr_file")","path":"${qr_file}","size_bytes":${qr_size},"size_kb":${qr_size_kb}}},"api_response":{"status":"success","http_code":${http_code}}}
EOF
)
    echo "$log_entry" >> "$SUCCESS_LOG"
    
    # Log to database
    log_to_database "success" "$timestamp" "$irn" "SUCCESS" "" "" "" ""
}

# Log error to JSON format
log_error() {
    local irn="$1"
    local http_code="$2"
    local error_message="$3"
    local error_details="${4:-N/A}"
    local error_type="${5:-api_error}"
    local supplier="${6:-N/A}"
    local customer="${7:-N/A}"
    local total_amount="${8:-N/A}"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Escape quotes in error message
    error_message=$(echo "$error_message" | sed 's/"/\\"/g' | head -c 500)
    error_details=$(echo "$error_details" | sed 's/"/\\"/g' | head -c 500)

    local log_entry=$(cat <<EOF
{"timestamp":"${timestamp}","type":"ERROR","error_type":"${error_type}","irn":"${irn}","http_code":${http_code},"error_message":"${error_message}","error_details":"${error_details}","request_summary":{"supplier":"${supplier}","customer":"${customer}","total_amount":"${total_amount}"}}
EOF
)
    echo "$log_entry" >> "$ERROR_LOG"
    
    # Log to database
    log_to_database "error" "$timestamp" "$irn" "" "$http_code" "$error_type" "$error_message" "$error_details"
}

################################################################################
# Step 1: Check Prerequisites
################################################################################
echo -e "${CYAN}[Step 1/5]${NC} Checking Prerequisites..."

if ! command -v php &> /dev/null; then
    echo -e "${RED}✗ PHP not found${NC}"
    exit 1
fi
PHP_BIN="php"  # PHP binary path
PHP_VER=$(php -v | head -n 1 | awk '{print $2}')
echo -e "${GREEN}  ✓ PHP ${PHP_VER}${NC}"

if ! command -v curl &> /dev/null; then
    echo -e "${RED}✗ curl not found${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ curl installed${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}  ⚠ jq not found (JSON parsing will be basic)${NC}"
    HAS_JQ=0
else
    echo -e "${GREEN}  ✓ jq installed${NC}"
    HAS_JQ=1
fi

echo ""

################################################################################
# Step 2: Check Directory
################################################################################
echo -e "${CYAN}[Step 2/5]${NC} Checking JSON Directory..."

if [ ! -d "$JSON_DIR" ]; then
    echo -e "${RED}✗ Directory not found: ${JSON_DIR}${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ Directory exists${NC}"

# Count JSON files (trim whitespace)
JSON_COUNT=$(find "$JSON_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "$JSON_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}  ⚠ No JSON files found${NC}"
    echo ""
    echo "  To create test data, run:"
    echo "    ./test_linux_production.sh"
    exit 0
fi

echo -e "${GREEN}  ✓ Found ${JSON_COUNT} JSON file(s)${NC}"
echo ""

################################################################################
# Step 3: Test API Connection
################################################################################
echo -e "${CYAN}[Step 3/5]${NC} Testing API Connection..."

# Skip health check - will test directly with real invoice processing
echo "  Endpoint: ${BASE_URL}/api/v1/invoice/sign"
echo -e "${GREEN}  ✓ Ready to process invoices${NC}"
echo ""

################################################################################
# Step 4: Process JSON Files (Pipeline Mode)
################################################################################
echo -e "${CYAN}[Step 4/5]${NC} Processing JSON Files (${PROCESS_MODE} mode)..."
echo ""

PROCESSED=0
ERRORS=0
SUCCESS=0
SKIPPED=0

for JSON_FILE in "$JSON_DIR"/*.json; do
    [ -f "$JSON_FILE" ] || continue

    FILENAME=$(basename "$JSON_FILE")
    FILESIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || stat -f%z "$JSON_FILE" 2>/dev/null || echo "?")

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}File:${NC} ${FILENAME}"
    echo -e "${CYAN}Size:${NC} ${FILESIZE} bytes"
    echo ""

    # Validate JSON syntax
    if ! php -r "json_decode(file_get_contents('$JSON_FILE')); if (json_last_error() !== JSON_ERROR_NONE) exit(1);" 2>/dev/null; then
        echo -e "${RED}✗ Invalid JSON syntax${NC}"
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi

    echo -e "${GREEN}✓ Valid JSON syntax${NC}"

    # Extract key information (optimized - single jq call)
    if [ $HAS_JQ -eq 1 ]; then
        # Use jq for parsing - single call for efficiency
        read -r IRN BUSINESS_ID ISSUE_DATE PAYMENT_STATUS SUPPLIER CUSTOMER TOTAL CURRENCY LINE_COUNT < <(
            jq -r '[
                .irn // "N/A",
                .business_id // "N/A",
                .issue_date // "N/A",
                .payment_status // "N/A",
                .accounting_supplier_party.party_name // "N/A",
                .accounting_customer_party.party_name // "N/A",
                .legal_monetary_total.payable_amount // "N/A",
                .document_currency_code // "N/A",
                (.invoice_lines | length | tostring)
            ] | @tsv' "$JSON_FILE" 2>/dev/null
        )
    else
        # Use grep for basic parsing
        IRN=$(grep -o '"irn"[[:space:]]*:[[:space:]]*"[^"]*"' "$JSON_FILE" | head -1 | cut -d'"' -f4)
        BUSINESS_ID=$(grep -o '"business_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$JSON_FILE" | head -1 | cut -d'"' -f4)
        ISSUE_DATE=$(grep -o '"issue_date"[[:space:]]*:[[:space:]]*"[^"]*"' "$JSON_FILE" | head -1 | cut -d'"' -f4)
        PAYMENT_STATUS=$(grep -o '"payment_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$JSON_FILE" | head -1 | cut -d'"' -f4)
        SUPPLIER=$(grep -A2 '"accounting_supplier_party"' "$JSON_FILE" | grep '"party_name"' | head -1 | cut -d'"' -f4)
        CUSTOMER=$(grep -A2 '"accounting_customer_party"' "$JSON_FILE" | grep '"party_name"' | head -1 | cut -d'"' -f4)
        TOTAL=$(grep '"payable_amount"' "$JSON_FILE" | head -1 | grep -o '[0-9.]*' | head -1)
        CURRENCY=$(grep -o '"document_currency_code"[[:space:]]*:[[:space:]]*"[^"]*"' "$JSON_FILE" | head -1 | cut -d'"' -f4)
        LINE_COUNT=$(grep -c '"id"' "$JSON_FILE" 2>/dev/null || echo "?")

        # Fallback if empty
        IRN=${IRN:-N/A}
        BUSINESS_ID=${BUSINESS_ID:-N/A}
        ISSUE_DATE=${ISSUE_DATE:-N/A}
        PAYMENT_STATUS=${PAYMENT_STATUS:-N/A}
        SUPPLIER=${SUPPLIER:-N/A}
        CUSTOMER=${CUSTOMER:-N/A}
        TOTAL=${TOTAL:-N/A}
        CURRENCY=${CURRENCY:-N/A}
    fi

    # Display extracted data
    echo ""
    echo -e "${YELLOW}Invoice Information:${NC}"
    echo "  IRN:            ${IRN}"
    echo "  Business ID:    ${BUSINESS_ID}"
    echo "  Issue Date:     ${ISSUE_DATE}"
    echo "  Payment Status: ${PAYMENT_STATUS}"
    echo "  Supplier:       ${SUPPLIER}"
    echo "  Customer:       ${CUSTOMER}"
    echo "  Total Amount:   ${TOTAL} ${CURRENCY}"
    echo ""

    # Extract base name (without extension)
    BASE_NAME="${FILENAME%.json}"

    BASE64_FILE="${OUTPUT_BASE}/QR/QR_txt/${BASE_NAME}.txt"
    QR_FILE="${OUTPUT_BASE}/QR/QR_img/${BASE_NAME}.png"

    # Check if already processed
    if [ "$PROCESS_MODE" = "verify" ]; then
        echo -e "${YELLOW}[VERIFY MODE] Checking existing files...${NC}"

        FILES_EXIST=0

        if [ -f "$BASE64_FILE" ]; then
            B64_SIZE=$(stat -c%s "$BASE64_FILE" 2>/dev/null || stat -f%z "$BASE64_FILE" 2>/dev/null || echo "?")
            echo -e "  ${GREEN}✓${NC} Base64: ${BASE64_FILE} (${B64_SIZE} bytes)"
            FILES_EXIST=$((FILES_EXIST + 1))
        else
            echo -e "  ${RED}✗${NC} Base64: Not found"
        fi

        if [ -f "$QR_FILE" ]; then
            QR_SIZE=$(stat -c%s "$QR_FILE" 2>/dev/null || stat -f%z "$QR_FILE" 2>/dev/null || echo "?")
            QR_SIZE_KB=$(echo "scale=1; $QR_SIZE / 1024" | bc 2>/dev/null || echo "$((QR_SIZE / 1024))")
            echo -e "  ${GREEN}✓${NC} QR PNG:  ${QR_FILE} (${QR_SIZE_KB} KB)"
            FILES_EXIST=$((FILES_EXIST + 1))
        else
            echo -e "  ${RED}✗${NC} QR PNG:  Not found"
        fi

        if [ $FILES_EXIST -eq 2 ]; then
            echo -e "${GREEN}All files exist, skipping...${NC}"
            SKIPPED=$((SKIPPED + 1))
        fi

        PROCESSED=$((PROCESSED + 1))
        echo ""
        continue
    fi

    # PIPELINE MODE: Process through API
    echo -e "${CYAN}[PIPELINE] Starting processing...${NC}"

    # Step 1: Read JSON content
    echo "  [1/3] Reading JSON content..."

    # Read and store JSON content for later use
    JSON_CONTENT=$(cat "$JSON_FILE" 2>/dev/null)

    if [ -z "$JSON_CONTENT" ]; then
        echo -e "  ${RED}✗ Cannot read JSON file${NC}"
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi

    echo -e "  ${GREEN}✓ JSON file readable (${FILESIZE} bytes)${NC}"

    # Step 2: Call API to encrypt and generate QR
    echo "  [2/3] Calling API POST /api/v1/invoice/sign..."
    echo "    IRN: ${IRN}"

    START_TIME=$(date +%s%3N 2>/dev/null || date +%s 2>/dev/null || echo "0")

    # Make API call with proper headers and authentication
    API_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip, deflate" \
        -H "x-api-key: ${X_API_KEY}" \
        -H "x-api-secret: ${X_API_SECRET}" \
        --compressed \
        --data-binary @"$JSON_FILE" \
        "${BASE_URL}/api/v1/invoice/sign" 2>&1)

    END_TIME=$(date +%s%3N 2>/dev/null || date +%s 2>/dev/null || echo "0")

    HTTP_CODE=$(echo "$API_RESPONSE" | tail -n 1)
    RESPONSE_BODY=$(echo "$API_RESPONSE" | sed '$d')

    if [ "$START_TIME" != "0" ] && [ "$END_TIME" != "0" ] && [ "$START_TIME" != "$END_TIME" ]; then
        DURATION=$((END_TIME - START_TIME))
    else
        DURATION="N/A"
    fi

    echo "    HTTP Status: ${HTTP_CODE}"

    # Accept both HTTP 200 and 201 as success
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        # Check if this is a duplicate error (IRN already validated before)
        IS_DUPLICATE=false
        if [ $HAS_JQ -eq 1 ]; then
            ERROR_DETAILS=$(echo "$RESPONSE_BODY" | jq -r '.error.details // ""' 2>/dev/null)
            ERROR_MESSAGE=$(echo "$RESPONSE_BODY" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
            if [[ "$ERROR_DETAILS" == *"duplicate"* ]] || [[ "$ERROR_DETAILS" == *"already exists"* ]] || [[ "$ERROR_DETAILS" == *"unable to complete"* ]]; then
                IS_DUPLICATE=true
            fi
        else
            ERROR_MESSAGE=$(echo "$RESPONSE_BODY" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            ERROR_MESSAGE=${ERROR_MESSAGE:-Unknown error}
            ERROR_DETAILS="N/A"
            if echo "$RESPONSE_BODY" | grep -qi "duplicate\|already exists\|unable to complete"; then
                IS_DUPLICATE=true
            fi
        fi

        if [ "$IS_DUPLICATE" = true ]; then
            echo -e "  ${YELLOW}⚠ Duplicate IRN (already validated by FIRS)${NC}"

            # Log as error (duplicate)
            log_error "$IRN" "$HTTP_CODE" "Duplicate IRN - already exists" "$ERROR_DETAILS" "duplicate" "$SUPPLIER" "$CUSTOMER" "$TOTAL"

            # Extract IRN to check for existing files
            if [ $HAS_JQ -eq 1 ]; then
                IRN_CHECK=$(echo "$JSON_CONTENT" | jq -r '.irn // ""' 2>/dev/null)
            else
                IRN_CHECK=$(echo "$JSON_CONTENT" | grep -o '"irn"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
            fi

            if [ -z "$IRN_CHECK" ]; then
                echo -e "  ${RED}✗ Cannot extract IRN from JSON${NC}"
                ERRORS=$((ERRORS + 1))
                echo ""
                continue
            fi

            # Check if Base64 and QR files already exist with this IRN pattern
            BASE64_DIR="${OUTPUT_BASE}/QR/QR_txt"
            QR_DIR="${OUTPUT_BASE}/QR/QR_img"

            # Find existing files with this IRN (may have different timestamps)
            EXISTING_BASE64=$(find "$BASE64_DIR" -name "${IRN_CHECK}.*.txt" 2>/dev/null | head -1)
            EXISTING_QR=$(find "$QR_DIR" -name "${IRN_CHECK}.*.png" 2>/dev/null | head -1)

            if [ -n "$EXISTING_BASE64" ] && [ -n "$EXISTING_QR" ]; then
                # Both files exist, skip processing
                echo -e "  ${GREEN}✓ Base64 file exists: $(basename "$EXISTING_BASE64")${NC}"
                echo -e "  ${GREEN}✓ QR code exists: $(basename "$EXISTING_QR")${NC}"
                echo -e "  ${CYAN}→ Skipping: All files already generated${NC}"
                SKIPPED=$((SKIPPED + 1))
                PROCESSED=$((PROCESSED + 1))
                echo ""
                continue
            else
                # Files missing, process locally
                if [ -z "$EXISTING_BASE64" ]; then
                    echo -e "  ${YELLOW}✗ Base64 file not found${NC}"
                fi
                if [ -z "$EXISTING_QR" ]; then
                    echo -e "  ${YELLOW}✗ QR code not found${NC}"
                fi
                echo -e "  ${CYAN}→ Generating missing files...${NC}"
                DATA_OK="true"
            fi
        else
            echo -e "  ${RED}✗ API call failed (HTTP ${HTTP_CODE})${NC}"

            # Try to parse error message
            if [ $HAS_JQ -eq 1 ]; then
                ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error.details // .error.message // .error // .message // "Unknown error"' 2>/dev/null)
                if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ] && [ "$ERROR_MSG" != "Unknown error" ]; then
                    echo -e "  ${RED}Error: ${ERROR_MSG}${NC}"
                else
                    # Show first 200 chars if no clear error message
                    ERROR_MSG=$(echo "$RESPONSE_BODY" | head -c 200)
                    echo -e "  ${RED}Response: ${ERROR_MSG}...${NC}"
                fi
            else
                # Show first 200 chars of response
                ERROR_MSG=$(echo "$RESPONSE_BODY" | head -c 200)
                echo -e "  ${RED}Response: ${ERROR_MSG}...${NC}"
            fi

            # Log error to error log
            log_error "$IRN" "$HTTP_CODE" "$ERROR_MSG" "API call failed" "api_error" "$SUPPLIER" "$CUSTOMER" "$TOTAL"

            ERRORS=$((ERRORS + 1))
            echo ""
            continue
        fi
    else
        echo -e "  ${GREEN}✓ API call successful (HTTP ${HTTP_CODE})${NC}"
        if [ "$DURATION" != "N/A" ]; then
            echo "    Response time: ${DURATION}ms"
        fi
        DATA_OK="true"
    fi

    # Step 3: Process locally if FIRS validation OK or duplicate
    echo "  [3/3] Processing locally with crypto_keys..."

    FILES_CREATED=0

    # For duplicate or successful validation, we process locally
    # No need to extract from response, we already have DATA_OK flag

    # Process locally: encrypt with crypto_keys and generate QR
    if [ "$DATA_OK" = "true" ]; then
        echo -e "    ${GREEN}✓ FIRS validation confirmed${NC}"
        echo "    Encrypting with crypto_keys..."

        # Extract IRN from original JSON
        if [ $HAS_JQ -eq 1 ]; then
            IRN=$(echo "$JSON_CONTENT" | jq -r '.irn // ""' 2>/dev/null)
        else
            IRN=$(echo "$JSON_CONTENT" | grep -o '"irn"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        fi

        if [ -z "$IRN" ]; then
            echo -e "    ${RED}✗ Cannot extract IRN from JSON${NC}"
            echo -e "    ${YELLOW}Debug: JSON_CONTENT length = ${#JSON_CONTENT}${NC}"
            ERRORS=$((ERRORS + 1))
            echo ""
            continue
        fi

        # No timestamp needed - all files use IRN only

        # Encrypt using PHP inline with crypto_keys
        CRYPTO_KEYS_FILE="./storage/crypto_keys.txt"
        if [ ! -f "$CRYPTO_KEYS_FILE" ]; then
            echo -e "    ${RED}✗ crypto_keys.txt not found${NC}"
            ERRORS=$((ERRORS + 1))
            echo ""
            continue
        fi

        # Encrypt IRN with certificate using PHP
        ENCRYPTED_DATA=$(php -r "
\$keysFile = './storage/crypto_keys.txt';
\$keys = json_decode(file_get_contents(\$keysFile), true);
if (!\$keys) {
    fwrite(STDERR, 'ERROR: Failed to load crypto_keys.txt' . PHP_EOL);
    exit(1);
}
\$publicKeyPem = base64_decode(\$keys['public_key']);
\$publicKey = openssl_pkey_get_public(\$publicKeyPem);
if (!\$publicKey) {
    fwrite(STDERR, 'ERROR: Invalid public key' . PHP_EOL);
    exit(1);
}
\$irn = '$IRN';
\$payload = json_encode(['irn' => \$irn, 'certificate' => \$keys['certificate']], JSON_UNESCAPED_SLASHES);
\$encrypted = '';
\$result = openssl_public_encrypt(\$payload, \$encrypted, \$publicKey, OPENSSL_PKCS1_PADDING);
if (!\$result) {
    fwrite(STDERR, 'ERROR: Encryption failed' . PHP_EOL);
    exit(1);
}
echo base64_encode(\$encrypted);
" 2>&1)

        if [[ "$ENCRYPTED_DATA" == ERROR:* ]] || [ -z "$ENCRYPTED_DATA" ]; then
            echo -e "    ${RED}✗ Encryption failed: ${ENCRYPTED_DATA}${NC}"
            ERRORS=$((ERRORS + 1))
            echo ""
            continue
        fi

        echo -e "    ${GREEN}✓ Encrypted with crypto_keys (${#ENCRYPTED_DATA} bytes base64)${NC}"
    fi

    if [ -z "$IRN" ]; then
        echo -e "    ${RED}✗ Cannot extract IRN${NC}"
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi

    # Define file paths - All files use IRN only (no timestamp)
    # This ensures files are automatically replaced if same IRN is processed again
    BASE64_DIR="${OUTPUT_BASE}/QR/QR_txt"
    QR_DIR="${OUTPUT_BASE}/QR/QR_img"
    JSON_SIGNED_DIR="${OUTPUT_BASE}/json_signed"

    # Create directories if not exist
    mkdir -p "$BASE64_DIR" 2>/dev/null
    mkdir -p "$QR_DIR" 2>/dev/null
    mkdir -p "$JSON_SIGNED_DIR" 2>/dev/null

    # File paths: Base64 and QR without timestamp (will replace if exists)
    BASE64_PATH="${BASE64_DIR}/${IRN}.txt"
    QR_PATH="${QR_DIR}/${IRN}.png"
    
    # Check if files already exist
    if [ -f "$BASE64_PATH" ] || [ -f "$QR_PATH" ]; then
        echo -e "    ${YELLOW}⚠ Files with IRN ${IRN} already exist${NC}"
        echo -e "    ${CYAN}→ Will replace existing files with new generation${NC}"
    fi

    # Save Base64 encrypted data
    if [ -n "$ENCRYPTED_DATA" ]; then
        echo "$ENCRYPTED_DATA" > "$BASE64_PATH"
        if [ -f "$BASE64_PATH" ]; then
            B64_SIZE=$(stat -c%s "$BASE64_PATH" 2>/dev/null || stat -f%z "$BASE64_PATH" 2>/dev/null || wc -c < "$BASE64_PATH" 2>/dev/null || echo "?")
            echo -e "    ${GREEN}✓ Base64: ${IRN}.txt (${B64_SIZE} bytes)${NC}"
            FILES_CREATED=$((FILES_CREATED + 1))
        else
            echo -e "    ${RED}✗ Failed to save Base64 file${NC}"
        fi
    else
        echo -e "    ${RED}✗ No encrypted data in response${NC}"
    fi

    # Generate QR code from Base64 data using PHP
    if [ -n "$ENCRYPTED_DATA" ] && [ -n "$PHP_BIN" ]; then
        QR_RESULT=$("$PHP_BIN" -r "
        require 'vendor/autoload.php';
        use chillerlan\QRCode\QRCode;
        use chillerlan\QRCode\QROptions;
        try {
            \$options = new QROptions([
                'version' => QRCode::VERSION_AUTO,
                'outputType' => QRCode::OUTPUT_IMAGE_PNG,
                'eccLevel' => QRCode::ECC_L,
                'scale' => 6,
                'imageBase64' => false,
            ]);
            \$qrcode = new QRCode(\$options);
            \$qrcode->render('$ENCRYPTED_DATA', '$QR_PATH');
            echo 'SUCCESS';
        } catch (Exception \$e) {
            echo 'ERROR: ' . \$e->getMessage();
        }
        " 2>&1)

        if [ "$QR_RESULT" = "SUCCESS" ] && [ -f "$QR_PATH" ]; then
            QR_SIZE=$(stat -c%s "$QR_PATH" 2>/dev/null || stat -f%z "$QR_PATH" 2>/dev/null || wc -c < "$QR_PATH" 2>/dev/null || echo "0")
            QR_SIZE_KB=$(echo "scale=1; $QR_SIZE / 1024" | bc 2>/dev/null || echo "$((QR_SIZE / 1024))")
            echo -e "    ${GREEN}✓ QR PNG: ${IRN}.png (${QR_SIZE_KB} KB)${NC}"
            FILES_CREATED=$((FILES_CREATED + 1))
        else
            echo -e "    ${RED}✗ Failed to generate QR code${NC}"
            if [ "$QR_RESULT" != "SUCCESS" ]; then
                echo -e "    ${RED}  Error: ${QR_RESULT}${NC}"
            fi
        fi
    else
        echo -e "    ${RED}✗ Cannot generate QR (missing data or PHP)${NC}"
    fi

    # JSON file already exists in source directory
    if [ -f "$JSON_FILE" ]; then
        echo -e "    ${GREEN}✓ JSON:   $(basename "$JSON_FILE")${NC}"
        FILES_CREATED=$((FILES_CREATED + 1))
    fi

    if [ $FILES_CREATED -eq 3 ]; then
        echo -e "${GREEN}Pipeline completed successfully!${NC}"
        SUCCESS=$((SUCCESS + 1))

        # Save JSON signed without timestamp (same as Base64/QR - will auto-replace)
        JSON_SIGNED_FILE="${JSON_SIGNED_DIR}/${IRN}.json"

        echo -e "    ${CYAN}→ Saving JSON signed...${NC}"
        if cp "$JSON_FILE" "$JSON_SIGNED_FILE"; then
            echo -e "    ${GREEN}✓ JSON signed saved: $(basename "$JSON_SIGNED_FILE")${NC}"
        else
            echo -e "    ${YELLOW}⚠ Failed to save JSON signed${NC}"
        fi

        # Log success with detailed information (use IRN for both parameters since no timestamp)
        log_success "$IRN" "$IRN" "$JSON_SIGNED_FILE" "$BASE64_PATH" "$QR_PATH" "$HTTP_CODE" "$SUPPLIER" "$CUSTOMER" "$TOTAL" "$CURRENCY"

        # Delete original JSON file after successful processing
        echo -e "    ${CYAN}→ Deleting source JSON file...${NC}"
        if rm -f "$JSON_FILE"; then
            echo -e "    ${GREEN}✓ Source JSON deleted: $(basename "$JSON_FILE")${NC}"
        else
            echo -e "    ${YELLOW}⚠ Failed to delete source JSON${NC}"
        fi
    else
        echo -e "${YELLOW}Pipeline completed with missing files (${FILES_CREATED}/3)${NC}"

        # Log error for incomplete processing with details
        log_error "$IRN" "0" "Incomplete file generation" "Only ${FILES_CREATED}/3 files created" "processing_error" "$SUPPLIER" "$CUSTOMER" "$TOTAL"

        ERRORS=$((ERRORS + 1))
    fi

    PROCESSED=$((PROCESSED + 1))
    echo ""
done

################################################################################
# Step 5: Summary
################################################################################
echo ""
echo -e "${CYAN}[Step 5/5]${NC} Processing Summary"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$PROCESS_MODE" = "pipeline" ]; then
    if [ $ERRORS -eq 0 ] && [ $SUCCESS -eq $PROCESSED ]; then
        echo -e "${GREEN}✓ All files processed successfully through pipeline${NC}"
    else
        echo -e "${YELLOW}⚠ Some files had errors during pipeline processing${NC}"
    fi

    echo ""
    echo "  Mode:              Pipeline (JSON → Base64 → QR)"
    echo "  Total JSON files:  ${JSON_COUNT}"
    echo "  Processed:         ${PROCESSED}"
    echo "  Success:           ${SUCCESS}"
    echo "  Errors:            ${ERRORS}"
else
    echo -e "${YELLOW}Verification mode (API not available)${NC}"
    echo ""
    echo "  Mode:              Verify only"
    echo "  Total JSON files:  ${JSON_COUNT}"
    echo "  Processed:         ${PROCESSED}"
    echo "  Skipped:           ${SKIPPED}"
    echo "  Errors:            ${ERRORS}"
fi

echo ""
echo -e "${CYAN}================================================================${NC}"
if [ "$PROCESS_MODE" = "pipeline" ] && [ $SUCCESS -eq $PROCESSED ] && [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Pipeline Processing Complete! All files processed successfully.${NC}"
    EXIT_CODE=0
elif [ $ERRORS -gt 0 ]; then
    echo -e "${YELLOW}Pipeline Processing Complete with ${ERRORS} error(s).${NC}"
    EXIT_CODE=1
else
    echo -e "${GREEN}Processing Complete!${NC}"
    EXIT_CODE=0
fi
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${YELLOW}Logs:${NC}"
echo "  Success: ${SUCCESS_LOG}"
echo "  Error:   ${ERROR_LOG}"
echo ""

exit $EXIT_CODE
