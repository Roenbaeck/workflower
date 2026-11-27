<#
.SYNOPSIS
    A differential test: the PowerShell module and unix\engine.js (under Jint) are given the same wanted and installed graphs, and
    must give the same problems, the same CREATE script, the same plan (order, phase, task, SQL text and reason), the same graphs
    read from SHOW TASKS rows and the same exported files.
.DESCRIPTION
    No Snowflake is needed. The installed graph is a list of task specifications; from it the rows of SHOW TASKS are made (the
    engine reads them through the mock of Test-Engine.ps1, the module through ConvertFrom-WfTaskRows). The wanted graph is a list of
    specifications as well, written as a graph file that the module imports with Import-TaskGraph and the engine receives as doc.
.EXAMPLE
    .\Compare-Engines.ps1
#>
[CmdletBinding()]
param([string] $JintPath)
if (-not $JintPath) { $JintPath = Join-Path $PSScriptRoot '../../../sisula/lib/Jint.2.11.58.dll' }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Test-Engine.ps1') -JintPath $JintPath
Import-Module (Join-Path $PSScriptRoot '..\..\Workflower\Workflower.psd1') -Force
$module = Get-Module Workflower
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wf-compare-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------------------------------------------------------
# Task specifications
# ---------------------------------------------------------------------------------------------------------------------------

# $Warehouse '' is serverless; $State '' is not said (in a wanted graph); a parameter is name -> text.
function S {
    param([string] $Name, [string[]] $After = @(), [string] $Finalize, [string] $Schedule, [string] $Warehouse = 'WH', [string] $Condition,
          [string] $State = '', [string] $Definition = 'SELECT 1', $Parameters = @{}, [string] $Comment, [string] $Config, $Overlap = $null,
          [string] $ErrorIntegration)
    $p = [ordered]@{}; foreach ($k in ($Parameters.Keys | Sort-Object)) { $p[$k] = [string]$Parameters[$k] }
    [ordered]@{ name = $Name; after = @($After); finalize = $Finalize; schedule = $Schedule; warehouse = $Warehouse; condition = $Condition; state = $State
        definition = $Definition; parameters = $p; comment = $Comment; config = $Config; overlap = $Overlap; errorIntegration = $ErrorIntegration }
}

# The standard graph: LOAD_ROOT, A and B after it, C after A and B, and a finalizer; all started.
function New-Base {
    @(
        (S 'LOAD_ROOT' -Schedule '60 MINUTE' -State 'started' -Parameters @{ USER_TASK_TIMEOUT_MS = '3600000' })
        (S 'LOAD_A' -After 'LOAD_ROOT' -State 'started' -Definition "BEGIN`n  CALL p('a');`nEND;")
        (S 'LOAD_B' -After 'LOAD_ROOT' -State 'started')
        (S 'LOAD_C' -After 'LOAD_A', 'LOAD_B' -State 'started' -Definition 'SELECT 3')
        (S 'LOAD_FINAL' -Finalize 'LOAD_ROOT' -State 'started' -Definition 'CALL notify()')
    )
}
function Get-Spec { param($Specs, [string] $Name) foreach ($s in $Specs) { if ($s.name -ceq $Name) { return $s } } }
function Remove-Spec { param($Specs, [string[]] $Names) @($Specs | Where-Object { $Names -cnotcontains $_.name }) }
function Copy-Specs {
    param($Specs)
    @($Specs | ForEach-Object { $c = [ordered]@{}; foreach ($k in $_.Keys) { $c[$k] = $_[$k] }; $c.after = @($_.after); $p = [ordered]@{}; foreach ($k in $_.parameters.Keys) { $p[$k] = $_.parameters[$k] }; $c.parameters = $p; $c })
}
function Set-AllStates { param($Specs, [string] $State) foreach ($s in $Specs) { $s.state = $State }; $Specs }
function Clear-States { param($Specs) Set-AllStates $Specs '' }

# The mock of the engine from the installed specs (and the lone task that is always there, to be left alone).
function New-CaseMock {
    param($Installed)
    $m = New-Mock
    foreach ($s in $Installed) {
        $state = $s.state; if (-not $state) { $state = 'suspended' }
        $overlap = 'null'; if ($null -ne $s.overlap) { $overlap = $(if ($s.overlap) { 'true' } else { 'false' }) }
        $row = New-Row $s.name -Definition $s.definition -After $s.after -Finalizes $s.finalize -Schedule $s.schedule -Warehouse $s.warehouse -State $state `
            -Condition $s.condition -Comment ([string]$s.comment) -Id ([string](100 + $m.Rows.Count)) -Overlap $overlap -Quote
        if ($s.config) { $row['config'] = $s.config }
        if ($s.errorIntegration) { $row['error_integration'] = $s.errorIntegration }
        [void]$m.Rows.Add($row)
        $rows = @(); foreach ($k in $s.parameters.Keys) { $rows += @{ key = $k; value = $s.parameters[$k]; default = ''; level = 'TASK' } }
        $rows += @{ key = 'SUSPEND_TASK_AFTER_NUM_FAILURES'; value = '0'; default = '0'; level = '' }
        $m.Params['DB.SC.' + $s.name] = $rows
    }
    [void]$m.Rows.Add((New-Row 'LONE' -Definition 'CALL p()' -Warehouse '' -Schedule 'USING CRON 0 * * * * UTC' -Id '900'))
    $m.Params['DB.SC.LONE'] = @()
    $m
}

# A task row as the SQL API gives it to the module: the predecessors and relations as JSON text, times as text.
function ConvertTo-PsRow {
    param($Row)
    $o = [ordered]@{}
    foreach ($k in $Row.Keys) {
        $v = $Row[$k]
        if ($k -eq 'predecessors') { $v = ConvertTo-Js @($v) }
        elseif ($k -eq 'task_relations' -and $v -isnot [string]) { $v = ConvertTo-Js $v }
        elseif ($v -is [System.Collections.IDictionary]) { $v = $v['__date'] }
        $o[$k] = $v
    }
    [pscustomobject]$o
}

# The graphs of the module from the mock's rows, with the parameters of the tasks as Get-TaskGraph sets them.
function Get-PsGraphs {
    param($Mock)
    $rows = @($Mock.Rows | ForEach-Object { ConvertTo-PsRow $_ })
    $graphs = & $module { param($r) , @(ConvertFrom-WfTaskRows $r) } $rows
    foreach ($g in $graphs) {
        foreach ($t in $g.tasks) {
            $key = $g.database + '.' + $g.schema + '.' + $t.name
            if ($Mock.Params.ContainsKey($key)) { foreach ($p in $Mock.Params[$key]) { if ($p.level -eq 'TASK') { $t.parameters[$p.key] = [string]$p.value } } }
            $sorted = [ordered]@{}; foreach ($k in ($t.parameters.Keys | Sort-Object)) { $sorted[$k] = $t.parameters[$k] }
            $t.parameters = $sorted
        }
    }
    $graphs
}

# The wanted specs as the text of a graph file.
function New-WantedDoc {
    param($Wanted, [string] $Db = 'DB', [string] $Sc = 'SC', [switch] $NoParameters)
    $tasks = @()
    foreach ($s in $Wanted) {
        $t = [ordered]@{ name = $s.name }
        if ($s.after.Count -gt 0) { $t.after = @($s.after) }
        if ($s.finalize) { $t.finalize = $s.finalize }
        if ($s.schedule) { $t.schedule = $s.schedule }
        if ($s.warehouse) { $t.warehouse = $s.warehouse }
        if ($s.condition) { $t.condition = $s.condition }
        if ($null -ne $s.overlap) { $t.allowOverlappingExecution = [bool]$s.overlap }
        if ($s.errorIntegration) { $t.errorIntegration = $s.errorIntegration }
        if ($s.comment) { $t.comment = $s.comment }
        if ($s.config) { $t.config = $s.config }
        if ($s.parameters.Count -gt 0 -and -not $NoParameters) { $t.parameters = $s.parameters }
        if ($s.state) { $t.state = $s.state }
        $t.definition = $s.definition
        $tasks += , $t
    }
    New-Doc $tasks -Db $Db -Sc $Sc
}

function Get-ProblemLines { param($Problems) @($Problems | ForEach-Object { $_.Severity + '|' + $_.Task + '|' + $_.Code + '|' + $_.Message }) }
function Get-StepLines { param($Steps) @($Steps | ForEach-Object { 'phase=' + $_.Phase + ' task=' + $_.Task + "`nsql=" + $_.Sql + "`nreason=" + $_.Reason }) }

$script:Cases = 0
# Compares two lists of lines: each difference is one failed assertion, with the lines that differ.
function Assert-SameLines {
    param([string[]] $Ps, [string[]] $Engine, [string] $Message)
    if (($Ps -join "`n") -ceq ($Engine -join "`n")) { Assert-True $true $Message; return }
    Assert-True $false $Message
    $n = [Math]::Max($Ps.Count, $Engine.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $a = ''; $b = ''; if ($i -lt $Ps.Count) { $a = $Ps[$i] }; if ($i -lt $Engine.Count) { $b = $Engine[$i] }
        if ($a -cne $b) { Write-Host ("        line {0}`n          PowerShell: {1}`n          engine:     {2}" -f ($i + 1), $a.Replace("`n", ' / '), $b.Replace("`n", ' / ')); break }
    }
}

# One case: the problems, the script and the plan of both.
function Compare-Case {
    param([string] $Name, $Installed, $Wanted, [string] $Db = 'DB', [string] $Sc = 'SC', [string] $Warehouse, [switch] $NoPlan)
    $script:Cases++
    Write-Host ('  ' + $Name)
    $mock = New-CaseMock $Installed
    $docObject = New-WantedDoc $Wanted -Db $Db -Sc $Sc
    $docText = ConvertTo-Js $docObject
    $psDocText = ConvertTo-Js (New-WantedDoc $Wanted -Db $Db -Sc $Sc -NoParameters)
    # the module: import the file, check, script, plan
    $file = Join-Path $tmp ('case' + $script:Cases + '.json')
    [System.IO.File]::WriteAllText($file, $psDocText, $utf8)
    $importArgs = @{}; if ($Warehouse) { $importArgs.Warehouse = $Warehouse }
    $graph = Import-TaskGraph $file @importArgs
    # the module cannot import a task with exactly one parameter (see the end), so the parameters are set as the import would
    foreach ($s in $Wanted) {
        $gt = @($graph.tasks | Where-Object { $_.name -ceq $s.name })[0]
        $gt.parameters = [ordered]@{}
        foreach ($k in (@($s.parameters.Keys | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object))) { $gt.parameters[$k] = [string]$s.parameters[$k] }
    }
    $psProblems = @(Test-TaskGraph $graph)
    $psErrors = @($psProblems | Where-Object { $_.Severity -eq 'error' })
    $psScript = ConvertTo-TaskGraphSql $graph -AsScript -IncludeState
    # the engine
    $request = @{ doc = (ConvertTo-B64 $docText) }; if ($Warehouse) { $request.warehouse = $Warehouse }
    $check = Invoke-Engine 'check' $request $mock
    Assert-SameLines (Get-ProblemLines $psProblems) (Get-ProblemLines @($check.Json.problems | ForEach-Object { [pscustomobject]@{ Severity = $_.severity; Task = $_.task; Code = $_.code; Message = $_.message } })) 'the problems'
    Assert-Equal $check.Exit $(if ($psErrors.Count -gt 0) { 1 } else { 0 }) 'the exit code of the check'
    $sql = Invoke-Engine 'sql' $request $mock
    Assert-SameLines @($psScript) @($sql.Texts[0]) 'the CREATE script'
    if ($NoPlan) { return }
    $plan = Invoke-Engine 'plan' $request $mock
    if ($psErrors.Count -gt 0) {
        Assert-True ($plan.Status -eq 'error' -and $plan.Texts[0] -match 'The graph is not valid') 'a graph with errors makes no plan in either'
        return
    }
    $actual = $null
    $wantedNames = @{}; foreach ($t in $graph.tasks) { $wantedNames[$t.name] = $true }
    foreach ($g in @(Get-PsGraphs $mock | Sort-Object database, schema, root)) {
        foreach ($t in $g.tasks) { if ($wantedNames.ContainsKey($t.name) -and -not $actual) { $actual = $g } }
    }
    $psPlan = Compare-TaskGraph $graph -Session $null -Actual $actual
    Assert-Equal $plan.Status 'ok' 'the engine makes a plan'
    Assert-Equal $plan.Steps @($psPlan.Steps).Count 'the number of steps (STEPS)'
    Assert-SameLines (Get-StepLines $psPlan.Steps) (Get-StepLines @($plan.Json.steps | ForEach-Object { [pscustomobject]@{ Phase = $_.phase; Task = $_.task; Sql = $_.sql; Reason = $_.reason } })) 'the steps: order, phase, task, SQL and reason'
    Assert-Equal @($plan.Json.added) @($psPlan.Added) 'the added tasks'
    Assert-Equal @($plan.Json.removed) @($psPlan.Removed) 'the removed tasks'
    Assert-Equal @($plan.Json.changed) @($psPlan.Changed) 'the changed tasks'
    Assert-Equal $plan.Json.exists $psPlan.Exists 'whether it is installed'
}

# ---------------------------------------------------------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------------------------------------------------------

Write-Host 'The plan cases of Test-Offline.ps1'
$base = New-Base
Compare-Case 'as installed' (New-Base) (New-Base)
Compare-Case 'not installed, tasks say started' @() (New-Base)
Compare-Case 'not installed, no state' @() (Clear-States (New-Base))
$w = Clear-States (New-Base); (Get-Spec $w 'LOAD_ROOT').state = 'started'
Compare-Case 'not installed, only the root is started: all are started' @() $w
$w = New-Base; (Get-Spec $w 'LOAD_A').definition = 'SELECT 2'
Compare-Case 'a changed body' (New-Base) $w
$w = Remove-Spec (New-Base) 'LOAD_C'
Compare-Case 'a task that goes' (New-Base) $w
$w = New-Base; (Get-Spec $w 'LOAD_C').after = @('LOAD_A')
Compare-Case 'a dependency that goes' (New-Base) $w
$w = (New-Base) + @(S 'LOAD_D' -After 'LOAD_C' -Definition 'SELECT 4')
Compare-Case 'a new task' (New-Base) $w
$w = New-Base; (Get-Spec $w 'LOAD_A').after = @('LOAD_ROOT', 'LOAD_B')
Compare-Case 'a new dependency' (New-Base) $w
Compare-Case 'a graph that is to stop' (New-Base) (Set-AllStates (New-Base) 'suspended')
$w = New-Base; $r = Get-Spec $w 'LOAD_ROOT'; $r.schedule = ''; $r.state = 'suspended'; $r.comment = 'hi'; $r.parameters['USER_TASK_TIMEOUT_MS'] = '1000'
Compare-Case 'a schedule unset, a comment and a parameter set' (New-Base) $w
$w = New-Base; (Get-Spec $w 'LOAD_A').definition = ((Get-Spec (New-Base) 'LOAD_A').definition -replace "`n", "`r`n") + "`r`n"
Compare-Case 'a different line ending is no change' (New-Base) $w

Write-Host 'More plans'
$w = New-Base
(Get-Spec $w 'LOAD_A').definition = 'SELECT 22'; (Get-Spec $w 'LOAD_A').comment = "it's a ""test"" \ done"
(Get-Spec $w 'LOAD_B').warehouse = 'OTHER_WH'; (Get-Spec $w 'LOAD_B').condition = "SYSTEM`$STREAM_HAS_DATA('S')"
(Get-Spec $w 'LOAD_C').after = @('LOAD_B'); (Get-Spec $w 'LOAD_ROOT').schedule = 'USING CRON 0 6 * * * UTC'
$w = (Remove-Spec $w 'LOAD_FINAL') + @(S 'LOAD_E' -After 'LOAD_A' -State 'started' -Definition 'SELECT 5')
Compare-Case 'several tasks changed at once' (New-Base) $w
$i = Remove-Spec (New-Base) 'LOAD_FINAL'
Compare-Case 'a finalizer added to a started graph' $i (New-Base)
Compare-Case 'a finalizer removed from a started graph' (New-Base) (Remove-Spec (New-Base) 'LOAD_FINAL')
$w = (Remove-Spec (New-Base) 'LOAD_FINAL') + @(S 'LOAD_FINAL2' -Finalize 'LOAD_ROOT' -State 'started' -Definition 'CALL notify2()')
Compare-Case 'a finalizer replaced by another' (New-Base) $w
$i = Set-AllStates (Remove-Spec (New-Base) 'LOAD_FINAL') 'suspended'
Compare-Case 'a finalizer added to a suspended graph' $i (Set-AllStates (New-Base) 'suspended')
$w = New-Base; $r = Get-Spec $w 'LOAD_ROOT'; $r.parameters['USER_TASK_TIMEOUT_MS'] = '120000'; $r.parameters['SUSPEND_TASK_AFTER_NUM_FAILURES'] = '3'; $r.overlap = $true
(Get-Spec $w 'LOAD_B').parameters['STATEMENT_TIMEOUT_IN_SECONDS'] = '600'
$i = New-Base; (Get-Spec $i 'LOAD_B').parameters['TASK_AUTO_RETRY_ATTEMPTS'] = '2'
Compare-Case 'parameters changed, added and removed, and overlapping set' $i $w
$w = New-Base; $r = Get-Spec $w 'LOAD_ROOT'; $r.parameters.Remove('USER_TASK_TIMEOUT_MS'); $r.config = '{"env":"test"}'; $r.errorIntegration = 'MY_INT'
Compare-Case 'a parameter unset, a config and an error integration set' (New-Base) $w
$w = New-Base; $b = Get-Spec $w 'LOAD_B'; $b.warehouse = ''; $b.parameters['USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE'] = 'XSMALL'
Compare-Case 'a task goes serverless' (New-Base) $w
$i = New-Base; $b = Get-Spec $i 'LOAD_B'; $b.warehouse = ''; $b.parameters['USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE'] = 'XSMALL'
Compare-Case 'and back to a warehouse' $i (New-Base)
$i = New-Base; (Get-Spec $i 'LOAD_ROOT').overlap = $false
$w = New-Base; (Get-Spec $w 'LOAD_ROOT').overlap = $true
Compare-Case 'overlapping changed on the root' $i $w
$tree = @(
    (S 'ROOT' -Schedule '1 MINUTE' -State 'started')
    (S 'A' -After 'ROOT' -State 'started')
    (S 'A1' -After 'A' -State 'started')
    (S 'A2' -After 'A' -State 'started')
    (S 'B' -After 'ROOT' -State 'started')
)
Compare-Case 'a dropped task with children (all go)' $tree (Remove-Spec $tree 'A', 'A1', 'A2')
$w = Remove-Spec $tree 'A'; (Get-Spec $w 'A1').after = @('ROOT'); (Get-Spec $w 'A2').after = @('ROOT', 'B')
Compare-Case 'a dropped task whose children move' $tree $w
$w = Remove-Spec $tree 'A', 'A1'; (Get-Spec $w 'A2').after = @('B')
Compare-Case 'a dropped task with children, one child kept and moved' $tree $w
Compare-Case 'a graph that is not installed (finalizer, parameters, condition, comment, config)' @() (@(
    (S 'R' -Schedule 'USING CRON 0 2 * * * Europe/Stockholm' -State 'started' -Parameters @{ USER_TASK_TIMEOUT_MS = '3600000'; SUSPEND_TASK_AFTER_NUM_FAILURES = '5' } -Comment "it's" -Config '{"a":"b"}' -Overlap $false)
    (S 'A' -After 'R' -Condition "SYSTEM`$STREAM_HAS_DATA('S')" -State 'started' -Warehouse '')
    (S 'F' -Finalize 'R' -State 'started' -ErrorIntegration 'MY_INT')
))
$w = @((S 'ROOT2' -Schedule '60 MINUTE' -State 'started'), (S 'LOAD_A' -After 'ROOT2' -State 'started'), (S 'LOAD_B' -After 'ROOT2' -State 'started'))
Compare-Case 'the root is renamed' (New-Base) $w
$w = Set-AllStates (New-Base) 'started'; (Get-Spec $w 'LOAD_B').state = 'suspended'
Compare-Case 'a child that stays suspended in a started graph' (Set-AllStates (New-Base) 'suspended') $w
$w = Clear-States (New-Base); (Get-Spec $w 'LOAD_ROOT').state = 'started'
Compare-Case 'a suspended graph whose root says started' (Set-AllStates (New-Base) 'suspended') $w
$i = Set-AllStates (New-Base) 'suspended'; (Get-Spec $i 'LOAD_C').definition = 'SELECT 33'
Compare-Case 'a suspended graph changed, no state said' $i (Clear-States (New-Base))
$i = Clear-States (New-Base); foreach ($s in $i) { $s.state = 'started' }; (Get-Spec $i 'LOAD_B').state = 'suspended'
Compare-Case 'a started graph with one child suspended is changed and no state said' $i (Clear-States (New-Base))
$w = Clear-States (New-Base); (Get-Spec $w 'LOAD_B').definition = 'SELECT 9'; (Get-Spec $w 'LOAD_ROOT').schedule = '30 MINUTE'
Compare-Case 'a started graph changed, no state said: it stays started' (New-Base) $w

Write-Host 'Hand-made graphs and odd names'
$hand = @(
    (S 'load root' -Schedule 'USING CRON 30 2 * * * Europe/Stockholm' -Definition 'BEGIN SELECT 1; END' -Comment 'made by hand' -Overlap $false -Parameters @{ USER_TASK_TIMEOUT_MS = '90000' })
    (S 'step 1' -After 'load root' -Definition "SELECT 'a;b'")
    (S 'step 2' -After 'load root' -Warehouse '' -Parameters @{ USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL' })
    (S 'Step 3' -After 'step 1', 'step 2' -Definition 'CALL SYSTEM$WAIT(1)')
    (S 'fin' -Finalize 'load root')
)
Compare-Case 'a hand-made graph is its own plan' $hand $hand
$w = Copy-Specs $hand; (Get-Spec $w 'step 1').definition = 'SELECT 2'
Compare-Case 'a hand-made graph with a body changed' $hand $w
$odd = @((S 'caf' + [char]0xE9 + ' "q" it''s \ x' -Schedule '1 MINUTE' -Definition ("SELECT '" + [char]0x20AC + "'") -Comment ("it's a ""test"" \ done " + [char]0x20AC)))
Compare-Case 'a name and a comment with quotes, a backslash and non-ASCII letters' $odd $odd
Compare-Case 'the same, not installed' @() $odd

Write-Host 'Overrides'
$w = New-Base; (Get-Spec $w 'LOAD_B').warehouse = ''
Compare-Case 'a warehouse override replaces the warehouse of the tasks that have one' @() $w -Warehouse 'BIG'
Compare-Case 'a database and schema override: the plan of another schema' @() (New-Base) -Db 'PROD' -Sc 'LIVE'

Write-Host 'Checks of graphs that are not valid'
function Test-Invalid { param([string] $Name, $Wanted) Compare-Case $Name @() $Wanted }
Test-Invalid 'two tasks with one name' @((S 'R'), (S 'R'))
Test-Invalid 'a predecessor that is not there' @((S 'R'), (S 'A' -After 'X'))
Test-Invalid 'two roots' @((S 'R'), (S 'S'))
Test-Invalid 'a schedule on a child' @((S 'R'), (S 'A' -After 'R' -Schedule '1 MINUTE'))
Test-Invalid 'a cycle' @((S 'R'), (S 'A' -After 'B'), (S 'B' -After 'A'))
Test-Invalid 'tasks with no root' @((S 'A' -After 'B'), (S 'B' -After 'A'))
Test-Invalid 'a task with nothing to run' @((S 'R' -Definition ' '))
Test-Invalid 'a finalizer of a task that is not there' @((S 'R'), (S 'F' -Finalize 'X'))
Test-Invalid 'a finalizer of a task that is not the root' @((S 'R'), (S 'A' -After 'R'), (S 'F' -Finalize 'A'))
Test-Invalid 'two finalizers' @((S 'R'), (S 'F' -Finalize 'R'), (S 'G' -Finalize 'R'))
Test-Invalid 'a task after a finalizer' @((S 'R'), (S 'F' -Finalize 'R'), (S 'A' -After 'F'))
Test-Invalid 'a finalizer with predecessors' @((S 'R'), (S 'F' -Finalize 'R' -After 'R'))
Test-Invalid 'a task after itself' @((S 'R'), (S 'A' -After 'A', 'R'))
Test-Invalid 'more than 100 children' (@(S 'R') + @(1..101 | ForEach-Object { S ('C' + $_) -After 'R' }))
Test-Invalid 'more than 100 predecessors' (@(S 'R') + @(1..101 | ForEach-Object { S ('P' + $_) -After 'R' }) + @(S 'Z' -After (@(1..101 | ForEach-Object { 'P' + $_ }))))
Test-Invalid 'more than 1,000 tasks' @(1..1001 | ForEach-Object { S ('N' + $_) })
Test-Invalid 'a warehouse and a serverless size' @((S 'R' -Schedule '1 MINUTE' -Parameters @{ USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL' }))
Test-Invalid 'a root that nothing starts' @((S 'R'))
Test-Invalid 'a started root that nothing starts' @((S 'R' -State 'started'))
Test-Invalid 'a suspended child of a started root' @((S 'R' -Schedule '1 MINUTE' -State 'started'), (S 'A' -After 'R' -State 'suspended'))
Test-Invalid 'overlapping set on a child' @((S 'R' -Schedule '1 MINUTE'), (S 'A' -After 'R' -Overlap $true))
Test-Invalid 'a root with a condition and no schedule, started' @((S 'R' -Condition "SYSTEM`$STREAM_HAS_DATA('S')" -State 'started'))

# ---------------------------------------------------------------------------------------------------------------------------
# Reading and writing graphs
# ---------------------------------------------------------------------------------------------------------------------------

Write-Host 'Graphs read from SHOW TASKS rows'
function Sort-Blocks {
    param($Lines)
    $blocks = @(); $cur = $null
    foreach ($l in $Lines) { if ($l.StartsWith("graph ")) { if ($cur) { $blocks += $cur }; $cur = $l } else { $cur += "`n" + $l } }
    if ($cur) { $blocks += $cur }
    $sorted = [string[]]$blocks; [array]::Sort($sorted, [StringComparer]::Ordinal)
    @($sorted | ForEach-Object { $_ -split "`n" })
}
function Compare-Reading {
    param([string] $Name, $Mock, [string] $Db = 'DB')
    Write-Host ('  ' + $Name)
    $psGraphs = @(Get-PsGraphs $Mock | Where-Object { $_.database -ceq $Db })
    $en = Invoke-Engine 'graphs' @{ database = $Db; parameters = $true } $Mock
    $psLines = @($psGraphs | ForEach-Object {
        $g = $_
        'graph ' + $g.database + '.' + $g.schema + ' root=' + $g.root + ' incomplete=' + $g.Incomplete
        foreach ($t in $g.tasks) { '  ' + $t.name + ' after=' + (@($t.after) -join ',') + ' finalize=' + $t.finalize + ' state=' + $t.state + ' wh=' + $t.warehouse + ' sched=' + $t.schedule + ' cond=' + $t.condition + ' overlap=' + $t.allowOverlappingExecution + ' comment=' + $t.comment + ' params=' + (($t.parameters.Keys | ForEach-Object { $_ + ':' + $t.parameters[$_] }) -join ',') + ' id=' + $t.info.id }
    })
    $enLines = @($en.Json.graphs | ForEach-Object {
        $g = $_
        'graph ' + $g.database + '.' + $g.schema + ' root=' + $g.root + ' incomplete=' + $g.incomplete
        foreach ($t in $g.tasks) { '  ' + $t.name + ' after=' + (@($t.after) -join ',') + ' finalize=' + $t.finalize + ' state=' + $t.state + ' wh=' + $t.warehouse + ' sched=' + $t.schedule + ' cond=' + $t.condition + ' overlap=' + $t.allowOverlappingExecution + ' comment=' + $t.comment + ' params=' + (($t.parameters.psobject.Properties | ForEach-Object { $_.Name + ':' + $_.Value }) -join ',') + ' id=' + $t.info.id }
    })
    $psLines = @($psLines | ForEach-Object { $_ -replace 'incomplete=False', 'incomplete=false' -replace 'incomplete=True', 'incomplete=true' -replace 'overlap=True', 'overlap=true' -replace 'overlap=False', 'overlap=false' })
    $enLines = @($enLines | ForEach-Object { $_ -replace 'incomplete=False', 'incomplete=false' -replace 'incomplete=True', 'incomplete=true' -replace 'overlap=True', 'overlap=true' -replace 'overlap=False', 'overlap=false' })
    # the order of graphs is ordinal in the engine and by culture in the module (see the end), so the graphs are compared in one order
    $psLines = Sort-Blocks $psLines; $enLines = Sort-Blocks $enLines
    Assert-SameLines $psLines $enLines 'the graphs, their tasks and what is known about them'
}
Compare-Reading 'the standard graph and a lone task' (New-CaseMock (New-Base))
Compare-Reading 'a hand-made graph with quoted names' (New-CaseMock $hand)
$incomplete = New-Mock
foreach ($r in @((New-Row 'S1' -After 'SX' -Id '1'), (New-Row 'S2' -Id '2'), (New-Row 'S3' -After 'S2' -Id '3'), (New-Row 'S4' -After 'S3' -Id '4'))) { [void]$incomplete.Rows.Add($r) }
Compare-Reading 'a hidden predecessor' $incomplete
$several = New-CaseMock (New-Base)
foreach ($r in @((New-Row 'X1' -Schedule '1 MINUTE' -Sc 'SC2' -Id '50'), (New-Row 'X2' -After 'X1' -Sc 'SC2' -Id '51'), (New-Row 'Z' -Schedule '1 MINUTE' -Sc 'AAA' -Id '60'))) { [void]$several.Rows.Add($r) }
Compare-Reading 'several schemas' $several

Write-Host 'Exported files'
function Compare-Export {
    param([string] $Name, $Mock, [string] $Root, [switch] $Split, [switch] $NoState)
    Write-Host ('  ' + $Name)
    $graph = @(Get-PsGraphs $Mock | Where-Object { $_.root -ceq $Root })[0]
    $dir = Join-Path $tmp ('export' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $args2 = @{ Directory = $dir }; if ($Split) { $args2.SplitDefinitions = $true }; if ($NoState) { $args2.NoState = $true }
    $graph | Export-TaskGraph @args2 | Out-Null
    $request = @{ database = 'DB'; schema = 'SC'; root = $Root }; if ($Split) { $request.split = $true }; if ($NoState) { $request.noState = $true }
    $en = Invoke-Engine 'export' $request $Mock
    $psFiles = @(Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object { $_.FullName.Substring($dir.Length + 1).Replace('\', '/') } | Sort-Object)
    Assert-Equal @($en.Files.Keys | Sort-Object) $psFiles 'the same files'
    foreach ($f in $psFiles) {
        $psText = [System.IO.File]::ReadAllText((Join-Path $dir $f), [System.Text.Encoding]::UTF8)
        Assert-True ($en.Files.Contains($f) -and $en.Files[$f] -ceq $psText) ('the same text in ' + $f)
    }
}
Compare-Export 'the standard graph' (New-CaseMock (New-Base)) 'LOAD_ROOT'
Compare-Export 'the standard graph, definitions apart' (New-CaseMock (New-Base)) 'LOAD_ROOT' -Split
Compare-Export 'the standard graph, no state' (New-CaseMock (New-Base)) 'LOAD_ROOT' -NoState
$rich = @(
    (S 'R' -Schedule 'USING CRON 0 2 * * * Europe/Stockholm' -State 'started' -Parameters @{ USER_TASK_TIMEOUT_MS = '3600000'; SUSPEND_TASK_AFTER_NUM_FAILURES = '5' } -Comment "it's ""x"" \ y $([char]0xE9)" -Config '{"a":"b"}' -Overlap $false)
    (S 'A' -After 'R' -Condition "SYSTEM`$STREAM_HAS_DATA('S')" -State 'started' -Warehouse '' -Definition "BEGIN`n  CALL p('caf$([char]0xE9)');`nEND;")
    (S 'F' -Finalize 'R' -State 'started' -ErrorIntegration 'MY_INT')
)
Compare-Export 'a graph with every property' (New-CaseMock $rich) 'R'
Compare-Export 'a graph with every property, definitions apart' (New-CaseMock $rich) 'R' -Split

# ---------------------------------------------------------------------------------------------------------------------------
# Where the two are known to differ
# ---------------------------------------------------------------------------------------------------------------------------

Write-Host 'Cases that once differed (exact names, ordinal order, one parameter): the two implementations agree now, and the lines below show both'
# 1. PowerShell hashtables ignore the case of a key, and Snowflake's quoted names do not: two tasks "a" and "A" are two tasks.
$ci = @((S 'r' -Schedule '1 MINUTE'), (S 'R' -After 'r'))
$docCi = ConvertTo-Request (New-WantedDoc $ci)
$en = Invoke-Engine 'check' $docCi
$file = Join-Path $tmp 'ci.json'; [System.IO.File]::WriteAllText($file, (ConvertTo-Js (New-WantedDoc $ci)), $utf8)
$psCodes = @(Test-TaskGraph (Import-TaskGraph $file) | ForEach-Object { $_.Code })
Assert-Equal @($en.Json.problems | ForEach-Object { $_.code }) @() 'two tasks whose names differ in case only are two tasks (engine)'
Write-Host ('        PowerShell says: ' + ($psCodes -join ', ') + ' (its hashtables ignore case)')
# 2. Sort-Object orders names by the culture and ignores case; the engine orders them by code unit, so that the order of
#    tasks that are read from Snowflake can differ for names such as LOAD_A and LOAD1 (underscore before digit in the culture, after it by code).
$mockSort = New-Mock
foreach ($r in @((New-Row 'ROOT' -Schedule '1 MINUTE'), (New-Row 'LOAD_A' -After 'ROOT' -Id '2'), (New-Row 'LOAD1' -After 'ROOT' -Id '3'))) { [void]$mockSort.Rows.Add($r) }
$psOrder = @((Get-PsGraphs $mockSort)[0].tasks | ForEach-Object { $_.name })
$enOrder = @((Invoke-Engine 'graphs' @{ database = 'DB' } $mockSort).Json.graphs[0].tasks | ForEach-Object { $_.name })
Write-Host ('        order of siblings, PowerShell: ' + ($psOrder -join ', ') + '; engine: ' + ($enOrder -join ', '))
Assert-Equal $enOrder @('ROOT', 'LOAD1', 'LOAD_A') 'the engine orders names ordinally'
# 4. A predecessor named with other case than the task: the module keeps the spelling of the relation (its hashtable matched it), the
#    engine the exact name of the task, which is what an ALTER TASK needs.
$ciRows = New-Mock
foreach ($r in @((New-Row 'S2' -Id '2'), (New-Row 'S3' -After 's2' -Id '3'))) { [void]$ciRows.Rows.Add($r) }
$psAfter = @((Get-PsGraphs $ciRows)[0].tasks | Where-Object { $_.name -ceq 'S3' })[0].after
$enAfter = @((Invoke-Engine 'graphs' @{ database = 'DB' } $ciRows).Json.graphs[0].tasks | Where-Object { $_.name -ceq 'S3' })[0].after
Assert-Equal @($enAfter) @('S2') 'the engine gives the exact name of a predecessor that the relations spell in another case'
Write-Host ('        predecessor, PowerShell: ' + (@($psAfter) -join ',') + '; engine: ' + (@($enAfter) -join ','))
# 5. The order of graphs: 'load root' and 'LONE'. The module sorts by culture without regard to case, the engine ordinally.
$lone = New-CaseMock $hand
$psRoots = @(Get-PsGraphs $lone | ForEach-Object { $_.root })
$enRoots = @((Invoke-Engine 'graphs' @{ database = 'DB' } $lone).Json.graphs | ForEach-Object { $_.root })
Write-Host ('        order of graphs, PowerShell: ' + ($psRoots -join ', ') + '; engine: ' + ($enRoots -join ', '))
# 3. A bug of the module: ConvertTo-WfTask cannot read a task with exactly one parameter (Sort-Object over one pair gives the pair's
#    elements, so $pair[0] is a character). The engine reads it.
$oneFile = Join-Path $tmp 'one.json'
[System.IO.File]::WriteAllText($oneFile, '{"database":"D","schema":"S","tasks":[{"name":"R","definition":"SELECT 1","schedule":"1 MINUTE","parameters":{"USER_TASK_TIMEOUT_MS":"60000"}}]}', $utf8)
$psMessage = $null
try { Import-TaskGraph $oneFile | Out-Null } catch { $psMessage = $_.Exception.Message }
$en = Invoke-Engine 'sql' @{ doc = (ConvertTo-B64 ([System.IO.File]::ReadAllText($oneFile))) }
Assert-True ($en.Status -eq 'ok' -and $en.Texts[0].Contains('USER_TASK_TIMEOUT_MS = 60000')) 'the engine reads a task with exactly one parameter'
Write-Host ('        PowerShell (Import-TaskGraph): ' + $(if ($psMessage) { $psMessage } else { 'reads it' }))

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("{0} cases compared" -f $script:Cases)
Complete-Tests
