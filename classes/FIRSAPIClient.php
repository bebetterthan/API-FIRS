<?php
namespace FIRS;


class FIRSAPIClient {
    private $config;

    public function __construct($config) {
        $this->config = $config;
    }


    public function validateIRN(string $irn, string $businessId, array $invoiceData): array {
        if (!$this->config['firs_api']['enabled']) {
            return [
                'status' => 'disabled',
                'message' => 'FIRS API integration is disabled',
            ];
        }

        $endpoint = $this->config['firs_api']['url'] . $this->config['firs_api']['endpoints']['validate_irn'];

        $payload = [
            'irn' => $irn,
            'business_id' => $businessId,
            'invoice_data' => $invoiceData,
        ];

        return $this->sendRequest('POST', $endpoint, $payload);
    }


    public function submitInvoice(array $invoiceData): array {
        if (!$this->config['firs_api']['enabled']) {
            return [
                'status' => 'disabled',
                'message' => 'FIRS API integration is disabled',
            ];
        }


        $endpoint = $this->config['firs_api']['url'] . '/api/v1/invoice/sign';

        return $this->sendRequest('POST', $endpoint, $invoiceData);
    }


    public function getInvoiceStatus(string $irn): array {
        if (!$this->config['firs_api']['enabled']) {
            return [
                'status' => 'disabled',
                'message' => 'FIRS API integration is disabled',
            ];
        }

        $endpoint = $this->config['firs_api']['url'] . $this->config['firs_api']['endpoints']['status'] . '/' . $irn;

        return $this->sendRequest('GET', $endpoint);
    }


    private function sendRequest(string $method, string $url, ?array $data = null, int $retry = 0): array {
        $ch = curl_init();

        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, $this->config['firs_api']['timeout']);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);

        // SSL/TLS Configuration for Windows Server compatibility
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
        curl_setopt($ch, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);

        // Windows Server: Use system CA bundle
        if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN') {
            // On Windows, try to use system CA bundle
            $caPath = ini_get('curl.cainfo');
            if (!$caPath || !file_exists($caPath)) {
                // Try common locations for CA bundle on Windows
                $possiblePaths = [
                    'C:/www/php/extras/ssl/cacert.pem',
                    'C:/php/extras/ssl/cacert.pem',
                    dirname(PHP_BINARY) . '/extras/ssl/cacert.pem',
                    dirname(PHP_BINARY) . '/cacert.pem',
                ];

                foreach ($possiblePaths as $path) {
                    if (file_exists($path)) {
                        curl_setopt($ch, CURLOPT_CAINFO, $path);
                        break;
                    }
                }
            }
        }

        $headers = [
            'Content-Type: application/json',
            'Accept: application/json',
            'x-api-key: ' . $this->config['api']['key'],
            'x-api-secret: ' . $this->config['api']['secret'],
        ];
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);


        if ($data !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }


        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);


        if ($error) {

            if ($retry < 3) {
                sleep(pow(2, $retry));
                return $this->sendRequest($method, $url, $data, $retry + 1);
            }

            throw new \Exception('FIRS API request failed: ' . $error);
        }


        $responseData = json_decode($response, true);

        if ($httpCode >= 400) {
            // Create custom exception with FIRS response data
            $exception = new FIRSAPIException(
                'FIRS API error: ' . ($responseData['message'] ?? 'Unknown error') . ' (HTTP ' . $httpCode . ')'
            );
            $exception->setHttpCode($httpCode);
            $exception->setResponseData($responseData);
            throw $exception;
        }

        return [
            'status' => 'success',
            'http_code' => $httpCode,
            'data' => $responseData,
        ];
    }


    public function testConnection(): bool {
        if (!$this->config['firs_api']['enabled']) {
            return false;
        }

        try {
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $this->config['firs_api']['url']);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 5);
            curl_setopt($ch, CURLOPT_NOBODY, true);

            // SSL/TLS Configuration for Windows Server
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
            curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
            curl_setopt($ch, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);

            curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            return $httpCode > 0;

        } catch (\Exception $e) {
            return false;
        }
    }
}
