#!/bin/bash
set -e

# FIRS E-Invoice API - Production Test Script
# Tests invoice signing with 3-file generation (JSON, Base64, QR)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_URL="${BASE_URL:-http://localhost}"
API_KEY="${API_KEY:-test-key}"
API_SECRET="${API_SECRET:-test-secret}"
OUTPUT_PATH="/www/wwwroot/sftp/user_data"

TIMESTAMP=$(date +%s)
IRN="PFNL0001-9D3009-$(date +%Y%m%d)"
SIGNED_IRN="${IRN}.${TIMESTAMP}"

echo ""
echo -e "${CYAN}FIRS E-Invoice API - Production Test${NC}"
echo "IRN: ${IRN} | Signed: ${SIGNED_IRN}"
echo ""

echo -e "${CYAN}[1/4] Checking Prerequisites...${NC}"
if ! command -v php &> /dev/null; then
    echo -e "${RED}PHP not found${NC}"
    exit 1
fi
echo -e "${GREEN}PHP OK${NC}"

if ! command -v curl &> /dev/null; then
    echo -e "${RED}curl not found${NC}"
    exit 1
fi
echo -e "${GREEN}curl OK${NC}"

echo ""
echo -e "${CYAN}[2/4] Verifying Folders...${NC}"
mkdir -p "${OUTPUT_PATH}/json"
mkdir -p "${OUTPUT_PATH}/QR/QR_txt"
mkdir -p "${OUTPUT_PATH}/QR/QR_img"
echo -e "${GREEN}Folders OK${NC}"

echo ""
echo -e "${CYAN}[3/4] Signing Invoice...${NC}"

TEMP_FILE="/tmp/firs_test_$$.json"

CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_TIME=$(date +%H:%M:%S)
DUE_DATE=$(date -d '+30 days' +%Y-%m-%d 2>/dev/null || date -v +30d +%Y-%m-%d 2>/dev/null || echo "2025-11-23")

cat > "$TEMP_FILE" <<'JSONEOF'
{
  "business_id": "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
  "irn": "IRN_PLACEHOLDER",
  "payment_status": "PAID",
  "issue_date": "DATE_PLACEHOLDER",
  "issue_time": "TIME_PLACEHOLDER",
  "due_date": "DUE_PLACEHOLDER",
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
JSONEOF

sed -i "s/IRN_PLACEHOLDER/${IRN}/" "$TEMP_FILE"
sed -i "s/DATE_PLACEHOLDER/${CURRENT_DATE}/" "$TEMP_FILE"
sed -i "s/TIME_PLACEHOLDER/${CURRENT_TIME}/" "$TEMP_FILE"
sed -i "s/DUE_PLACEHOLDER/${DUE_DATE}/" "$TEMP_FILE"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -H "x-api-secret: ${API_SECRET}" \
    -d @"$TEMP_FILE" \
    "${BASE_URL}/api/v1/invoice/sign" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')
rm -f "$TEMP_FILE"

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}FAILED (HTTP ${HTTP_CODE})${NC}"
    echo "$BODY"
    exit 1
fi

echo -e "${GREEN}Signed OK (HTTP ${HTTP_CODE})${NC}"

JSON_FILE=$(echo "$BODY" | grep -o '"json":"[^"]*"' | head -1 | cut -d'"' -f4)
BASE64_FILE=$(echo "$BODY" | grep -o '"encrypted":"[^"]*"' | head -1 | cut -d'"' -f4)
QR_FILE=$(echo "$BODY" | grep -o '"qr_code":"[^"]*"' | head -1 | cut -d'"' -f4)

echo ""
echo -e "${CYAN}[4/4] Verifying Files...${NC}"

FILES_OK=0

if [ -n "$JSON_FILE" ] && [ -f "$JSON_FILE" ]; then
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || stat -f%z "$JSON_FILE" 2>/dev/null || echo "?")
    echo -e "${GREEN}JSON:   $(basename "$JSON_FILE") (${JSON_SIZE} bytes)${NC}"
    FILES_OK=$((FILES_OK + 1))
else
    echo -e "${RED}JSON NOT FOUND${NC}"
fi

if [ -n "$BASE64_FILE" ] && [ -f "$BASE64_FILE" ]; then
    B64_SIZE=$(stat -c%s "$BASE64_FILE" 2>/dev/null || stat -f%z "$BASE64_FILE" 2>/dev/null || echo "?")
    echo -e "${GREEN}Base64: $(basename "$BASE64_FILE") (${B64_SIZE} bytes)${NC}"
    FILES_OK=$((FILES_OK + 1))
else
    echo -e "${RED}Base64 NOT FOUND${NC}"
fi

if [ -n "$QR_FILE" ] && [ -f "$QR_FILE" ]; then
    QR_SIZE=$(stat -c%s "$QR_FILE" 2>/dev/null || stat -f%z "$QR_FILE" 2>/dev/null || echo "?")
    QR_SIZE_KB=$(echo "scale=1; $QR_SIZE / 1024" | bc 2>/dev/null || echo "$((QR_SIZE / 1024))")
    echo -e "${GREEN}QR PNG: $(basename "$QR_FILE") (${QR_SIZE_KB} KB)${NC}"
    FILES_OK=$((FILES_OK + 1))
else
    echo -e "${RED}QR PNG NOT FOUND${NC}"
fi

echo ""
if [ $FILES_OK -eq 3 ]; then
    echo -e "${GREEN}ALL TESTS PASSED (3/3 files created)${NC}"
    exit 0
else
    echo -e "${RED}TEST FAILED (${FILES_OK}/3 files created)${NC}"
    exit 1
fi