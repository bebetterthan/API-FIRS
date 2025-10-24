<?php
namespace FIRS;


class IRNProcessor {
    private $config;

    public function __construct($config) {
        $this->config = $config;
    }


    public function extractIRN(array $invoice): string {
        if (!isset($invoice['irn']) || empty($invoice['irn'])) {
            throw new \Exception('IRN not found in invoice data');
        }

        $irn = trim($invoice['irn']);


        if (!$this->validateIRNFormat($irn)) {
            throw new \Exception('Invalid IRN format: ' . $irn);
        }

        return $irn;
    }


    public function validateIRNFormat(string $irn): bool {
        // Format: PFNLXXXX-YYYYYY-YYYYMMDD (without timestamp)
        // Example: PFNL0001-9D3009-20251024
        return preg_match('/^PFNL[A-Z0-9]{4}-[A-Z0-9]{6}-\d{8}$/', $irn) === 1;
    }


    public function formatSignedIRN(string $irn, ?int $timestamp = null): string {
        if ($timestamp === null) {
            $timestamp = time();
        }

        return $irn . '.' . $timestamp;
    }


    public function sanitizeForFilename(string $irn): string {
        // IRN dengan timestamp untuk filename: PFNLXXXX-YYYYYY-YYYYMMDD.timestamp
        // Keep dots, alphanumeric, and hyphens only
        $sanitized = preg_replace('/[^A-Z0-9.-]/i', '', $irn);
        
        // Remove any path traversal attempts
        $sanitized = str_replace(['..', './', '\\'], '', $sanitized);

        return $sanitized;
    }


    public function getDateFolder(array $invoice): string {
        $issueDate = $invoice['issue_date'] ?? date('Y-m-d');


        if (preg_match('/^(\d{4})-(\d{2})/', $issueDate, $matches)) {
            return $matches[1] . '-' . $matches[2];
        }


        return date('Y-m');
    }
}
