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
# Production configuration from .env
JSON_DIR="${JSON_DIR:-/www/wwwroot/sftp/user_data/json}"
OUTPUT_BASE="${OUTPUT_BASE:-/www/wwwroot/sftp/user_data}"
BASE_URL="${BASE_URL:-https://eivc-k6z6d.ondigitalocean.app}"
X_API_KEY="${X_API_KEY:-62b9fd03-d9ab-4417-a834-be90616253a4}"
X_API_SECRET="${X_API_SECRET:-c72DlrZgxvzl4E2AHjyQqNHMDohqbUZphSPBDDaLJKW4zibksYg6cW5Bsa6g4rZy2vx1xA3r9DGaP27rVamx8wf7OZCAEcKKydkC}"

# Processing mode
PROCESS_MODE="${PROCESS_MODE:-pipeline}"  # pipeline or verify

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
echo ""

################################################################################
# Step 1: Check Prerequisites
################################################################################
echo -e "${CYAN}[Step 1/5]${NC} Checking Prerequisites..."

if ! command -v php &> /dev/null; then
    echo -e "${RED}✗ PHP not found${NC}"
    exit 1
fi
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
    
    # Validate JSON can be read
    if ! cat "$JSON_FILE" > /dev/null 2>&1; then
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
        echo -e "  ${RED}✗ API call failed (HTTP ${HTTP_CODE})${NC}"
        
        # Try to parse error message
        if [ $HAS_JQ -eq 1 ]; then
            ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error.message // .error // .message // "Unknown error"' 2>/dev/null)
            if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ] && [ "$ERROR_MSG" != "Unknown error" ]; then
                echo -e "  ${RED}Error: ${ERROR_MSG}${NC}"
            else
                # Show first 200 chars if no clear error message
                echo -e "  ${RED}Response: $(echo "$RESPONSE_BODY" | head -c 200)...${NC}"
            fi
        else
            # Show first 200 chars of response
            echo -e "  ${RED}Response: $(echo "$RESPONSE_BODY" | head -c 200)...${NC}"
        fi
        
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi
    
    echo -e "  ${GREEN}✓ API call successful (HTTP ${HTTP_CODE})${NC}"
    if [ "$DURATION" != "N/A" ]; then
        echo "    Response time: ${DURATION}ms"
    fi
    
    # Step 3: Extract data from response and save files locally
    echo "  [3/3] Saving files to local storage..."
    
    FILES_CREATED=0
    
    # Extract IRN signed and encrypted data from response
    if [ $HAS_JQ -eq 1 ]; then
        IRN_SIGNED=$(echo "$RESPONSE_BODY" | jq -r '.data.irn_signed // .data.irn // ""' 2>/dev/null)
        ENCRYPTED_DATA=$(echo "$RESPONSE_BODY" | jq -r '.data.encrypted_data // ""' 2>/dev/null)
    else
        IRN_SIGNED=$(echo "$RESPONSE_BODY" | grep -o '"irn_signed":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -z "$IRN_SIGNED" ]; then
            IRN_SIGNED=$(echo "$RESPONSE_BODY" | grep -o '"irn":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
        ENCRYPTED_DATA=$(echo "$RESPONSE_BODY" | grep -o '"encrypted_data":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$IRN_SIGNED" ]; then
        echo -e "    ${RED}✗ Cannot extract IRN from response${NC}"
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi
    
    # Define file paths based on signed IRN
    BASE64_DIR="${OUTPUT_BASE}/QR/QR_txt"
    QR_DIR="${OUTPUT_BASE}/QR/QR_img"
    
    # Create directories if not exist
    mkdir -p "$BASE64_DIR" 2>/dev/null
    mkdir -p "$QR_DIR" 2>/dev/null
    
    BASE64_PATH="${BASE64_DIR}/${IRN_SIGNED}.txt"
    QR_PATH="${QR_DIR}/${IRN_SIGNED}.png"
    
    # Save Base64 encrypted data
    if [ -n "$ENCRYPTED_DATA" ]; then
        echo "$ENCRYPTED_DATA" > "$BASE64_PATH"
        if [ -f "$BASE64_PATH" ]; then
            B64_SIZE=$(stat -c%s "$BASE64_PATH" 2>/dev/null || stat -f%z "$BASE64_PATH" 2>/dev/null || wc -c < "$BASE64_PATH" 2>/dev/null || echo "?")
            echo -e "    ${GREEN}✓ Base64: ${IRN_SIGNED}.txt (${B64_SIZE} bytes)${NC}"
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
                'version' => 5,
                'outputType' => QRCode::OUTPUT_IMAGE_PNG,
                'eccLevel' => QRCode::ECC_L,
                'scale' => 10,
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
            echo -e "    ${GREEN}✓ QR PNG: ${IRN_SIGNED}.png (${QR_SIZE_KB} KB)${NC}"
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
    else
        echo -e "${YELLOW}Pipeline completed with missing files (${FILES_CREATED}/3)${NC}"
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

################################################################################
# Usage & Maintenance
################################################################################
if [ "$PROCESSED" -gt 0 ]; then
    echo -e "${YELLOW}Usage Examples:${NC}"
    echo ""
    echo "  Pipeline mode (process files):"
    echo "    ./test_process_json_files.sh"
    echo ""
    echo "  Verify mode only:"
    echo "    PROCESS_MODE=verify ./test_process_json_files.sh"
    echo ""
    echo "  Custom configuration:"
    echo "    BASE_URL=https://your-api.com X_API_KEY=key X_API_SECRET=secret ./test_process_json_files.sh"
    echo ""
    echo "  Custom paths:"
    echo "    JSON_DIR=/custom/path OUTPUT_BASE=/custom/output ./test_process_json_files.sh"
    echo ""
    echo -e "${YELLOW}Maintenance Commands:${NC}"
    echo ""
    echo "  Delete all processed files:"
    echo "    rm -f ${JSON_DIR}/*.json ${OUTPUT_BASE}/QR/QR_txt/*.txt ${OUTPUT_BASE}/QR/QR_img/*.png"
    echo ""
    echo "  Archive old files (30+ days):"
    echo "    find ${JSON_DIR} -name '*.json' -mtime +30 -exec mv {} /archive/ \;"
    echo ""
fi

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

exit $EXIT_CODE
