<#
.SYNOPSIS
    Tests of unix\engine.js that need no Snowflake: the engine runs under Jint (an ES5 interpreter), against a mock of the global
    `snowflake` that answers the statements the engine issues from fixtures and records every statement that changes something.
.DESCRIPTION
    The harness (the mock, the way the engine is called and the answer is decoded) is also used by Compare-Engines.ps1, which
    dot-sources this file: when it is dot-sourced, only the functions are defined.
.EXAMPLE
    .\Test-Engine.ps1
#>
[CmdletBinding()]
param([string] $JintPath)
if (-not $JintPath) { $JintPath = Join-Path $PSScriptRoot '../../../sisula/lib/Jint.2.11.58.dll' }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tests\TestHelpers.ps1')

# ---------------------------------------------------------------------------------------------------------------------------
# The harness
# ---------------------------------------------------------------------------------------------------------------------------

Add-Type -Path $JintPath
Add-Type -AssemblyName System.Web.Extensions
# Jint cannot call a delegate made from a script block, but it can call a method of an object, so the handler sits in a small class.
if (-not ('WfJintHost' -as [type])) {
    Add-Type -TypeDefinition 'public class WfJintHost { public System.Func<string, string, string> Handler; public string Call(string sql, string binds) { return Handler(sql, binds); } }'
}
$global:WfSer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$global:WfSer.MaxJsonLength = [int]::MaxValue
$global:WfEnginePath = Join-Path $PSScriptRoot '..\engine.js'
$global:WfEngineText = [System.IO.File]::ReadAllText($global:WfEnginePath, [System.Text.Encoding]::UTF8)

# The global `snowflake` as Snowflake gives it to a procedure: execute({sqlText, binds}) returns a result set that is walked with
# next() and getColumnValue(i) (1-based); a failed statement throws. A value that is a time arrives as a Date.
$global:WfPrelude = @'
function wfRevive(v) {
  if (v !== null && typeof v === 'object' && !Array.isArray(v) && v.__date !== undefined) { return new Date(v.__date); }
  return v;
}
var snowflake = {
  execute: function (cmd) {
    var k, binds, out, rows, cols, pos = -1;
    for (k in cmd) { if (k !== 'sqlText' && k !== 'binds') { throw new Error('mock: unknown property of a statement: ' + k); } }
    if (typeof cmd.sqlText !== 'string') { throw new Error('mock: sqlText is not a string'); }
    binds = cmd.binds || [];
    if (!Array.isArray(binds)) { throw new Error('mock: binds is not an array'); }
    out = JSON.parse(host.Call(cmd.sqlText, JSON.stringify(binds)));
    if (out.error) { throw new Error(out.error); }
    rows = out.rows; cols = out.columns;
    return {
      next: function () { pos++; return pos < rows.length; },
      getColumnValue: function (i) {
        if (pos < 0 || pos >= rows.length) { throw new Error('mock: no current row'); }
        if (i < 1 || i > cols.length) { throw new Error('mock: no column ' + i); }
        return wfRevive(rows[pos][i - 1]);
      },
      getColumnName: function (i) { if (i < 1 || i > cols.length) { throw new Error('mock: no column ' + i); } return cols[i - 1]; },
      getColumnCount: function () { return cols.length; }
    };
  }
};
'@

function ConvertTo-B64 { param([string] $Text) [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }
function ConvertFrom-B64 { param([string] $B64) [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64)) }

# JSON text of dictionaries, arrays and scalars (ASCII only). The .NET serializer is not used for this: it trips over the wrapped
# objects that PowerShell makes.
function ConvertTo-Js {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($c in $Value.ToCharArray()) {
            $n = [int]$c
            if ($n -eq 34) { [void]$sb.Append('\"') } elseif ($n -eq 92) { [void]$sb.Append('\\') } elseif ($n -eq 10) { [void]$sb.Append('\n') }
            elseif ($n -eq 13) { [void]$sb.Append('\r') } elseif ($n -eq 9) { [void]$sb.Append('\t') }
            elseif ($n -lt 32 -or $n -gt 126) { [void]$sb.Append('\u' + $n.ToString('x4')) } else { [void]$sb.Append($c) }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $items = @(foreach ($k in $Value.Keys) { (ConvertTo-Js ([string]$k)) + ':' + (ConvertTo-Js $Value[$k]) })
        return '{' + ($items -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @(foreach ($x in $Value) { ConvertTo-Js $x })
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [double] -or $Value -is [decimal]) { return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value) }
    if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
    ConvertTo-Js ([string]$Value)
}
# Parsed JSON: dictionaries, object arrays and scalars. The comma keeps an array from being unrolled.
function ConvertFrom-Js {
    param([string] $Text)
    $o = $global:WfSer.DeserializeObject($Text)
    if ($o -is [array]) { , $o } else { $o }
}

# Splits a dotted, possibly quoted name into its parts (the mock reads the scope of SHOW from it).
function Split-MockName {
    param([string] $Text)
    $parts = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $Text.Length) {
        if ($Text[$i] -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $i++
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '"') { if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '"') { [void]$sb.Append('"'); $i += 2; continue }; $i++; break }
                [void]$sb.Append($Text[$i]); $i++
            }
            $parts.Add($sb.ToString())
        } else {
            $start = $i
            while ($i -lt $Text.Length -and $Text[$i] -ne '.') { $i++ }
            $parts.Add($Text.Substring($start, $i - $start))
        }
        if ($i -lt $Text.Length -and $Text[$i] -eq '.') { $i++ }
    }
    , $parts.ToArray()
}

function New-Mock {
    [pscustomobject]@{
        Rows = (New-Object System.Collections.ArrayList)        # the rows of SHOW TASKS (ordered dictionaries)
        Params = @{}                                            # 'DB.SC.TASK' -> rows of SHOW PARAMETERS IN TASK
        History = (New-Object System.Collections.ArrayList)     # the rows of TASK_HISTORY
        Recorded = (New-Object System.Collections.ArrayList)    # every statement that changes something, in order
        All = (New-Object System.Collections.ArrayList)         # every statement
        FailOn = $null                                          # a pattern: a recorded statement that matches it fails
        HistoryFails = $false                                  # reading the history raises an error (no MONITOR privilege)
    }
}

function Invoke-MockSql {
    param($Mock, [string] $Sql, [string] $BindsJson)
    $binds = @($global:WfSer.DeserializeObject($BindsJson))
    [void]$Mock.All.Add($Sql)
    if ($Sql -match '^SHOW TASKS IN (SCHEMA|DATABASE|ACCOUNT)(?: (.+))?$') {
        $scope = $Matches[1]; $parts = @(); if ($Matches[2]) { $parts = Split-MockName $Matches[2] }
        $rows = New-Object System.Collections.ArrayList
        foreach ($r in $Mock.Rows) {
            if ($scope -eq 'ACCOUNT' -or ($scope -eq 'DATABASE' -and $r['database_name'] -ceq $parts[0]) -or
                ($scope -eq 'SCHEMA' -and $r['database_name'] -ceq $parts[0] -and $r['schema_name'] -ceq $parts[1])) { [void]$rows.Add(@($r.Values)) }
        }
        $columns = @(); if ($Mock.Rows.Count -gt 0) { $columns = @($Mock.Rows[0].Keys) }
        return (ConvertTo-Js ([ordered]@{ columns = $columns; rows = $rows }))
    }
    if ($Sql -match '^SHOW PARAMETERS IN TASK (.+)$') {
        $key = ((Split-MockName $Matches[1]) -join '.')
        $rows = New-Object System.Collections.ArrayList
        if ($Mock.Params.ContainsKey($key)) { foreach ($p in $Mock.Params[$key]) { [void]$rows.Add(@($p.key, $p.value, $p.default, $p.level, 'description', 'type')) } }
        return (ConvertTo-Js ([ordered]@{ columns = @('key', 'value', 'default', 'level', 'description', 'type'); rows = $rows }))
    }
    if ($Sql -match '^SELECT (BASE64_DECODE_STRING\(\?\)(?:, )?)+$') {
        $values = New-Object System.Collections.ArrayList
        foreach ($b in $binds) {
            try { [void]$values.Add((ConvertFrom-B64 ([string]$b))) } catch { return (ConvertTo-Js @{ error = 'Invalid base64 in BASE64_DECODE_STRING' }) }
        }
        $names = @(1..$values.Count | ForEach-Object { 'BASE64_DECODE_STRING(?)' })
        $one = New-Object System.Collections.ArrayList; [void]$one.Add(@($values.ToArray()))
        return (ConvertTo-Js ([ordered]@{ columns = $names; rows = $one }))
    }
    if ($Sql -match 'INFORMATION_SCHEMA\.TASK_HISTORY') {
        if ($Mock.HistoryFails) { return (ConvertTo-Js @{ error = 'Insufficient privileges to operate on task history' }) }
        $columns = @('GRAPH_RUN_GROUP_ID', 'RUN_ID', 'QUERY_ID', 'NAME', 'STATE', 'ERROR_CODE', 'ERROR_MESSAGE', 'ATTEMPT_NUMBER', 'SCHEDULED_FROM', 'SCHEDULED', 'STARTED', 'COMPLETED')
        $rows = New-Object System.Collections.ArrayList
        foreach ($h in $Mock.History) { [void]$rows.Add(@($columns | ForEach-Object { $h[$_] })) }
        return (ConvertTo-Js ([ordered]@{ columns = $columns; rows = $rows }))
    }
    if ($Sql -match '^(ALTER TASK|CREATE OR REPLACE TASK|CREATE TASK|DROP TASK|EXECUTE TASK) ') {
        [void]$Mock.Recorded.Add($Sql)
        if ($Mock.FailOn -and $Sql -match $Mock.FailOn) { return (ConvertTo-Js @{ error = 'SQL compilation error: mock failure' }) }
        $one = New-Object System.Collections.ArrayList; [void]$one.Add(@('Statement executed successfully.'))
        return (ConvertTo-Js ([ordered]@{ columns = @('status'); rows = $one }))
    }
    ConvertTo-Js @{ error = ('mock: a statement that the engine should not issue: ' + $Sql.Substring(0, [Math]::Min(80, $Sql.Length))) }
}

$global:WfHost = New-Object WfJintHost
$global:WfHost.Handler = [Func[string, string, string]] {
    param($sql, $binds)
    try { Invoke-MockSql $global:WfMock $sql $binds } catch { ConvertTo-Js @{ error = ('mock failed: ' + $_.Exception.Message) } }
}

# The answer: one base64 string, decoded into its lines.
function Read-Answer {
    param([string] $B64)
    if ($B64 -notmatch '^[A-Za-z0-9+/]+={0,2}$') { throw 'the answer is not one base64 string' }
    if ($B64.Length -lt 24) { throw ('the answer has fewer than 24 characters: ' + $B64) }
    $text = ConvertFrom-B64 $B64
    $lines = @($text -split "`n")
    if ($lines[$lines.Count - 1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
    $a = [pscustomobject]@{ Status = $null; Exit = $null; Steps = $null; Texts = @(); JsonText = $null; Json = $null; Files = [ordered]@{}; Keywords = @(); Raw = $text }
    $texts = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $space = $line.IndexOf(' ')
        if ($space -lt 1) { throw ('a line of the answer without keyword and rest: ' + $line) }
        $kw = $line.Substring(0, $space); $rest = $line.Substring($space + 1)
        $a.Keywords += $kw
        switch ($kw) {
            'STATUS' { $a.Status = $rest }
            'EXIT' { $a.Exit = [int]$rest }
            'STEPS' { $a.Steps = [int]$rest }
            'TEXT' { $texts.Add((ConvertFrom-B64 $rest)) }
            'JSON' { $a.JsonText = ConvertFrom-B64 $rest; $a.Json = $a.JsonText | ConvertFrom-Json }
            'FILE' { $sp = $rest.IndexOf(' '); $a.Files[$rest.Substring(0, $sp)] = (ConvertFrom-B64 $rest.Substring($sp + 1)) }
            default { throw ('an unknown keyword in the answer: ' + $kw) }
        }
    }
    $a.Texts = $texts.ToArray()
    $a
}

# Runs the engine as Snowflake would: OP and ARGS are the arguments of the function that holds the engine's text.
function Invoke-Engine {
    param([string] $Op, $Request = @{}, $Mock = $null)
    if (-not $Mock) { $Mock = New-Mock }
    $global:WfMock = $Mock
    $engine = New-Object Jint.Engine
    [void]$engine.SetValue('host', $global:WfHost)
    [void]$engine.Execute($global:WfPrelude)
    [void]$engine.Execute("var __engine = function (OP, ARGS) {`n" + $global:WfEngineText + "`n};")
    [void]$engine.SetValue('__op', $Op)
    [void]$engine.SetValue('__args', (ConvertTo-Js $Request))
    $value = $engine.Execute('__engine(__op, __args)').GetCompletionValue()
    Read-Answer $value.ToString()
}

# A row of SHOW TASKS as a procedure sees it: lower case column names, the predecessors as an array, the relations as an object
# (or as text), times as Dates, and the newer columns that the engine has to ignore.
function New-Row {
    param([string] $Name, [string] $Definition = 'SELECT 1', [string[]] $After = @(), [string] $Finalizes, [string] $Schedule,
          [string] $Warehouse = 'WH', [string] $State = 'suspended', [string] $Condition, [string] $Id = '1', [string] $Db = 'DB',
          [string] $Sc = 'SC', [switch] $RelationsAsText, [switch] $PredecessorsAsText, [switch] $Quote, [string] $Comment = '',
          [string] $Overlap = 'null')
    $full = { param($n) if ($Quote -and $n -match '[^A-Z0-9_]') { $Db + '.' + $Sc + '."' + $n.Replace('"', '""') + '"' } else { "$Db.$Sc.$n" } }
    $names = @($After | ForEach-Object { & $full $_ })
    $rel = [ordered]@{ Predecessors = $names }
    if ($Finalizes) { $rel.FinalizedRootTask = (& $full $Finalizes) }
    $relations = $rel; if ($RelationsAsText) { $relations = (ConvertTo-Js $rel) }
    $pred = $names; if ($PredecessorsAsText) { $pred = (ConvertTo-Js $names) }
    [ordered]@{
        created_on = @{ __date = '2026-11-01T10:00:00.000Z' }; name = $Name; id = $Id; database_name = $Db; schema_name = $Sc; owner = 'SYSADMIN'
        comment = $Comment; warehouse = $Warehouse; schedule = $Schedule; predecessors = $pred; state = $State; definition = $Definition
        condition = $Condition; allow_overlapping_execution = $Overlap; error_integration = 'null'; last_committed_on = $null
        last_suspended_on = $null; owner_role_type = 'ROLE'; config = $null; budget = $null; task_relations = $relations
        last_suspended_reason = ''; scheduling_mode = 'Normal'; success_integration = 'null'; execute_as_user = 'null'
        overlap_policy = 'null'; target_completion_interval = $null
    }
}

# The fixture of most tests: LOAD_ROOT with children A, B, C (after A and B) and a finalizer, a lone task, and a task elsewhere.
function New-LoadMock {
    $m = New-Mock
    foreach ($r in @(
        (New-Row 'LOAD_ROOT' -Schedule '60 MINUTE' -State 'started' -Id '10')
        (New-Row 'LOAD_A' -After 'LOAD_ROOT' -State 'started' -Id '11')
        (New-Row 'LOAD_B' -After 'LOAD_ROOT' -State 'started' -Id '12')
        (New-Row 'LOAD_C' -After 'LOAD_A', 'LOAD_B' -State 'started' -Id '13')
        (New-Row 'LOAD_FINAL' -Finalizes 'LOAD_ROOT' -State 'started' -Id '14')
        (New-Row 'LONE' -Definition 'CALL p()' -Warehouse '' -Schedule 'USING CRON 0 * * * * UTC' -Id '20')
        (New-Row 'Other Schema Task' -Db 'DB' -Sc 'OTHER' -Id '30')
    )) { [void]$m.Rows.Add($r) }
    # the parameters of a task: those at the task level are what is set on it, the others are defaults and are not read
    $noise = @(
        @{ key = 'SUSPEND_TASK_AFTER_NUM_FAILURES'; value = '0'; default = '0'; level = '' }
        @{ key = 'USER_TASK_TIMEOUT_MS'; value = '3600000'; default = '3600000'; level = '' }
    )
    foreach ($t in 'LOAD_ROOT', 'LOAD_A', 'LOAD_B', 'LOAD_C', 'LOAD_FINAL', 'LONE') { $m.Params['DB.SC.' + $t] = @($noise) }
    $m.Params['DB.OTHER.Other Schema Task'] = @($noise)
    $m.Params['DB.SC.LOAD_ROOT'] = @(@{ key = 'USER_TASK_TIMEOUT_MS'; value = '3600000'; default = '3600000'; level = 'TASK' }) + $noise
    $m
}

# The graph that a mock holds as a graph document (the engine's own export), to be changed and planned again.
function Get-InstalledDocument {
    param($Mock, [string] $Root)
    $a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC'; root = $Root } $Mock
    $text = $a.Files['DB.SC.' + $Root + '.json']
    @{ Text = $text; Doc = (ConvertFrom-Js $text) }
}

function Get-DocTask { param($Doc, [string] $Name) foreach ($t in $Doc['tasks']) { if ($t['name'] -ceq $Name) { return $t } } }
function ConvertTo-Request { param($Doc, $Extra = @{}) $r = @{ doc = (ConvertTo-B64 (ConvertTo-Js $Doc)) }; foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }; $r }
function New-DocTask {
    param([string] $Name, [string[]] $After = @(), [string] $Schedule, [string] $Finalize, [string] $Definition = 'SELECT 1')
    $t = [ordered]@{ name = $Name; definition = $Definition }
    if ($After.Count -gt 0) { $t.after = @($After) }
    if ($Schedule) { $t.schedule = $Schedule }
    if ($Finalize) { $t.finalize = $Finalize }
    $t
}
function New-Doc { param($Tasks, [string] $Db = 'DB', [string] $Sc = 'SC') [ordered]@{ format = 'workflower-graph'; version = 1; database = $Db; schema = $Sc; tasks = @($Tasks) } }
function Get-Codes { param($Tasks) $a = Invoke-Engine 'check' (ConvertTo-Request (New-Doc $Tasks)); @($a.Json.problems | ForEach-Object { $_.code }) }
function Get-Phases { param($Answer) @(@($Answer.Json.steps) | ForEach-Object { $_.phase }) }

if ($MyInvocation.InvocationName -eq '.') { return }

# ---------------------------------------------------------------------------------------------------------------------------
# The tests
# ---------------------------------------------------------------------------------------------------------------------------

Write-Host 'The text of the engine'
$engineText = $global:WfEngineText
Assert-True ($engineText -notmatch '[^\x00-\x7e\r\n\t]') 'it is ASCII only'
Assert-True (-not $engineText.Contains('$$')) 'it has no two dollar signs in a row'
$noStrings = $engineText -replace "'[^'\r\n]*'", "''" -replace '//[^\r\n]*', ''
Assert-True ($noStrings -notmatch '=>|\blet\s|\bconst\s|`|\bclass\s|\.startsWith|\.endsWith|\.includes|\.padEnd|\.repeat\(|\bnew Map|\bnew Set|Object\.assign') 'it has no ES6 syntax or methods'
Assert-True (@($engineText -split "`n").Count -le 1300) 'it is compact'
Assert-True ($engineText.TrimEnd().EndsWith('return main();')) 'it ends by returning the answer'

Write-Host 'The answer'
$a = Invoke-Engine 'check' (ConvertTo-Request (New-Doc @((New-DocTask 'R' -Schedule '1 MINUTE'), (New-DocTask 'A' -After 'R'))))
Assert-Equal $a.Status 'ok' 'a good graph answers STATUS ok'
Assert-Equal $a.Keywords[0] 'STATUS' 'STATUS is the first line'
Assert-Equal $a.Exit 0 'EXIT is 0'
Assert-Equal $a.Texts @('no problems') 'and says no problems'
Assert-True ($null -eq $a.Steps) 'a check has no STEPS line'
$a = Invoke-Engine 'nonsense' @{}
Assert-Equal $a.Status 'error' 'an unknown operation is STATUS error'
Assert-Equal $a.Exit 1 'with EXIT 1'
Assert-True ($a.Texts[0] -match "Unknown operation 'nonsense'") 'and says why'
$a = Invoke-Engine 'graphs' @{} (New-Mock)
Assert-Equal $a.Texts @('no graphs') 'no tasks, no graphs (an account scope is read when no database is given)'
$a = Invoke-Engine 'graphs' @{ schema = 'SC' } (New-Mock)
Assert-Equal $a.Status 'error' 'a schema without a database is an error'

Write-Host 'Reading graphs'
$m = New-LoadMock
$a = Invoke-Engine 'graphs' @{ database = 'DB' } $m
$graphs = @($a.Json.graphs)
Assert-Equal $graphs.Count 3 'two graphs in one schema and one in another are three graphs'
Assert-Equal @($graphs | ForEach-Object { $_.root }) @('Other Schema Task', 'LOAD_ROOT', 'LONE') 'the graphs are in order of schema and root'
$g = @($graphs | Where-Object { $_.root -ceq 'LOAD_ROOT' })[0]
Assert-Equal @($g.tasks | ForEach-Object { $_.name }) @('LOAD_ROOT', 'LOAD_A', 'LOAD_B', 'LOAD_C', 'LOAD_FINAL') 'a graph is in order, the finalizer last'
Assert-Equal @($g.tasks[3].after) @('LOAD_A', 'LOAD_B') 'predecessors are read from the relations, without the qualifier'
Assert-Equal $g.tasks[4].finalize 'LOAD_ROOT' 'a finalizer says what it finalizes'
Assert-Equal $g.tasks[0].info.id '10' 'the id is kept as information'
Assert-Equal $g.tasks[0].info.createdOn '2026-11-01T10:00:00.000Z' 'a time that arrives as a Date is ISO text'
Assert-Equal $g.state 'started' 'the state of a graph is the root''s'
Assert-Equal $g.incomplete $false 'and it is complete'
$lone = @($graphs | Where-Object { $_.root -ceq 'LONE' })[0]
Assert-Equal @($lone.tasks).Count 1 'a task that stands alone is a graph of one'
Assert-Equal $lone.tasks[0].warehouse $null 'no warehouse is null (serverless)'
Assert-Equal $lone.tasks[0].allowOverlappingExecution $null 'the text null is no value'
Assert-Equal $lone.tasks[0].errorIntegration $null 'the text null is no integration'
Assert-Equal $lone.state 'suspended' 'a suspended graph'
$odd = @($graphs | Where-Object { $_.schema -ceq 'OTHER' })[0]
Assert-Equal $odd.root 'Other Schema Task' 'a task name with spaces is kept as it is'
Assert-True (@($m.All | Where-Object { $_ -like 'SHOW PARAMETERS*' }).Count -eq 0) 'no parameters are read unless asked for'
Assert-Equal $m.All[0] 'SHOW TASKS IN DATABASE "DB"' 'SHOW TASKS IN DATABASE with a quoted name'
Assert-True ($a.Texts[0] -match 'LOAD_ROOT\s+started\s+5\s+DB\.SC') 'the table has root, state, tasks and schema'
$m = New-LoadMock
$a = Invoke-Engine 'graphs' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; parameters = $true } $m
Assert-Equal @($a.Json.graphs).Count 1 'a root selects one graph'
Assert-Equal $m.All[0] 'SHOW TASKS IN SCHEMA "DB"."SC"' 'SHOW TASKS IN SCHEMA'
Assert-Equal @($m.All | Where-Object { $_ -like 'SHOW PARAMETERS IN TASK "DB"."SC"."LOAD_*' }).Count 5 'with parameters, one SHOW PARAMETERS for each task of the graph'
Assert-Equal $a.Json.graphs[0].tasks[0].parameters.USER_TASK_TIMEOUT_MS '3600000' 'a parameter at the task level is read'
Assert-Equal @($a.Json.graphs[0].tasks[1].parameters.psobject.Properties).Count 0 'a default is not'

$m2 = New-Mock
foreach ($r in @(
    (New-Row 'S1' -After 'SX' -Id '1')
    (New-Row 'S2' -Id '2' -RelationsAsText)
    (New-Row 'S3' -After 's2' -Id '3' -RelationsAsText -PredecessorsAsText)
)) { [void]$m2.Rows.Add($r) }
$a = Invoke-Engine 'graphs' @{ database = 'DB' } $m2
$gs = @($a.Json.graphs)
Assert-Equal $gs.Count 2 'a predecessor that is not there does not join graphs'
$s1 = @($gs | Where-Object { $_.tasks[0].name -ceq 'S1' })[0]
Assert-Equal $s1.incomplete $true 'a graph with a hidden task is incomplete'
Assert-True ($a.Texts[0] -match '(?m)^! ') 'and marked in the table'
Assert-Equal @($s1.tasks[0].after) @('SX') 'the missing predecessor is kept by name'
$s3 = @($gs | Where-Object { $_.tasks[0].name -ceq 'S2' })[0]
Assert-Equal @($s3.tasks | ForEach-Object { $_.name }) @('S2', 'S3') 'relations as text are read, and a name that differs in case only is found'

Write-Host 'A graph made by hand'
$m3 = New-Mock
foreach ($r in @(
    (New-Row 'load root' -Schedule 'USING CRON 30 2 * * * Europe/Stockholm' -Definition 'BEGIN SELECT 1; END' -Quote -Comment 'made by hand' -Overlap 'false' -State 'suspended')
    (New-Row 'step 1' -After 'load root' -Definition "SELECT 'a;b'" -Quote)
    (New-Row 'step 2' -After 'load root' -Warehouse '' -Quote)
    (New-Row 'Step 3' -After 'step 1', 'step 2' -Definition 'CALL SYSTEM$WAIT(1)' -Quote)
    (New-Row 'fin' -Finalizes 'load root' -Quote)
)) { [void]$m3.Rows.Add($r) }
$m3.Params['DB.SC.load root'] = @(@{ key = 'USER_TASK_TIMEOUT_MS'; value = '90000'; default = '3600000'; level = 'TASK' })
$m3.Params['DB.SC.step 2'] = @(@{ key = 'USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE'; value = 'XSMALL'; default = ''; level = 'TASK' })
$a = Invoke-Engine 'graphs' @{ database = 'DB'; schema = 'SC'; parameters = $true } $m3
Assert-Equal @($a.Json.graphs).Count 1 'five hand-made tasks are one graph'
$g = $a.Json.graphs[0]
Assert-Equal $g.root 'load root' 'a root name with a space is read'
Assert-Equal @($g.tasks | ForEach-Object { $_.name }) @('load root', 'step 1', 'step 2', 'Step 3', 'fin') 'in order, the finalizer last'
Assert-Equal @($g.tasks[3].after) @('step 1', 'step 2') 'quoted names in the relations are read'
Assert-Equal $g.tasks[0].allowOverlappingExecution $false 'FALSE overlapping is read'
Assert-True ($m3.All -contains 'SHOW PARAMETERS IN TASK "DB"."SC"."load root"') 'the task is asked for by its exact name, quoted'
$exported = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC' } $m3
$doc = (ConvertFrom-Js $exported.Files['DB.SC.load_root.json'])
$plan = Invoke-Engine 'plan' (ConvertTo-Request $doc) $m3
Assert-Equal $plan.Steps 0 'it is its own plan: nothing to do'
Assert-Equal $plan.Exit 0 'and the exit is 0'
$a = Invoke-Engine 'check' (ConvertTo-Request $doc) $m3
Assert-Equal @($a.Json.problems | Where-Object { $_.severity -eq 'error' }).Count 0 'and it passes the checks'
$a = Invoke-Engine 'sql' (ConvertTo-Request $doc) $m3
Assert-True ($a.Texts[0].Contains("CREATE OR REPLACE TASK `"DB`".`"SC`".`"load root`"`n  WAREHOUSE = `"WH`"`n  SCHEDULE = 'USING CRON 30 2 * * * Europe/Stockholm'`n  ALLOW_OVERLAPPING_EXECUTION = FALSE`n  USER_TASK_TIMEOUT_MS = 90000`n  COMMENT = 'made by hand'")) 'the SQL of a hand-made graph is quoted'
Assert-True ($a.Texts[0].Contains("AS`nBEGIN SELECT 1; END;`n`n")) 'a BEGIN ... END body keeps its semicolon and gets no second one'

Write-Host 'Validation'
function T { param([string] $Name, [string[]] $After = @(), [string] $Schedule, [string] $Finalize, [string] $Definition = 'SELECT 1') New-DocTask $Name $After $Schedule $Finalize $Definition }
Assert-Equal @(Get-Codes @((T 'R' -Schedule '1 MINUTE'), (T 'A' -After 'R'))) @() 'a good graph has no problems'
Assert-True ((Get-Codes @((T 'R'), (T 'R'))) -contains 'duplicate-name') 'two tasks with one name'
Assert-True ((Get-Codes @((T 'R'), (T 'A' -After 'X'))) -contains 'missing-predecessor') 'a predecessor that is not there'
Assert-True ((Get-Codes @((T 'R'), (T 'S'))) -contains 'several-roots') 'two roots'
Assert-True ((Get-Codes @((T 'R'), (T 'A' -After 'R' -Schedule '1 MINUTE'))) -contains 'schedule-on-child') 'a schedule on a child'
Assert-True ((Get-Codes @((T 'R'), (T 'A' -After 'B'), (T 'B' -After 'A'))) -contains 'cycle') 'a cycle'
Assert-True ((Get-Codes @((T 'A' -After 'B'), (T 'B' -After 'A'))) -contains 'no-root') 'tasks with no root'
Assert-True ((Get-Codes @((T 'R' -Definition ' '))) -contains 'no-definition') 'a task with nothing to run'
Assert-True ((Get-Codes @((T 'R'), (T 'F' -Finalize 'X'))) -contains 'finalize-missing') 'a finalizer of a task that is not there'
Assert-True ((Get-Codes @((T 'R'), (T 'A' -After 'R'), (T 'F' -Finalize 'A'))) -contains 'finalize-not-root') 'a finalizer of a task that is not the root'
Assert-True ((Get-Codes @((T 'R'), (T 'F' -Finalize 'R'), (T 'G' -Finalize 'R'))) -contains 'several-finalizers') 'two finalizers'
Assert-True ((Get-Codes @((T 'R'), (T 'F' -Finalize 'R'), (T 'A' -After 'F'))) -contains 'after-finalizer') 'a task after a finalizer'
Assert-True ((Get-Codes @((T 'R'), (T 'F' -Finalize 'R' -After 'R'))) -contains 'finalizer-after') 'a finalizer with predecessors'
Assert-True ((Get-Codes @((T 'R' -After 'R'))) -contains 'self') 'a task after itself'
$many = @(T 'R') + @(1..101 | ForEach-Object { T ('C' + $_) -After 'R' })
Assert-True ((Get-Codes $many) -contains 'too-many-children') 'more than 100 children'
$wide = @(T 'R') + @(1..101 | ForEach-Object { T ('P' + $_) -After 'R' }) + @(T 'Z' -After (@(1..101 | ForEach-Object { 'P' + $_ })))
Assert-True ((Get-Codes $wide) -contains 'too-many-predecessors') 'more than 100 predecessors'
Assert-True ((Get-Codes @(1..1001 | ForEach-Object { T ('N' + $_) })) -contains 'too-many-tasks') 'more than 1,000 tasks'
Assert-True ((Get-Codes @()) -contains 'empty') 'no tasks'
$both = T 'R'; $both.warehouse = 'WH'; $both.parameters = @{ USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL' }
Assert-True ((Get-Codes @($both)) -contains 'two-computes') 'a warehouse and a serverless size'
Assert-True ((Get-Codes @((T 'R'))) -contains 'manual-root') 'a root that nothing starts is an info'
$started = T 'R'; $started.state = 'started'
Assert-True ((Get-Codes @($started)) -contains 'root-cannot-start') 'a started root with no schedule cannot be resumed'
$child = T 'A' -After 'R'; $child.state = 'suspended'; $rs = T 'R' -Schedule '1 MINUTE'; $rs.state = 'started'
Assert-True ((Get-Codes @($rs, $child)) -contains 'suspended-child') 'a suspended child of a started root'
$ov = T 'A' -After 'R'; $ov.allowOverlappingExecution = $true
Assert-True ((Get-Codes @((T 'R' -Schedule '1 MINUTE'), $ov)) -contains 'overlap-on-child') 'overlapping set on a child is a warning'
$a = Invoke-Engine 'check' (ConvertTo-Request (New-Doc @((T 'R'), (T 'S'))))
Assert-Equal $a.Status 'ok' 'a check that finds an error is still an answer'
Assert-Equal $a.Exit 1 'with EXIT 1'
Assert-True ($a.Texts[0] -match "(?m)^error   -  The graph has more than one task with no predecessors: R, S\. A graph has one root\.") 'and a line for the problem'
Assert-Equal $a.Json.problems[0].severity 'error' 'the JSON has the problems'
$a = Invoke-Engine 'check' (ConvertTo-Request (New-Doc @((T 'R' -Schedule '1 MINUTE'))))
Assert-Equal $a.Exit 0 'a graph with no error has EXIT 0'

Write-Host 'SQL'
$r = T 'R' -Schedule '5 MINUTE'; $r.warehouse = 'WH'; $r.state = 'started'; $r.parameters = [ordered]@{ USER_TASK_TIMEOUT_MS = '60000' }
$aa = T 'A' -After 'R' -Definition "CALL load('x')"; $aa.condition = 'SYSTEM$STREAM_HAS_DATA(''S'')'; $aa.comment = "it's"; $aa.state = 'started'
$ff = T 'F' -Finalize 'R'
$a = Invoke-Engine 'sql' (ConvertTo-Request (New-Doc @($r, $aa, $ff)))
$expected = "CREATE OR REPLACE TASK `"DB`".`"SC`".`"R`"`n  WAREHOUSE = `"WH`"`n  SCHEDULE = '5 MINUTE'`n  USER_TASK_TIMEOUT_MS = 60000`nAS`nSELECT 1;`n`n" +
    "CREATE OR REPLACE TASK `"DB`".`"SC`".`"A`"`n  COMMENT = 'it''s'`n  AFTER `"DB`".`"SC`".`"R`"`n  WHEN SYSTEM`$STREAM_HAS_DATA('S')`nAS`nCALL load('x');`n`n" +
    "CREATE OR REPLACE TASK `"DB`".`"SC`".`"F`"`n  FINALIZE = `"DB`".`"SC`".`"R`"`nAS`nSELECT 1;`n`n" +
    "ALTER TASK `"DB`".`"SC`".`"A`" RESUME;`n`nALTER TASK `"DB`".`"SC`".`"R`" RESUME;`n`n"
Assert-Equal $a.Texts[0] $expected 'the script: root, child with comment, after and when, finalizer, then the resumes with the child first'
$odd = T 'R' -Schedule '1 MINUTE'; $odd.comment = "it's a ""test"" \ done"; $odd.config = '{"env":"test"}'; $odd.errorIntegration = 'MY_INT'; $odd.allowOverlappingExecution = $true
$a = Invoke-Engine 'sql' (ConvertTo-Request (New-Doc @($odd)))
Assert-True ($a.Texts[0].Contains("  SCHEDULE = '1 MINUTE'`n  CONFIG = '{`"env`":`"test`"}'`n  ALLOW_OVERLAPPING_EXECUTION = TRUE`n  ERROR_INTEGRATION = `"MY_INT`"`n  COMMENT = 'it''s a `"test`" \\ done'`nAS")) 'a literal doubles the quote and the backslash; the properties are in the order of CREATE TASK'
$typed = T 'R' -Schedule '1 MINUTE'; $typed.parameters = [ordered]@{ ZZ_NUMBER = '3600000'; AA_BOOL = 'true'; MM_TEXT = 'XSMALL'; BB_FLAG = $true }
$a = Invoke-Engine 'sql' (ConvertTo-Request (New-Doc @($typed)))
Assert-True ($a.Texts[0].Contains("  AA_BOOL = TRUE`n  BB_FLAG = TRUE`n  MM_TEXT = 'XSMALL'`n  ZZ_NUMBER = 3600000`n")) 'parameters are in order, numbers and booleans are not quoted, text is'
$body = T 'R' -Schedule '1 MINUTE' -Definition "BEGIN`n  CALL p('caf$([char]0xE9)');`nEND;  `n"
$a = Invoke-Engine 'sql' (ConvertTo-Request (New-Doc @($body)))
Assert-True ($a.Texts[0].Contains("AS`nBEGIN`n  CALL p('caf$([char]0xE9)');`nEND;`n`n")) 'a body is sent as it is (a non-ASCII letter too), its trailing space cut'

Write-Host 'Files'
$m = New-LoadMock
$a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT' } $m
Assert-Equal @($a.Files.Keys) @('DB.SC.LOAD_ROOT.json') 'export makes one file for a graph, named by database, schema and root'
Assert-Equal $a.Keywords[($a.Keywords.Count - 1)] 'TEXT' 'with a TEXT that says what was made'
$text = $a.Files['DB.SC.LOAD_ROOT.json']
Assert-True ($text.StartsWith("{`n  `"format`": `"workflower-graph`",`n  `"version`": 1,`n  `"database`": `"DB`",`n  `"schema`": `"SC`",`n  `"tasks`": [`n")) 'the file is laid out as the PowerShell module lays it out'
Assert-True ($text.Contains("`"after`": [`"LOAD_A`", `"LOAD_B`"]")) 'a short array is on one line'
Assert-True ($text.Contains("`"parameters`": {`n        `"USER_TASK_TIMEOUT_MS`": `"3600000`"`n      }")) 'parameters are an object'
Assert-True ($text.EndsWith("}`n")) 'the file ends with a line break'
$doc = (ConvertFrom-Js $text)
Assert-Equal @($doc['tasks'] | ForEach-Object { $_['name'] }) @('LOAD_ROOT', 'LOAD_A', 'LOAD_B', 'LOAD_C', 'LOAD_FINAL') 'the tasks are in order'
Assert-Equal (Get-DocTask $doc 'LOAD_ROOT')['state'] 'started' 'the state is written'
Assert-True ((Get-DocTask $doc 'LOAD_A').ContainsKey('warehouse')) 'a warehouse is written'
Assert-True (-not (Get-DocTask $doc 'LOAD_ROOT').ContainsKey('info')) 'read-only fields are not'
$a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; noState = $true } $m
Assert-True (-not $a.Files['DB.SC.LOAD_ROOT.json'].Contains('"state"')) 'noState leaves the state out'
# a body with a multi-line text and a non-ASCII letter
$m.Rows[1]['definition'] = "BEGIN`n  CALL p('caf$([char]0xE9)');`nEND;"
$a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT' } $m
$text = $a.Files['DB.SC.LOAD_ROOT.json']
Assert-True ($text -notmatch '[^\x00-\x7e\r\n]') 'the file is ASCII (a non-ASCII letter is an escape)'
Assert-Equal (Get-DocTask (ConvertFrom-Js $text) 'LOAD_A')['definition'] $m.Rows[1]['definition'] 'a multi-line body with a non-ASCII letter comes back as it was'
$again = Invoke-Engine 'plan' @{ doc = (ConvertTo-B64 $text) } $m
Assert-Equal $again.Steps 0 'an exported file is its own plan: nothing to change'
$a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; split = $true } $m
Assert-Equal @($a.Files.Keys) @('DB.SC.LOAD_ROOT.d/LOAD_ROOT.sql', 'DB.SC.LOAD_ROOT.d/LOAD_A.sql', 'DB.SC.LOAD_ROOT.d/LOAD_B.sql', 'DB.SC.LOAD_ROOT.d/LOAD_C.sql', 'DB.SC.LOAD_ROOT.d/LOAD_FINAL.sql', 'DB.SC.LOAD_ROOT.json') 'split: a .sql file for each task in a folder, then the JSON'
Assert-Equal @($a.Files.Keys | Where-Object { $_ -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.\-]*(/[A-Za-z0-9_][A-Za-z0-9_.\-]*)?$' }).Count 0 'every path is letters, digits, _ . - and at most one slash'
Assert-Equal $a.Files['DB.SC.LOAD_ROOT.d/LOAD_A.sql'] ($m.Rows[1]['definition'] + "`n") 'a .sql file holds the body and a line break'
$splitDoc = (ConvertFrom-Js $a.Files['DB.SC.LOAD_ROOT.json'])
Assert-Equal (Get-DocTask $splitDoc 'LOAD_A')['definitionFile'] 'DB.SC.LOAD_ROOT.d/LOAD_A.sql' 'the JSON points to it'
Assert-True (-not (Get-DocTask $splitDoc 'LOAD_A').ContainsKey('definition')) 'and has no definition'
$files = @{}; foreach ($k in $a.Files.Keys) { if ($k -like '*.sql') { $files[$k] = ConvertTo-B64 $a.Files[$k] } }
$again = Invoke-Engine 'plan' @{ doc = (ConvertTo-B64 $a.Files['DB.SC.LOAD_ROOT.json']); files = $files } $m
Assert-Equal $again.Steps 0 'definitions in their own files come back too (definitionFile through files)'
$missing = Invoke-Engine 'plan' @{ doc = (ConvertTo-B64 $a.Files['DB.SC.LOAD_ROOT.json']); files = @{} } $m
Assert-Equal $missing.Status 'error' 'a definitionFile that is not sent is an error'
Assert-True ($missing.Texts[0] -match "Task 'LOAD_ROOT': the definition file DB\.SC\.LOAD_ROOT\.d/LOAD_ROOT\.sql is not there") 'that names the task and the file'
$m4 = New-Mock
[void]$m4.Rows.Add((New-Row 'Odd Name/1' -Schedule '1 MINUTE')); [void]$m4.Rows.Add((New-Row 'Odd_Name_1' -Schedule '1 MINUTE' -Id '2')); [void]$m4.Rows.Add((New-Row '.hidden' -After 'Odd Name/1'))
$a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC'; split = $true } $m4
Assert-Equal @($a.Files.Keys | Where-Object { $_ -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.\-]*(/[A-Za-z0-9_][A-Za-z0-9_.\-]*)?$' }).Count 0 'odd task names make safe paths'
$d1 = @($a.Files.Keys | Where-Object { $_ -like '*.d/*.sql' })
Assert-Equal @($d1 | Select-Object -Unique).Count $d1.Count 'and no two tasks write one file'
$over = Invoke-Engine 'plan' @{ doc = (ConvertTo-B64 $text); database = 'PROD'; schema = 'LIVE'; warehouse = 'BIG' } (New-Mock)
Assert-True ($over.Texts[0].Contains('CREATE TASK "PROD"."LIVE"."LOAD_ROOT"')) '-Database and -Schema replace those of the file'
Assert-True ($over.Texts[0].Contains('WAREHOUSE = "BIG"') -and -not $over.Texts[0].Contains('WAREHOUSE = "WH"')) '-Warehouse replaces the warehouse of a task that has one'
Assert-Equal $over.Json.database 'PROD' 'the plan names the database'
$serverless = (ConvertFrom-Js $text); [void](Get-DocTask $serverless 'LOAD_B').Remove('warehouse')
$over = Invoke-Engine 'sql' @{ doc = (ConvertTo-B64 (ConvertTo-Js $serverless)); warehouse = 'BIG' }
Assert-True ($over.Texts[0] -notmatch '(?s)"LOAD_B"\n  WAREHOUSE') 'and none is given to a task that has none'
$bad = Invoke-Engine 'check' @{ doc = (ConvertTo-B64 '{"tasks":[{"name":"X","definiton":"oops"}]}') }
Assert-Equal $bad.Status 'error' 'a misspelt field is refused'
Assert-True ($bad.Texts[0] -match "unknown field 'definiton'") 'and named'
Assert-True ($bad.Texts[0] -match "Task 'X'") 'with the task'
foreach ($c in @(
    @{ Text = '{"format":"other","tasks":[]}'; Pattern = "unknown format 'other'" }
    @{ Text = '{"name":"x"}'; Pattern = 'no "tasks"' }
    @{ Text = '{"tasks":[{"definition":"SELECT 1"}]}'; Pattern = 'A task has no name' }
    @{ Text = '{"tasks":[{"name":"X","state":"running"}]}'; Pattern = 'state must be started or suspended' }
)) {
    $a = Invoke-Engine 'check' @{ doc = (ConvertTo-B64 $c.Text) }
    Assert-True ($a.Status -eq 'error' -and $a.Texts[0] -match $c.Pattern) ('refused: ' + $c.Pattern)
}
# Jint raises a .NET parser exception from JSON.parse where V8 raises a SyntaxError that the engine catches; Test-EngineLive.ps1
# runs this case in Snowflake.
Assert-Throws { Invoke-Engine 'check' @{ doc = (ConvertTo-B64 '{"tasks":[{"name":"X"') } } 'Unexpected end of input' 'a document that is not JSON is refused (under Jint, as an exception)'
$a = Invoke-Engine 'check' @{ doc = 'not base64!' }
Assert-Equal $a.Status 'error' 'a document that is not base64 is an error'
$a = Invoke-Engine 'check' @{}
Assert-Equal $a.Status 'error' 'a request with no document is an error'
$bom = Invoke-Engine 'check' @{ doc = ([Convert]::ToBase64String(@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes('{"tasks":[{"name":"R","definition":"SELECT 1","schedule":"1 MINUTE"}]}'))) }
Assert-Equal $bom.Status 'ok' 'a byte order mark is ignored'
$a = Invoke-Engine 'check' @{ doc = (ConvertTo-B64 '{"database":"D","schema":"S","tasks":[{"name":"R","definition":"SELECT 1","schedule":"1 MINUTE","after":"X","parameters":{"user_task_timeout_ms":3600000,"flag":true},"allowOverlappingExecution":"yes"}]}') }
Assert-Equal $a.Status 'ok' 'a loose file is read: a single predecessor as text, a number, a boolean, a lower case parameter name'
Assert-True (@($a.Json.problems | ForEach-Object { $_.code }) -contains 'missing-predecessor') 'and checked'
$a = Invoke-Engine 'sql' @{ doc = (ConvertTo-B64 '{"database":"D","schema":"S","tasks":[{"name":"R","definition":"SELECT 1","parameters":{"user_task_timeout_ms":3600000,"flag":true}}]}') }
Assert-True ($a.Texts[0].Contains("  FLAG = TRUE`n  USER_TASK_TIMEOUT_MS = 3600000`n")) 'parameter names are upper case and in order, a boolean is TRUE'

Write-Host 'The plan'
$m = New-LoadMock
$base = Get-InstalledDocument $m 'LOAD_ROOT'
function Copy-Doc { param($Doc) (ConvertFrom-Js (ConvertTo-Js $Doc)) }
function Get-Plan { param($Doc, $Mock = $m) Invoke-Engine 'plan' (ConvertTo-Request $Doc) $Mock }
$p = Get-Plan (Copy-Doc $base.Doc)
Assert-Equal $p.Steps 0 'a graph that is as installed needs nothing'
Assert-Equal $p.Status 'ok' 'and the answer is ok'
Assert-True ($p.Texts[0] -match 'nothing to change') 'and says so'
Assert-True ($p.Json.isEmpty) 'the JSON says it is empty'
$d = Copy-Doc $base.Doc; $d['database'] = 'DB'
$p = Get-Plan $d (New-Mock)
Assert-Equal (Get-Phases $p) @('create', 'create', 'create', 'create', 'create', 'resume', 'resume', 'resume', 'resume', 'resume') 'a graph that is not installed is made, and started when its tasks say started'
Assert-Equal $p.Json.steps[9].task 'LOAD_ROOT' 'the root is resumed last'
Assert-Equal $p.Json.exists $false 'and the plan says it is new'
Assert-Equal $p.Steps 10 'STEPS is the number of steps'
foreach ($t in $d['tasks']) { [void]$t.Remove('state') }
$p = Get-Plan $d (New-Mock)
Assert-Equal (Get-Phases $p) @('create', 'create', 'create', 'create', 'create') 'a graph with no state is made suspended'
Assert-True ($p.Json.steps[4].sql -match 'FINALIZE = "DB"."SC"."LOAD_ROOT"') 'with the finalizer made last'
Assert-True ($p.Texts[0].StartsWith("Graph DB.SC.LOAD_ROOT: 5 steps`n  1. create   LOAD_ROOT   Task 'LOAD_ROOT' is new.`n       CREATE TASK `"DB`".`"SC`".`"LOAD_ROOT`"`n")) 'the text of a plan reads like the protocol says'

$d = Copy-Doc $base.Doc; (Get-DocTask $d 'LOAD_A')['definition'] = 'SELECT 2'
$p = Get-Plan $d
Assert-Equal (Get-Phases $p) @('suspend', 'alter', 'resume') 'a changed body: suspend the root, alter, resume'
Assert-Equal $p.Json.steps[1].sql "ALTER TASK `"DB`".`"SC`".`"LOAD_A`" MODIFY AS`nSELECT 2" 'the alter is MODIFY AS'
Assert-Equal $p.Json.steps[2].task 'LOAD_ROOT' 'only the root had to be resumed'
Assert-Equal @($p.Json.changed) @('LOAD_A') 'the plan names the changed task'
Assert-Equal $p.Json.steps[0].sql 'ALTER TASK "DB"."SC"."LOAD_ROOT" SUSPEND' 'the root is suspended first'
Assert-Equal $p.Json.steps[1].reason "Task 'LOAD_A': the definition is changed." 'the reason'
Assert-True ($p.Texts[0].Contains("  2. alter    LOAD_A   Task 'LOAD_A': the definition is changed.`n       ALTER TASK `"DB`".`"SC`".`"LOAD_A`" MODIFY AS`n       SELECT 2")) 'a body is indented as a whole'

$d = Copy-Doc $base.Doc; $d['tasks'] = @($d['tasks'] | Where-Object { $_['name'] -cne 'LOAD_C' })
$p = Get-Plan $d
Assert-Equal (Get-Phases $p) @('suspend', 'drop', 'resume') 'a task that goes is dropped'
Assert-Equal @($p.Json.removed) @('LOAD_C') 'and named'
Assert-Equal $p.Json.steps[1].sql 'DROP TASK "DB"."SC"."LOAD_C"' 'with DROP TASK'

$d = Copy-Doc $base.Doc; (Get-DocTask $d 'LOAD_C')['after'] = @('LOAD_A')
$p = Get-Plan $d
Assert-Equal (Get-Phases $p) @('suspend', 'unlink', 'resume') 'a dependency that goes is removed'
Assert-Equal $p.Json.steps[1].sql 'ALTER TASK "DB"."SC"."LOAD_C" REMOVE AFTER "DB"."SC"."LOAD_B"' 'with REMOVE AFTER'

$d = Copy-Doc $base.Doc; $d['tasks'] = @($d['tasks']) + @([ordered]@{ name = 'LOAD_D'; definition = 'SELECT 4'; after = @('LOAD_C'); warehouse = 'WH' })
$p = Get-Plan $d
Assert-Equal (Get-Phases $p) @('suspend', 'create', 'resume', 'resume') 'a new task is made, and started because the graph is started'
Assert-Equal $p.Json.steps[2].task 'LOAD_D' 'the new task is resumed before the root'
Assert-Equal @($p.Json.added) @('LOAD_D') 'and named'

$d = Copy-Doc $base.Doc; (Get-DocTask $d 'LOAD_A')['after'] = @('LOAD_ROOT', 'LOAD_B')
$p = Get-Plan $d
Assert-True (@(@($p.Json.steps) | Where-Object { $_.sql -match 'ADD AFTER "DB"."SC"."LOAD_B"' }).Count -eq 1) 'a new dependency is added with ADD AFTER'

$d = Copy-Doc $base.Doc; foreach ($t in $d['tasks']) { $t['state'] = 'suspended' }
$p = Get-Plan $d
Assert-Equal (Get-Phases $p) @('suspend', 'suspend', 'suspend', 'suspend', 'suspend') 'a graph that is to stop is suspended, the root first'
Assert-Equal $p.Json.steps[0].task 'LOAD_ROOT' 'the root first'
Assert-Equal $p.Json.steps[0].reason "Task 'LOAD_ROOT' is to be suspended." 'for that reason'

$d = Copy-Doc $base.Doc; $rt = Get-DocTask $d 'LOAD_ROOT'; [void]$rt.Remove('schedule'); $rt['state'] = 'suspended'; $rt['comment'] = 'hi'; $rt['parameters']['USER_TASK_TIMEOUT_MS'] = '1000'
$p = Get-Plan $d
Assert-True (@(@($p.Json.steps) | Where-Object { $_.sql -eq 'ALTER TASK "DB"."SC"."LOAD_ROOT" UNSET SCHEDULE' }).Count -eq 1) 'a schedule that goes is unset'
Assert-True (@(@($p.Json.steps) | Where-Object { $_.sql -match "SET COMMENT = 'hi', USER_TASK_TIMEOUT_MS = 1000$" }).Count -eq 1) 'a comment and a parameter are set together'
Assert-Equal $p.Json.steps[1].reason "Task 'LOAD_ROOT': schedule, comment, parameter USER_TASK_TIMEOUT_MS is unset." 'the reasons list every property that is changed, as the PowerShell module does'

$d = Copy-Doc $base.Doc; (Get-DocTask $d 'LOAD_A')['definition'] = (([string](Get-DocTask $base.Doc 'LOAD_A')['definition']) -replace "`n", "`r`n") + "`r`n"
$p = Get-Plan $d
Assert-Equal $p.Steps 0 'a different line ending or a trailing break is no change'

$d = Copy-Doc $base.Doc; (Get-DocTask $d 'LOAD_B')['warehouse'] = 'OTHER_WH'; (Get-DocTask $d 'LOAD_B')['condition'] = "SYSTEM`$STREAM_HAS_DATA('S')"
$p = Get-Plan $d
Assert-Equal @(@($p.Json.steps) | ForEach-Object { $_.sql }) @('ALTER TASK "DB"."SC"."LOAD_ROOT" SUSPEND', 'ALTER TASK "DB"."SC"."LOAD_B" SET WAREHOUSE = "OTHER_WH"', "ALTER TASK `"DB`".`"SC`".`"LOAD_B`" MODIFY WHEN SYSTEM`$STREAM_HAS_DATA('S')", 'ALTER TASK "DB"."SC"."LOAD_ROOT" RESUME') 'a warehouse and a condition are changed'

$d = Copy-Doc $base.Doc; $d['tasks'] = @($d['tasks'] | Where-Object { $_['name'] -cne 'LOAD_FINAL' })
$p = Get-Plan $d
Assert-Equal (Get-Phases $p) @('suspend', 'drop', 'resume') 'a finalizer that goes is dropped'
$m5 = New-LoadMock; $m5.Rows.RemoveAt(4)
$p = Get-Plan (Copy-Doc $base.Doc) $m5
Assert-Equal (Get-Phases $p) @('suspend', 'create', 'resume', 'resume') 'a finalizer that is added is made, and started'
Assert-True ($p.Json.steps[1].sql -match 'FINALIZE = "DB"."SC"."LOAD_ROOT"') 'with FINALIZE'

Write-Host 'Apply'
$m = New-LoadMock
$d = Copy-Doc $base.Doc; (Get-DocTask $d 'LOAD_A')['definition'] = 'SELECT 2'
$a = Invoke-Engine 'apply' (ConvertTo-Request $d) $m
Assert-Equal $a.Status 'ok' 'apply is ok'
Assert-Equal $a.Steps 3 'with STEPS 3'
Assert-Equal @($m.Recorded) @('ALTER TASK "DB"."SC"."LOAD_ROOT" SUSPEND', "ALTER TASK `"DB`".`"SC`".`"LOAD_A`" MODIFY AS`nSELECT 2", 'ALTER TASK "DB"."SC"."LOAD_ROOT" RESUME') 'the statements run are the plan, in order, verbatim'
Assert-True ($a.Texts[0].StartsWith('Graph DB.SC.LOAD_ROOT: 3 steps')) 'the text prints the plan'
Assert-Equal $a.Texts[$a.Texts.Count - 1] 'done: 3 steps' 'and then done'
$m = New-LoadMock
$a = Invoke-Engine 'apply' (ConvertTo-Request (Copy-Doc $base.Doc)) $m
Assert-Equal $a.Steps 0 'nothing to change: STEPS 0'
Assert-Equal $m.Recorded.Count 0 'and nothing is run'
$m = New-LoadMock; $m.FailOn = '^ALTER TASK "DB"."SC"."LOAD_A" MODIFY AS'
$a = Invoke-Engine 'apply' (ConvertTo-Request $d) $m
Assert-Equal $a.Status 'error' 'a step that fails is STATUS error'
Assert-Equal $a.Exit 1 'with EXIT 1'
Assert-Equal $a.Steps 3 'STEPS still says how many the plan had'
Assert-Equal $m.Recorded.Count 2 'the rest of the steps are not run'
Assert-True ($a.Texts[$a.Texts.Count - 1] -match 'Step 2 of 3 failed \(ALTER TASK "DB"."SC"."LOAD_A" MODIFY AS\): SQL compilation error: mock failure\. Steps 1 to 1 were done:\n  ALTER TASK "DB"."SC"."LOAD_ROOT" SUSPEND\nThe graph is left as it is') 'the message says which step failed and which were done'
$bad = Copy-Doc $base.Doc; (Get-DocTask $bad 'LOAD_C')['after'] = @('NOWHERE')
$m = New-LoadMock
$a = Invoke-Engine 'apply' (ConvertTo-Request $bad) $m
Assert-Equal $a.Status 'error' 'a graph with errors is not applied'
Assert-True ($a.Texts[0] -match "(?s)The graph is not valid:\n  Task 'LOAD_C' is after 'NOWHERE', which is not in the graph\.") 'and the errors are listed'
Assert-Equal $m.Recorded.Count 0 'nothing is run'
Assert-True ($null -eq $a.Steps) 'and there is no plan'
$a = Invoke-Engine 'plan' (ConvertTo-Request $bad) $m
Assert-Equal $a.Status 'error' 'a plan of a graph with errors is not made'
$noDb = New-Doc @((T 'R' -Schedule '1 MINUTE')) -Db '' -Sc ''
$a = Invoke-Engine 'plan' (ConvertTo-Request $noDb) (New-Mock)
Assert-True ($a.Status -eq 'error' -and $a.Texts[0] -match 'no database and schema') 'a graph that says no database and schema is refused'
$a = Invoke-Engine 'apply' (ConvertTo-Request $d) (New-LoadMock)
Assert-Equal @($a.Json.steps).Count 3 'the JSON of apply is the plan'
$m = New-LoadMock; foreach ($r in $m.Rows) { $r['state'] = 'suspended' }
$d2 = Copy-Doc $base.Doc; foreach ($t in $d2['tasks']) { $t['state'] = 'started' }
$a = Invoke-Engine 'apply' (ConvertTo-Request $d2) $m
Assert-Equal @($m.Recorded) @('ALTER TASK "DB"."SC"."LOAD_FINAL" RESUME', 'ALTER TASK "DB"."SC"."LOAD_C" RESUME', 'ALTER TASK "DB"."SC"."LOAD_B" RESUME', 'ALTER TASK "DB"."SC"."LOAD_A" RESUME', 'ALTER TASK "DB"."SC"."LOAD_ROOT" RESUME') 'a suspended graph that is wanted started is resumed, the root last'

Write-Host 'Operate'
foreach ($c in @(
    @{ Action = 'resume'; State = 'suspended'; Expect = @('ALTER TASK "DB"."SC"."LOAD_FINAL" RESUME', 'ALTER TASK "DB"."SC"."LOAD_C" RESUME', 'ALTER TASK "DB"."SC"."LOAD_B" RESUME', 'ALTER TASK "DB"."SC"."LOAD_A" RESUME', 'ALTER TASK "DB"."SC"."LOAD_ROOT" RESUME') }
    @{ Action = 'suspend'; State = 'started'; Expect = @('ALTER TASK "DB"."SC"."LOAD_ROOT" SUSPEND', 'ALTER TASK "DB"."SC"."LOAD_A" SUSPEND', 'ALTER TASK "DB"."SC"."LOAD_B" SUSPEND', 'ALTER TASK "DB"."SC"."LOAD_C" SUSPEND', 'ALTER TASK "DB"."SC"."LOAD_FINAL" SUSPEND') }
    @{ Action = 'run'; State = 'suspended'; Expect = @('EXECUTE TASK "DB"."SC"."LOAD_ROOT"') }
    @{ Action = 'retry'; State = 'suspended'; Expect = @('EXECUTE TASK "DB"."SC"."LOAD_ROOT" RETRY LAST') }
)) {
    $m = New-LoadMock
    foreach ($r in $m.Rows) { $r['state'] = $c.State }
    $a = Invoke-Engine 'operate' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; action = $c.Action } $m
    Assert-Equal $a.Status 'ok' ($c.Action + ' is ok')
    Assert-Equal @($m.Recorded) $c.Expect ($c.Action + ': the statements, in the order that is right')
    Assert-True (@($m.All | Where-Object { $_ -like 'SHOW PARAMETERS*' }).Count -eq 0) ($c.Action + ' reads no parameters')
}
$m = New-LoadMock
$a = Invoke-Engine 'operate' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; action = 'resume' } $m
Assert-Equal $m.Recorded.Count 0 'resume of a started graph does nothing'
Assert-True ($a.Texts[0] -match 'nothing to resume') 'and says so'
$a = Invoke-Engine 'operate' @{ database = 'DB'; schema = 'SC'; root = 'NO_SUCH'; action = 'resume' } $m
Assert-True ($a.Status -eq 'error' -and $a.Texts[0] -match "There is no graph with the root 'NO_SUCH' in DB\.SC") 'a graph that is not there is an error'
$a = Invoke-Engine 'operate' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; action = 'explode' } $m
Assert-Equal $a.Status 'error' 'an unknown action is an error'
$a = Invoke-Engine 'operate' @{ database = 'DB'; schema = 'SC'; action = 'resume' } $m
Assert-Equal $a.Status 'error' 'a request that does not say which graph is an error'
$m = New-LoadMock; $m.FailOn = 'EXECUTE TASK'
$a = Invoke-Engine 'operate' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; action = 'run' } $m
Assert-True ($a.Status -eq 'error' -and $a.Texts[0] -match 'mock failure') 'a statement that fails is an error with its message'

Write-Host 'Runs'
$m = New-LoadMock
function New-HistoryRow { param($Group, $Name, $State, $Scheduled, $Started, $Completed, $Error, $Code, $Query = 'q1')
    @{ GRAPH_RUN_GROUP_ID = $Group; RUN_ID = '1'; QUERY_ID = $Query; NAME = $Name; STATE = $State; ERROR_CODE = $Code; ERROR_MESSAGE = $Error; ATTEMPT_NUMBER = '1'
       SCHEDULED_FROM = 'SCHEDULE'; SCHEDULED = $Scheduled; STARTED = $Started; COMPLETED = $Completed } }
foreach ($h in @(
    (New-HistoryRow 'g2' 'LOAD_ROOT' 'SUCCEEDED' '2026-11-02T10:00:00.000Z' '2026-11-02T10:00:01.000Z' '2026-11-02T10:00:02.500Z')
    (New-HistoryRow 'g2' 'LOAD_A' 'FAILED' '2026-11-02T10:00:02.500Z' '2026-11-02T10:00:03.000Z' '2026-11-02T10:00:04.000Z' 'SQL compilation error: Object does not exist' '2003')
    (New-HistoryRow 'g2' 'LOAD_B' 'SKIPPED' '2026-11-02T10:00:02.500Z' $null $null)
    (New-HistoryRow 'g1' 'LOAD_ROOT' 'SUCCEEDED' '2026-11-01T10:00:00.000Z' '2026-11-01T10:00:01.000Z' '2026-11-01T10:00:03.000Z')
    (New-HistoryRow 'g3' 'LOAD_ROOT' 'EXECUTING' '2026-11-03T10:00:00.000Z' '2026-11-03T10:00:01.000Z' $null)
    (New-HistoryRow 'g4' 'LOAD_ROOT' 'SCHEDULED' '2026-11-04T10:00:00.000Z' $null $null)
)) { [void]$m.History.Add($h) }
$a = Invoke-Engine 'runs' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; hours = 48; limit = 3 } $m
Assert-Equal $a.Status 'ok' 'runs is ok'
$histSql = @($m.All | Where-Object { $_ -match 'TASK_HISTORY' })[0]
Assert-True ($histSql.Contains('FROM TABLE("DB".INFORMATION_SCHEMA.TASK_HISTORY(SCHEDULED_TIME_RANGE_START => DATEADD(hour, -48, CURRENT_TIMESTAMP()), RESULT_LIMIT => 10000, ROOT_TASK_ID => ''10''))')) 'the history is asked for the root task id and the hours'
Assert-True ($histSql.Contains("TO_VARCHAR(CONVERT_TIMEZONE('UTC', QUERY_START_TIME), 'YYYY-MM-DD`"T`"HH24:MI:SS.FF3') || 'Z' AS STARTED")) 'times are made ISO text by Snowflake'
Assert-True ($histSql.EndsWith('ORDER BY SCHEDULED_TIME DESC')) 'newest first'
$runs = @($a.Json.runs)
Assert-Equal $runs.Count 3 'the limit is applied'
Assert-Equal @($runs | ForEach-Object { $_.runId }) @('g2', 'g1', 'g3') 'the runs are in the order of the history, tasks grouped by run group'
Assert-Equal @($runs | ForEach-Object { $_.state }) @('FAILED', 'SUCCEEDED', 'RUNNING') 'a failed task fails the run; an executing one is running'
Assert-Equal $runs[0].seconds 3.0 'seconds are from the first start to the last end'
Assert-Equal $runs[0].started '2026-11-02T10:00:01' 'the start is ISO without a zone'
Assert-Equal $runs[2].completed '' 'a run that is running has no completion'
Assert-Equal @($runs[0].tasks).Count 3 'the tasks of a run are there'
Assert-Equal $runs[0].tasks[1].error 'SQL compilation error: Object does not exist' 'with their errors'
Assert-True ($a.Texts[0] -match '(?m)^    LOAD_A failed: 2003 SQL compilation error: Object does not exist') 'a failed task is under its run in the text'
$a = Invoke-Engine 'runs' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT' } $m
Assert-Equal @($a.Json.runs).Count 4 'the default limit is 20'
Assert-Equal $a.Json.runs[3].state 'SCHEDULED' 'a run that is only scheduled is SCHEDULED'
Assert-True (@($m.All | Where-Object { $_ -match 'DATEADD\(hour, -24,' }).Count -eq 1) 'and the default is 24 hours'
$a = Invoke-Engine 'runs' @{ database = 'DB'; schema = 'SC'; root = 'LONE' } (New-LoadMock)
Assert-True ($a.Texts[0] -match 'no runs') 'no runs is said'
$a = Invoke-Engine 'runs' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; hours = 'x1' } $m
Assert-Equal $a.Status 'error' 'hours must be a number'
$a = Invoke-Engine 'runs' @{ database = 'DB'; schema = 'SC'; root = 'LOAD_ROOT'; hours = '1) UNION SELECT 1 --' } $m
Assert-Equal $a.Status 'ok' 'a number with SQL after it is read as the number (parseInt), and only the number reaches the statement'
Assert-True (@($m.All | Where-Object { $_ -match 'UNION' }).Count -eq 0) 'no SQL of the request reaches Snowflake'

Write-Host 'View (the data of the static viewer)'
$m = New-LoadMock
[void]$m.History.Add((New-HistoryRow 'g1' 'LOAD_ROOT' 'SUCCEEDED' '2026-11-01T10:00:00.000Z' '2026-11-01T10:00:01.000Z' '2026-11-01T10:00:03.000Z'))
[void]$m.History.Add((New-HistoryRow 'g1' 'LOAD_A' 'FAILED' '2026-11-01T10:00:03.000Z' '2026-11-01T10:00:03.500Z' '2026-11-01T10:00:04.000Z' 'boom' '100'))
$a = Invoke-Engine 'view' @{ database = 'DB'; schema = 'SC' } $m
Assert-Equal $a.Status 'ok' 'view is ok'
Assert-Equal $a.Texts @('2 graphs') 'one TEXT line says how many graphs'
$v = $a.Json
Assert-Equal @($v.psobject.Properties | ForEach-Object { $_.Name }) @('session', 'graphs', 'runs') 'the JSON has session, graphs and runs'
Assert-Equal $v.session.backend 'Cli' 'the session is the placeholder of the viewer'
Assert-Equal @($v.session.psobject.Properties | ForEach-Object { $_.Name }) @('backend', 'account', 'warehouse', 'role') 'with the four fields'
Assert-Equal @($v.graphs | ForEach-Object { $_.root }) @('LOAD_ROOT', 'LONE') 'the graphs of the schema'
Assert-Equal @($v.graphs[0].psobject.Properties | ForEach-Object { $_.Name }) @('database', 'schema', 'root', 'state', 'incomplete', 'tasks') 'a graph has the shape of the web interface'
Assert-Equal @($v.graphs[0].tasks[0].psobject.Properties | ForEach-Object { $_.Name }) @('name', 'definition', 'after', 'finalize', 'schedule', 'warehouse', 'condition', 'allowOverlappingExecution', 'errorIntegration', 'comment', 'config', 'parameters', 'state', 'info') 'and a task too'
Assert-Equal @($v.graphs[0].tasks[0].info.psobject.Properties | ForEach-Object { $_.Name }) @('id', 'owner', 'createdOn', 'lastCommittedOn', 'lastSuspendedOn', 'lastSuspendedReason', 'budget') 'with its info'
Assert-Equal $v.graphs[0].tasks[0].parameters.USER_TASK_TIMEOUT_MS '3600000' 'the parameters are read'
Assert-Equal @($v.runs.psobject.Properties | ForEach-Object { $_.Name }) @('LOAD_ROOT', 'LONE') 'runs are keyed by the name of the root'
Assert-Equal @($v.runs.LOAD_ROOT).Count 1 'a run'
Assert-Equal @($v.runs.LOAD_ROOT[0].psobject.Properties | ForEach-Object { $_.Name }) @('runId', 'state', 'scheduled', 'started', 'completed', 'seconds', 'tasks') 'has the shape of the web interface'
Assert-Equal @($v.runs.LOAD_ROOT[0].tasks[0].psobject.Properties | ForEach-Object { $_.Name }) @('task', 'state', 'started', 'completed', 'error', 'errorCode', 'queryId', 'attempt') 'and so do its tasks'
Assert-Equal $v.runs.LOAD_ROOT[0].state 'FAILED' 'a failed task fails the run'
Assert-Equal $v.runs.LOAD_ROOT[0].tasks[1].error 'boom' 'with the error'
$m = New-LoadMock; $m.HistoryFails = $true
$a = Invoke-Engine 'view' @{ database = 'DB'; schema = 'SC' } $m
Assert-Equal $a.Status 'ok' 'a history that cannot be read is no error'
Assert-Equal @($a.Json.runs.LOAD_ROOT).Count 0 'its runs are an empty list'
Assert-Equal @($a.Json.graphs).Count 2 'and the graphs are there'
$a = Invoke-Engine 'graphs' @{ database = 'DB' } (New-LoadMock)
Assert-Equal @($a.Json.graphs[1].psobject.Properties | ForEach-Object { $_.Name }) @('database', 'schema', 'root', 'state', 'incomplete', 'tasks') 'the JSON of graphs has the same shape'

Write-Host 'Odd characters'
$m = New-Mock
$name = 'caf' + [char]0xE9 + ' "q" it''s \ x'
[void]$m.Rows.Add((New-Row $name -Schedule '1 MINUTE' -Quote -Definition ("SELECT '" + [char]0x20AC + "'") -Comment ("it's a ""test"" \ done " + [char]0x20AC)))
$a = Invoke-Engine 'graphs' @{ database = 'DB' } $m
Assert-Equal $a.Json.graphs[0].root $name 'a name with quotes, a backslash and an accent is read'
$a = Invoke-Engine 'export' @{ database = 'DB'; schema = 'SC' } $m
$exportedFile = @($a.Files.Keys)[0]
Assert-True ($exportedFile -match '^[A-Za-z0-9_.\-]+$') 'its file name is plain'
$a2 = Invoke-Engine 'plan' @{ doc = (ConvertTo-B64 $a.Files[$exportedFile]) } $m
Assert-Equal $a2.Steps 0 'it round trips through its file'
$a3 = Invoke-Engine 'sql' @{ doc = (ConvertTo-B64 $a.Files[$exportedFile]) } $m
Assert-True ($a3.Texts[0].Contains('CREATE OR REPLACE TASK "DB"."SC"."caf' + [char]0xE9 + ' ""q"" it''s \ x"')) 'its identifier is quoted with the quote doubled'
Assert-True ($a3.Texts[0].Contains("COMMENT = 'it''s a `"test`" \\ done " + [char]0x20AC + "'")) 'its comment is a literal with quote and backslash doubled'

Complete-Tests
