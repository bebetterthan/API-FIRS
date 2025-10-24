<?php
namespace FIRS;


class CryptoService {
    private $config;
    private static $keysCache = null;
    private static $publicKeyResource = null;

    public function __construct($config) {
        $this->config = $config;
    }


    private function loadKeys(): array {
        if (self::$keysCache !== null) {
            return self::$keysCache;
        }

        $cacheKey = 'firs_crypto_keys';
        if (extension_loaded('apcu') && apcu_enabled()) {
            $cached = apcu_fetch($cacheKey);
            if ($cached !== false) {
                self::$keysCache = $cached;
                return self::$keysCache;
            }
        }

        $keysFile = $this->config['paths']['crypto_keys'];

        if (!file_exists($keysFile)) {
            throw new \Exception('Crypto keys file not found: ' . $keysFile);
        }

        $content = file_get_contents($keysFile);
        $keys = json_decode($content, true);

        if (json_last_error() !== JSON_ERROR_NONE || !isset($keys['public_key'])) {
            throw new \Exception('Invalid crypto keys file format');
        }


        $publicKeyPem = base64_decode($keys['public_key']);

        if (!$publicKeyPem) {
            throw new \Exception('Failed to decode public key from Base64');
        }

        self::$keysCache = [
            'public_key_pem' => $publicKeyPem,
            'certificate' => $keys['certificate'] ?? '',
        ];

        if (extension_loaded('apcu') && apcu_enabled()) {
            apcu_store($cacheKey, self::$keysCache, 3600);
        }

        return self::$keysCache;
    }

    private function getPublicKeyResource() {
        if (self::$publicKeyResource !== null) {
            return self::$publicKeyResource;
        }

        $keys = $this->loadKeys();
        self::$publicKeyResource = openssl_pkey_get_public($keys['public_key_pem']);

        if (!self::$publicKeyResource) {
            throw new \Exception('Failed to load public key: ' . openssl_error_string());
        }

        return self::$publicKeyResource;
    }


    public function encryptIRN(string $irn, string $signedIRN): string {
        $keys = $this->loadKeys();


        $payload = json_encode([
            'irn' => $signedIRN,
            'certificate' => $keys['certificate'],
        ], JSON_UNESCAPED_SLASHES);


        $publicKey = $this->getPublicKeyResource();


        $encrypted = '';
        $result = openssl_public_encrypt(
            $payload,
            $encrypted,
            $publicKey,
            OPENSSL_PKCS1_PADDING
        );

        if (!$result) {
            throw new \Exception('Encryption failed: ' . openssl_error_string());
        }


        return base64_encode($encrypted);
    }


    public function testEncryption(): bool {
        try {
            $keys = $this->loadKeys();
            $publicKey = openssl_pkey_get_public($keys['public_key_pem']);
            return $publicKey !== false;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Clean up OpenSSL resource on shutdown (for long-running processes)
     */
    public static function cleanup(): void {
        if (self::$publicKeyResource !== null) {
            openssl_pkey_free(self::$publicKeyResource);
            self::$publicKeyResource = null;
        }
    }
}
