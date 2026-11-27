<#
.SYNOPSIS
    Tests against a real Snowflake account: the statements that the module writes are accepted, a graph that was installed reads back
    as what was wanted (so that a second plan has nothing to do), and graphs that the module did not make can be read, copied and run.
.DESCRIPTION
    Everything is made in a scratch database that the test drops at the end. Tasks are made suspended; the test resumes and runs one
    graph, which needs the EXECUTE TASK privilege (the tests that need it are skipped with a message if the role has none).
.EXAMPLE
    .\Test-Live.ps1 -Account myorg-myaccount -TokenFile ~\.snowflake\pat.txt -Warehouse WH -Role SYSADMIN
.EXAMPLE
    .\Test-Live.ps1 -Connection default
#>
[CmdletBinding(DefaultParameterSetName = 'Api')]
param(
    [Parameter(ParameterSetName = 'Api', Mandatory = $true)][string] $Account,
    [Parameter(ParameterSetName = 'Api', Mandatory = $true)][string] $TokenFile,
    [Parameter(ParameterSetName = 'Cli', Mandatory = $true)][string] $Connection,
    [string] $Warehouse,
    [string] $Role,
    [switch] $Keep
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\TestHelpers.ps1"
Import-Module (Join-Path $PSScriptRoot '..\Workflower\Workflower.psd1') -Force
$module = Get-Module Workflower

if ($PSCmdlet.ParameterSetName -eq 'Cli') { $s = New-WfSession -Connection $Connection -Warehouse $Warehouse -Role $Role }
else { $s = New-WfSession -Account $Account -TokenFile $TokenFile -Warehouse $Warehouse -Role $Role }

$db = 'WORKFLOWER_TEST_' + (Get-Random -Minimum 10000 -Maximum 99999)
$wh = $Warehouse
if (-not $wh) { $wh = [string](@(Invoke-WfSql $s 'SELECT CURRENT_WAREHOUSE() AS W')[0].W) }
Write-Host ("Scratch database {0}, warehouse {1}" -f $db, $wh)

function Run { param([string] $Sql) Invoke-WfSql $s $Sql | Out-Null }
function Step { param([string] $Name, [scriptblock] $Block)
    try { & $Block } catch { $global:Failed++; Write-Host ('  FAIL  ' + $Name + ': ' + $_.Exception.Message) -ForegroundColor Red }
}
function New-T { param([string] $Name, [string[]] $After = @(), [string] $Def = 'SELECT 1', [string] $Schedule)
    $t = & $module { param($n) New-WfTaskObject $n } $Name
    $t.definition = $Def; $t.after = @($After); $t.schedule = $Schedule; $t.warehouse = $wh; $t }
function New-Graph { param([string] $Schema, $Tasks)
    $g = & $module { param($d, $sc, $t) $x = New-WfGraphObject $d $sc $null $t; Update-WfGraph $x } $db $Schema @($Tasks); $g }
function Plan-Phases { param($Plan) @($Plan.Steps | ForEach-Object { $_.Phase }) }
function Settle { param($Graph, [string] $Message)
    # after a publish the installed graph is what was wanted, so a second plan is empty
    $again = Compare-TaskGraph $Graph -Session $s
    Assert-True $again.IsEmpty ($Message + ': a second plan has nothing to do')
    if (-not $again.IsEmpty) { $again.Steps | ForEach-Object { Write-Host ('        ' + ($_.Sql -split "`n")[0] + '   -- ' + $_.Reason) } }
}

Run ('CREATE OR REPLACE DATABASE "' + $db + '"')
Run ('CREATE SCHEMA "' + $db + '"."ONE"')
Run ('CREATE SCHEMA "' + $db + '"."TWO"')
Run ('CREATE TABLE "' + $db + '"."ONE"."SRC" (ID NUMBER)')

try {
    Write-Host 'A graph is made'
    Step 'make' {
        $r = New-T 'ROOT' -Schedule '60 MINUTE'
        $a = New-T 'LOAD_A' -After 'ROOT' -Def "INSERT INTO SRC VALUES (1)"
        $b = New-T 'LOAD_B' -After 'ROOT'
        $c = New-T 'JOIN_C' -After 'LOAD_A', 'LOAD_B' -Def 'SELECT 3'
        $g = New-Graph 'ONE' @($r, $a, $b, $c)
        $plan = Compare-TaskGraph $g -Session $s
        Assert-Equal (Plan-Phases $plan) @('create', 'create', 'create', 'create') 'a graph that is not there is planned as four creates'
        Publish-TaskGraph $g -Session $s | Out-Null
        $read = @(Get-TaskGraph $s -Database $db -Schema 'ONE')
        Assert-Equal $read.Count 1 'one graph is read back'
        Assert-Equal $read[0].root 'ROOT' 'with the right root'
        Assert-Equal @($read[0].tasks).Count 4 'and four tasks'
        Assert-Equal @(@($read[0].tasks | Where-Object { $_.name -eq 'JOIN_C' })[0].after | Sort-Object) @('LOAD_A', 'LOAD_B') 'the predecessors are read'
        Assert-Equal @($read[0].tasks | Where-Object { $_.name -eq 'ROOT' })[0].schedule '60 MINUTE' 'the schedule is read'
        Assert-Equal @($read[0].tasks | Where-Object { $_.name -eq 'ROOT' })[0].state 'suspended' 'a new task is suspended'
        Settle $g 'after creating'
    }

    Write-Host 'Changes to an installed graph'
    $installed = $null
    Step 'body' {
        $g = Import-TaskGraph (Export-TaskGraph (@(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]) -Directory (Join-Path ([IO.Path]::GetTempPath()) ('wf-' + [guid]::NewGuid().ToString('N'))) ).FullName
        $g.tasks | Where-Object { $_.name -eq 'LOAD_B' } | ForEach-Object { $_.definition = 'SELECT 22' }
        $plan = Compare-TaskGraph $g -Session $s
        Assert-Equal (Plan-Phases $plan) @('alter') 'a changed body is one alter (the graph was suspended)'
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after MODIFY AS'
    }
    Step 'properties' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $r = @($g.tasks | Where-Object { $_.name -eq 'ROOT' })[0]
        $r.schedule = 'USING CRON 0 6 * * * UTC'; $r.comment = "it's a ""test"" \ done"; $r.parameters['USER_TASK_TIMEOUT_MS'] = '120000'
        $r.parameters['SUSPEND_TASK_AFTER_NUM_FAILURES'] = '3'; $r.allowOverlappingExecution = $true
        $r.config = '{"env":"test"}'
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after setting schedule, comment, parameters, overlap and config'
        $g2 = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $r2 = @($g2.tasks | Where-Object { $_.name -eq 'ROOT' })[0]
        Assert-Equal $r2.comment "it's a ""test"" \ done" 'a comment with quotes and a backslash is exact'
        $r2.schedule = $null; $r2.comment = $null; $r2.config = $null; $r2.allowOverlappingExecution = $null; $r2.parameters.Remove('USER_TASK_TIMEOUT_MS')
        Publish-TaskGraph $g2 -Session $s | Out-Null
        Settle $g2 'after unsetting them again'
        $r3 = @((@(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]).tasks | Where-Object { $_.name -eq 'ROOT' })[0]
        Assert-Equal $r3.schedule $null 'the schedule is gone'
        $g4 = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        @($g4.tasks | Where-Object { $_.name -eq 'ROOT' })[0].schedule = '60 MINUTE'
        Publish-TaskGraph $g4 -Session $s | Out-Null
        Settle $g4 'after the schedule is set again'
    }
    Step 'condition' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $t = @($g.tasks | Where-Object { $_.name -eq 'LOAD_A' })[0]
        Run ('CREATE STREAM "' + $db + '"."ONE"."S" ON TABLE "' + $db + '"."ONE"."SRC"')
        $t.condition = 'SYSTEM$STREAM_HAS_DATA(''' + $db + '.ONE.S'')'
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after MODIFY WHEN'
        $t.condition = $null
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after removing the condition'
    }
    Step 'dependencies' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $c = @($g.tasks | Where-Object { $_.name -eq 'JOIN_C' })[0]
        $c.after = @('LOAD_A')
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after removing a predecessor'
        $new = New-T 'LATE_D' -After 'JOIN_C' -Def 'SELECT 4'
        $g.tasks = @($g.tasks) + @($new)
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after adding a child'
        $g3 = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        ($g3.tasks | Where-Object { $_.name -eq 'LATE_D' }).after = @('LOAD_B', 'JOIN_C')
        Publish-TaskGraph $g3 -Session $s | Out-Null
        Settle $g3 'after adding a dependency to a task'
        $g4 = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $g4.tasks = @($g4.tasks | Where-Object { $_.name -ne 'LATE_D' })
        Publish-TaskGraph $g4 -Session $s | Out-Null
        Settle $g4 'after dropping a task'
        Assert-Equal @(@(Get-TaskGraph $s -Database $db -Schema 'ONE')[0].tasks).Count 4 'and it is gone'
    }
    Step 'finalizer' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $f = New-T 'FINAL' -Def 'SELECT 99'; $f.finalize = 'ROOT'
        $g.tasks = @($g.tasks) + @($f)
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after adding a finalizer'
        $read = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        Assert-Equal @($read.tasks | Where-Object { $_.finalize })[0].name 'FINAL' 'the finalizer is read'
        $read.tasks = @($read.tasks | Where-Object { $_.name -ne 'FINAL' })
        Publish-TaskGraph $read -Session $s | Out-Null
        Settle $read 'after dropping the finalizer'
    }
    Step 'serverless' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE')[0]
        $b = @($g.tasks | Where-Object { $_.name -eq 'LOAD_B' })[0]
        $b.warehouse = $null; $b.parameters['USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE'] = 'XSMALL'
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'after a task goes serverless'
        $b.parameters.Remove('USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE'); $b.warehouse = $wh
        Publish-TaskGraph $g -Session $s | Out-Null
        Settle $g 'and back to a warehouse'
    }

    Write-Host 'A graph that was not made by this module'
    Step 'foreign' {
        $q = '"' + $db + '"."TWO".'
        Run ('CREATE TASK ' + $q + '"load root" WAREHOUSE = "' + $wh + '" SCHEDULE = ''USING CRON 30 2 * * * Europe/Stockholm'' COMMENT = ''made by hand'' USER_TASK_TIMEOUT_MS = 90000 ALLOW_OVERLAPPING_EXECUTION = FALSE AS BEGIN SELECT 1; END')
        Run ('CREATE TASK ' + $q + '"step 1" WAREHOUSE = "' + $wh + '" AFTER ' + $q + '"load root" AS SELECT ''a;b''')
        Run ('CREATE TASK ' + $q + '"step 2" USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = XSMALL AFTER ' + $q + '"load root" AS SELECT 2')
        Run ('CREATE TASK ' + $q + '"Step 3" WAREHOUSE = "' + $wh + '" AFTER ' + $q + '"step 1", ' + $q + '"step 2" AS CALL SYSTEM$WAIT(1)')
        Run ('CREATE TASK ' + $q + '"fin" WAREHOUSE = "' + $wh + '" FINALIZE = ' + $q + '"load root" AS SELECT 0')
        $read = @(Get-TaskGraph $s -Database $db -Schema 'TWO')
        Assert-Equal $read.Count 1 'five hand-made tasks are one graph'
        $g = $read[0]
        Assert-Equal $g.root 'load root' 'a root name with a space is read'
        Assert-Equal @($g.tasks | ForEach-Object { $_.name }) @('load root', 'step 1', 'step 2', 'Step 3', 'fin') 'in order, the finalizer last'
        Assert-True (@(Test-TaskGraph $g | Where-Object { $_.Severity -eq 'error' }).Count -eq 0) 'and it passes the checks'
        $plan = Compare-TaskGraph $g -Session $s
        Assert-True $plan.IsEmpty 'it is its own plan: nothing to do'
        if (-not $plan.IsEmpty) { $plan.Steps | ForEach-Object { Write-Host ('        ' + ($_.Sql -split "`n")[0] + '   -- ' + $_.Reason) } }
        # copy it into the first schema by rendering it
        $copy = & $module { param($x) $y = $x.psobject.Copy(); $y } $g
        $copy.schema = 'ONE'
        $copy.tasks = @($g.tasks | ForEach-Object { $c = $_.psobject.Copy(); $c.name = 'copy of ' + $c.name; $c.after = @($c.after | ForEach-Object { 'copy of ' + $_ }); if ($c.finalize) { $c.finalize = 'copy of ' + $c.finalize }; $c })
        $copy.root = 'copy of load root'
        $sql = @(ConvertTo-TaskGraphSql $copy)
        foreach ($statement in $sql) { Run $statement }
        $again = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'copy of load root' })
        Assert-Equal $again.Count 1 'the rendered SQL makes the copy'
        Settle $copy 'the copy is as rendered'
    }

    Write-Host 'Operations'
    Step 'operate' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        $threw = $null
        try { Resume-TaskGraph $g -Session $s } catch { $threw = $_.Exception.Message }
        if ($threw) { Write-Host ('        (Resume needs a privilege here: ' + $threw + ')'); return }
        $now = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        Assert-True (@($now.tasks | Where-Object { $_.state -ne 'started' }).Count -eq 0) 'every task is started after Resume-TaskGraph'
        # a started graph is changed with its root suspended and started again afterwards
        $edit = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        @($edit.tasks | Where-Object { $_.name -eq 'LOAD_B' })[0].definition = 'SELECT 33'
        $plan = Compare-TaskGraph $edit -Session $s
        Assert-Equal (Plan-Phases $plan) @('suspend', 'alter', 'resume') 'a started graph is changed as suspend, alter, resume'
        Publish-TaskGraph $edit -Session $s | Out-Null
        $after = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        Assert-True (@($after.tasks | Where-Object { $_.state -ne 'started' }).Count -eq 0) 'and it is started again afterwards'
        Settle $edit 'after changing a started graph'
        # what Snowflake says when a child of a started graph is altered without suspending the root
        $direct = 'ALTER TASK "' + $db + '"."ONE"."LOAD_B" MODIFY AS SELECT 34'
        $why = $null
        try { Run $direct } catch { $why = $_.Exception.Message }
        Write-Host ('        (altering a child of a started graph directly: ' + $(if ($why) { $why } else { 'accepted' }) + ')')
        $now = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        Suspend-TaskGraph $now -Session $s
        $off = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        Assert-True (@($off.tasks | Where-Object { $_.state -eq 'started' }).Count -eq 0) 'and suspended after Suspend-TaskGraph'
        Start-TaskGraph $off -Session $s
        $runs = @()
        for ($i = 0; $i -lt 30 -and $runs.Count -eq 0; $i++) { Start-Sleep -Seconds 4; $runs = @(Get-TaskGraphRun $off -Session $s -Hours 1) }
        Assert-True ($runs.Count -ge 1) 'a run shows in the history'
        if ($runs.Count -ge 1) {
            Write-Host ('        run ' + $runs[0].RunId + ' ' + $runs[0].State + ', ' + @($runs[0].Tasks).Count + ' tasks')
        }
    }

    Write-Host 'Failures'
    Step 'failures' {
        $g = @(Get-TaskGraph $s -Database $db -Schema 'ONE' | Where-Object { $_.root -ceq 'ROOT' })[0]
        $t = @($g.tasks | Where-Object { $_.name -eq 'LOAD_A' })[0]
        $t.warehouse = 'NO_SUCH_WAREHOUSE_' + $db
        Assert-Throws { Publish-TaskGraph $g -Session $s } 'Step \d+ of \d+ failed' 'a step that fails says which step it was'
    }
}
finally {
    if (-not $Keep) { try { Run ('DROP DATABASE IF EXISTS "' + $db + '"') } catch { Write-Host ('could not drop ' + $db + ': ' + $_.Exception.Message) } }
    else { Write-Host ('kept ' + $db) }
}
Complete-Tests
