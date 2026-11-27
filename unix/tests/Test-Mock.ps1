<#
.SYNOPSIS
    Tests of mock-snowflake.js, the stand-in for Snowflake and for the Snowflake CLI, under Jint: the fixtures, the statements it
    answers, the state that lives between calls, and the engine run through it as mock-snow.js runs it (the file of a request as
    unix\workflower writes it). mock-snow.js itself (Node: argument parsing, a file for the state) is not run here.
.EXAMPLE
    .\Test-Mock.ps1
#>
[CmdletBinding()]
param([string] $JintPath)
if (-not $JintPath) { $JintPath = Join-Path $PSScriptRoot '../../../sisula/lib/Jint.2.11.58.dll' }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Test-Engine.ps1') -JintPath $JintPath

$mockText = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'mock-snowflake.js'), [System.Text.Encoding]::UTF8)

# One call of the stand-in for the CLI: a new engine each time, the state passed as JSON text and handed back, as mock-snow.js does
# with its file.
$script:State = $null
function Invoke-Cli {
    param([string] $Sql)
    $e = New-Object Jint.Engine
    [void]$e.Execute($mockText)
    if ($null -eq $script:State) { $script:State = $e.Execute('JSON.stringify(MockSnowflake.newState())').GetCompletionValue().ToString() }
    [void]$e.SetValue('__state', $script:State)
    [void]$e.SetValue('__sql', $Sql)
    [void]$e.Execute('var __s = JSON.parse(__state); var __out = JSON.stringify(MockSnowflake.handleFile(__s, __sql));')
    $out = $e.Execute('__out').GetCompletionValue().ToString()
    $script:State = $e.Execute('JSON.stringify(__s)').GetCompletionValue().ToString()
    foreach ($r in ($out | ConvertFrom-Json)) { $r }
}

# The file that unix/workflower writes for the engine.
function New-EngineFile {
    param([string] $Op, $Request)
    'WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS' + "`n" + '$$' + "`n" + $global:WfEngineText + "`n" + '$$' + "`n" +
        "CALL wf('" + $Op + "', BASE64_DECODE_STRING('" + (ConvertTo-B64 (ConvertTo-Js $Request)) + "'))`n"
}
function Invoke-CliEngine {
    param([string] $Op, $Request = @{})
    $rows = @(Invoke-Cli (New-EngineFile $Op $Request))
    if ($rows.Count -ne 1 -or $null -eq $rows[0].WF) { throw 'the answer is not [{"WF": ...}]' }
    Read-Answer $rows[0].WF
}
function Get-StateObject { $script:State | ConvertFrom-Json }

Write-Host 'Plain statements'
$rows = @(Invoke-Cli 'SHOW DATABASES')
Assert-Equal @($rows | ForEach-Object { $_.name }) @('SALES', 'FINANCE') 'the databases'
$rows = @(Invoke-Cli 'SHOW SCHEMAS IN DATABASE "SALES"')
Assert-Equal @($rows | ForEach-Object { $_.name }) @('LOAD', 'MAINTENANCE', 'INFORMATION_SCHEMA') 'the schemas of SALES, with a lower case name column'
$rows = @(Invoke-Cli 'SHOW SCHEMAS IN DATABASE "FINANCE"')
Assert-True ($rows.Count -ge 1 -and $rows[0].name) 'the schemas of another database'
$rows = @(Invoke-Cli 'SELECT CURRENT_ACCOUNT_NAME(), CURRENT_ROLE(), CURRENT_WAREHOUSE()')
Assert-Equal $rows.Count 1 'a session query is one row'
Assert-Equal @($rows[0].psobject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) @('ACCOUNT=demo', 'ROLE=DEMO', 'WAREHOUSE=DEMO_WH') 'with ACCOUNT, ROLE and WAREHOUSE'
$rows = @(Invoke-Cli "SELECT CURRENT_ROLE() AS R;`n")
Assert-Equal @($rows[0].psobject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) @('ROLE=DEMO') 'a session query of one function, a closing semicolon'
$rows = @(Invoke-Cli 'SHOW TASKS IN SCHEMA "SALES"."LOAD"')
Assert-Equal $rows.Count 9 'nine tasks in SALES.LOAD'
Assert-Equal $rows[0].name 'NIGHTLY_ROOT' 'the first is the nightly root'
Assert-Equal $rows[0].created_on '2026-11-20T08:00:00.000Z' 'its time comes out as ISO text'
Assert-Equal @(Invoke-Cli 'SHOW TASKS IN SCHEMA "SALES"."MAINTENANCE"').Count 0 'no tasks in another schema'
Assert-Equal @(Invoke-Cli 'SHOW TASKS IN DATABASE "FINANCE"').Count 0 'no tasks in FINANCE'
Assert-Equal @(Invoke-Cli 'SHOW TASKS IN ACCOUNT').Count 9 'nine in the account'
$rows = @(Invoke-Cli 'SHOW PARAMETERS IN TASK "SALES"."LOAD"."NIGHTLY_ROOT"')
Assert-Equal @($rows | Where-Object { $_.level -eq 'TASK' } | ForEach-Object { $_.key }) @('USER_TASK_TIMEOUT_MS', 'SUSPEND_TASK_AFTER_NUM_FAILURES') 'the root has two parameters at the task level'
$rows = @(Invoke-Cli 'SHOW PARAMETERS IN TASK "SALES"."LOAD"."CLEAN_UP"')
Assert-Equal @($rows | Where-Object { $_.level -eq 'TASK' }).Count 0 'the others have none'
Assert-Equal $rows.Count 1 'BASE64_ENCODE answers (the engine of the shell script does not need a bind here, a bind is in the procedure only)'

Write-Host 'The state between calls'
$before = @((Get-StateObject).tasks | Where-Object { $_.state -eq 'started' }).Count
Assert-Equal $before 8 'eight tasks are started, EVENT_ROOT is not'
[void](Invoke-Cli 'ALTER TASK "SALES"."LOAD"."EVENT_ROOT" RESUME')
Assert-Equal @((Get-StateObject).tasks | Where-Object { $_.name -eq 'EVENT_ROOT' })[0].state 'started' 'RESUME starts that task'
[void](Invoke-Cli 'ALTER TASK "SALES"."LOAD"."CLEAN_UP" SUSPEND')
Assert-Equal @((Get-StateObject).tasks | Where-Object { $_.name -eq 'CLEAN_UP' })[0].state 'suspended' 'SUSPEND stops that task'
Assert-Equal @((Get-StateObject).tasks | Where-Object { $_.state -eq 'started' }).Count 8 'and no other task changed'
[void](Invoke-Cli 'CREATE TASK "SALES"."LOAD"."X" AS SELECT 1')
[void](Invoke-Cli 'EXECUTE TASK "SALES"."LOAD"."NIGHTLY_ROOT"')
Assert-Equal @((Get-StateObject).recorded) @('ALTER TASK "SALES"."LOAD"."EVENT_ROOT" RESUME', 'ALTER TASK "SALES"."LOAD"."CLEAN_UP" SUSPEND', 'CREATE TASK "SALES"."LOAD"."X" AS SELECT 1', 'EXECUTE TASK "SALES"."LOAD"."NIGHTLY_ROOT"') 'every other statement is only recorded, and SHOW and SELECT are not'
Assert-Equal @((Get-StateObject).tasks).Count 9 'a CREATE does not add a task'
[void](Invoke-Cli 'ALTER TASK "SALES"."LOAD"."EVENT_ROOT" SUSPEND')
[void](Invoke-Cli 'ALTER TASK "SALES"."LOAD"."CLEAN_UP" RESUME')
$bad = $null
try { [void](Invoke-Cli 'SELECT 1') } catch { $bad = $_ }
Assert-True ($null -eq $bad) 'an unknown statement is recorded, not refused'
$script:State = $null

Write-Host 'The engine through the stand-in'
$a = Invoke-CliEngine 'graphs' @{ database = 'SALES'; schema = 'LOAD'; parameters = $true }
Assert-Equal $a.Status 'ok' 'graphs is answered'
Assert-Equal @($a.Json.graphs | ForEach-Object { $_.root }) @('CLEAN_UP', 'EVENT_ROOT', 'NIGHTLY_ROOT') 'three graphs'
$n = @($a.Json.graphs | Where-Object { $_.root -eq 'NIGHTLY_ROOT' })[0]
Assert-Equal @($n.tasks | ForEach-Object { $_.name }) @('NIGHTLY_ROOT', 'LOAD_CUSTOMERS', 'LOAD_ORDERS', 'LOAD_PRODUCTS', 'BUILD_FACTS', 'PUBLISH', 'NOTIFY_DONE') 'the nightly graph: seven tasks, the finalizer last'
Assert-Equal $n.tasks[6].finalize 'NIGHTLY_ROOT' 'with a finalizer'
Assert-Equal $n.tasks[3].warehouse $null 'and a serverless task'
Assert-Equal @($n.tasks[4].after) @('LOAD_CUSTOMERS', 'LOAD_ORDERS', 'LOAD_PRODUCTS') 'BUILD_FACTS is after three tasks'
Assert-Equal $n.tasks[0].parameters.SUSPEND_TASK_AFTER_NUM_FAILURES '3' 'the root has parameters'
Assert-Equal $n.state 'started' 'it is started'
$e = @($a.Json.graphs | Where-Object { $_.root -eq 'EVENT_ROOT' })[0]
Assert-Equal $e.state 'suspended' 'EVENT_ROOT is suspended'
Assert-Equal $e.tasks[0].condition "SYSTEM`$STREAM_HAS_DATA('EVENTS_STREAM')" 'with a condition'
Assert-Equal $n.tasks[0].info.createdOn '2026-11-20T08:00:00.000Z' 'times are read as dates'

$v = Invoke-CliEngine 'view' @{ database = 'SALES'; schema = 'LOAD' }
$runs = @($v.Json.runs.NIGHTLY_ROOT)
Assert-Equal $runs.Count 4 'four days of runs'
Assert-Equal @($runs | ForEach-Object { $_.state }) @('SUCCEEDED', 'FAILED', 'SUCCEEDED', 'SUCCEEDED') 'one of them failed'
Assert-Equal $runs[1].tasks[2].task 'LOAD_ORDERS' 'LOAD_ORDERS'
Assert-Equal $runs[1].tasks[2].state 'FAILED' 'failed'
Assert-True ($runs[1].tasks[2].error -match 'ORDERS does not exist') 'with its error'
Assert-Equal $runs[0].tasks[0].started '2026-11-26T02:00:00.000Z' 'times are ISO text'
Assert-Equal @($v.Json.runs.EVENT_ROOT).Count 0 'the other graphs have no runs'

$d = (Invoke-CliEngine 'export' @{ database = 'SALES'; schema = 'LOAD'; root = 'NIGHTLY_ROOT' })
$text = $d.Files['SALES.LOAD.NIGHTLY_ROOT.json']
$p = Invoke-CliEngine 'plan' @{ doc = (ConvertTo-B64 $text) }
Assert-True ($p.Status -eq 'ok' -and $p.Steps -eq 0) 'the exported nightly graph is its own plan (the base64 argument is decoded)'
$doc = ConvertFrom-Js $text
(Get-DocTask $doc 'PUBLISH')['definition'] = 'CALL publish_marts(2)'
$a = Invoke-CliEngine 'apply' @{ doc = (ConvertTo-B64 (ConvertTo-Js $doc)) }
Assert-Equal $a.Status 'ok' 'a changed task is applied'
Assert-Equal @((Get-StateObject).recorded) @('ALTER TASK "SALES"."LOAD"."NIGHTLY_ROOT" SUSPEND', "ALTER TASK `"SALES`".`"LOAD`".`"PUBLISH`" MODIFY AS`nCALL publish_marts(2)", 'ALTER TASK "SALES"."LOAD"."NIGHTLY_ROOT" RESUME') 'the statements are recorded'
Assert-Equal @((Get-StateObject).tasks | Where-Object { $_.name -eq 'NIGHTLY_ROOT' })[0].state 'started' 'and the root is started again (RESUME changed the state, SUSPEND before it)'
$a = Invoke-CliEngine 'operate' @{ database = 'SALES'; schema = 'LOAD'; root = 'EVENT_ROOT'; action = 'resume' }
Assert-Equal $a.Status 'ok' 'operate resume'
Assert-Equal @((Get-StateObject).tasks | Where-Object { $_.name -eq 'EVENT_ROOT' })[0].state 'started' 'EVENT_ROOT is started, in the state that lives to the next call'
$g = Invoke-CliEngine 'graphs' @{ database = 'SALES'; schema = 'LOAD'; root = 'EVENT_ROOT' }
Assert-Equal $g.Json.graphs[0].state 'started' 'and the next call reads it so'
$a = Invoke-CliEngine 'operate' @{ database = 'SALES'; schema = 'LOAD'; root = 'NIGHTLY_ROOT'; action = 'suspend' }
Assert-Equal @((Get-StateObject).tasks | Where-Object { $_.state -eq 'started' -and $_.schema_name -eq 'LOAD' } | ForEach-Object { $_.name }) @('EVENT_ROOT', 'CLEAN_UP') 'suspend stops the whole nightly graph'
$i = Invoke-CliEngine 'import' @{ doc = (ConvertTo-B64 $text) }
Assert-Equal $i.Json.graph.root 'NIGHTLY_ROOT' 'import through the stand-in'
$a = Invoke-CliEngine 'check' @{ doc = '!not base64!' }
Assert-Equal $a.Status 'error' 'a request that fails is still an answer'
# the literal form of the call (a JSON text in quotes), which the engine tests use
$lit = 'WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS' + "`n" + '$$' + "`n" + $global:WfEngineText + "`n" + '$$' + "`n" + 'CALL wf(''graphs'', ''{"database":"SALES"}'')'
$rows = @(Invoke-Cli $lit)
Assert-True ($rows.Count -eq 1 -and (Read-Answer $rows[0].WF).Status -eq 'ok') 'the literal form of the call is answered too'
$gone = $null
try { [void](Invoke-Cli ("WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS`n" + '$$' + "`nthrow new Error('boom');`n" + '$$' + "`nCALL wf('x', BASE64_DECODE_STRING('e30='))")) } catch { $gone = $_.Exception.Message }
Assert-True ($null -ne $gone -and $gone -match 'boom') 'a procedure that throws fails the statement, as in Snowflake'

Complete-Tests
