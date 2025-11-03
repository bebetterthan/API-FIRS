<?php
/**
 * Test FIRS API with Original Response Logging
 *
 * Script ini akan mengirim invoice ke FIRS API dan
 * mencatat response ASLI dari FIRS (tanpa translasi)
 */

require_once __DIR__ . '/vendor/autoload.php';

use FIRS\LogManager;
use FIRS\FIRSAPIClient;
use FIRS\FIRSAPIException;

$config = require __DIR__ . '/config.php';
$logManager = new LogManager($config);
$firsClient = new FIRSAPIClient($config);

echo "========================================\n";
echo "FIRS API TEST - ORIGINAL RESPONSE\n";
echo "========================================\n\n";

if (!$config['firs_api']['enabled']) {
    echo "❌ FIRS API is disabled\n";
    exit(1);
}

// Test invoice data
$invoiceData = [
    "business_id" => "d91c22f8-0912-4f42-8349-33f28e4a6c4e",
    "irn" => "ORIGINAL-" . date('Ymd-His'),
    "issue_date" => date('Y-m-d'),
    "due_date" => date('Y-m-d', strtotime('+21 days')),
    "invoice_type_code" => "380",
    "document_currency_code" => "NGN",
    "tax_currency_code" => "NGN",
    "accounting_supplier_party" => [
        "party_name" => "PRIMERA FOOD NIGERIA LTD.",
        "tin" => "16069538-0001",
        "email" => "sys@primerafood-nigeria.com",
        "telephone" => "+23480989999",
        "postal_address" => [
            "street_name" => "Plot 4-6, Block I, Industrial 1, OPIC Estate, Agbara, Ogun State",
            "city_name" => "Agbara",
            "postal_zone" => "110123",
            "country" => "NG"
        ]
    ],
    "accounting_customer_party" => [
        "party_name" => "EURO MEGA ATLANTIC NIGERIA LTD. North",
        "tin" => "17778013-0001",
        "email" => "rino@asmr.com",
        "telephone" => "+234",
        "postal_address" => [
            "street_name" => "Suite 21B, Lagos",
            "city_name" => "Lagos",
            "postal_zone" => "100001",
            "country" => "NG"
        ]
    ],
    "tax_total" => [[
        "tax_amount" => 3313304.02,
        "tax_subtotal" => [[
            "taxable_amount" => 44177386.87,
            "tax_amount" => 3313304.02,
            "tax_category" => ["id" => "LOCAL_SALES_TAX", "percent" => 7.5]
        ]]
    ]],
    "legal_monetary_total" => [
        "line_extension_amount" => 44177386.87,
        "tax_exclusive_amount" => 44177386.87,
        "tax_inclusive_amount" => 47490690.89,
        "payable_amount" => 47490690.89
    ],
    "invoice_line" => [[
        "hsn_code" => "1902.30",
        "product_category" => "Food and Beverages",
        "discount_rate" => 0.0,
        "discount_amount" => 0,
        "fee_rate" => 0,
        "fee_amount" => 0,
        "invoiced_quantity" => 4343.0,
        "line_extension_amount" => 44177386.87,
        "item" => [
            "name" => "Sedaap Supreme chicken Flavour 120 GR",
            "description" => "Sedaap Supreme chicken Flavour 120 GR",
            "sellers_item_identification" => "16000002"
        ],
        "price" => [
            "price_amount" => 10172.09,
            "base_quantity" => 4343.0,
            "price_unit" => "NGN per 1"
        ]
    ]]
];

$irn = $invoiceData['irn'];

echo "Invoice: {$irn}\n";
echo "Sending to FIRS API...\n\n";

try {
    $response = $firsClient->submitInvoice($invoiceData);

    echo "✅ SUCCESS\n";
    echo json_encode($response, JSON_PRETTY_PRINT) . "\n\n";

    $logManager->logSuccess(
        irn: $irn,
        signedIRN: $response['data']['signed_irn'] ?? $irn,
        files: [],
        apiResponse: $response,
        invoiceData: $invoiceData
    );

} catch (FIRSAPIException $e) {
    echo "❌ FIRS API ERROR\n\n";

    echo "=== ORIGINAL FIRS RESPONSE ===\n";
    $firsResponse = $e->getResponseData();
    echo json_encode($firsResponse, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n\n";

    echo "=== EXTRACTED FIRS FIELDS ===\n";
    echo "IRN: {$irn}\n";
    echo "HTTP Code: " . $e->getHttpCode() . "\n";
    echo "FIRS Handler: " . ($e->getFIRSHandler() ?? 'N/A') . "\n";
    echo "FIRS Public Message: " . ($e->getFIRSPublicMessage() ?? 'N/A') . "\n";
    echo "FIRS Details: " . ($e->getFIRSDetails() ?? 'N/A') . "\n";
    echo "FIRS Error ID: " . ($e->getFIRSErrorId() ?? 'N/A') . "\n";
    echo "Source File: N/A (test script, not from JSON file)\n\n";

    // Log dengan data ORIGINAL dari FIRS + source_file
    $logManager->logError(
        irn: $irn,
        httpCode: $e->getHttpCode(),
        publicMessage: $e->getFIRSPublicMessage() ?? 'FIRS API error',
        detailedMessage: $e->getFIRSDetails() ?? $e->getMessage(),
        handler: $e->getFIRSHandler() ?? 'unknown',
        errorDetails: [
            'firs_error_id' => $e->getFIRSErrorId(),
            'firs_full_response' => $firsResponse,
            'exception_message' => $e->getMessage()
        ],
        requestPayload: $invoiceData,
        errorType: 'firs_api_error',
        sourceFile: 'test_firs_original_response.php'
    );

    echo "✓ Logged to: {$config['logging']['api_error_log']}\n\n";

} catch (\Exception $e) {
    echo "❌ GENERAL ERROR\n";
    echo "Message: " . $e->getMessage() . "\n";
    echo "Code: " . $e->getCode() . "\n\n";

    $logManager->logException(
        irn: $irn,
        exception: $e,
        handler: 'FIRSAPIClient::submitInvoice',
        publicMessage: null,
        additionalContext: ['endpoint' => '/api/v1/invoice/sign']
    );
}

echo "========================================\n";
echo "CHECK THE LOG FILE\n";
echo "========================================\n\n";

echo "Recent error logs:\n";
$recentLogs = $logManager->getRecentLogs('error', 1);

foreach ($recentLogs as $log) {
    echo "\nTimestamp: {$log['timestamp']}\n";
    echo "IRN: {$log['irn']}\n";
    echo "Source File: {$log['source_file']}\n";
    echo "Handler (dari FIRS): {$log['handler']}\n";
    echo "Public Message (dari FIRS): {$log['public_message']}\n";
    echo "Detailed Message (dari FIRS): {$log['detailed_message']}\n";
    echo "HTTP Code: {$log['http_code']}\n";
}

echo "\n✅ Test selesai!\n";
echo "Log berisi response ORIGINAL dari FIRS API (tidak diterjemahkan)\n";
