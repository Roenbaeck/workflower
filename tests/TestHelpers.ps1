# A very small test runner. Dot-source it, call Assert-*, end with Complete-Tests.
$global:Passed = 0
$global:Failed = 0

function global:Assert-True {
    param($Condition, [string] $Message)
    if ($Condition) { $global:Passed++; Write-Host ('  ok    ' + $Message) }
    else { $global:Failed++; Write-Host ('  FAIL  ' + $Message) -ForegroundColor Red }
}

function global:Assert-Equal {
    param($Actual, $Expected, [string] $Message)
    $a = ConvertTo-Json -InputObject @($Actual) -Depth 8 -Compress
    $e = ConvertTo-Json -InputObject @($Expected) -Depth 8 -Compress
    if ($a -ceq $e) { $global:Passed++; Write-Host ('  ok    ' + $Message) }
    else { $global:Failed++; Write-Host ('  FAIL  ' + $Message) -ForegroundColor Red; Write-Host ('        expected: ' + $e); Write-Host ('        actual:   ' + $a) }
}

function global:Assert-Throws {
    param([scriptblock] $Block, [string] $Pattern, [string] $Message)
    $text = $null
    try { & $Block | Out-Null } catch { $text = $_.Exception.Message }
    if ($null -ne $text -and $text -match $Pattern) { $global:Passed++; Write-Host ('  ok    ' + $Message) }
    else { $global:Failed++; Write-Host ('  FAIL  ' + $Message) -ForegroundColor Red; Write-Host ('        message: ' + $text) }
}

function global:Complete-Tests {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $global:Passed, $global:Failed)
    if ($global:Failed -gt 0) { exit 1 }
    exit 0
}
