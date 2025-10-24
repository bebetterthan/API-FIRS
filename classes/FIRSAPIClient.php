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
            throw new \Exception('FIRS API error: ' . ($responseData['message'] ?? 'Unknown error') . ' (HTTP ' . $httpCode . ')');
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

            curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            return $httpCode > 0;

        } catch (\Exception $e) {
            return false;
        }
    }
}
