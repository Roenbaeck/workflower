<#
.SYNOPSIS
    Tests the web server and its API over HTTP, with the demo session (no Snowflake): the routes answer, a graph can be edited and
    planned, and the server refuses what it must refuse (no secret, a foreign Host).
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\TestHelpers.ps1"
$root = Split-Path -Parent $PSScriptRoot
$port = 8790 + (Get-Random -Minimum 0 -Maximum 9)
$job = Start-Job -ScriptBlock { param($p, $port) Import-Module "$p\Workflower\Workflower.psd1" -Force; Start-Workflower -Session (New-WfSession -Demo) -NoBrowser -Port $port } -ArgumentList $root, $port
try {
    $base = "http://127.0.0.1:$port"
    $page = $null
    for ($i = 0; $i -lt 20 -and -not $page; $i++) { Start-Sleep -Milliseconds 500; try { $page = Invoke-WebRequest "$base/" -UseBasicParsing } catch { } }
    Assert-True ($null -ne $page) 'the server answers'
    $secret = [regex]::Match($page.Content, 'name="workflower-secret" content="([0-9a-f]{64})"').Groups[1].Value
    Assert-Equal $secret.Length 64 'the page carries a 64 character secret'
    Assert-True ($page.Headers['Content-Security-Policy'] -match "script-src 'self'") 'the page has a content security policy'
    $h = @{ 'X-Workflower-Secret' = $secret }
    function Get-Api { param($Path) $r = Invoke-WebRequest "$base$Path" -Headers $h -UseBasicParsing; (ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()))) }
    function Post-Api { param($Path, $Object) $r = Invoke-WebRequest "$base$Path" -Method Post -Headers $h -ContentType 'application/json' -Body (ConvertTo-Json $Object -Depth 20) -UseBasicParsing; (ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()))) }
    function Get-Status { param($Block) try { & $Block | Out-Null; 200 } catch { [int]$_.Exception.Response.StatusCode } }

    Assert-Equal (Get-Status { Invoke-WebRequest "$base/api/session" -UseBasicParsing }) 403 'the API refuses a request without the secret'
    Assert-Equal (Get-Status { Invoke-WebRequest "$base/api/session" -Headers @{ 'X-Workflower-Secret' = 'wrong' } -UseBasicParsing }) 403 'and one with the wrong secret'
    Assert-True ((Get-Status { Invoke-WebRequest "$base/" -Headers @{ Host = 'evil.example' } -UseBasicParsing }) -ne 200) 'a request for another host is refused'
    Assert-True ((Get-Status { Invoke-WebRequest "$base/..%2f..%2fWorkflower.psd1" -UseBasicParsing }) -ne 200) 'a path outside the interface folder is not served'

    $session = Get-Api '/api/session'
    Assert-Equal $session.backend 'Demo' 'the session is the demo'
    Assert-Equal @((Get-Api '/api/databases').databases) @('FINANCE', 'SALES') 'databases'
    Assert-Equal @((Get-Api '/api/schemas?database=SALES').schemas) @('LOAD', 'MAINTENANCE') 'schemas, without INFORMATION_SCHEMA'
    $graphs = (Get-Api '/api/graphs?database=SALES&schema=LOAD').graphs
    Assert-Equal @($graphs).Count 3 'three graphs in the schema'
    $one = Get-Api '/api/graph?database=SALES&schema=LOAD&root=NIGHTLY_ROOT'
    Assert-Equal @($one.graph.tasks).Count 7 'the nightly graph has seven tasks'
    Assert-Equal $one.graph.state 'started' 'and is started'
    Assert-Equal @($one.graph.tasks | Where-Object { $_.finalize }).Count 1 'with a finalizer'
    Assert-Equal @($one.graph.tasks[0].parameters.PSObject.Properties).Count 2 'the parameters of the root are read'

    $v = Post-Api '/api/validate' @{ graph = $one.graph }
    Assert-Equal @($v.problems).Count 0 'a good graph has no problems'
    $broken = $one.graph | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $broken.tasks[1].after = @('NOPE')
    $v = Post-Api '/api/validate' @{ graph = $broken }
    Assert-True (@($v.problems | Where-Object { $_.code -eq 'missing-predecessor' }).Count -eq 1) 'a missing predecessor is reported'
    $p = Post-Api '/api/plan' @{ graph = $broken }
    Assert-Equal $p.plan $null 'a graph with errors has no plan'

    $edited = $one.graph | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $edited.tasks[1].definition = 'SELECT 42'
    $p = Post-Api '/api/plan' @{ graph = $edited }
    Assert-Equal @($p.plan.steps | ForEach-Object { $_.phase }) @('suspend', 'alter', 'resume') 'an edit is planned as suspend, alter, resume'
    Assert-Equal @($p.plan.changed) @('LOAD_CUSTOMERS') 'and names the changed task'
    $same = Post-Api '/api/plan' @{ graph = $one.graph }
    Assert-True $same.plan.isEmpty 'an untouched graph has an empty plan'
    $applied = Post-Api '/api/apply' @{ graph = $edited }
    Assert-Equal $applied.plan.executed 3 'applying runs the three steps'
    $sql = Post-Api '/api/sql' @{ graph = $one.graph }
    Assert-True ($sql.sql -match 'CREATE OR REPLACE TASK "SALES"."LOAD"."NIGHTLY_ROOT"') 'the SQL route renders the script'
    $exported = Post-Api '/api/export' @{ graph = $one.graph }
    Assert-Equal $exported.fileName 'SALES.LOAD.NIGHTLY_ROOT.json' 'the export has a file name'
    $imported = Post-Api '/api/import' @{ text = $exported.text }
    Assert-Equal @($imported.graph.tasks).Count 7 'and its text imports again'
    Assert-Equal $imported.graph.root 'NIGHTLY_ROOT' 'with the same root'
    $runs = (Get-Api '/api/runs?database=SALES&schema=LOAD&root=NIGHTLY_ROOT&hours=168').runs
    Assert-True (@($runs).Count -ge 2) 'runs are listed'
    Assert-True (@($runs | Where-Object { $_.state -eq 'FAILED' }).Count -ge 1) 'one of them failed'
    $op = Post-Api '/api/operate' @{ database = 'SALES'; schema = 'LOAD'; root = 'EVENT_ROOT'; action = 'resume' }
    Assert-Equal $op.graph.state 'started' 'a graph is resumed through the API'
    Assert-Equal (Get-Status { Post-Api '/api/operate' @{ database = 'SALES'; schema = 'LOAD'; root = 'EVENT_ROOT'; action = 'explode' } }) 400 'an unknown action is refused'
} finally {
    Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
}
Complete-Tests
