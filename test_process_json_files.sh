#!/bin/bash

################################################################################
# FIRS E-Invoice API - JSON Pipeline Processor
# Processes JSON files: JSON -> Base64 Encryption -> QR Code Generation
# Same flow as /api/v1/invoice/sign but for batch processing
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
JSON_DIR="${JSON_DIR:-/www/wwwroot/sftp/user_data/json}"
OUTPUT_BASE="${OUTPUT_BASE:-/www/wwwroot/sftp/user_data}"
API_URL="${API_URL:-http://localhost}"
API_KEY="${API_KEY:-test-key}"
API_SECRET="${API_SECRET:-test-secret}"

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
echo "  API URL:        ${API_URL}"
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

# Count JSON files
JSON_COUNT=$(find "$JSON_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l)

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

HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/health" 2>/dev/null || echo "000")

if [ "$HEALTH_CHECK" = "200" ]; then
    echo -e "${GREEN}  ✓ API is reachable${NC}"
else
    echo -e "${RED}  ✗ API not reachable (HTTP ${HEALTH_CHECK})${NC}"
    echo -e "${YELLOW}  Continuing in verify-only mode...${NC}"
    PROCESS_MODE="verify"
fi

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
    
    # Extract key information
    if [ $HAS_JQ -eq 1 ]; then
        # Use jq for parsing
        IRN=$(jq -r '.irn // "N/A"' "$JSON_FILE" 2>/dev/null)
        BUSINESS_ID=$(jq -r '.business_id // "N/A"' "$JSON_FILE" 2>/dev/null)
        ISSUE_DATE=$(jq -r '.issue_date // "N/A"' "$JSON_FILE" 2>/dev/null)
        PAYMENT_STATUS=$(jq -r '.payment_status // "N/A"' "$JSON_FILE" 2>/dev/null)
        SUPPLIER=$(jq -r '.accounting_supplier_party.party_name // "N/A"' "$JSON_FILE" 2>/dev/null)
        CUSTOMER=$(jq -r '.accounting_customer_party.party_name // "N/A"' "$JSON_FILE" 2>/dev/null)
        TOTAL=$(jq -r '.legal_monetary_total.payable_amount // "N/A"' "$JSON_FILE" 2>/dev/null)
        CURRENCY=$(jq -r '.document_currency_code // "N/A"' "$JSON_FILE" 2>/dev/null)
        LINE_COUNT=$(jq -r '.invoice_lines | length' "$JSON_FILE" 2>/dev/null)
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
    echo "  [1/3] Reading JSON file..."
    
    # Step 2: Call API to encrypt and generate QR
    echo "  [2/3] Calling API (encrypt + QR generation)..."
    
    START_TIME=$(date +%s%3N 2>/dev/null || date +%s 2>/dev/null || echo "0")
    
    API_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${API_KEY}" \
        -H "x-api-secret: ${API_SECRET}" \
        -d @"$JSON_FILE" \
        "${API_URL}/api/v1/invoice/sign" 2>&1)
    
    END_TIME=$(date +%s%3N 2>/dev/null || date +%s 2>/dev/null || echo "0")
    
    HTTP_CODE=$(echo "$API_RESPONSE" | tail -n 1)
    RESPONSE_BODY=$(echo "$API_RESPONSE" | sed '$d')
    
    if [ "$START_TIME" != "0" ] && [ "$END_TIME" != "0" ] && [ "$START_TIME" != "$END_TIME" ]; then
        DURATION=$((END_TIME - START_TIME))
    else
        DURATION="N/A"
    fi
    
    if [ "$HTTP_CODE" != "200" ]; then
        echo -e "  ${RED}✗ API call failed (HTTP ${HTTP_CODE})${NC}"
        if [ $HAS_JQ -eq 1 ]; then
            ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
            echo -e "  ${RED}Error: ${ERROR_MSG}${NC}"
        fi
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi
    
    echo -e "  ${GREEN}✓ API call successful${NC}"
    if [ "$DURATION" != "N/A" ]; then
        echo "    Response time: ${DURATION}ms"
    fi
    
    # Step 3: Verify created files
    echo "  [3/3] Verifying generated files..."
    
    FILES_CREATED=0
    
    # Extract file paths from response
    if [ $HAS_JQ -eq 1 ]; then
        JSON_PATH=$(echo "$RESPONSE_BODY" | jq -r '.data.files.json // empty' 2>/dev/null)
        BASE64_PATH=$(echo "$RESPONSE_BODY" | jq -r '.data.files.encrypted // empty' 2>/dev/null)
        QR_PATH=$(echo "$RESPONSE_BODY" | jq -r '.data.files.qr_code // empty' 2>/dev/null)
    else
        JSON_PATH=$(echo "$RESPONSE_BODY" | grep -o '"json":"[^"]*"' | head -1 | cut -d'"' -f4)
        BASE64_PATH=$(echo "$RESPONSE_BODY" | grep -o '"encrypted":"[^"]*"' | head -1 | cut -d'"' -f4)
        QR_PATH=$(echo "$RESPONSE_BODY" | grep -o '"qr_code":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    # Verify JSON (already exists, just check)
    if [ -n "$JSON_PATH" ] && [ -f "$JSON_PATH" ]; then
        echo -e "    ${GREEN}✓ JSON:   $(basename "$JSON_PATH")${NC}"
        FILES_CREATED=$((FILES_CREATED + 1))
    fi
    
    # Verify Base64
    if [ -n "$BASE64_PATH" ] && [ -f "$BASE64_PATH" ]; then
        B64_SIZE=$(stat -c%s "$BASE64_PATH" 2>/dev/null || stat -f%z "$BASE64_PATH" 2>/dev/null || echo "?")
        echo -e "    ${GREEN}✓ Base64: $(basename "$BASE64_PATH") (${B64_SIZE} bytes)${NC}"
        FILES_CREATED=$((FILES_CREATED + 1))
    else
        echo -e "    ${RED}✗ Base64 file not created${NC}"
    fi
    
    # Verify QR
    if [ -n "$QR_PATH" ] && [ -f "$QR_PATH" ]; then
        QR_SIZE=$(stat -c%s "$QR_PATH" 2>/dev/null || stat -f%z "$QR_PATH" 2>/dev/null || echo "?")
        QR_SIZE_KB=$(echo "scale=1; $QR_SIZE / 1024" | bc 2>/dev/null || echo "$((QR_SIZE / 1024))")
        echo -e "    ${GREEN}✓ QR PNG: $(basename "$QR_PATH") (${QR_SIZE_KB} KB)${NC}"
        FILES_CREATED=$((FILES_CREATED + 1))
    else
        echo -e "    ${RED}✗ QR PNG file not created${NC}"
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
    echo "  Custom paths:"
    echo "    JSON_DIR=/custom/path API_URL=http://example.com ./test_process_json_files.sh"
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
