<?php
namespace FIRS;


class FileManager {
    private $config;
    private static $dirCache = [];

    public function __construct($config) {
        $this->config = $config;
    }

    private function ensureDir(string $dir): void {
        if (isset(self::$dirCache[$dir])) {
            return;
        }
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        self::$dirCache[$dir] = true;
    }

    public function saveInvoiceJSON(string $signedIRN, array $invoice): string {
        $irnProcessor = new IRNProcessor($this->config);
        // Use signedIRN (includes timestamp) for filename
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($signedIRN);
        $baseDir = $this->config['paths']['json'];
        $this->ensureDir($baseDir);
        $filename = $sanitizedIRN . '.json';
        $filepath = $baseDir . '/' . $filename;
        
        $jsonContent = json_encode($invoice, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
        // Use LOCK_EX for atomic write and FILE_APPEND for buffering
        $result = file_put_contents($filepath, $jsonContent, LOCK_EX);
        if ($result === false) {
            throw new \Exception('Failed to save JSON invoice file');
        }
        return $filepath;
    }

    public function saveEncryptedData(string $irn, string $signedIRN, string $encryptedData, array $invoice): string {
        $irnProcessor = new IRNProcessor($this->config);
        // Use signedIRN (includes timestamp) for filename
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($signedIRN);
        $baseDir = $this->config['paths']['encrypted'];
        $this->ensureDir($baseDir);
        $filename = $sanitizedIRN . '.txt';
        $filepath = $baseDir . '/' . $filename;

        // Save pure Base64 encrypted data with atomic write
        $result = file_put_contents($filepath, $encryptedData, LOCK_EX);
        if ($result === false) {
            throw new \Exception('Failed to save encrypted data file');
        }
        return $filepath;
    }


    public function fileExists(string $irn): bool {
        $irnProcessor = new IRNProcessor($this->config);
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($irn);


        $encryptedDir = $this->config['paths']['encrypted'];

        if (!is_dir($encryptedDir)) {
            return false;
        }

        $folders = scandir($encryptedDir);

        foreach ($folders as $folder) {
            if ($folder === '.' || $folder === '..') {
                continue;
            }

            $filepath = $encryptedDir . '/' . $folder . '/' . $sanitizedIRN . '.txt';
            if (file_exists($filepath)) {
                return true;
            }
        }

        return false;
    }


    public function findFilePath(string $irn): ?string {
        $irnProcessor = new IRNProcessor($this->config);
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($irn);


        $encryptedDir = $this->config['paths']['encrypted'];

        if (!is_dir($encryptedDir)) {
            return null;
        }

        $folders = scandir($encryptedDir);

        foreach ($folders as $folder) {
            if ($folder === '.' || $folder === '..') {
                continue;
            }

            $filepath = $encryptedDir . '/' . $folder . '/' . $sanitizedIRN . '.txt';
            if (file_exists($filepath)) {
                return $filepath;
            }
        }

        return null;
    }


    public function findQRPath(string $irn): ?string {
        $irnProcessor = new IRNProcessor($this->config);
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($irn);


        $qrDir = $this->config['paths']['qrcodes'];

        if (!is_dir($qrDir)) {
            return null;
        }

        $folders = scandir($qrDir);

        foreach ($folders as $folder) {
            if ($folder === '.' || $folder === '..') {
                continue;
            }

            $filepath = $qrDir . '/' . $folder . '/' . $sanitizedIRN . '.png';
            if (file_exists($filepath)) {
                return $filepath;
            }
        }

        return null;
    }


    public function downloadFile(string $irn, string $type = 'qr'): void {
        $irnProcessor = new IRNProcessor($this->config);
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($irn);

        switch ($type) {
            case 'txt':
                $this->downloadEncryptedFile($sanitizedIRN);
                break;

            case 'qr':
                $this->downloadQRFile($sanitizedIRN);
                break;

            case 'both':
                $this->downloadBothFiles($sanitizedIRN);
                break;

            case 'json':
                $this->returnMetadata($sanitizedIRN);
                break;

            default:
                throw new \Exception('Invalid download type');
        }
    }


    private function downloadEncryptedFile(string $sanitizedIRN): void {
        $filepath = $this->findFilePath($sanitizedIRN);

        if (!$filepath || !file_exists($filepath)) {
            throw new \Exception('Encrypted file not found');
        }

        header('Content-Type: application/json');
        header('Content-Disposition: attachment; filename="' . $sanitizedIRN . '.txt"');
        header('Content-Length: ' . filesize($filepath));
        header('Cache-Control: private, max-age=3600');

        readfile($filepath);
        exit;
    }


    private function downloadQRFile(string $sanitizedIRN): void {
        $filepath = $this->findQRPath($sanitizedIRN);

        if (!$filepath || !file_exists($filepath)) {
            throw new \Exception('QR code file not found');
        }

        header('Content-Type: image/png');
        header('Content-Disposition: inline; filename="' . $sanitizedIRN . '.png"');
        header('Content-Length: ' . filesize($filepath));
        header('Cache-Control: public, max-age=86400');

        readfile($filepath);
        exit;
    }


    private function downloadBothFiles(string $sanitizedIRN): void {
        $encryptedPath = $this->findFilePath($sanitizedIRN);
        $qrPath = $this->findQRPath($sanitizedIRN);

        if (!$encryptedPath || !$qrPath) {
            throw new \Exception('One or more files not found');
        }


        $zipFile = sys_get_temp_dir() . '/' . $sanitizedIRN . '_package.zip';
        $zip = new \ZipArchive();

        if ($zip->open($zipFile, \ZipArchive::CREATE | \ZipArchive::OVERWRITE) !== true) {
            throw new \Exception('Failed to create ZIP file');
        }

        $zip->addFile($encryptedPath, $sanitizedIRN . '_encrypted.txt');
        $zip->addFile($qrPath, $sanitizedIRN . '_qr.png');
        $zip->close();


        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="' . $sanitizedIRN . '_package.zip"');
        header('Content-Length: ' . filesize($zipFile));

        readfile($zipFile);
        unlink($zipFile);
        exit;
    }


    private function returnMetadata(string $sanitizedIRN): void {
        $encryptedPath = $this->findFilePath($sanitizedIRN);
        $qrPath = $this->findQRPath($sanitizedIRN);

        $metadata = [
            'irn' => $sanitizedIRN,
            'files' => [],
        ];

        if ($encryptedPath && file_exists($encryptedPath)) {
            $data = json_decode(file_get_contents($encryptedPath), true);
            $metadata['encrypted_file'] = [
                'path' => basename(dirname($encryptedPath)) . '/' . basename($encryptedPath),
                'size' => filesize($encryptedPath),
                'created' => date('Y-m-d\TH:i:s\Z', filectime($encryptedPath)),
                'data' => $data,
            ];
        }

        if ($qrPath && file_exists($qrPath)) {
            $metadata['qr_file'] = [
                'path' => basename(dirname($qrPath)) . '/' . basename($qrPath),
                'size' => filesize($qrPath),
                'created' => date('Y-m-d\TH:i:s\Z', filectime($qrPath)),
                'url' => $this->config['app']['url'] . '/output/qrcodes/' . basename(dirname($qrPath)) . '/' . basename($qrPath),
            ];
        }

        header('Content-Type: application/json');
        echo json_encode($metadata, JSON_PRETTY_PRINT);
        exit;
    }
}
