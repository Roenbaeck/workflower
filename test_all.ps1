<#
    Run the Snowflake SQL test suite in sql/.

    These are smoke tests: they render templates and print the result. They catch errors
    and regressions in the engine, not wrong output. Read the output.

    Usage: .\test_all.ps1 <connection_name>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'webapp\Snow.ps1')

$tests = [ordered]@{
    'Basic rendering'      = 'test_render.sql'
    'AND/OR operators'     = 'test_and_or.sql'
    'contains() function'  = 'test_contains.sql'
    'Inline IF OR'         = 'test_inline_if_or.sql'
    'Nested inline IF'     = 'test_nested_inline_if.sql'
    'Escaping tokens'      = 'test_escaping.sql'
}

Write-Host '=== sisula-snowflake test suite ==='
Write-Host "Connection: $Connection"
Write-Host ''

$passed = 0
$failed = 0

foreach ($name in $tests.Keys) {
    $file = Join-Path $root (Join-Path 'sql' $tests[$name])
    Write-Host "--- $name ---"
    $sql = Get-Content -LiteralPath $file -Raw
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    Write-Host $result.Text
    # Files that assert report a STATUS column; a FAIL there is a regression even though
    # the statement itself executed cleanly.
    $asserted = $result.Text -match '"STATUS"\s*:\s*"FAIL"'
    if ($result.Success -and -not $asserted) { $passed++; Write-Host '  PASS' }
    else { $failed++; Write-Host '  FAIL' }
    Write-Host ''
}

Write-Host "=== Results: $passed passed, $failed failed ==="
if ($failed -gt 0) { exit 1 }
