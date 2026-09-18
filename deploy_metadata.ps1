<#
    Deploy the metadata model, logging procedures and stage-backed procedures.

    The CreateTaskGraph template is seeded through the stage rather than inlined into a
    CALL, so no escaping of the template text is required.

    Usage: .\deploy_metadata.ps1 <connection_name>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'webapp\Snow.ps1')

$steps = [ordered]@{
    '1. Schema'          = 'metadata\Install_1_CreateMetadataSchema.sql'
    '2. Model (DDL)'     = 'metadata\Install_2_MetadataModel.sql'
    '3. Knot values'     = 'metadata\Install_3_InsertKnotValues.sql'
    '4. Logging procs'   = 'metadata\Install_4_CreateLoggingProcedures.sql'
    '5. Config procs'    = 'metadata\Install_5_ConfigurationProcedures.sql'
    '6. Stage procs'     = 'metadata\Install_6_StageProcedures.sql'
    '7. Import procs'    = 'metadata\Install_7_ImportProcedures.sql'
}

Write-Host '=== metadata deploy ==='
Write-Host "Connection: $Connection"
Write-Host ''

foreach ($name in $steps.Keys) {
    Write-Host "--- $name ---"
    $sql = Get-Content -LiteralPath (Join-Path $root $steps[$name]) -Raw
    Invoke-SnowSqlChecked -Sql $sql -Connection $Connection -Activity $name | Out-Null
    Write-Host '  OK'
    Write-Host ''
}

# --- Seed the template through the stage ---
Write-Host '--- 7. Seed template: CreateTaskGraph ---'
$runId = New-RunId
$templatePath = Join-Path $root 'webapp\templates\CreateTaskGraph.sql'
$staged = Join-Path ([System.IO.Path]::GetTempPath()) "$runId.sql"
Copy-Item -LiteralPath $templatePath -Destination $staged -Force
try {
    Copy-ToStage -LocalPath $staged -StagePath '@metadata.WORKFLOWER/in/' -Connection $Connection | Out-Null
    $sql = "CALL metadata._TemplateUpsertFromStage('$(Assert-RunId $runId)', 'CreateTaskGraph');"
    Invoke-SnowSqlChecked -Sql $sql -Connection $Connection -Activity 'Seed CreateTaskGraph' | Out-Null
    Write-Host '  OK'
}
finally {
    Remove-Item $staged -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=== deploy complete ==='
