<#
    Remove aged files from the Workflower stage.

    Snowflake has no expiry for staged files, and both LIST and REMOVE are rejected inside
    a stored procedure, so this cannot be a Snowflake task. Schedule it with Windows Task
    Scheduler on the server instead.

    Defaults keep the audit trail long and the rest short: out/ holds the SQL that was
    actually executed, while in/ duplicates a configuration already stored historized in
    the metadata model and export/ has already been downloaded.

    Usage:
      .\prune.ps1 <connection_name> [-InDays 7] [-OutDays 90] [-ExportDays 7] [-WhatIf]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection,
    [double] $InDays = 7,
    [double] $OutDays = 90,
    [double] $ExportDays = 7,
    [switch] $WhatIf
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'webapp\Snow.ps1')

foreach ($days in @($InDays, $OutDays, $ExportDays)) {
    if ($days -lt 0) { throw 'Retention in days must be zero or greater' }
}

# The directory table on an internal stage does not refresh itself.
Write-Host 'Refreshing the stage directory...'
Invoke-SnowSqlChecked -Sql 'ALTER STAGE metadata.WORKFLOWER REFRESH;' -Connection $Connection -Activity 'Stage refresh' | Out-Null

$areas = [ordered]@{
    'in'     = $InDays
    'out'    = $OutDays
    'export' = $ExportDays
}

$doomed = @()
foreach ($area in $areas.Keys) {
    # Only the area name and a validated number reach the SQL.
    $days = [double]$areas[$area]
    if ($area -notmatch '^[a-z]+$') { throw "Unexpected area name: $area" }

    $sql = "SELECT PATH, ROUND(AGE_DAYS, 2) AS AGE_DAYS, BYTES FROM metadata.WORKFLOWER_STAGE_FILES " +
           "WHERE AREA = '$area' AND AGE_DAYS > $($days.ToString([System.Globalization.CultureInfo]::InvariantCulture)) " +
           "ORDER BY AGE_DAYS DESC;"
    $result = Invoke-SnowSqlChecked -Sql $sql -Connection $Connection -Activity "Find aged files in $area/"

    $rows = @()
    if ($null -ne $result.Json) {
        $parsed = $result.Json
        if ($parsed -is [System.Array]) { $rows = $parsed } else { $rows = @($parsed) }
    }
    foreach ($row in $rows) {
        if ($null -eq $row -or -not $row.PATH) { continue }
        $doomed += [pscustomobject]@{ Path = $row.PATH; AgeDays = $row.AGE_DAYS; Bytes = $row.BYTES }
    }
    Write-Host ("  {0,-8} keep {1,5} days -> {2} file(s) to remove" -f ($area + '/'), $days, @($rows).Count)
}

if ($doomed.Count -eq 0) {
    Write-Host 'Nothing to remove.'
    exit 0
}

$totalBytes = ($doomed | Measure-Object -Property Bytes -Sum).Sum
Write-Host ''
Write-Host ("{0} file(s), {1:N0} bytes" -f $doomed.Count, $totalBytes)
foreach ($item in $doomed | Select-Object -First 10) {
    Write-Host ("  {0}  ({1} days)" -f $item.Path, $item.AgeDays)
}
if ($doomed.Count -gt 10) { Write-Host ("  ... and {0} more" -f ($doomed.Count - 10)) }

if ($WhatIf) {
    Write-Host ''
    Write-Host 'WhatIf: nothing was removed.'
    exit 0
}

# One statement per file, all in a single call. Paths come from the directory table, but
# they are still checked before being concatenated into SQL.
$statements = New-Object System.Text.StringBuilder
foreach ($item in $doomed) {
    if ($item.Path -notmatch '^[A-Za-z0-9_\-/.]+$') {
        throw "Refusing to build a REMOVE for an unexpected path: $($item.Path)"
    }
    [void]$statements.AppendLine("REMOVE @metadata.WORKFLOWER/$($item.Path);")
}

Write-Host ''
Write-Host 'Removing...'
Invoke-SnowSqlChecked -Sql $statements.ToString() -Connection $Connection -Activity 'Stage prune' | Out-Null
Invoke-SnowSqlChecked -Sql 'ALTER STAGE metadata.WORKFLOWER REFRESH;' -Connection $Connection -Activity 'Stage refresh' | Out-Null
Write-Host ("Removed {0} file(s)." -f $doomed.Count)
