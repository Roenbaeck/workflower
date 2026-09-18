<#
    Render workflow JSON with the template deployed in Snowflake, then optionally execute it.

    The input is rendered but not stored as a configuration; save it through the editor if
    you want it in the workflow library.

    Usage:
      .\install.ps1 <connection_name> <directory> [-DryRun] [-Template CreateTaskGraph]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection,
    [Parameter(Mandatory = $true, Position = 1)][string] $Directory,
    [string] $Template = 'CreateTaskGraph',
    [switch] $DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'webapp\Snow.ps1')

if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    throw "Directory does not exist: $Directory"
}
# The template name reaches SQL as a literal and is also part of an output filename.
if ($Template -notmatch '^[A-Za-z0-9_]+$') {
    throw "Template name must be alphanumeric: '$Template'"
}

$files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.json' | Sort-Object Name)
if ($files.Count -eq 0) {
    Write-Host "No .json files found in $Directory"
    exit 0
}

# Validate every input before executing any DDL.
foreach ($file in $files) {
    try { Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null }
    catch { throw "Workflow JSON is invalid in $($file.Name): $($_.Exception.Message)" }
}

$outputDir = Join-Path $Directory 'rendered'
if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

foreach ($file in $files) {
    Write-Host "Rendering: $($file.Name)"

    $inRunId  = Assert-RunId (New-RunId)
    $outRunId = Assert-RunId (New-RunId)
    $staged   = Join-Path ([System.IO.Path]::GetTempPath()) "$inRunId.json"

    Copy-Item -LiteralPath $file.FullName -Destination $staged -Force
    try {
        Copy-ToStage -LocalPath $staged -StagePath '@metadata.WORKFLOWER/in/' -Connection $Connection | Out-Null
    }
    finally {
        Remove-Item $staged -Force -ErrorAction SilentlyContinue
    }

    $sql = "CALL metadata._RenderStageFileToStage('$inRunId', '$Template', '$outRunId');"
    Invoke-SnowSqlChecked -Sql $sql -Connection $Connection -Activity "Render $($file.Name)" | Out-Null

    # Keep a local copy of exactly what will run. The stage keeps one too.
    Copy-FromStage -StagePath "@metadata.WORKFLOWER/out/$outRunId.sql" -LocalDirectory $outputDir -Connection $Connection | Out-Null
    $rendered = Join-Path $outputDir "$($Template)_$($file.BaseName).sql"
    Move-Item -LiteralPath (Join-Path $outputDir "$outRunId.sql") -Destination $rendered -Force
    Write-Host "Rendered: $rendered"

    if ($DryRun) { continue }

    # Execution stops at the first failure and leaves earlier statements applied.
    $sql = "EXECUTE IMMEDIATE FROM @metadata.WORKFLOWER/out/$outRunId.sql;"
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    if (-not $result.Success) {
        Write-Host $result.Text
        throw "Install failed for $($file.Name). Earlier statements may already have been applied; inspect Snowflake before retrying. Rendered SQL: $rendered"
    }
    Write-Host "Installed: $($file.Name)"
}

Write-Host 'Done.'
