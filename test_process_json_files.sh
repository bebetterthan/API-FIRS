#!/bin/bash

################################################################################
# FIRS E-Invoice API - JSON Files Processor Test Script
# Reads and processes all JSON files in /www/wwwroot/sftp/user_data/json/
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

# Header
echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN} FIRS E-Invoice - JSON Files Processor${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  JSON Directory: ${JSON_DIR}"
echo "  Output Base:    ${OUTPUT_BASE}"
echo ""

################################################################################
# Step 1: Check Prerequisites
################################################################################
echo -e "${CYAN}[Step 1/4]${NC} Checking Prerequisites..."

if ! command -v php &> /dev/null; then
    echo -e "${RED}✗ PHP not found${NC}"
    exit 1
fi
PHP_VER=$(php -v | head -n 1 | awk '{print $2}')
echo -e "${GREEN}  ✓ PHP ${PHP_VER}${NC}"

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
echo -e "${CYAN}[Step 2/4]${NC} Checking JSON Directory..."

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
# Step 3: Process JSON Files
################################################################################
echo -e "${CYAN}[Step 3/4]${NC} Processing JSON Files..."
echo ""

PROCESSED=0
ERRORS=0

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
    echo ""
    echo -e "${YELLOW}Parties:${NC}"
    echo "  Supplier:       ${SUPPLIER}"
    echo "  Customer:       ${CUSTOMER}"
    echo ""
    echo -e "${YELLOW}Financial:${NC}"
    echo "  Total Amount:   ${TOTAL} ${CURRENCY}"
    echo "  Invoice Lines:  ${LINE_COUNT}"
    echo ""
    
    # Check for related files (Base64 and QR)
    # Extract base IRN (without extension if any)
    BASE_NAME="${FILENAME%.json}"
    
    BASE64_FILE="${OUTPUT_BASE}/QR/QR_txt/${BASE_NAME}.txt"
    QR_FILE="${OUTPUT_BASE}/QR/QR_img/${BASE_NAME}.png"
    
    echo -e "${YELLOW}Related Files:${NC}"
    
    if [ -f "$BASE64_FILE" ]; then
        B64_SIZE=$(stat -c%s "$BASE64_FILE" 2>/dev/null || stat -f%z "$BASE64_FILE" 2>/dev/null || echo "?")
        echo -e "  ${GREEN}✓${NC} Base64: ${BASE64_FILE} (${B64_SIZE} bytes)"
        
        # Validate Base64 content
        if base64 -d "$BASE64_FILE" > /dev/null 2>&1; then
            echo -e "    ${GREEN}Valid Base64 encoding${NC}"
        else
            echo -e "    ${RED}Invalid Base64 encoding${NC}"
        fi
    else
        echo -e "  ${RED}✗${NC} Base64: Not found"
    fi
    
    if [ -f "$QR_FILE" ]; then
        QR_SIZE=$(stat -c%s "$QR_FILE" 2>/dev/null || stat -f%z "$QR_FILE" 2>/dev/null || echo "?")
        QR_SIZE_KB=$(echo "scale=1; $QR_SIZE / 1024" | bc 2>/dev/null || echo "$((QR_SIZE / 1024))")
        echo -e "  ${GREEN}✓${NC} QR PNG:  ${QR_FILE} (${QR_SIZE_KB} KB)"
        
        # Validate PNG format
        if command -v file > /dev/null 2>&1; then
            if file "$QR_FILE" 2>/dev/null | grep -q "PNG"; then
                echo -e "    ${GREEN}Valid PNG image${NC}"
                
                # Get dimensions if identify is available
                if command -v identify > /dev/null 2>&1; then
                    DIM=$(identify -format "%wx%h" "$QR_FILE" 2>/dev/null)
                    if [ -n "$DIM" ]; then
                        echo -e "    ${GREEN}Dimensions: ${DIM} pixels${NC}"
                    fi
                fi
            else
                echo -e "    ${RED}Invalid PNG format${NC}"
            fi
        fi
    else
        echo -e "  ${RED}✗${NC} QR PNG:  Not found"
    fi
    
    PROCESSED=$((PROCESSED + 1))
    echo ""
done

################################################################################
# Step 4: Summary
################################################################################
echo ""
echo -e "${CYAN}[Step 4/4]${NC} Processing Summary"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All files processed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Some files had errors${NC}"
fi

echo ""
echo "  Total JSON files:  ${JSON_COUNT}"
echo "  Processed:         ${PROCESSED}"
echo "  Errors:            ${ERRORS}"
echo ""

################################################################################
# Optional: Cleanup old files
################################################################################
if [ "$PROCESSED" -gt 0 ]; then
    echo -e "${YELLOW}Maintenance Options:${NC}"
    echo ""
    echo "  To delete all processed files:"
    echo "    rm -f ${JSON_DIR}/*.json"
    echo "    rm -f ${OUTPUT_BASE}/QR/QR_txt/*.txt"
    echo "    rm -f ${OUTPUT_BASE}/QR/QR_img/*.png"
    echo ""
    echo "  To archive old files (older than 30 days):"
    echo "    find ${JSON_DIR} -name '*.json' -mtime +30 -delete"
    echo ""
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}Processing Complete!${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

exit 0
