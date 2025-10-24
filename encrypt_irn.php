<?php
/**
 * Encrypt IRN with certificate using RSA public key from crypto_keys.txt
 * Usage: php encrypt_irn.php <IRN_SIGNED>
 * Output: Base64-encoded encrypted data
 */

if ($argc < 2) {
    fwrite(STDERR, "ERROR: Missing IRN parameter\n");
    exit(1);
}

$irnSigned = $argv[1];
$keysFile = __DIR__ . '/storage/crypto_keys.txt';

// Load crypto keys
if (!file_exists($keysFile)) {
    fwrite(STDERR, "ERROR: crypto_keys.txt not found at: $keysFile\n");
    exit(1);
}

$keys = json_decode(file_get_contents($keysFile), true);
if (!$keys || !isset($keys['public_key']) || !isset($keys['certificate'])) {
    fwrite(STDERR, "ERROR: Invalid crypto_keys.txt format\n");
    exit(1);
}

// Decode public key
$publicKeyPem = base64_decode($keys['public_key']);
if (!$publicKeyPem) {
    fwrite(STDERR, "ERROR: Failed to decode public key\n");
    exit(1);
}

// Create public key resource
$publicKey = openssl_pkey_get_public($publicKeyPem);
if (!$publicKey) {
    fwrite(STDERR, "ERROR: Invalid public key: " . openssl_error_string() . "\n");
    exit(1);
}

// Create payload
$payload = json_encode([
    'irn' => $irnSigned,
    'certificate' => $keys['certificate']
], JSON_UNESCAPED_SLASHES);

// Encrypt with RSA
$encrypted = '';
$result = openssl_public_encrypt($payload, $encrypted, $publicKey, OPENSSL_PKCS1_PADDING);

if (!$result) {
    fwrite(STDERR, "ERROR: Encryption failed: " . openssl_error_string() . "\n");
    exit(1);
}

// Output Base64
echo base64_encode($encrypted);
exit(0);
