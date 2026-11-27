function Test-TaskGraph {
    <#
    .SYNOPSIS
        Checks a graph against the rules that Snowflake enforces, before anything is sent to it.
    .DESCRIPTION
        Returns the problems found one by one, each with Severity (error, warning or info), Task (or empty), Code and Message; nothing when the
        graph is fine. An error is something that Snowflake rejects (a cycle, two roots, a schedule on a child, a missing
        predecessor, more than 1,000 tasks, more than 100 children of a task, more than 100 predecessors of a task, a finalizer that
        does not finalize the root). A warning is something that is allowed but is probably not what was meant.
    .EXAMPLE
        Import-TaskGraph .\load.json | Test-TaskGraph
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)] $Graph)
    process {
        $problems = New-Object System.Collections.Generic.List[object]
        $add = {
            param($severity, $task, $code, $message)
            $problems.Add([pscustomobject]@{ Severity = $severity; Task = $task; Code = $code; Message = $message })
        }
        $tasks = @($Graph.tasks)
        $names = New-WfMap
        foreach ($t in $tasks) {
            if ($names.ContainsKey($t.name)) { & $add 'error' $t.name 'duplicate-name' ("There are two tasks called '" + $t.name + "'.") }
            $names[$t.name] = $t
        }
        if ($tasks.Count -eq 0) { & $add 'error' $null 'empty' 'The graph has no tasks.' }
        if ($tasks.Count -gt 1000) { & $add 'error' $null 'too-many-tasks' ('A graph has at most 1,000 tasks; this one has ' + $tasks.Count + '.') }

        $children = New-WfMap
        foreach ($t in $tasks) {
            if (-not ([string]$t.definition).Trim()) { & $add 'error' $t.name 'no-definition' ("Task '" + $t.name + "' has nothing to run (definition).") }
            foreach ($a in @($t.after)) {
                if ($a -ceq $t.name) { & $add 'error' $t.name 'self' ("Task '" + $t.name + "' is after itself.") }
                elseif (-not $names.ContainsKey($a)) { & $add 'error' $t.name 'missing-predecessor' ("Task '" + $t.name + "' is after '" + $a + "', which is not in the graph.") }
                else {
                    if (-not $children.ContainsKey($a)) { $children[$a] = 0 }
                    $children[$a]++
                }
            }
            if (@($t.after).Count -gt 100) { & $add 'error' $t.name 'too-many-predecessors' ("Task '" + $t.name + "' has " + @($t.after).Count + ' predecessors; the most is 100.') }
        }
        foreach ($k in $children.Keys) {
            if ($children[$k] -gt 100) { & $add 'error' $k 'too-many-children' ("Task '" + $k + "' has " + $children[$k] + ' child tasks; the most is 100.') }
        }

        $order = Get-WfTaskOrder $tasks
        $unplacedNames = @($order.Unplaced | ForEach-Object { $_.name })
        $inCycle = @($order.Unplaced | Where-Object {
            $t = $_
            $waiting = @($t.after | Where-Object { $names.ContainsKey($_) -and ($unplacedNames -ccontains $_) })
            $waiting.Count -gt 0
        })
        if ($inCycle.Count -gt 0) { & $add 'error' $null 'cycle' ('The tasks wait for each other (a cycle): ' + (($inCycle | ForEach-Object { $_.name }) -join ', ') + '.') }

        $finalizers = @($tasks | Where-Object { $_.finalize })
        $roots = @($tasks | Where-Object { @($_.after).Count -eq 0 -and -not $_.finalize })
        if ($tasks.Count -gt 0) {
            if ($roots.Count -eq 0) { & $add 'error' $null 'no-root' 'The graph has no root task (a task with no predecessors).' }
            elseif ($roots.Count -gt 1) { & $add 'error' $null 'several-roots' ('The graph has more than one task with no predecessors: ' + (($roots | ForEach-Object { $_.name }) -join ', ') + '. A graph has one root.') }
        }
        $rootName = $null
        if ($roots.Count -ge 1) { $rootName = $roots[0].name }

        foreach ($t in $tasks) {
            $isRoot = ($rootName -and $t.name -ceq $rootName)
            if ($t.schedule -and -not $isRoot) { & $add 'error' $t.name 'schedule-on-child' ("Task '" + $t.name + "' has a schedule, but only the root task can have one.") }
            if ($t.warehouse -and $t.parameters.Contains('USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE')) {
                & $add 'error' $t.name 'two-computes' ("Task '" + $t.name + "' names a warehouse and a serverless size; it can have only one of them.")
            }
            if ($null -ne $t.allowOverlappingExecution -and -not $isRoot) {
                & $add 'warning' $t.name 'overlap-on-child' ("ALLOW_OVERLAPPING_EXECUTION is set on '" + $t.name + "', which is not the root; Snowflake takes it from the root.")
            }
        }
        if ($finalizers.Count -gt 1) { & $add 'error' $null 'several-finalizers' ('A graph has at most one finalizer task: ' + (($finalizers | ForEach-Object { $_.name }) -join ', ') + '.') }
        foreach ($f in $finalizers) {
            if (-not $names.ContainsKey($f.finalize)) { & $add 'error' $f.name 'finalize-missing' ("Task '" + $f.name + "' finalizes '" + $f.finalize + "', which is not in the graph.") }
            elseif ($rootName -and $f.finalize -cne $rootName) { & $add 'error' $f.name 'finalize-not-root' ("Task '" + $f.name + "' finalizes '" + $f.finalize + "', which is not the root of the graph ('" + $rootName + "').") }
            if (@($f.after).Count -gt 0) { & $add 'error' $f.name 'finalizer-after' ("The finalizer '" + $f.name + "' has predecessors; a finalizer runs after the whole graph and has none.") }
            foreach ($t in $tasks) { if (@($t.after) -ccontains $f.name) { & $add 'error' $t.name 'after-finalizer' ("Task '" + $t.name + "' is after the finalizer '" + $f.name + "'; nothing can be after a finalizer.") } }
        }

        if ($rootName) {
            $root = $names[$rootName]
            if (-not $root.schedule -and -not $root.condition) {
                if ($root.state -eq 'started') {
                    & $add 'error' $rootName 'root-cannot-start' ("The root '" + $rootName + "' has no schedule and no condition, and Snowflake does not resume such a task; it can only be run by hand (EXECUTE TASK).")
                } else {
                    & $add 'info' $rootName 'manual-root' ("The root '" + $rootName + "' has no schedule and no condition, so the graph runs only when it is run by hand (EXECUTE TASK).")
                }
            }
            if ($root.state -eq 'started') {
                foreach ($t in $tasks) {
                    if ($t.state -eq 'suspended' -and $t.name -cne $rootName) {
                        & $add 'warning' $t.name 'suspended-child' ("'" + $t.name + "' is suspended while the root is started, so it does not run, and neither does anything after it.")
                    }
                }
            }
        }
        $problems.ToArray()
    }
}
