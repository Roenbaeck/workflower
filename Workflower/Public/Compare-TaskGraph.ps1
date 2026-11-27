function Compare-TaskGraph {
    <#
    .SYNOPSIS
        Compares the graph that is wanted with the graph that is installed and gives the steps that turn one into the other.
    .DESCRIPTION
        Nothing is sent to Snowflake that changes anything. The plan has Steps, in the order in which they have to run, each with the
        SQL and the reason; IsEmpty is true when the installed graph is already what is wanted. The order is the one that Snowflake
        needs: the root is suspended first, dependencies that go are removed, tasks that go are dropped (children first), new tasks are
        made (parents first), changed tasks are altered, and then the graph is started again if it was started, or is wanted started.
        A graph that is not installed is made, suspended unless its state says started.
        The installed graph is the one that holds the tasks of the wanted one, in the same schema.
    .EXAMPLE
        Import-TaskGraph .\load.json | Compare-TaskGraph -Session $s
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] $Desired,
        $Session,
        $Actual
    )
    process {
        $db = $Desired.database; $sc = $Desired.schema
        if (-not $db -or -not $sc) { throw 'The graph says no database and schema; give them in the file or with Import-TaskGraph -Database -Schema.' }
        $desired = $Desired
        $wanted = @{}
        foreach ($t in @($desired.tasks)) { $wanted[$t.name] = $t }
        if (-not $PSBoundParameters.ContainsKey("Actual")) {
            if (-not $Session) { throw "Compare-TaskGraph needs -Session to read the installed graph (or -Actual)." }
            $installed = @(Get-TaskGraph $Session -Database $db -Schema $sc)
            $Actual = $null
            foreach ($g in $installed) {
                foreach ($t in @($g.tasks)) { if ($wanted.ContainsKey($t.name)) { if (-not $Actual) { $Actual = $g } } }
            }
        }
        $steps = New-Object System.Collections.Generic.List[object]
        $q = { param($name) ConvertTo-WfQualified $db $sc $name }
        $step = { param($phase, $task, $sql, $reason) $steps.Add([pscustomobject]@{ Phase = $phase; Task = $task; Sql = $sql; Reason = $reason }) }

        # a graph that is not installed is made
        if (-not $Actual) {
            $rootState = $null
            foreach ($t in @($desired.tasks)) { if ($t.name -ceq $desired.root) { $rootState = $t.state } }
            $copy = New-WfGraphObject $db $sc $desired.root @($desired.tasks | ForEach-Object { $c = $_.psobject.Copy(); $c })
            $order = Get-WfTaskOrder @($copy.tasks)
            foreach ($t in (@($order.Order) + @($order.Unplaced))) {
                & $step 'create' $t.name (ConvertTo-WfCreateTask $copy $t $false) ("Task '" + $t.name + "' is new.")
            }
            $startAll = ($rootState -eq 'started')
            $reverse = @(@($order.Order) + @($order.Unplaced)); [array]::Reverse($reverse)
            foreach ($t in $reverse) {
                $final = $t.state
                if (-not $final -and $startAll) { $final = 'started' }
                if ($final -eq 'started') { & $step 'resume' $t.name ('ALTER TASK ' + (& $q $t.name) + ' RESUME') ("Task '" + $t.name + "' is to be started.") }
            }
            return (New-WfPlan $desired $false $steps.ToArray())
        }

        $actual = $Actual
        $have = @{}
        foreach ($t in @($actual.tasks)) { $have[$t.name] = $t }
        $actualRoot = $have[$actual.root]
        $actualOrder = Get-WfTaskOrder @($actual.tasks)

        $added = @($desired.tasks | Where-Object { -not $have.ContainsKey($_.name) })
        $removed = @($actualOrder.Order | Where-Object { -not $wanted.ContainsKey($_.name) })
        $changes = @{}
        foreach ($t in @($desired.tasks)) {
            if ($have.ContainsKey($t.name)) {
                $d = @(Get-WfTaskDifference $t $have[$t.name])
                if ($d.Count -gt 0) { $changes[$t.name] = $d }
            }
        }
        $needsChange = ($added.Count -gt 0 -or $removed.Count -gt 0 -or $changes.Count -gt 0)

        # the state that the graph ends in
        $desiredRoot = $wanted[$desired.root]
        $graphState = 'suspended'
        if ($actualRoot -and $actualRoot.state) { $graphState = $actualRoot.state }
        if ($desiredRoot -and $desiredRoot.state) { $graphState = $desiredRoot.state }
        $finalState = { param($t, $existing)
            if ($t.state) { return $t.state }
            $graphState
        }

        $suspendedRoot = $false
        if ($needsChange -and $actualRoot -and $actualRoot.state -eq 'started') {
            & $step 'suspend' $actual.root ('ALTER TASK ' + (& $q $actual.root) + ' SUSPEND') 'The root is suspended while the graph is changed.'
            $suspendedRoot = $true
        }
        # dependencies that go, before the tasks that go
        foreach ($t in @($desired.tasks)) {
            if ($changes.ContainsKey($t.name)) {
                $cur = $have[$t.name]
                $gone = @(@($cur.after) | Where-Object { @($t.after) -cnotcontains $_ })
                if ($gone.Count -gt 0) {
                    & $step 'unlink' $t.name ('ALTER TASK ' + (& $q $t.name) + ' REMOVE AFTER ' + (($gone | ForEach-Object { & $q $_ }) -join ', ')) ("Task '" + $t.name + "' is no longer after " + ($gone -join ', ') + '.')
                }
                if ($cur.finalize -and -not $t.finalize) {
                    & $step 'unlink' $t.name ('ALTER TASK ' + (& $q $t.name) + ' UNSET FINALIZE') ("Task '" + $t.name + "' no longer finalizes '" + $cur.finalize + "'.")
                }
            }
        }
        $reverseActual = @($actualOrder.Order); [array]::Reverse($reverseActual)
        foreach ($t in $reverseActual) {
            if (-not $wanted.ContainsKey($t.name)) { & $step 'drop' $t.name ('DROP TASK ' + (& $q $t.name)) ("Task '" + $t.name + "' is not in the wanted graph.") }
        }
        $wantedOrder = Get-WfTaskOrder @($desired.tasks)
        foreach ($t in (@($wantedOrder.Order) + @($wantedOrder.Unplaced))) {
            if (-not $have.ContainsKey($t.name)) {
                & $step 'create' $t.name (ConvertTo-WfCreateTask $desired $t $false) ("Task '" + $t.name + "' is new.")
            }
        }
        foreach ($t in (@($wantedOrder.Order) + @($wantedOrder.Unplaced))) {
            if (-not $changes.ContainsKey($t.name)) { continue }
            $cur = $have[$t.name]
            foreach ($sql in @(Get-WfAlterStatements $db $sc $t $cur)) {
                & $step 'alter' $t.name $sql.Sql $sql.Reason
            }
        }
        # the state: started tasks are resumed with the root last, tasks that are to stop are suspended with the root first
        $order = @($wantedOrder.Order) + @($wantedOrder.Unplaced)
        $resume = @($order); [array]::Reverse($resume)
        foreach ($t in $resume) {
            $existing = $null
            if ($have.ContainsKey($t.name)) { $existing = $have[$t.name] }
            $final = & $finalState $t $existing
            $now = $null
            if ($existing) { $now = $existing.state }
            if ($final -eq 'started') {
                $touched = (-not $existing) -or ($t.name -ceq $desired.root -and $suspendedRoot)
                if ($now -ne 'started' -or $touched) { & $step 'resume' $t.name ('ALTER TASK ' + (& $q $t.name) + ' RESUME') ("Task '" + $t.name + "' is to be started.") }
            }
        }
        foreach ($t in $order) {
            if (-not $have.ContainsKey($t.name)) { continue }
            $existing = $have[$t.name]
            $final = & $finalState $t $existing
            if ($final -eq 'suspended' -and $existing.state -eq 'started' -and -not ($t.name -ceq $desired.root -and $suspendedRoot)) {
                & $step 'suspend' $t.name ('ALTER TASK ' + (& $q $t.name) + ' SUSPEND') ("Task '" + $t.name + "' is to be suspended.")
            }
        }
        $result = New-WfPlan $desired $true $steps.ToArray()
        $result.Added = @($added | ForEach-Object { $_.name })
        $result.Removed = @($removed | ForEach-Object { $_.name })
        $result.Changed = @($changes.Keys | Sort-Object)
        $result
    }
}

function New-WfPlan {
    param($Graph, [bool] $Exists, $Steps)
    [pscustomobject]@{
        Database = $Graph.database; Schema = $Graph.schema; Root = $Graph.root; Exists = $Exists
        IsEmpty = (@($Steps).Count -eq 0); Steps = @($Steps)
        Added = @(); Removed = @(); Changed = @()
    }
}

$script:WfLineBreaks = [regex]'\r\n?'

function ConvertTo-WfComparable {
    param($Text)
    if ($null -eq $Text) { return '' }
    $script:WfLineBreaks.Replace([string]$Text, "`n").TrimEnd()
}

# The names of the fields in which a wanted task is not the installed one.
function Get-WfTaskDifference {
    param($Wanted, $Installed)
    $d = New-Object System.Collections.Generic.List[string]
    if ((ConvertTo-WfComparable $Wanted.definition) -cne (ConvertTo-WfComparable $Installed.definition)) { $d.Add('definition') }
    if ((ConvertTo-WfComparable $Wanted.condition) -cne (ConvertTo-WfComparable $Installed.condition)) { $d.Add('condition') }
    foreach ($f in @('schedule', 'warehouse', 'comment', 'config', 'errorIntegration')) {
        if ((ConvertTo-WfComparable $Wanted.$f) -cne (ConvertTo-WfComparable $Installed.$f)) { $d.Add($f) }
    }
    # a field that is not said (null) is not compared for the flag, since Snowflake gives the root a value and a child none
    if ($null -ne $Wanted.allowOverlappingExecution -and $Wanted.allowOverlappingExecution -ne $Installed.allowOverlappingExecution) { $d.Add('allowOverlappingExecution') }
    $a1 = @(@($Wanted.after) | Sort-Object) -join "`n"; $a2 = @(@($Installed.after) | Sort-Object) -join "`n"
    if ($a1 -cne $a2) { $d.Add('after') }
    if ((ConvertTo-WfComparable $Wanted.finalize) -cne (ConvertTo-WfComparable $Installed.finalize)) { $d.Add('finalize') }
    $keys = @(@($Wanted.parameters.Keys) + @($Installed.parameters.Keys) | Sort-Object -Unique)
    foreach ($k in $keys) {
        $w = $null; $i = $null
        if ($Wanted.parameters.Contains($k)) { $w = [string]$Wanted.parameters[$k] }
        if ($Installed.parameters.Contains($k)) { $i = [string]$Installed.parameters[$k] }
        if ($null -eq $w -or $null -eq $i -or $w -ine $i) { $d.Add('parameter ' + $k) }
    }
    $d.ToArray()
}

# The ALTER TASK statements that turn an installed task into a wanted one (the dependencies that go are removed before).
function Get-WfAlterStatements {
    param($Db, $Sc, $Wanted, $Installed)
    $q = ConvertTo-WfQualified $Db $Sc $Wanted.name
    $out = New-Object System.Collections.Generic.List[object]
    $diff = @(Get-WfTaskDifference $Wanted $Installed)
    $set = New-Object System.Collections.Generic.List[string]
    $unset = New-Object System.Collections.Generic.List[string]
    $labels = New-Object System.Collections.Generic.List[string]
    $scalar = [ordered]@{ warehouse = 'WAREHOUSE'; schedule = 'SCHEDULE'; config = 'CONFIG'; errorIntegration = 'ERROR_INTEGRATION'; comment = 'COMMENT' }
    foreach ($f in $scalar.Keys) {
        if ($diff -ccontains $f) {
            $labels.Add($f)
            $value = $Wanted.$f
            if ($value) {
                if ($f -in @('warehouse', 'errorIntegration')) { $set.Add($scalar[$f] + ' = ' + (ConvertTo-WfIdentifier $value)) } else { $set.Add($scalar[$f] + ' = ' + (ConvertTo-WfLiteral $value)) }
            } else { $unset.Add($scalar[$f]) }
        }
    }
    if ($diff -ccontains 'allowOverlappingExecution') { $labels.Add('allowOverlappingExecution'); $set.Add('ALLOW_OVERLAPPING_EXECUTION = ' + $(if ($Wanted.allowOverlappingExecution) { 'TRUE' } else { 'FALSE' })) }
    foreach ($entry in $diff) {
        if ($entry.StartsWith('parameter ')) {
            $k = $entry.Substring(10)
            $labels.Add($entry)
            if ($Wanted.parameters.Contains($k)) { $set.Add($k + ' = ' + (ConvertTo-WfParameterValue $Wanted.parameters[$k])) } else { $unset.Add($k) }
        }
    }
    if ($unset.Count -gt 0) { $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + ' UNSET ' + ($unset -join ', '); Reason = "Task '" + $Wanted.name + "': " + (($labels | Where-Object { $_ }) -join ', ') + ' is unset.' }) }
    if ($set.Count -gt 0) { $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + ' SET ' + ($set -join ', '); Reason = "Task '" + $Wanted.name + "': " + (($labels | Where-Object { $_ }) -join ', ') + ' is changed.' }) }
    if ($diff -ccontains 'definition') { $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + " MODIFY AS`n" + ([string]$Wanted.definition).TrimEnd(); Reason = "Task '" + $Wanted.name + "': the definition is changed." }) }
    if ($diff -ccontains 'condition') {
        if ($Wanted.condition) { $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + ' MODIFY WHEN ' + $Wanted.condition; Reason = "Task '" + $Wanted.name + "': the condition is changed." }) }
        else { $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + ' REMOVE WHEN'; Reason = "Task '" + $Wanted.name + "': the condition is removed." }) }
    }
    $new = @(@($Wanted.after) | Where-Object { @($Installed.after) -cnotcontains $_ })
    if ($new.Count -gt 0) {
        $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + ' ADD AFTER ' + (($new | ForEach-Object { ConvertTo-WfQualified $Db $Sc $_ }) -join ', '); Reason = "Task '" + $Wanted.name + "' is now after " + ($new -join ', ') + '.' })
    }
    if ($Wanted.finalize -and ($Wanted.finalize -cne $Installed.finalize)) {
        $out.Add([pscustomobject]@{ Sql = 'ALTER TASK ' + $q + ' SET FINALIZE = ' + (ConvertTo-WfQualified $Db $Sc $Wanted.finalize); Reason = "Task '" + $Wanted.name + "' now finalizes '" + $Wanted.finalize + "'." })
    }
    $out.ToArray()
}
