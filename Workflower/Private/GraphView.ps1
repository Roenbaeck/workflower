# Graphs as the interface and the files see them: plain ordered dictionaries that become JSON.

# A task as a file holds it, without the SQL it runs (a file holds that under definition, or beside it).
function ConvertTo-WfTaskDocument {
    param([Parameter(Mandatory = $true)] $Task, [switch] $NoState)
    $t = $Task
    $o = [ordered]@{ name = $t.name }
    if (@($t.after).Count -gt 0) { $o.after = @($t.after) }
    if ($t.finalize) { $o.finalize = $t.finalize }
    if ($t.schedule) { $o.schedule = $t.schedule }
    if ($t.warehouse) { $o.warehouse = $t.warehouse }
    if ($t.condition) { $o.condition = $t.condition }
    if ($null -ne $t.allowOverlappingExecution) { $o.allowOverlappingExecution = $t.allowOverlappingExecution }
    if ($t.errorIntegration) { $o.errorIntegration = $t.errorIntegration }
    if ($t.comment) { $o.comment = $t.comment }
    if ($t.config) { $o.config = $t.config }
    if ($t.parameters.Count -gt 0) { $o.parameters = $t.parameters }
    if ($t.state -and -not $NoState) { $o.state = $t.state }
    $o
}

# The text of a graph file, with every task's SQL in it.
function ConvertTo-WfGraphFileText {
    param([Parameter(Mandatory = $true)] $Graph, [switch] $NoState)
    $tasks = New-Object System.Collections.Generic.List[object]
    foreach ($t in @($Graph.tasks)) {
        $o = ConvertTo-WfTaskDocument $t -NoState:$NoState
        $o.definition = $t.definition
        $tasks.Add($o)
    }
    $doc = [ordered]@{ format = 'workflower-graph'; version = 1; database = $Graph.database; schema = $Graph.schema; tasks = $tasks.ToArray() }
    (ConvertTo-WfJson $doc) + "`n"
}

# A task for the interface: all its fields, and what is only known about an installed task (owner, ids, times) under info.
function ConvertTo-WfTaskView {
    param([Parameter(Mandatory = $true)] $Task)
    $t = $Task
    $o = [ordered]@{
        name = $t.name; definition = $t.definition; after = @($t.after); finalize = $t.finalize; schedule = $t.schedule; warehouse = $t.warehouse
        condition = $t.condition; allowOverlappingExecution = $t.allowOverlappingExecution; errorIntegration = $t.errorIntegration
        comment = $t.comment; config = $t.config; parameters = $t.parameters; state = $t.state
    }
    if ($t.psobject.Properties['info']) { $o.info = $t.info }
    $o
}

function ConvertTo-WfGraphView {
    param([Parameter(Mandatory = $true)] $Graph)
    $g = $Graph
    $root = $null
    foreach ($t in @($g.tasks)) { if ($t.name -ceq $g.root) { $root = $t } }
    $state = 'suspended'
    if ($root -and $root.state) { $state = $root.state }
    $incomplete = $false
    if ($g.psobject.Properties['Incomplete']) { $incomplete = [bool]$g.Incomplete }
    [ordered]@{
        database = $g.database; schema = $g.schema; root = $g.root; state = $state; incomplete = $incomplete
        tasks = @($g.tasks | ForEach-Object { ConvertTo-WfTaskView $_ })
    }
}

# A graph from what the interface sends: the same fields as a task view (info is ignored).
function ConvertTo-WfGraph {
    param([Parameter(Mandatory = $true)] $Source)
    $tasks = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-WfValue $Source 'tasks')) {
        $copy = [ordered]@{}
        foreach ($k in $item.Keys) { if ([string]$k -ine 'info') { $copy[$k] = $item[$k] } }
        $tasks.Add((ConvertTo-WfTask $copy))
    }
    $g = New-WfGraphObject ([string](Get-WfValue $Source 'database')) ([string](Get-WfValue $Source 'schema')) $null $tasks.ToArray()
    Update-WfGraph $g
}
