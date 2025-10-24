<?php
namespace FIRS;


class InvoiceManager {
    private $config;
    private $indexFile;

    public function __construct($config) {
        $this->config = $config;
        $this->indexFile = $this->config['paths']['invoice_index'];
        $this->initializeIndex();
    }


    private function initializeIndex(): void {
        if (!file_exists($this->indexFile)) {
            $this->saveIndex([
                'invoices' => [],
                'last_updated' => date('Y-m-d\TH:i:s\Z'),
                'total_count' => 0,
            ]);
        }
    }


    private function loadIndex(): array {
        if (!file_exists($this->indexFile)) {
            return ['invoices' => [], 'total_count' => 0];
        }

        $content = file_get_contents($this->indexFile);
        return json_decode($content, true) ?? ['invoices' => [], 'total_count' => 0];
    }


    private function saveIndex(array $data): void {
        $content = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
        file_put_contents($this->indexFile, $content, LOCK_EX);
    }


    public function isDuplicate(string $irn): bool {
        $index = $this->loadIndex();

        foreach ($index['invoices'] as $invoice) {
            if ($invoice['irn'] === $irn) {
                return true;
            }
        }

        return false;
    }


    public function createInvoiceRecord(string $irn, string $signedIRN, array $invoiceData, string $encryptedFile, string $qrFile): void {
        $index = $this->loadIndex();

        $record = [
            'irn' => $irn,
            'irn_signed' => $signedIRN,
            'business_id' => $invoiceData['business_id'] ?? null,
            'issue_date' => $invoiceData['issue_date'] ?? null,
            'due_date' => $invoiceData['due_date'] ?? null,
            'payment_status' => $invoiceData['payment_status'] ?? 'UNPAID',
            'signed' => true,
            'signed_at' => date('Y-m-d\TH:i:s\Z'),
            'files' => [
                'encrypted' => $this->getRelativePath($encryptedFile),
                'qr_code' => $this->getRelativePath($qrFile),
            ],
            'summary' => [
                'supplier' => $invoiceData['accounting_supplier_party']['party']['party_name']['name'] ?? 'N/A',
                'customer' => $invoiceData['accounting_customer_party']['party']['party_name']['name'] ?? 'N/A',
                'total_amount' => $invoiceData['legal_monetary_total']['payable_amount'] ?? 0,
                'currency' => $invoiceData['document_currency_code'] ?? 'NGN',
            ],
        ];

        $index['invoices'][] = $record;
        $index['total_count'] = count($index['invoices']);
        $index['last_updated'] = date('Y-m-d\TH:i:s\Z');

        $this->saveIndex($index);
    }


    public function getInvoiceStatus(string $irn, ?string $businessId = null): array {
        $index = $this->loadIndex();

        foreach ($index['invoices'] as $invoice) {
            if ($invoice['irn'] === $irn) {

                if ($businessId && $invoice['business_id'] !== $businessId) {
                    throw new \Exception('Business ID mismatch');
                }


                $encryptedPath = $this->config['paths']['storage'] . '/' . $invoice['files']['encrypted'];
                $qrPath = $this->config['paths']['output'] . '/' . $invoice['files']['qr_code'];

                $status = 'complete';
                if (!file_exists($encryptedPath) || !file_exists($qrPath)) {
                    $status = 'partial';
                }

                return [
                    'status' => $status,
                    'irn' => $invoice['irn'],
                    'irn_signed' => $invoice['irn_signed'],
                    'signed' => $invoice['signed'],
                    'signed_at' => $invoice['signed_at'],
                    'files' => [
                        'encrypted' => [
                            'path' => $invoice['files']['encrypted'],
                            'exists' => file_exists($encryptedPath),
                        ],
                        'qr_code' => [
                            'path' => $invoice['files']['qr_code'],
                            'exists' => file_exists($qrPath),
                        ],
                    ],
                    'summary' => $invoice['summary'],
                ];
            }
        }

        throw new \Exception('Invoice not found');
    }


    public function getInvoiceByIRN(string $irn): ?array {
        $index = $this->loadIndex();

        foreach ($index['invoices'] as $invoice) {
            if ($invoice['irn'] === $irn) {
                return $invoice;
            }
        }

        return null;
    }


    private function getRelativePath(string $fullPath): string {
        $basePath = dirname($this->config['paths']['storage']);
        return str_replace($basePath . '/', '', $fullPath);
    }
}
