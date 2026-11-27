<#
.SYNOPSIS
    Runs the self-test of the web interface (Workflower/ui/selftest.js) in a headless browser against the demo server, and fails if any
    check fails. Needs Microsoft Edge or Chrome; give -Browser if it is not found.
#>
param([string] $Browser)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/TestHelpers.ps1"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Browser) {
    $candidates = @(
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe', 'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
    )
    $Browser = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Browser) { throw 'No Edge or Chrome found; give -Browser.' }
$port = 8780 + (Get-Random -Minimum 0 -Maximum 9)
$job = Start-Job -ScriptBlock { param($p, $port) Import-Module "$p\Workflower\Workflower.psd1" -Force; Start-Workflower -Session (New-WfSession -Demo) -NoBrowser -Port $port } -ArgumentList $root, $port
try {
    Start-Sleep -Seconds 4
    $saved = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $dom = & $Browser --headless=new --disable-gpu --dump-dom --virtual-time-budget=60000 "http://127.0.0.1:$port/?selftest=1" 2>$null | Out-String
    $ErrorActionPreference = $saved
    $match = [regex]::Match($dom, '(?s)<pre id="selftest"[^>]*>(.*?)</pre>')
    Assert-True $match.Success 'the self-test ran and wrote its result into the page'
    $text = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
    $lines = $text -split "`n"
    $failures = @($lines | Where-Object { $_ -match '^FAIL' })
    $failures | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Red }
    $summary = @($lines | Where-Object { $_ -match '^(ALL PASSED|SOME FAILED|\d+ passed)' } | Select-Object -Last 1)
    if ($summary.Count -gt 0) { Write-Host ('  ' + $summary[0]) }
    Assert-True ($failures.Count -eq 0) 'no check of the interface failed'
    Assert-True ($text -match 'ALL PASSED') 'the self-test says all passed'
} finally {
    Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
}
Complete-Tests
