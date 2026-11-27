<#
.SYNOPSIS
    Test-Live.ps1 through unix\engine.js: the engine is sent to a real Snowflake account as an anonymous JavaScript procedure, exactly
    as unix\workflower sends it, and what it reads, plans and does is checked.
.DESCRIPTION
    The PowerShell module is loaded only for its session and SQL helpers (New-WfSession, Invoke-WfSql) and for the literal of a
    string. Every engine call is one statement,

        WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS $$ <engine.js> $$ CALL wf('<op>', '<json>')

    Everything is made in a scratch database that the test drops at the end. A programmatic access token may need to be activated
    again by its owner after some hours (HTTP 401, "Network policy is required"); then nothing can be tested here.
.EXAMPLE
    ./Test-EngineLive.ps1 -Account myorg-myaccount -TokenFile ~/.snowflake/pat.txt -Warehouse WH -Role SYSADMIN
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Account,
    [Parameter(Mandatory = $true)][string] $TokenFile,
    [string] $Warehouse,
    [string] $Role,
    [string] $JintPath,
    [switch] $Keep
)
if (-not $JintPath) { $JintPath = Join-Path $PSScriptRoot '../../../sisula/lib/Jint.2.11.58.dll' }
$ErrorActionPreference = 'Stop'
# the harness of Test-Engine.ps1 gives the helpers for JSON, base64, answers and graph documents (it runs no test when dot-sourced)
. (Join-Path $PSScriptRoot 'Test-Engine.ps1') -JintPath $JintPath
Import-Module (Join-Path $PSScriptRoot '..\..\Workflower\Workflower.psd1') -Force
$module = Get-Module Workflower

$s = New-WfSession -Account $Account -TokenFile $TokenFile -Warehouse $Warehouse -Role $Role
$db = 'WORKFLOWER_ENGINE_TEST_' + (Get-Random -Minimum 10000 -Maximum 99999)
$wh = $Warehouse
Write-Host ('Scratch database {0}, warehouse {1}' -f $db, $wh)

function Run { param([string] $Sql) Invoke-WfSql $s $Sql | Out-Null }
function Step { param([string] $Name, [scriptblock] $Block)
    try { & $Block } catch { $global:Failed++; Write-Host ('  FAIL  ' + $Name + ': ' + $_.Exception.Message) -ForegroundColor Red }
}
function Get-Literal { param([string] $Text) & $module { param($t) ConvertTo-WfLiteral $t } $Text }

# One statement that holds the engine and calls it; the answer is the one value of the one row.
function Send-Engine {
    param([string] $Op, $Request = @{})
    $d = [string][char]36 + [string][char]36
    $statement = 'WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS' + "`n" + $d + "`n" + $global:WfEngineText + "`n" + $d + "`n" +
        'CALL wf(' + (Get-Literal $Op) + ', ' + (Get-Literal (ConvertTo-Js $Request)) + ')'
    $rows = @(Invoke-WfSql $s $statement)
    if ($rows.Count -ne 1) { throw ('the engine gave ' + $rows.Count + ' rows') }
    $value = @($rows[0].psobject.Properties)[0].Value
    Read-Answer ([string]$value)
}
function Eng { param([string] $Op, $Request = @{}) $a = Send-Engine $Op $Request; $a }
function Show-Problem { param($Answer) if ($Answer.Status -ne 'ok') { Write-Host ('        ' + ($Answer.Texts -join ' | ')) } }

function New-LiveTask {
    param([string] $Name, [string[]] $After = @(), [string] $Def = 'SELECT 1', [string] $Schedule, [string] $Warehouse = $wh)
    $t = New-DocTask $Name $After $Schedule '' $Def
    if ($Warehouse) { $t.warehouse = $Warehouse }
    $t
}
function Get-Installed { param([string] $Schema, [string] $Root) $a = Eng 'export' @{ database = $db; schema = $Schema; root = $Root }; (ConvertFrom-Js $a.Files[$db + '.' + $Schema + '.' + $Root + '.json']) }
function Get-Graph { param([string] $Schema, [string] $Root) $a = Eng 'graphs' @{ database = $db; schema = $Schema; root = $Root; parameters = $true }; $a.Json.graphs[0] }
function Plan-Of { param($Doc, $Extra = @{}) Eng 'plan' (ConvertTo-Request $Doc $Extra) }
function Publish { param($Doc, [string] $Message)
    $a = Eng 'apply' (ConvertTo-Request $Doc)
    Assert-Equal $a.Status 'ok' ($Message + ': apply is ok')
    Show-Problem $a
    $a
}
function Settle { param($Doc, [string] $Message)
    $again = Plan-Of $Doc
    Assert-True ($again.Status -eq 'ok' -and $again.Steps -eq 0) ($Message + ': a second plan has nothing to do')
    if ($again.Steps -ne 0) { Show-Problem $again; $again.Texts | ForEach-Object { Write-Host ('        ' + $_.Replace("`n", "`n        ")) } }
}

try {
    Run ('CREATE OR REPLACE DATABASE "' + $db + '"')
    Run ('CREATE SCHEMA "' + $db + '"."ONE"')
    Run ('CREATE SCHEMA "' + $db + '"."TWO"')
    Run ('CREATE TABLE "' + $db + '"."ONE"."SRC" (ID NUMBER)')

    Write-Host 'The engine runs in Snowflake'
    Step 'health' {
        $a = Eng 'check' (ConvertTo-Request (New-Doc @((New-DocTask 'R' -Schedule '1 MINUTE'), (New-DocTask 'A' -After 'R')) -Db $db -Sc 'ONE'))
        Assert-Equal $a.Status 'ok' 'a check is answered'
        Assert-Equal $a.Texts @('no problems') 'the answer is decoded'
        Assert-Equal $a.Keywords[0] 'STATUS' 'STATUS comes first'
        $bad = Eng 'check' @{ doc = (ConvertTo-B64 '{"tasks":[{"name":"X"') }
        Assert-True ($bad.Status -eq 'error' -and $bad.Texts[0] -match 'not valid JSON') 'a document that is not JSON is an error answer (the SyntaxError is caught)'
        $nb = Eng 'check' @{ doc = '!!not base64!!' }
        Assert-Equal $nb.Status 'error' 'a document that is not base64 is an error answer'
        Show-Problem $nb
        $unk = Eng 'check' @{ doc = (ConvertTo-B64 '{"tasks":[{"name":"X","definiton":"oops"}]}') }
        Assert-True ($unk.Status -eq 'error' -and $unk.Texts[0] -match "unknown field 'definiton'") 'an unknown field is named'
        $nope = Eng 'frobnicate' @{}
        Assert-True ($nope.Status -eq 'error' -and $nope.Exit -eq 1) 'an unknown operation is an error answer'
        $none = Eng 'graphs' @{ database = $db; schema = 'TWO' }
        Assert-Equal $none.Texts @('no graphs') 'a schema with no tasks has no graphs'
    }

    Write-Host 'A graph is made'
    $doc = $null
    Step 'make' {
        $r = New-LiveTask 'ROOT' -Schedule '60 MINUTE'
        $a = New-LiveTask 'LOAD_A' -After 'ROOT' -Def 'INSERT INTO SRC VALUES (1)'
        $b = New-LiveTask 'LOAD_B' -After 'ROOT'
        $c = New-LiveTask 'JOIN_C' -After 'LOAD_A', 'LOAD_B' -Def 'SELECT 3'
        $script:doc = New-Doc @($r, $a, $b, $c) -Db $db -Sc 'ONE'
        $check = Eng 'check' (ConvertTo-Request $script:doc)
        Assert-Equal @($check.Json.problems | Where-Object { $_.severity -eq 'error' }).Count 0 'the document has no errors'
        $plan = Plan-Of $script:doc
        Assert-Equal $plan.Status 'ok' 'a plan is made'
        Assert-Equal (Get-Phases $plan) @('create', 'create', 'create', 'create') 'a graph that is not there is planned as four creates'
        Assert-Equal $plan.Steps 4 'with STEPS 4'
        $sql = Eng 'sql' (ConvertTo-Request $script:doc)
        Assert-True ($sql.Texts[0].Contains('CREATE OR REPLACE TASK "' + $db + '"."ONE"."ROOT"')) 'the script is made'
        $applied = Publish $script:doc 'making the graph'
        Assert-Equal $applied.Texts[$applied.Texts.Count - 1] 'done: 4 steps' 'four steps are done'
        $read = Eng 'graphs' @{ database = $db; schema = 'ONE' }
        Assert-Equal @($read.Json.graphs).Count 1 'one graph is read back'
        $g = $read.Json.graphs[0]
        Assert-Equal $g.root 'ROOT' 'with the right root'
        Assert-Equal @($g.tasks).Count 4 'and four tasks'
        Assert-Equal @(@($g.tasks | Where-Object { $_.name -eq 'JOIN_C' })[0].after | Sort-Object) @('LOAD_A', 'LOAD_B') 'the predecessors are read'
        Assert-Equal @($g.tasks | Where-Object { $_.name -eq 'ROOT' })[0].schedule '60 MINUTE' 'the schedule is read'
        Assert-Equal @($g.tasks | Where-Object { $_.name -eq 'ROOT' })[0].state 'suspended' 'a new task is suspended'
        Assert-True ($read.Texts[0] -match 'ROOT\s+suspended\s+4\s+' + $db + '\.ONE') 'the table shows it'
        Assert-True (@($g.tasks | Where-Object { $_.info.id })[0].info.createdOn -match '^\d{4}-\d\d-\d\dT') 'the time of creation is ISO text'
        Settle $script:doc 'after creating'
    }

    Write-Host 'Changes to an installed graph'
    Step 'body' {
        $d = Get-Installed 'ONE' 'ROOT'
        (Get-DocTask $d 'LOAD_B')['definition'] = 'SELECT 22'
        $plan = Plan-Of $d
        Assert-Equal (Get-Phases $plan) @('alter') 'a changed body is one alter (the graph was suspended)'
        Publish $d 'MODIFY AS' | Out-Null
        Settle $d 'after MODIFY AS'
        (Get-DocTask $d 'LOAD_A')['definition'] = "BEGIN`n  INSERT INTO SRC VALUES (2);`nEND"
        Publish $d 'a BEGIN ... END body' | Out-Null
        Settle $d 'after a BEGIN ... END body'
    }
    Step 'properties' {
        $d = Get-Installed 'ONE' 'ROOT'
        $r = Get-DocTask $d 'ROOT'
        $r['schedule'] = 'USING CRON 0 6 * * * UTC'; $r['comment'] = "it's a ""test"" \ done"; $r['config'] = '{"env":"test"}'; $r['allowOverlappingExecution'] = $true
        $r['parameters'] = [ordered]@{ SUSPEND_TASK_AFTER_NUM_FAILURES = '3'; USER_TASK_TIMEOUT_MS = '120000' }
        Publish $d 'setting schedule, comment, parameters, overlap and config' | Out-Null
        Settle $d 'after setting schedule, comment, parameters, overlap and config'
        $g2 = Get-Graph 'ONE' 'ROOT'
        Assert-Equal @($g2.tasks | Where-Object { $_.name -eq 'ROOT' })[0].comment "it's a ""test"" \ done" 'a comment with quotes and a backslash is exact'
        $d2 = Get-Installed 'ONE' 'ROOT'
        $r2 = Get-DocTask $d2 'ROOT'
        foreach ($k in 'comment', 'config', 'allowOverlappingExecution') { [void]$r2.Remove($k) }
        $r2['schedule'] = '60 MINUTE'; $r2['parameters'] = [ordered]@{ SUSPEND_TASK_AFTER_NUM_FAILURES = '3' }
        $p = Plan-Of $d2
        Assert-True (@(@($p.Json.plan.steps) | Where-Object { $_.sql -match ' UNSET .*COMMENT' }).Count -eq 1) 'what goes is unset'
        Publish $d2 'unsetting them again' | Out-Null
        Settle $d2 'after unsetting them again'
        $r3 = @((Get-Graph 'ONE' 'ROOT').tasks | Where-Object { $_.name -eq 'ROOT' })[0]
        Assert-True ($null -eq $r3.comment -and $null -eq $r3.config) 'the comment and the config are gone'
    }
    Step 'unicode' {
        $d = Get-Installed 'ONE' 'ROOT'
        $t = Get-DocTask $d 'LOAD_B'
        $t['comment'] = 'caf' + [char]0xE9 + ' ' + [char]0x20AC + ' ' + [char]0x65E5 + [char]0x672C
        $t['definition'] = "SELECT '" + [char]0xE9 + [char]0x20AC + "' AS TXT"
        Publish $d 'non-ASCII text' | Out-Null
        Settle $d 'after non-ASCII text'
        $g = Get-Graph 'ONE' 'ROOT'
        Assert-Equal @($g.tasks | Where-Object { $_.name -eq 'LOAD_B' })[0].comment ('caf' + [char]0xE9 + ' ' + [char]0x20AC + ' ' + [char]0x65E5 + [char]0x672C) 'a non-ASCII comment is exact, both ways'
        $x = Eng 'export' @{ database = $db; schema = 'ONE'; root = 'ROOT' }
        Assert-True ($x.Files[$db + '.ONE.ROOT.json'] -notmatch '[^\x00-\x7e\r\n]') 'and the exported file is ASCII'
    }
    Step 'condition' {
        $d = Get-Installed 'ONE' 'ROOT'
        Run ('CREATE STREAM "' + $db + '"."ONE"."S" ON TABLE "' + $db + '"."ONE"."SRC"')
        $t = Get-DocTask $d 'LOAD_A'
        $t['condition'] = 'SYSTEM$STREAM_HAS_DATA(''' + $db + '.ONE.S'')'
        Publish $d 'MODIFY WHEN' | Out-Null
        Settle $d 'after MODIFY WHEN'
        [void]$t.Remove('condition')
        Publish $d 'removing the condition' | Out-Null
        Settle $d 'after removing the condition'
    }
    Step 'dependencies' {
        $d = Get-Installed 'ONE' 'ROOT'
        (Get-DocTask $d 'JOIN_C')['after'] = @('LOAD_A')
        Publish $d 'removing a predecessor' | Out-Null
        Settle $d 'after removing a predecessor'
        $d['tasks'] = @($d['tasks']) + @((New-LiveTask 'LATE_D' -After 'JOIN_C' -Def 'SELECT 4'))
        Publish $d 'adding a child' | Out-Null
        Settle $d 'after adding a child'
        $d3 = Get-Installed 'ONE' 'ROOT'
        (Get-DocTask $d3 'LATE_D')['after'] = @('LOAD_B', 'JOIN_C')
        Publish $d3 'adding a dependency to a task' | Out-Null
        Settle $d3 'after adding a dependency to a task'
        $d4 = Get-Installed 'ONE' 'ROOT'
        $d4['tasks'] = @($d4['tasks'] | Where-Object { $_['name'] -ne 'LATE_D' })
        Publish $d4 'dropping a task' | Out-Null
        Settle $d4 'after dropping a task'
        Assert-Equal @((Get-Graph 'ONE' 'ROOT').tasks).Count 4 'and it is gone'
    }
    Step 'finalizer' {
        $d = Get-Installed 'ONE' 'ROOT'
        $f = New-LiveTask 'FINAL' -Def 'SELECT 99'; $f['finalize'] = 'ROOT'
        $d['tasks'] = @($d['tasks']) + @($f)
        Publish $d 'adding a finalizer' | Out-Null
        Settle $d 'after adding a finalizer'
        $read = Get-Graph 'ONE' 'ROOT'
        Assert-Equal @($read.tasks | Where-Object { $_.finalize })[0].name 'FINAL' 'the finalizer is read'
        $d2 = Get-Installed 'ONE' 'ROOT'
        $d2['tasks'] = @($d2['tasks'] | Where-Object { $_['name'] -ne 'FINAL' })
        Publish $d2 'dropping the finalizer' | Out-Null
        Settle $d2 'after dropping the finalizer'
    }
    Step 'serverless' {
        $d = Get-Installed 'ONE' 'ROOT'
        $b = Get-DocTask $d 'LOAD_B'
        [void]$b.Remove('warehouse'); $b['parameters'] = [ordered]@{ USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL' }
        Publish $d 'a task goes serverless' | Out-Null
        Settle $d 'after a task goes serverless'
        $d2 = Get-Installed 'ONE' 'ROOT'
        $b2 = Get-DocTask $d2 'LOAD_B'
        [void]$b2.Remove('parameters'); $b2['warehouse'] = $wh
        Publish $d2 'and back to a warehouse' | Out-Null
        Settle $d2 'and back to a warehouse'
    }

    Write-Host 'A graph that was not made by this tool'
    Step 'foreign' {
        $q = '"' + $db + '"."TWO".'
        Run ('CREATE TASK ' + $q + '"load root" WAREHOUSE = "' + $wh + '" SCHEDULE = ''USING CRON 30 2 * * * Europe/Stockholm'' COMMENT = ''made by hand'' USER_TASK_TIMEOUT_MS = 90000 ALLOW_OVERLAPPING_EXECUTION = FALSE AS BEGIN SELECT 1; END')
        Run ('CREATE TASK ' + $q + '"step 1" WAREHOUSE = "' + $wh + '" AFTER ' + $q + '"load root" AS SELECT ''a;b''')
        Run ('CREATE TASK ' + $q + '"step 2" USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = XSMALL AFTER ' + $q + '"load root" AS SELECT 2')
        Run ('CREATE TASK ' + $q + '"Step 3" WAREHOUSE = "' + $wh + '" AFTER ' + $q + '"step 1", ' + $q + '"step 2" AS CALL SYSTEM$WAIT(1)')
        Run ('CREATE TASK ' + $q + '"fin" WAREHOUSE = "' + $wh + '" FINALIZE = ' + $q + '"load root" AS SELECT 0')
        $a = Eng 'graphs' @{ database = $db; schema = 'TWO'; parameters = $true }
        Assert-Equal @($a.Json.graphs).Count 1 'five hand-made tasks are one graph'
        $g = $a.Json.graphs[0]
        Assert-Equal $g.root 'load root' 'a root name with a space is read'
        Assert-Equal @($g.tasks | ForEach-Object { $_.name }) @('load root', 'step 1', 'step 2', 'Step 3', 'fin') 'in order, the finalizer last'
        Assert-Equal $g.incomplete $false 'and it is complete'
        Assert-Equal $g.tasks[0].parameters.USER_TASK_TIMEOUT_MS '90000' 'a parameter set by hand is read'
        Assert-Equal $g.tasks[0].allowOverlappingExecution $false 'so is overlapping'
        Assert-Equal $g.tasks[0].definition 'BEGIN SELECT 1; END' 'a BEGIN ... END body is read'
        Assert-Equal $g.tasks[2].parameters.USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE 'XSMALL' 'a serverless task is read'
        $ex = Eng 'export' @{ database = $db; schema = 'TWO' }
        $name = @($ex.Files.Keys)[0]
        Assert-Equal $name ($db + '.TWO.load_root.json') 'the file name of a root with a space is plain'
        $d = ConvertFrom-Js $ex.Files[$name]
        $check = Eng 'check' (ConvertTo-Request $d)
        Assert-Equal @($check.Json.problems | Where-Object { $_.severity -eq 'error' }).Count 0 'it passes the checks'
        $plan = Plan-Of $d
        Assert-True ($plan.Status -eq 'ok' -and $plan.Steps -eq 0) 'it is its own plan: nothing to do'
        if ($plan.Steps -ne 0) { $plan.Texts | ForEach-Object { Write-Host ('        ' + $_.Replace("`n", "`n        ")) } }
        # a copy in the first schema, by the override of schema and database and by new names
        $copy = ConvertFrom-Js $ex.Files[$name]
        $copy['schema'] = 'ONE'
        foreach ($t in $copy['tasks']) {
            $t['name'] = 'copy of ' + $t['name']
            if ($t.ContainsKey('after')) { $t['after'] = @($t['after'] | ForEach-Object { 'copy of ' + $_ }) }
            if ($t.ContainsKey('finalize')) { $t['finalize'] = 'copy of ' + $t['finalize'] }
        }
        $a = Eng 'apply' (ConvertTo-Request $copy)
        Assert-Equal $a.Status 'ok' 'the copy is made'
        Show-Problem $a
        $again = Eng 'graphs' @{ database = $db; schema = 'ONE'; root = 'copy of load root' }
        Assert-Equal @($again.Json.graphs).Count 1 'and read'
        Settle $copy 'the copy is as installed'
        # the same file moved by the overrides
        $moved = Eng 'plan' @{ doc = (ConvertTo-B64 $ex.Files[$name]); schema = 'ONE'; warehouse = $wh }
        Assert-True ($moved.Status -eq 'ok' -and $moved.Steps -gt 0) 'the file moved to another schema is a plan of creates'
        Assert-True ($moved.Texts[0].Contains('CREATE TASK "' + $db + '"."ONE"."load root"')) 'in the schema that was asked for'
    }

    Write-Host 'Export and import'
    Step 'files' {
        $x = Eng 'export' @{ database = $db; schema = 'ONE'; root = 'ROOT'; split = $true }
        $json = $db + '.ONE.ROOT.json'
        Assert-True ($x.Files.Contains($json)) 'a JSON file for the graph'
        Assert-Equal @($x.Files.Keys | Where-Object { $_ -like '*.sql' }).Count 4 'and a .sql file for each task'
        Assert-Equal @($x.Files.Keys | Where-Object { $_ -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.\-]*(/[A-Za-z0-9_][A-Za-z0-9_.\-]*)?$' }).Count 0 'with paths that are plain'
        $files = @{}; foreach ($k in $x.Files.Keys) { if ($k -like '*.sql') { $files[$k] = ConvertTo-B64 $x.Files[$k] } }
        $p = Eng 'plan' @{ doc = (ConvertTo-B64 $x.Files[$json]); files = $files }
        Assert-True ($p.Status -eq 'ok' -and $p.Steps -eq 0) 'the exported text, with the definitions in files, is its own plan'
        $one = Eng 'export' @{ database = $db; schema = 'ONE'; root = 'ROOT' }
        $p2 = Eng 'plan' @{ doc = (ConvertTo-B64 $one.Files[$json]) }
        Assert-True ($p2.Status -eq 'ok' -and $p2.Steps -eq 0) 'so is the exported text with the definitions inside'
        $all = Eng 'export' @{ database = $db }
        Assert-True (@($all.Files.Keys).Count -ge 3) 'a database exports all its graphs'
    }

    Write-Host 'Operations'
    Step 'operate' {
        $r = Eng 'operate' @{ database = $db; schema = 'ONE'; root = 'ROOT'; action = 'resume' }
        if ($r.Status -ne 'ok') { Write-Host ('        (resume needs a privilege here: ' + ($r.Texts -join ' ') + ')'); return }
        $now = Get-Graph 'ONE' 'ROOT'
        Assert-True (@($now.tasks | Where-Object { $_.state -ne 'started' }).Count -eq 0) 'every task is started after resume'
        Assert-Equal $now.state 'started' 'and the graph says started'
        $edit = Get-Installed 'ONE' 'ROOT'
        (Get-DocTask $edit 'LOAD_B')['definition'] = 'SELECT 33'
        $plan = Plan-Of $edit
        Assert-Equal (Get-Phases $plan) @('suspend', 'alter', 'resume') 'a started graph is changed as suspend, alter, resume'
        Publish $edit 'changing a started graph' | Out-Null
        $after = Get-Graph 'ONE' 'ROOT'
        Assert-True (@($after.tasks | Where-Object { $_.state -ne 'started' }).Count -eq 0) 'and it is started again afterwards'
        Settle $edit 'after changing a started graph'
        $v = Eng 'view' @{ database = $db; schema = 'ONE' }
        Assert-Equal $v.Status 'ok' 'view of a started graph'
        Assert-Equal @($v.Json.graphs | ForEach-Object { $_.root }) @('ROOT', 'copy of load root') 'has the graphs'
        Assert-True ($null -ne $v.Json.runs.psobject.Properties['ROOT']) 'and runs for each root (maybe none)'
        $off = Eng 'operate' @{ database = $db; schema = 'ONE'; root = 'ROOT'; action = 'suspend' }
        Assert-Equal $off.Status 'ok' 'suspend is ok'
        $offGraph = Get-Graph 'ONE' 'ROOT'
        Assert-True (@($offGraph.tasks | Where-Object { $_.state -eq 'started' }).Count -eq 0) 'and every task is suspended after it'
        $nothing = Eng 'operate' @{ database = $db; schema = 'ONE'; root = 'ROOT'; action = 'suspend' }
        Assert-True ($nothing.Status -eq 'ok' -and $nothing.Texts[0] -match 'nothing to suspend') 'suspending again does nothing'
        $run = Eng 'operate' @{ database = $db; schema = 'ONE'; root = 'ROOT'; action = 'run' }
        Assert-Equal $run.Status 'ok' 'run is ok'
        Show-Problem $run
        $runs = @()
        for ($i = 0; $i -lt 30 -and $runs.Count -eq 0; $i++) {
            Start-Sleep -Seconds 4
            $rr = Eng 'runs' @{ database = $db; schema = 'ONE'; root = 'ROOT'; hours = 1 }
            if ($rr.Status -ne 'ok') { Show-Problem $rr; break }
            $runs = @($rr.Json.runs)
        }
        Assert-True ($runs.Count -ge 1) 'a run shows in the history'
        if ($runs.Count -ge 1) {
            Write-Host ('        run ' + $runs[0].runId + ' ' + $runs[0].state + ', ' + @($runs[0].tasks).Count + ' tasks')
            Assert-True ($runs[0].started -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$' -or $runs[0].scheduled -match '^\d{4}-\d\d-\d\dT') 'times are ISO text'
            Assert-True ($rr.Texts[0] -match 'RUN\s+STATE') 'the table has a heading'
            $vv = Eng 'view' @{ database = $db; schema = 'ONE'; hours = 1 }
            Assert-True (@($vv.Json.runs.ROOT).Count -ge 1) 'view has the run'
            Assert-Equal @($vv.Json.runs.ROOT[0].psobject.Properties | ForEach-Object { $_.Name }) @('runId', 'state', 'scheduled', 'started', 'completed', 'seconds', 'tasks') 'in the shape of the web interface'
        }
        $rt = Eng 'operate' @{ database = $db; schema = 'ONE'; root = 'ROOT'; action = 'retry' }
        Write-Host ('        (retry: ' + $rt.Status + ' ' + ($rt.Texts -join ' ').Substring(0, [Math]::Min(120, ($rt.Texts -join ' ').Length)) + ')')
        $missing = Eng 'operate' @{ database = $db; schema = 'ONE'; root = 'NO_SUCH'; action = 'resume' }
        Assert-True ($missing.Status -eq 'error' -and $missing.Texts[0] -match 'There is no graph') 'a graph that is not there is an error'
    }

    Write-Host 'The shapes that the server relies on, and the call of the shell script'
    Step 'shapes' {
        $d = Get-Installed 'ONE' 'ROOT'
        $i = Eng 'import' (ConvertTo-Request $d)
        Assert-Equal $i.Status 'ok' 'import is ok'
        Assert-Equal @($i.Json.psobject.Properties | ForEach-Object { $_.Name }) @('graph', 'problems') 'import: graph and problems'
        Assert-Equal $i.Json.graph.root 'ROOT' 'import: the root'
        Assert-Equal @($i.Json.graph.tasks[0].psobject.Properties | ForEach-Object { $_.Name }) @('name', 'definition', 'after', 'finalize', 'schedule', 'warehouse', 'condition', 'allowOverlappingExecution', 'errorIntegration', 'comment', 'config', 'parameters', 'state') 'import: a task has all its fields and no info'
        $bad = Eng 'import' @{ doc = (ConvertTo-B64 '{"tasks":[{"name":"X","definiton":"oops"}]}') }
        Assert-True ($bad.Status -eq 'error' -and $bad.Texts[0] -match "unknown field 'definiton'") 'import: an unknown field is STATUS error'
        $p = Plan-Of $d
        Assert-Equal @($p.Json.plan.psobject.Properties | ForEach-Object { $_.Name }) @('database', 'schema', 'root', 'exists', 'isEmpty', 'added', 'removed', 'changed', 'executed', 'steps') 'plan: the shape of the web interface'
        Assert-Equal $p.Json.plan.isEmpty $true 'plan: isEmpty is a boolean'
        $sq = Eng 'sql' (ConvertTo-Request $d)
        Assert-Equal $sq.Json.sql $sq.Texts[0] 'sql: the JSON holds the script'
        (Get-DocTask $d 'LOAD_A')['definition'] = 'SELECT 77'
        $ap = Eng 'apply' (ConvertTo-Request $d)
        Assert-True ($ap.Status -eq 'ok' -and $ap.Json.plan.executed -eq @($ap.Json.plan.steps).Count -and $ap.Json.plan.executed -ge 1) 'apply: executed is the number of steps run'
        # the call as unix/workflower writes it: the arguments are decoded by Snowflake
        $dd = [string][char]36 + [string][char]36
        $args64 = ConvertTo-B64 (ConvertTo-Js @{ database = $db; schema = 'ONE'; root = 'ROOT' })
        $statement = 'WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS' + "`n" + $dd + "`n" + $global:WfEngineText + "`n" + $dd + "`n" +
            "CALL wf('graphs', BASE64_DECODE_STRING('" + $args64 + "'))"
        $rows = @(Invoke-WfSql $s $statement)
        $g = Read-Answer ([string]@($rows[0].psobject.Properties)[0].Value)
        Assert-True ($g.Status -eq 'ok' -and @($g.Json.graphs).Count -eq 1) 'CALL wf(op, BASE64_DECODE_STRING(...)) works in Snowflake'
    }

    Write-Host 'Failures'
    Step 'failures' {
        $d = Get-Installed 'ONE' 'ROOT'
        (Get-DocTask $d 'LOAD_A')['warehouse'] = 'NO_SUCH_WAREHOUSE_' + $db
        $a = Eng 'apply' (ConvertTo-Request $d)
        Assert-Equal $a.Status 'error' 'a step that fails is an error answer'
        Assert-Equal $a.Exit 1 'with EXIT 1'
        Assert-True ($a.Steps -ge 1) 'and STEPS says how many the plan had'
        Assert-True ($a.Texts[$a.Texts.Count - 1] -match 'Step \d+ of \d+ failed') 'the message says which step it was'
        Show-Problem $a
        $bad = Get-Installed 'ONE' 'ROOT'
        (Get-DocTask $bad 'LOAD_B')['after'] = @('NOWHERE')
        $a2 = Eng 'apply' (ConvertTo-Request $bad)
        Assert-True ($a2.Status -eq 'error' -and $a2.Texts[0] -match 'The graph is not valid') 'a graph with errors is not applied'
    }
}
finally {
    if (-not $Keep) { try { Run ('DROP DATABASE IF EXISTS "' + $db + '"') } catch { Write-Host ('could not drop ' + $db + ': ' + $_.Exception.Message) } }
    else { Write-Host ('kept ' + $db) }
}
Complete-Tests
