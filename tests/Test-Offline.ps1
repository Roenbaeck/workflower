<#
.SYNOPSIS
    Tests that need no Snowflake: how tasks are read into graphs, checked, written as SQL and files, and compared.
    The rows are shaped like the result of SHOW TASKS.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\TestHelpers.ps1"
Import-Module (Join-Path $PSScriptRoot '..\Workflower\Workflower.psd1') -Force
$module = Get-Module Workflower
function In-Module { param([scriptblock] $Block) & $module $Block }

function New-Row {
    param([string] $Name, [string] $Definition = 'SELECT 1', [string[]] $After = @(), [string] $Finalizes, [string] $Finalizer,
          [string] $Schedule, [string] $Warehouse = 'WH', [string] $State = 'suspended', [string] $Condition, [string] $Id = '1',
          [string] $Db = 'DB', [string] $Sc = 'SC')
    $rel = [ordered]@{ Predecessors = @($After | ForEach-Object { "$Db.$Sc.$_" }) }
    if ($Finalizer) { $rel.FinalizerTask = "$Db.$Sc.$Finalizer" }
    if ($Finalizes) { $rel.FinalizedRootTask = "$Db.$Sc.$Finalizes" }
    [pscustomobject]@{
        created_on = '2026-11-01 10:00:00'; name = $Name; id = $Id; database_name = $Db; schema_name = $Sc; owner = 'SYSADMIN'; comment = ''
        warehouse = $Warehouse; schedule = $Schedule; predecessors = (ConvertTo-Json -InputObject @($After | ForEach-Object { "$Db.$Sc.$_" }) -Compress)
        state = $State; definition = $Definition; condition = $Condition; allow_overlapping_execution = 'null'; error_integration = 'null'
        last_committed_on = ''; last_suspended_on = ''; owner_role_type = 'ROLE'; config = ''; budget = ''
        task_relations = (ConvertTo-Json -InputObject $rel -Compress); last_suspended_reason = ''
    }
}

Write-Host 'Names and literals'
In-Module { Assert-Equal @('load root', 'LONE', 'LOAD_A', 'LOAD1' | Sort-WfOrdinal) @('LOAD1', 'LOAD_A', 'LONE', 'load root') 'names are sorted ordinally, whatever the culture of the machine' }
In-Module {
    Assert-Equal (ConvertTo-WfIdentifier 'a"b') '"a""b"' 'a quote in an identifier is doubled'
    Assert-Equal (ConvertTo-WfQualified 'DB' 'My Schema' 'T') '"DB"."My Schema"."T"' 'a qualified name is quoted part by part'
    Assert-Equal (ConvertTo-WfLiteral "it's a \ test") "'it''s a \\ test'" 'a literal doubles the quote and the backslash'
    Assert-Equal (ConvertTo-WfParameterValue '3600000') '3600000' 'a number is not quoted'
    Assert-Equal (ConvertTo-WfParameterValue 'true') 'TRUE' 'a boolean is not quoted'
    Assert-Equal (ConvertTo-WfParameterValue 'XSMALL') "'XSMALL'" 'text is quoted'
    Assert-Equal (Split-WfQualified 'DB.SC.T') @('DB', 'SC', 'T') 'a plain dotted name is split'
    Assert-Equal (Split-WfQualified '"My.Db"."s""x"."t"') @('My.Db', 's"x', 't') 'a quoted name keeps its dots and quotes'
    Assert-Equal (Get-WfLastPart 'DB.SC."Load Root"') 'Load Root' 'the last part is the task'
}

Write-Host 'JSON'
In-Module {
    $text = ConvertTo-WfJson ([ordered]@{ a = 'x"y'; b = @(1, 2); c = [ordered]@{ d = $true; e = $null }; f = "line1`nline2"; g = 'caf' + [char]0xE9 })
    $back = (ConvertFrom-WfJson $text)
    Assert-Equal $back['a'] 'x"y' 'a quote survives a JSON round trip'
    Assert-Equal $back['f'] "line1`nline2" 'a line break survives'
    Assert-Equal $back['g'] ('caf' + [char]0xE9) 'a non-ASCII letter survives (written as an escape)'
    Assert-True ($text -notmatch '[^\x00-\x7e]') 'the text is ASCII'
    Assert-Equal @($back['b']).Count 2 'an array keeps its length'
}

Write-Host 'Reading graphs'
$rows = @(
    New-Row 'LOAD_ROOT' -Schedule '60 MINUTE' -State 'started' -Id '10'
    New-Row 'LOAD_A' -After 'LOAD_ROOT' -State 'started' -Id '11'
    New-Row 'LOAD_B' -After 'LOAD_ROOT' -State 'started' -Id '12'
    New-Row 'LOAD_C' -After 'LOAD_A', 'LOAD_B' -State 'started' -Id '13'
    New-Row 'LOAD_FINAL' -Finalizes 'LOAD_ROOT' -State 'started' -Id '14'
    New-Row 'LONE' -Definition 'CALL p()' -Warehouse '' -Schedule 'USING CRON 0 * * * * UTC' -Id '20'
    New-Row 'Other Schema Task' -Db 'DB' -Sc 'OTHER' -Id '30'
)
$graphs = & $module { param($r) ,@(ConvertFrom-WfTaskRows $r) } $rows
Assert-Equal @($graphs).Count 3 'two graphs in one schema and one in another are three graphs'
$g = @($graphs | Where-Object { $_.root -ceq 'LOAD_ROOT' })[0]
Assert-Equal @($g.tasks | ForEach-Object { $_.name }) @('LOAD_ROOT', 'LOAD_A', 'LOAD_B', 'LOAD_C', 'LOAD_FINAL') 'a graph is in order, the finalizer last'
Assert-Equal @(@($g.tasks)[3].after) @('LOAD_A', 'LOAD_B') 'predecessors are read from the relations, without the qualifier'
Assert-Equal (@($g.tasks)[4].finalize) 'LOAD_ROOT' 'a finalizer says what it finalizes'
Assert-Equal (@($g.tasks)[0].info.id) '10' 'the id is kept as information'
$lone = @($graphs | Where-Object { $_.root -ceq 'LONE' })[0]
Assert-Equal @($lone.tasks).Count 1 'a task that stands alone is a graph of one'
Assert-Equal $lone.tasks[0].warehouse $null 'no warehouse is null (serverless)'
Assert-Equal $lone.tasks[0].allowOverlappingExecution $null 'the text null is no value'
Assert-Equal $lone.tasks[0].errorIntegration $null 'the text null is no integration'
$odd = @($graphs | Where-Object { $_.schema -ceq 'OTHER' })[0]
Assert-Equal $odd.root 'Other Schema Task' 'a task name with spaces is kept as it is'

Write-Host 'Validation'
function New-G { param($Tasks) New-Object psobject -Property @{ database = 'DB'; schema = 'SC'; root = $null; tasks = @($Tasks) } }
function T { param([string] $Name, [string[]] $After = @(), [string] $Schedule, [string] $Finalize, [string] $Definition = 'SELECT 1')
    $t = & $module { param($n) New-WfTaskObject $n } $Name
    $t.definition = $Definition; $t.after = @($After); $t.schedule = $Schedule; $t.finalize = $Finalize; $t }
function Codes { param($Graph) @(Test-TaskGraph $Graph | ForEach-Object { $_.Code }) }
Assert-Equal @(Codes (New-G @((T 'R' -Schedule '1 MINUTE'), (T 'A' -After 'R')))) @() 'a good graph has no problems'
Assert-True ((Codes (New-G @((T 'R'), (T 'R')))) -contains 'duplicate-name') 'two tasks with one name'
Assert-True ((Codes (New-G @((T 'r' -Schedule '1 MINUTE'), (T 'R' -After 'r')))) -notcontains 'duplicate-name') 'names that differ in case are two tasks (Snowflake names are exact)'
Assert-True ((Codes (New-G @((T 'R'), (T 'A' -After 'X')))) -contains 'missing-predecessor') 'a predecessor that is not there'
Assert-True ((Codes (New-G @((T 'R'), (T 'S')))) -contains 'several-roots') 'two roots'
Assert-True ((Codes (New-G @((T 'R'), (T 'A' -After 'R' -Schedule '1 MINUTE')))) -contains 'schedule-on-child') 'a schedule on a child'
Assert-True ((Codes (New-G @((T 'R'), (T 'A' -After 'B'), (T 'B' -After 'A')))) -contains 'cycle') 'a cycle'
Assert-True ((Codes (New-G @((T 'A' -After 'B'), (T 'B' -After 'A')))) -contains 'no-root') 'tasks with no root'
Assert-True ((Codes (New-G @((T 'R' -Definition ' ')))) -contains 'no-definition') 'a task with nothing to run'
Assert-True ((Codes (New-G @((T 'R'), (T 'F' -Finalize 'X')))) -contains 'finalize-missing') 'a finalizer of a task that is not there'
Assert-True ((Codes (New-G @((T 'R'), (T 'A' -After 'R'), (T 'F' -Finalize 'A')))) -contains 'finalize-not-root') 'a finalizer of a task that is not the root'
Assert-True ((Codes (New-G @((T 'R'), (T 'F' -Finalize 'R'), (T 'G' -Finalize 'R')))) -contains 'several-finalizers') 'two finalizers'
Assert-True ((Codes (New-G @((T 'R'), (T 'F' -Finalize 'R'), (T 'A' -After 'F')))) -contains 'after-finalizer') 'a task after a finalizer'
$many = @(T 'R') + @(1..101 | ForEach-Object { T ('C' + $_) -After 'R' })
Assert-True ((Codes (New-G $many)) -contains 'too-many-children') 'more than 100 children'
$wide = @(1..101 | ForEach-Object { T ('P' + $_) }); $wide = @(T 'R') + @(1..101 | ForEach-Object { T ('P' + $_) -After 'R' }) + @(T 'Z' -After (@(1..101 | ForEach-Object { 'P' + $_ })))
Assert-True ((Codes (New-G $wide)) -contains 'too-many-predecessors') 'more than 100 predecessors'
$both = New-G @((T 'R')); $both.tasks[0].warehouse = 'WH'; $both.tasks[0].parameters['USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE'] = 'XSMALL'
Assert-True ((Codes $both) -contains 'two-computes') 'a warehouse and a serverless size'
Assert-True ((Codes (New-G @((T 'R')))) -contains 'manual-root') 'a root that nothing starts is an info'

Write-Host 'SQL'
$gg = New-G @((T 'R' -Schedule '5 MINUTE'), (T 'A' -After 'R' -Definition "CALL load('x')"), (T 'F' -Finalize 'R'))
$gg.tasks[0].warehouse = 'WH'; $gg.tasks[1].condition = "SYSTEM`$STREAM_HAS_DATA('S')"; $gg.tasks[1].comment = "it's"; $gg.tasks[0].state = 'started'; $gg.tasks[1].state = 'started'
$gg.tasks[0].parameters['USER_TASK_TIMEOUT_MS'] = '60000'
$sql = @(ConvertTo-TaskGraphSql $gg)
Assert-Equal $sql.Count 3 'one statement for each task'
Assert-Equal $sql[0] "CREATE OR REPLACE TASK `"DB`".`"SC`".`"R`"`n  WAREHOUSE = `"WH`"`n  SCHEDULE = '5 MINUTE'`n  USER_TASK_TIMEOUT_MS = 60000`nAS`nSELECT 1" 'the root'
Assert-Equal $sql[1] "CREATE OR REPLACE TASK `"DB`".`"SC`".`"A`"`n  COMMENT = 'it''s'`n  AFTER `"DB`".`"SC`".`"R`"`n  WHEN SYSTEM`$STREAM_HAS_DATA('S')`nAS`nCALL load('x')" 'a child: comment, after, when, body'
Assert-True ($sql[2] -match 'FINALIZE = "DB"."SC"."R"') 'a finalizer'
$withState = @(ConvertTo-TaskGraphSql $gg -IncludeState -NoReplace)
Assert-Equal $withState.Count 5 'two resumes for the two tasks that are started'
Assert-Equal $withState[3] 'ALTER TASK "DB"."SC"."A" RESUME' 'the child is resumed first'
Assert-Equal $withState[4] 'ALTER TASK "DB"."SC"."R" RESUME' 'the root last'
Assert-True ($withState[0] -match '^CREATE TASK ') '-NoReplace makes CREATE TASK'
Assert-True ((ConvertTo-TaskGraphSql $gg -AsScript) -match ';\n\n') 'a script ends each statement'

Write-Host 'Files'
$dir = Join-Path ([System.IO.Path]::GetTempPath()) ('wf-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $g = @($graphs | Where-Object { $_.root -ceq 'LOAD_ROOT' })[0]
    $g.tasks[1].definition = "BEGIN`n  CALL p('caf" + [char]0xE9 + "');`nEND;"
    $file = $g | Export-TaskGraph -Directory $dir
    $back = Import-TaskGraph $file.FullName
    Assert-Equal @($back.tasks | ForEach-Object { $_.name }) @($g.tasks | ForEach-Object { $_.name }) 'the tasks come back in order'
    Assert-Equal $back.tasks[1].definition $g.tasks[1].definition 'a multi-line body with a non-ASCII letter comes back as it was'
    Assert-Equal @($back.tasks[3].after) @('LOAD_A', 'LOAD_B') 'predecessors come back'
    Assert-Equal $back.tasks[0].schedule '60 MINUTE' 'the schedule comes back'
    Assert-Equal $back.database 'DB' 'the database comes back'
    Assert-Throws { $g | Export-TaskGraph -Directory $dir } 'Refusing to overwrite' 'a file is not overwritten'
    $split = $g | Export-TaskGraph -Directory (Join-Path $dir 'split') -SplitDefinitions
    $back2 = Import-TaskGraph $split.FullName
    Assert-Equal $back2.tasks[1].definition $g.tasks[1].definition 'definitions in their own files come back too'
    Assert-True (Test-Path (Join-Path $dir 'split\DB.SC.LOAD_ROOT.d\LOAD_A.sql')) 'and there is a .sql file for a task'
    $over = Import-TaskGraph $file.FullName -Database 'PROD' -Warehouse 'BIG'
    Assert-Equal $over.database 'PROD' '-Database replaces the database'
    Assert-Equal $over.tasks[0].warehouse 'BIG' '-Warehouse replaces the warehouse of a task that has one'
    Set-Content -LiteralPath (Join-Path $dir 'bad.json') -Value '{"tasks":[{"name":"X","definiton":"oops"}]}'
    Assert-Throws { Import-TaskGraph (Join-Path $dir 'bad.json') } 'unknown field .definiton' 'a misspelt field is refused'
    Set-Content -LiteralPath (Join-Path $dir 'one.json') -Value '{"tasks":[{"name":"X","definition":"SELECT 1","parameters":{"user_task_timeout_ms":"1000"}}]}'
    $one = Import-TaskGraph (Join-Path $dir 'one.json')
    Assert-Equal @($one.tasks[0].parameters.Keys) @('USER_TASK_TIMEOUT_MS') 'a task with exactly one parameter imports, the name in upper case'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'The plan'
function Copy-G { param($G)
    $tasks = @($G.tasks | ForEach-Object { $c = $_.psobject.Copy(); $p = [ordered]@{}; foreach ($k in $_.parameters.Keys) { $p[$k] = $_.parameters[$k] }; $c.parameters = $p; $c.after = @($_.after); $c })
    $n = New-Object psobject -Property @{ database = $G.database; schema = $G.schema; root = $G.root; tasks = $tasks }; $n }
function Plan { param($Desired, $Actual) Compare-TaskGraph $Desired -Session $null -Actual $Actual }
$actual = @($graphs | Where-Object { $_.root -ceq 'LOAD_ROOT' })[0]
$p = Plan (Copy-G $actual) $actual
Assert-True $p.IsEmpty 'a graph that is as installed needs nothing'
$new = Copy-G $actual; $new.database = 'DB'
$p = Plan $new $null
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('create', 'create', 'create', 'create', 'create', 'resume', 'resume', 'resume', 'resume', 'resume') 'a graph that is not installed is made, and started when its tasks say started'
Assert-Equal $p.Steps[9].Task 'LOAD_ROOT' 'the root is resumed last'
Assert-Equal $p.Exists $false 'and the plan says it is new'
foreach ($t in $new.tasks) { $t.state = $null }
$p = Plan $new $null
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('create', 'create', 'create', 'create', 'create') 'a graph with no state is made suspended'

$d = Copy-G $actual; $d.tasks[1].definition = 'SELECT 2'
$p = Plan $d $actual
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('suspend', 'alter', 'resume') 'a changed body: suspend the root, alter, resume'
Assert-True ($p.Steps[1].Sql -match '^ALTER TASK "DB"."SC"."LOAD_A" MODIFY AS\nSELECT 2$') 'the alter is MODIFY AS'
Assert-Equal $p.Steps[2].Task 'LOAD_ROOT' 'only the root had to be resumed'
Assert-Equal $p.Changed @('LOAD_A') 'the plan names the changed task'

$d = Copy-G $actual; $d.tasks = @($d.tasks | Where-Object { $_.name -cne 'LOAD_C' })
$p = Plan $d $actual
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('suspend', 'drop', 'resume') 'a task that goes is dropped'
Assert-Equal $p.Removed @('LOAD_C') 'and named'

$d = Copy-G $actual; $d.tasks[3].after = @('LOAD_A')
$p = Plan $d $actual
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('suspend', 'unlink', 'resume') 'a dependency that goes is removed'
Assert-True ($p.Steps[1].Sql -eq 'ALTER TASK "DB"."SC"."LOAD_C" REMOVE AFTER "DB"."SC"."LOAD_B"') 'with REMOVE AFTER'

$d = Copy-G $actual
$extra = & $module { New-WfTaskObject 'LOAD_D' }; $extra.definition = 'SELECT 4'; $extra.after = @('LOAD_C'); $extra.warehouse = 'WH'
$d.tasks = @($d.tasks) + @($extra)
$p = Plan $d $actual
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('suspend', 'create', 'resume', 'resume') 'a new task is made, and started because the graph is started'
Assert-Equal $p.Steps[2].Task 'LOAD_D' 'the new task is resumed before the root'

$d = Copy-G $actual; $d.tasks[1].after = @('LOAD_ROOT', 'LOAD_B')
$p = Plan $d $actual
Assert-True (@($p.Steps | Where-Object { $_.Sql -match 'ADD AFTER "DB"."SC"."LOAD_B"' }).Count -eq 1) 'a new dependency is added with ADD AFTER'

$d = Copy-G $actual; $d.tasks[0].state = 'suspended'; foreach ($t in $d.tasks) { $t.state = 'suspended' }
$p = Plan $d $actual
Assert-Equal @($p.Steps | ForEach-Object { $_.Phase }) @('suspend', 'suspend', 'suspend', 'suspend', 'suspend') 'a graph that is to stop is suspended, the root first'
Assert-Equal $p.Steps[0].Task 'LOAD_ROOT' 'the root first'

$d = Copy-G $actual; $d.tasks[0].schedule = $null; $d.tasks[0].comment = 'hi'; $d.tasks[0].parameters['USER_TASK_TIMEOUT_MS'] = '1000'
$p = Plan $d $actual
Assert-True (@($p.Steps | Where-Object { $_.Sql -eq 'ALTER TASK "DB"."SC"."LOAD_ROOT" UNSET SCHEDULE' }).Count -eq 1) 'a schedule that goes is unset'
Assert-True (@($p.Steps | Where-Object { $_.Sql -match 'SET COMMENT = ''hi'', USER_TASK_TIMEOUT_MS = 1000$' }).Count -eq 1) 'a comment and a parameter are set together'

$d = Copy-G $actual; $d.tasks[1].definition = (([string]$actual.tasks[1].definition) -replace "`n", "`r`n") + "`r`n"
$p = Plan $d $actual
Assert-True $p.IsEmpty 'a different line ending or a trailing break is no change'

Complete-Tests
