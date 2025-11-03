<?php
namespace FIRS;

/**
 * Custom Exception for FIRS API Errors
 *
 * Stores the original response data from FIRS API
 * including error details, handler, and public_message
 */
class FIRSAPIException extends \Exception {
    private $httpCode;
    private $responseData;

    /**
     * Set HTTP status code
     */
    public function setHttpCode(int $code): void {
        $this->httpCode = $code;
    }

    /**
     * Get HTTP status code
     */
    public function getHttpCode(): int {
        return $this->httpCode ?? 500;
    }

    /**
     * Set full response data from FIRS API
     */
    public function setResponseData(?array $data): void {
        $this->responseData = $data;
    }

    /**
     * Get full response data from FIRS API
     */
    public function getResponseData(): ?array {
        return $this->responseData;
    }

    /**
     * Get FIRS error details
     */
    public function getFIRSError(): ?array {
        return $this->responseData['error'] ?? null;
    }

    /**
     * Get FIRS handler (original from FIRS)
     */
    public function getFIRSHandler(): ?string {
        return $this->responseData['error']['handler'] ?? null;
    }

    /**
     * Get FIRS message (original from FIRS API)
     */
    public function getFIRSMessage(): ?string {
        return $this->responseData['error']['message'] ?? null;
    }

    /**
     * Get FIRS public message (original from FIRS)
     */
    public function getFIRSPublicMessage(): ?string {
        return $this->responseData['error']['public_message'] ?? null;
    }

    /**
     * Get FIRS error details/description
     */
    public function getFIRSDetails(): ?string {
        return $this->responseData['error']['details'] ?? null;
    }

    /**
     * Get FIRS error ID
     */
    public function getFIRSErrorId(): ?string {
        return $this->responseData['error']['id'] ?? null;
    }
}
