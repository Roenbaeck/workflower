# The work of the fake snow: see the snow script beside this file.
param([Parameter(ValueFromRemainingArguments = $true)] $Arguments)
$ErrorActionPreference = 'Stop'
$file = $null; $role = $env:FAKE_SNOW_ROLE; $warehouse = $env:FAKE_SNOW_WAREHOUSE; $database = $null; $schema = $null
for ($i = 0; $i -lt $Arguments.Count; $i++) {
    switch ([string]$Arguments[$i]) {
        '-f' { $file = [string]$Arguments[$i + 1]; $i++ }
        '--role' { $role = [string]$Arguments[$i + 1]; $i++ }
        '--warehouse' { $warehouse = [string]$Arguments[$i + 1]; $i++ }
        '--database' { $database = [string]$Arguments[$i + 1]; $i++ }
        '--schema' { $schema = [string]$Arguments[$i + 1]; $i++ }
        '-c' { $i++ }
        '--format' { $i++ }
        '--enable-templating' { $i++ }
    }
}
if (-not $file) { [Console]::Error.WriteLine('fake snow: no -f file'); exit 1 }
Import-Module (Join-Path $PSScriptRoot '..\..\..\Workflower\Workflower.psd1') -Force
$session = New-WfSession -Account $env:FAKE_SNOW_ACCOUNT -TokenFile $env:FAKE_SNOW_TOKENFILE -Warehouse $warehouse -Role $role
$sql = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
try {
    $rows = @(Invoke-WfSql $session $sql -Database $database -Schema $schema)
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
$out = New-Object System.Collections.Generic.List[string]
foreach ($r in $rows) {
    $pairs = @($r.psobject.Properties | ForEach-Object { '"' + ([string]$_.Name).Replace('\', '\\').Replace('"', '\"') + '": ' + $(if ($null -eq $_.Value) { 'null' } else { '"' + ([string]$_.Value).Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t') + '"' }) })
    $out.Add('{' + ($pairs -join ', ') + '}')
}
[Console]::Out.Write('[' + ($out -join ', ') + "]`n")
