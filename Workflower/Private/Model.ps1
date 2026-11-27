# The model of a task graph. It is what Get-TaskGraph reads, what a file holds, what the plan compares and what the SQL is made from.
#
# A graph:  database, schema, root (the name of the root task), tasks (root first, a finalizer last)
# A task:   name, definition (the SQL that it runs, as written), after (names of its predecessors), finalize (the name of the root
#           that this task finalizes), schedule, warehouse, condition (the WHEN expression), allowOverlappingExecution,
#           errorIntegration, comment, config, parameters (task parameters such as USER_TASK_TIMEOUT_MS and session parameters set
#           on the task), state (started or suspended; null when it is not said)
# All tasks of a graph are in one schema, which Snowflake requires. Names are the exact names, case and all.

$script:WfTaskProperties = @('name', 'definition', 'after', 'finalize', 'schedule', 'warehouse', 'condition',
    'allowOverlappingExecution', 'errorIntegration', 'comment', 'config', 'parameters', 'state')

function New-WfTaskObject {
    param([Parameter(Mandatory = $true)][string] $Name)
    [pscustomobject][ordered]@{
        name = $Name; definition = ''; after = @(); finalize = $null; schedule = $null; warehouse = $null; condition = $null
        allowOverlappingExecution = $null; errorIntegration = $null; comment = $null; config = $null
        parameters = [ordered]@{}; state = $null
    }
}

# A value of a loose object (a hashtable, a dictionary from JSON, a custom object), the key matched without regard to case.
function Get-WfValue {
    param($Object, [string] $Key)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($k in $Object.Keys) { if ([string]$k -ieq $Key) { return $Object[$k] } }
        return $null
    }
    foreach ($p in $Object.psobject.Properties) { if ($p.Name -ieq $Key) { return $p.Value } }
    $null
}

function Test-WfHas {
    param($Object, [string] $Key)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($k in $Object.Keys) { if ([string]$k -ieq $Key) { return $true } }
        return $false
    }
    foreach ($p in $Object.psobject.Properties) { if ($p.Name -ieq $Key) { return $true } }
    $false
}

function ConvertTo-WfBool {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return $Value }
    $text = ([string]$Value).Trim()
    if ($text -eq '') { return $null }
    if ($text -match '^(?i:true|1|yes)$') { return $true }
    if ($text -match '^(?i:false|0|no)$') { return $false }
    $null
}

function ConvertTo-WfNullIfEmpty {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ($text -eq '') { return $null }
    $text
}

# A task from anything that has the task's fields: an unknown field is an error, so that a misspelling is not silently ignored.
function ConvertTo-WfTask {
    param([Parameter(Mandatory = $true)] $Source)
    $name = [string](Get-WfValue $Source 'name')
    if (-not $name) { throw 'A task has no name.' }
    $keys = @()
    if ($Source -is [System.Collections.IDictionary]) { $keys = @($Source.Keys | ForEach-Object { [string]$_ }) } else { $keys = @($Source.psobject.Properties | ForEach-Object { $_.Name }) }
    foreach ($k in $keys) {
        if ($script:WfTaskProperties -inotcontains $k) {
            throw ("Task '" + $name + "': unknown field '" + $k + "' (the fields are " + ($script:WfTaskProperties -join ', ') + ').')
        }
    }
    $t = New-WfTaskObject $name
    $def = Get-WfValue $Source 'definition'
    if ($null -ne $def) { $t.definition = [string]$def }
    $after = Get-WfValue $Source 'after'
    if ($null -ne $after) { $t.after = @(@($after) | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
    $t.finalize = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'finalize')
    $t.schedule = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'schedule')
    $t.warehouse = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'warehouse')
    $t.condition = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'condition')
    $t.allowOverlappingExecution = ConvertTo-WfBool (Get-WfValue $Source 'allowOverlappingExecution')
    $t.errorIntegration = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'errorIntegration')
    $t.comment = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'comment')
    $t.config = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'config')
    $parameters = Get-WfValue $Source 'parameters'
    if ($null -ne $parameters) {
        $pairs = @()
        if ($parameters -is [System.Collections.IDictionary]) { foreach ($k in $parameters.Keys) { $pairs += , @([string]$k, $parameters[$k]) } }
        else { foreach ($p in $parameters.psobject.Properties) { $pairs += , @($p.Name, $p.Value) } }
        foreach ($pair in ($pairs | Sort-Object { $_[0] })) {
            $v = $pair[1]
            if ($v -is [bool]) { $v = $(if ($v) { 'TRUE' } else { 'FALSE' }) }
            $t.parameters[$pair[0].ToUpperInvariant()] = [string]$v
        }
    }
    $state = ConvertTo-WfNullIfEmpty (Get-WfValue $Source 'state')
    if ($state) {
        $state = $state.ToLowerInvariant()
        if ($state -notin @('started', 'suspended')) { throw ("Task '" + $name + "': state must be started or suspended, not '" + $state + "'.") }
    }
    $t.state = $state
    $t
}

function New-WfGraphObject {
    param([string] $Database, [string] $Schema, [string] $Root, $Tasks)
    $g = [pscustomobject][ordered]@{ database = $Database; schema = $Schema; root = $Root; tasks = @($Tasks) }
    $g
}

# The tasks in an order in which each comes after its predecessors; the root first and a finalizer last. Tasks that are in a cycle,
# or wait for a predecessor that is not there, are in Unplaced.
function Get-WfTaskOrder {
    param([Parameter(Mandatory = $true)] $Tasks)
    $all = @($Tasks)
    $byName = @{}
    foreach ($t in $all) { $byName[$t.name] = $t }
    $placed = New-Object System.Collections.Generic.List[object]
    $done = @{}
    $progress = $true
    $rest = New-Object System.Collections.Generic.List[object]
    foreach ($t in $all) { if (-not $t.finalize) { $rest.Add($t) } }
    $finalizers = @($all | Where-Object { $_.finalize })
    while ($progress -and $rest.Count -gt 0) {
        $progress = $false
        $next = New-Object System.Collections.Generic.List[object]
        foreach ($t in $rest) {
            $ready = $true
            foreach ($a in @($t.after)) { if (-not $done.ContainsKey($a)) { $ready = $false } }
            if ($ready) { $placed.Add($t); $done[$t.name] = $true; $progress = $true } else { $next.Add($t) }
        }
        $rest = $next
    }
    foreach ($f in $finalizers) { $placed.Add($f); $done[$f.name] = $true }
    [pscustomobject]@{ Order = $placed.ToArray(); Unplaced = $rest.ToArray() }
}

# Brings a graph into the form that a comparison needs: the tasks in order, the root named.
function Update-WfGraph {
    param([Parameter(Mandatory = $true)] $Graph)
    $tasks = @($Graph.tasks)
    $order = Get-WfTaskOrder $tasks
    $sorted = @($order.Order) + @($order.Unplaced)
    $roots = @($tasks | Where-Object { @($_.after).Count -eq 0 -and -not $_.finalize })
    $root = $null
    if ($roots.Count -ge 1) { $root = $roots[0].name }
    $Graph.tasks = $sorted
    $Graph.root = $root
    $Graph
}
