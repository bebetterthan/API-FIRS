# Test PowerShell 4 Compatibility
# Run this to verify the script works on PowerShell 4

Write-Host "Testing PowerShell Version Compatibility..." -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
Write-Host ""

# Test 1: TLS 1.2 Support
Write-Host "[Test 1] TLS 1.2 Configuration..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "  ✓ TLS 1.2 enabled successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ TLS 1.2 not supported" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: String Concatenation (PS4 compatible)
Write-Host "[Test 2] String Concatenation (PS4 Compatible)..."
$testVar = "test"
$testNum = 123
$msg1 = "Variable: " + $testVar + " Number: " + $testNum
Write-Host "  $msg1" -ForegroundColor Green
Write-Host ""

# Test 3: Variable in String (May fail in PS4)
Write-Host "[Test 3] Complex String Interpolation..."
try {
    # This may cause issues in PS4
    $testMsg = "Value: $($testVar.Length) chars"
    Write-Host "  $testMsg" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Complex interpolation failed (expected in PS4)" -ForegroundColor Yellow
    # Workaround
    $length = $testVar.Length
    $testMsg = "Value: " + $length + " chars"
    Write-Host "  Workaround: $testMsg" -ForegroundColor Green
}
Write-Host ""

# Test 4: JSON Parsing
Write-Host "[Test 4] JSON Parsing..."
try {
    $jsonStr = '{"name":"test","value":123}'
    $jsonObj = $jsonStr | ConvertFrom-Json
    Write-Host "  ✓ JSON parsed: name=$($jsonObj.name), value=$($jsonObj.value)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ JSON parsing failed" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: Web Request (HTTPS)
Write-Host "[Test 5] HTTPS Web Request..."
try {
    $response = Invoke-WebRequest -Uri "https://www.google.com" -Method GET -UseBasicParsing -TimeoutSec 5
    Write-Host "  ✓ HTTPS request successful (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "  ✗ HTTPS request failed" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "Compatibility test complete!" -ForegroundColor Cyan
