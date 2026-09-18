<#
    Deploy the Sisula engine to Snowflake.

    Splices webapp/sisula.js into the SISULATE JavaScript UDF in sql/deploy.sql, replacing
    the __SISULA_JS_SOURCE__ marker, then runs the result.

    Usage: .\deploy.ps1 <connection_name>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'webapp\Snow.ps1')

$sourcePath   = Join-Path $root 'webapp\sisula.js'
$templatePath = Join-Path $root 'sql\deploy.sql'

$javascript = Get-Content -LiteralPath $sourcePath -Raw

# A doubled dollar inside the JavaScript would close the UDF body early.
if ($javascript -match '\$\$') {
    throw "$sourcePath contains a doubled dollar, which would break the SQL UDF delimiter."
}

# The UDF has no module system; drop the Node export so the body is plain script.
$lines = $javascript -split "`r?`n" | Where-Object { $_ -notmatch '^\s*module\.exports\s*=\s*sisulate;\s*$' }
$javascript = $lines -join [Environment]::NewLine

$template = Get-Content -LiteralPath $templatePath -Raw
if ($template -notmatch '__SISULA_JS_SOURCE__') {
    throw "Missing __SISULA_JS_SOURCE__ marker in $templatePath"
}

# Replace() rather than -replace: the JavaScript contains regex literals with $ groups that
# -replace would treat as substitution patterns.
$rendered = $template.Replace('// __SISULA_JS_SOURCE__', $javascript)

Write-Host '=== sisula-snowflake deploy ==='
Write-Host "Connection: $Connection"
Write-Host ''

$result = Invoke-SnowSqlChecked -Sql $rendered -Connection $Connection -Activity 'Sisula engine deploy'
Write-Host $result.Text
Write-Host ''
Write-Host '=== Deploy complete ==='
