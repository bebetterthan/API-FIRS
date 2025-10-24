<?php
namespace FIRS;

use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;


class QRGenerator {
    private $config;
    private static $dirCache = [];
    private static $qrOptions = null;

    public function __construct($config) {
        $this->config = $config;
        if (self::$qrOptions === null) {
            self::$qrOptions = new QROptions([
                'version'          => QRCode::VERSION_AUTO,
                'outputType'       => QRCode::OUTPUT_IMAGE_PNG,
                'eccLevel'         => QRCode::ECC_L,  // Low error correction = faster
                'scale'            => 10,              // 10 pixels per module (adjust based on QR version)
                'imageBase64'      => false,
                'imageTransparent' => false,           // Disable transparency = faster
                'addQuietzone'     => true,            // Add white border
                'quietzoneSize'    => 2,               // Minimal quiet zone
                'outputInterface'  => null,            // Use default output
                'returnResource'   => false,
            ]);
        }
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


    public function generate(string $encryptedData, string $signedIRN): string {
        $irnProcessor = new IRNProcessor($this->config);
        // Use signedIRN (includes timestamp) for filename
        $sanitizedIRN = $irnProcessor->sanitizeForFilename($signedIRN);
        $baseDir = $this->config['paths']['qrcodes'];
        $this->ensureDir($baseDir);
        $filename = $sanitizedIRN . '.png';
        $filepath = $baseDir . '/' . $filename;
        try {
            $qrcode = new QRCode(self::$qrOptions);
            $qrcode->render($encryptedData, $filepath);
            
            if (!file_exists($filepath)) {
                throw new \Exception('QR code file was not created');
            }
            
            // Resize to 300x300px to save storage
            $this->resizeImage($filepath, 300, 300);
            
            return $filepath;
        } catch (\Exception $e) {
            throw new \Exception('QR code generation failed: ' . $e->getMessage());
        }
    }

    /**
     * Resize image to specific dimensions
     */
    private function resizeImage(string $filepath, int $width, int $height): void {
        if (!extension_loaded('gd')) {
            return; // Skip resize if GD not available
        }
        
        $source = imagecreatefrompng($filepath);
        if (!$source) {
            return;
        }
        
        $dest = imagecreatetruecolor($width, $height);
        
        // Enable better resampling for smaller files
        imagecopyresampled(
            $dest, $source,
            0, 0, 0, 0,
            $width, $height,
            imagesx($source), imagesy($source)
        );
        
        // Compression level 9 = max compression (0-9, where 9 is smallest file)
        imagepng($dest, $filepath, 9);
        imagedestroy($source);
        imagedestroy($dest);
    }


    public function getRelativePath(string $filepath): string {
        $basePath = $this->config['paths']['qrcodes'];
        return str_replace($basePath . '/', '', $filepath);
    }


    public function getPublicUrl(string $filepath): string {
        $relativePath = $this->getRelativePath($filepath);
        return $this->config['app']['url'] . '/output/qrcodes/' . $relativePath;
    }
}
