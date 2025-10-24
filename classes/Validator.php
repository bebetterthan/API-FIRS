<?php
namespace FIRS;


class Validator {
    private $config;
    private $errors = [];
    private $warnings = [];

    public function __construct($config) {
        $this->config = $config;
    }


    public function validateIRNQuick(array $data): array {
        $this->errors = [];


        if (!isset($data['business_id'])) {
            $this->addError('business_id', 'Business ID is required');
        } elseif (!$this->isValidUUID($data['business_id'])) {
            $this->addError('business_id', 'Invalid UUID format');
        }

        if (!isset($data['irn'])) {
            $this->addError('irn', 'IRN is required');
        } elseif (!$this->validateIRNFormat($data['irn'])) {
            $this->addError('irn', 'Invalid IRN format');
        }

        return [
            'valid' => empty($this->errors),
            'errors' => $this->errors,
            'irn' => $data['irn'] ?? null,
            'business_id' => $data['business_id'] ?? null,
        ];
    }


    public function validateFull(array $invoice): array {
        $this->errors = [];
        $this->warnings = [];


        $this->validateRequiredFields($invoice);


        $this->validateFormats($invoice);


        $this->validateBusinessLogic($invoice);


        $this->validateTaxCalculations($invoice);


        $this->validateInvoiceLines($invoice);

        return [
            'valid' => empty($this->errors),
            'errors' => $this->errors,
            'warnings' => $this->warnings,
            'fields_validated' => $this->config['validation']['required_fields'],
        ];
    }


    private function validateRequiredFields(array $invoice): void {
        $required = [
            'irn', 'business_id', 'issue_date', 'due_date', 'invoice_type_code',
            'document_currency_code', 'accounting_supplier_party', 'accounting_customer_party',
            'tax_total', 'legal_monetary_total', 'invoice_line'
        ];

        foreach ($required as $field) {
            if (!isset($invoice[$field]) || $invoice[$field] === null || $invoice[$field] === '') {
                $this->addError($field, 'Required field is missing or empty');
            }
        }
    }


    private function validateFormats(array $invoice): void {

        if (isset($invoice['irn']) && !$this->validateIRNFormat($invoice['irn'])) {
            $this->addError('irn', 'Invalid IRN format (must be A-Z0-9- only, 10-50 chars)');
        }


        if (isset($invoice['business_id']) && !$this->isValidUUID($invoice['business_id'])) {
            $this->addError('business_id', 'Invalid UUID format');
        }


        if (isset($invoice['issue_date']) && !$this->isValidDate($invoice['issue_date'])) {
            $this->addError('issue_date', 'Invalid date format (expected YYYY-MM-DD)');
        }

        if (isset($invoice['due_date']) && !$this->isValidDate($invoice['due_date'])) {
            $this->addError('due_date', 'Invalid date format (expected YYYY-MM-DD)');
        }


        $validTypes = array_keys($this->config['nigeria']['invoice_types']);
        if (isset($invoice['invoice_type_code']) && !in_array($invoice['invoice_type_code'], $validTypes)) {
            $this->addError('invoice_type_code', 'Invalid invoice type code (expected: ' . implode(', ', $validTypes) . ')');
        }


        if (isset($invoice['document_currency_code']) && strlen($invoice['document_currency_code']) !== 3) {
            $this->addError('document_currency_code', 'Invalid currency code (expected 3-letter ISO code)');
        }
    }


    private function validateBusinessLogic(array $invoice): void {

        if (isset($invoice['issue_date']) && isset($invoice['due_date'])) {
            if (strtotime($invoice['due_date']) < strtotime($invoice['issue_date'])) {
                $this->addError('due_date', 'Due date cannot be before issue date');
            }


            $daysUntilDue = (strtotime($invoice['due_date']) - strtotime($invoice['issue_date'])) / 86400;
            if ($daysUntilDue < 7) {
                $this->addWarning('due_date', 'Due date is less than 7 days from issue date');
            }
        }
    }


    private function validateTaxCalculations(array $invoice): void {
        if (!isset($invoice['tax_total']) || !is_array($invoice['tax_total'])) {
            return;
        }

        $taxTotal = $invoice['tax_total'];
        $tolerance = $this->config['validation']['tax_tolerance'];


        $taxExclusive = $taxTotal['tax_exclusive_amount'] ?? 0;
        $taxAmount = $taxTotal['tax_amount'] ?? 0;
        $taxInclusive = $taxTotal['tax_inclusive_amount'] ?? 0;
        $taxPercent = $taxTotal['tax_percent'] ?? $this->config['validation']['standard_vat_rate'];


        $expectedTaxAmount = $taxExclusive * ($taxPercent / 100);
        $expectedTaxInclusive = $taxExclusive + $taxAmount;


        if (abs($taxAmount - $expectedTaxAmount) > $tolerance) {
            $this->addError('tax_total.tax_amount', sprintf(
                'Tax amount mismatch (expected: %.2f, got: %.2f)',
                $expectedTaxAmount,
                $taxAmount
            ));
        }

        if (abs($taxInclusive - $expectedTaxInclusive) > $tolerance) {
            $this->addError('tax_total.tax_inclusive_amount', sprintf(
                'Tax inclusive amount mismatch (expected: %.2f, got: %.2f)',
                $expectedTaxInclusive,
                $taxInclusive
            ));
        }
    }


    private function validateInvoiceLines(array $invoice): void {
        if (!isset($invoice['invoice_line']) || !is_array($invoice['invoice_line'])) {
            return;
        }

        $totalLineExtension = 0;

        foreach ($invoice['invoice_line'] as $index => $line) {

            if (!isset($line['invoiced_quantity']) || $line['invoiced_quantity'] <= 0) {
                $this->addError("invoice_line[$index].invoiced_quantity", 'Quantity must be greater than 0');
            }


            if (!isset($line['item'])) {
                $this->addError("invoice_line[$index].item", 'Item details are required');
                continue;
            }

            $item = $line['item'];


            if (!isset($item['name']) || empty($item['name'])) {
                $this->addError("invoice_line[$index].item.name", 'Item name is required');
            }

            if (!isset($item['description']) || empty($item['description'])) {
                $this->addError("invoice_line[$index].item.description", 'Item description is required');
            }


            if (!isset($item['sellers_item_identification'])) {
                $this->addError("invoice_line[$index].item.sellers_item_identification", 'Seller item ID is required');
            } elseif (!is_string($item['sellers_item_identification'])) {
                $this->addError("invoice_line[$index].item.sellers_item_identification", 'Seller item ID must be a string (e.g., "18000001")');
            }


            $priceAmount = $line['price']['price_amount'] ?? $line['price_amount'] ?? 0;

            if ($priceAmount <= 0) {
                $this->addError("invoice_line[$index].price_amount", 'Price must be greater than 0');
            }


            if (!isset($line['hsn_code']) || empty($line['hsn_code'])) {
                $this->addWarning("invoice_line[$index].hsn_code", 'HSN code is recommended for FIRS submission');
            }

            if (!isset($line['product_category']) || empty($line['product_category'])) {
                $this->addWarning("invoice_line[$index].product_category", 'Product category is recommended');
            }


            $quantity = $line['invoiced_quantity'] ?? 0;
            $price = $priceAmount;
            $expectedTotal = $quantity * $price;

            $actualTotal = $line['line_extension_amount'] ?? 0;
            $tolerance = $this->config['validation']['tax_tolerance'];

            if (abs($actualTotal - $expectedTotal) > $tolerance) {
                $this->addError("invoice_line[$index].line_extension_amount", sprintf(
                    'Line total mismatch (expected: %.2f, got: %.2f)',
                    $expectedTotal,
                    $actualTotal
                ));
            }

            $totalLineExtension += $actualTotal;
        }


        if (isset($invoice['legal_monetary_total']['line_extension_amount'])) {
            $expectedTotal = $invoice['legal_monetary_total']['line_extension_amount'];
            $tolerance = $this->config['validation']['tax_tolerance'];

            if (abs($totalLineExtension - $expectedTotal) > $tolerance) {
                $this->addError('legal_monetary_total.line_extension_amount', sprintf(
                    'Total line extension mismatch (expected: %.2f, got: %.2f)',
                    $totalLineExtension,
                    $expectedTotal
                ));
            }
        }
    }


    private function validateIRNFormat(string $irn): bool {
        return preg_match('/^[A-Z0-9-]{10,50}$/', $irn) === 1;
    }


    private function isValidUUID(string $uuid): bool {
        return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $uuid) === 1;
    }


    private function isValidDate(string $date): bool {
        $d = \DateTime::createFromFormat('Y-m-d', $date);
        return $d && $d->format('Y-m-d') === $date;
    }


    private function addError(string $field, string $message): void {
        $this->errors[] = [
            'field' => $field,
            'message' => $message,
        ];
    }


    private function addWarning(string $field, string $message): void {
        $this->warnings[] = [
            'field' => $field,
            'message' => $message,
        ];
    }
}
