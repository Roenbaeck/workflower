<#
    Reverse engineer existing Snowflake task graphs into Workflower JSON.

    Read-only: it reads SHOW TASKS and GET_DDL and writes files locally. It never alters a
    task. Only tasks visible to the connection's role can be discovered, so a hidden child
    makes the graph incomplete and the export fails rather than emitting a partial graph.

    Usage:
      .\read.ps1 <connection_name> <directory> -Schema DATABASE.SCHEMA [-Root ROOT_TASK]

    Quote case-sensitive identifiers with SQL double quotes:
      .\read.ps1 Teracom .\imported -Schema 'MY_DB."Mixed.Schema"' -Root '"Root Task"'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection,
    [Parameter(Mandatory = $true, Position = 1)][string] $Directory,
    [Parameter(Mandatory = $true)][string] $Schema,
    [string] $Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'webapp\Snow.ps1')

$paramsRunId = Assert-RunId (New-RunId)
$outRunId    = Assert-RunId (New-RunId)

$params = @{ schema = $Schema }
if ($Root) { $params['root'] = $Root }

$paramsFile = Join-Path ([System.IO.Path]::GetTempPath()) "$paramsRunId.json"
[System.IO.File]::WriteAllText($paramsFile, (ConvertTo-Json -InputObject $params -Compress), (New-Object System.Text.UTF8Encoding($false)))
try {
    Copy-ToStage -LocalPath $paramsFile -StagePath '@metadata.WORKFLOWER/in/' -Connection $Connection | Out-Null
}
finally {
    Remove-Item $paramsFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Reading tasks in $Schema..."
$result = Invoke-SnowSqlChecked -Sql "CALL metadata._ExportTaskGraphs('$paramsRunId', '$outRunId');" -Connection $Connection -Activity 'Task export'

$result = Invoke-SnowSqlChecked -Sql "CALL metadata._StageReadText('export/$outRunId.json');" -Connection $Connection -Activity 'Read export'
$row = @($result.Json)[0]
$json = ($row.psobject.Properties | Select-Object -First 1).Value
# ConvertFrom-Json emits a JSON array as one pipeline item on PowerShell 7 but enumerates
# it on 5.1, so neither @() nor the pipeline gives the same thing on both. Test the type.
$parsed = ConvertFrom-Json -InputObject $json
if ($parsed -is [System.Array]) { $graphs = $parsed } else { $graphs = @($parsed) }

if ($graphs.Count -eq 0) {
    Write-Host 'No visible tasks found.'
    exit 0
}

if (-not (Test-Path -LiteralPath $Directory)) { New-Item -ItemType Directory -Path $Directory | Out-Null }

# Work out every destination before writing any file, and refuse to overwrite.
$planned = @()
foreach ($graph in $graphs) {
    $name = [string]$graph.WORKFLOW
    $slug = ($name -replace '[^A-Za-z0-9_-]+', '_').Trim('_')
    if ($slug.Length -gt 100) { $slug = $slug.Substring(0, 100) }
    if (-not $slug) { $slug = 'workflow' }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($name))
        $suffix = (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
    }
    finally { $sha.Dispose() }

    $path = Join-Path $Directory "$($slug)_$suffix.json"
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite $path; select another output directory"
    }
    $planned += [pscustomobject]@{ Path = $path; Graph = $graph }
}

foreach ($item in $planned) {
    $content = ConvertTo-Json -InputObject $item.Graph -Depth 100
    [System.IO.File]::WriteAllText($item.Path, $content + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Exported $($item.Path)"
}

Write-Host "Exported $($planned.Count) graph(s). Native SQL is preserved; imported tasks install suspended."
Write-Host 'Referenced objects and grants are not exported. Import the JSON into the editor to inspect it.'
