# Starting, stopping and running a graph that is installed.

function Resolve-WfInstalledGraph {
    param($Session, $Graph, [string] $Database, [string] $Schema, [string] $Root)
    if ($Graph) { $Database = $Graph.database; $Schema = $Graph.schema; $Root = $Graph.root }
    if (-not $Database -or -not $Schema -or -not $Root) { throw 'Say which graph: give -Graph, or -Database, -Schema and -Root.' }
    $found = @(Get-TaskGraph $Session -Database $Database -Schema $Schema -Root $Root -NoParameters)
    if ($found.Count -eq 0) { throw ("There is no graph with the root '" + $Root + "' in " + $Database + '.' + $Schema + ' (or the role cannot see it).') }
    $found[0]
}

function Resume-TaskGraph {
    <#
    .SYNOPSIS
        Starts a graph: every task that is suspended is resumed, the children before the root, so that the graph never runs with a
        part of it off.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromPipeline = $true)] $Graph, [Parameter(Mandatory = $true)] $Session, [string] $Database, [string] $Schema, [string] $Root)
    process {
        $g = Resolve-WfInstalledGraph $Session $Graph $Database $Schema $Root
        $order = Get-WfTaskOrder @($g.tasks)
        $tasks = @($order.Order) + @($order.Unplaced)
        [array]::Reverse($tasks)
        foreach ($t in $tasks) {
            if ($t.state -eq 'started') { continue }
            $sql = 'ALTER TASK ' + (ConvertTo-WfQualified $g.database $g.schema $t.name) + ' RESUME'
            if ($PSCmdlet.ShouldProcess($t.name, 'resume')) { Invoke-WfSql $Session $sql | Out-Null }
        }
    }
}

function Suspend-TaskGraph {
    <#
    .SYNOPSIS
        Stops a graph: the root is suspended first, so that nothing new starts, then the other tasks.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromPipeline = $true)] $Graph, [Parameter(Mandatory = $true)] $Session, [string] $Database, [string] $Schema, [string] $Root)
    process {
        $g = Resolve-WfInstalledGraph $Session $Graph $Database $Schema $Root
        $order = Get-WfTaskOrder @($g.tasks)
        foreach ($t in (@($order.Order) + @($order.Unplaced))) {
            if ($t.state -ne 'started') { continue }
            $sql = 'ALTER TASK ' + (ConvertTo-WfQualified $g.database $g.schema $t.name) + ' SUSPEND'
            if ($PSCmdlet.ShouldProcess($t.name, 'suspend')) { Invoke-WfSql $Session $sql | Out-Null }
        }
    }
}

function Start-TaskGraph {
    <#
    .SYNOPSIS
        Runs a graph now (EXECUTE TASK on its root); with -Retry the last run is continued from the tasks that failed.
    .DESCRIPTION
        The role must have the EXECUTE TASK privilege or own the task. The graph runs on its own afterwards; Get-TaskGraphRun shows how.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromPipeline = $true)] $Graph, [Parameter(Mandatory = $true)] $Session, [string] $Database, [string] $Schema, [string] $Root, [switch] $Retry)
    process {
        $g = Resolve-WfInstalledGraph $Session $Graph $Database $Schema $Root
        $sql = 'EXECUTE TASK ' + (ConvertTo-WfQualified $g.database $g.schema $g.root)
        if ($Retry) { $sql += ' RETRY LAST' }
        if ($PSCmdlet.ShouldProcess($g.root, 'run')) { Invoke-WfSql $Session $sql | Out-Null }
    }
}

function Get-TaskGraphRun {
    <#
    .SYNOPSIS
        The runs of a graph, newest first, each with its tasks: when it ran, how long, how it ended and what the failures said.
    .DESCRIPTION
        Reads the task history that Snowflake keeps (INFORMATION_SCHEMA.TASK_HISTORY, which keeps a few days and needs the role to
        own the tasks or to have the MONITOR privilege on them). A run is the tasks that share a graph run group. State is
        FAILED if a task failed, RUNNING if one is scheduled or executing, else the state of the root.
    .EXAMPLE
        Get-TaskGraphRun $s -Database ETL -Schema LOAD -Root LOAD_ROOT -Hours 48 | Select-Object RunId, State, Started, Seconds
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)] $Graph, [Parameter(Mandatory = $true)] $Session, [string] $Database, [string] $Schema, [string] $Root, [int] $Hours = 24, [int] $Limit = 20)
    process {
        $g = Resolve-WfInstalledGraph $Session $Graph $Database $Schema $Root
        $rootTask = @($g.tasks | Where-Object { $_.name -ceq $g.root })[0]
        $id = $rootTask.info.id
        $sql = 'SELECT * FROM TABLE(' + (ConvertTo-WfIdentifier $g.database) + '.INFORMATION_SCHEMA.TASK_HISTORY(SCHEDULED_TIME_RANGE_START => DATEADD(hour, -' + [int]$Hours + ', CURRENT_TIMESTAMP()), RESULT_LIMIT => 10000, ROOT_TASK_ID => ' + (ConvertTo-WfLiteral $id) + ')) ORDER BY SCHEDULED_TIME DESC'
        $rows = @(Invoke-WfSql $Session $sql)
        ConvertFrom-WfHistoryRows $rows $g.root | Select-Object -First $Limit
    }
}

function ConvertFrom-WfHistoryRows {
    param($Rows, [string] $Root)
    $runs = [ordered]@{}
    foreach ($r in @($Rows)) {
        $key = [string](Get-WfValue $r 'GRAPH_RUN_GROUP_ID')
        if (-not $key) { $key = [string](Get-WfValue $r 'RUN_ID') }
        if (-not $key) { $key = [string](Get-WfValue $r 'QUERY_ID') }
        if (-not $runs.Contains($key)) { $runs[$key] = New-Object System.Collections.Generic.List[object] }
        $runs[$key].Add($r)
    }
    foreach ($key in $runs.Keys) {
        $rows = $runs[$key].ToArray()
        $tasks = @($rows | ForEach-Object {
            [pscustomobject]@{
                Task = [string](Get-WfValue $_ 'NAME'); State = [string](Get-WfValue $_ 'STATE'); Scheduled = [string](Get-WfValue $_ 'SCHEDULED_TIME')
                Started = [string](Get-WfValue $_ 'QUERY_START_TIME'); Completed = [string](Get-WfValue $_ 'COMPLETED_TIME')
                Error = [string](Get-WfValue $_ 'ERROR_MESSAGE'); ErrorCode = [string](Get-WfValue $_ 'ERROR_CODE'); QueryId = [string](Get-WfValue $_ 'QUERY_ID')
                Attempt = [string](Get-WfValue $_ 'ATTEMPT_NUMBER'); ScheduledFrom = [string](Get-WfValue $_ 'SCHEDULED_FROM')
            }
        })
        $rootRow = @($tasks | Where-Object { $_.Task -ceq $Root } | Select-Object -First 1)
        $state = 'SUCCEEDED'
        if (@($tasks | Where-Object { $_.State -match '^(SCHEDULED|EXECUTING)$' }).Count -gt 0) { $state = 'RUNNING' }
        elseif (@($tasks | Where-Object { $_.State -eq 'FAILED' }).Count -gt 0) { $state = 'FAILED' }
        elseif ($rootRow.Count -gt 0) { $state = $rootRow[0].State }
        $starts = @($tasks | Where-Object { $_.Started } | ForEach-Object { [datetime]::Parse($_.Started, [Globalization.CultureInfo]::InvariantCulture) } | Sort-Object)
        $ends = @($tasks | Where-Object { $_.Completed } | ForEach-Object { [datetime]::Parse($_.Completed, [Globalization.CultureInfo]::InvariantCulture) } | Sort-Object)
        $seconds = $null
        if ($starts.Count -gt 0 -and $ends.Count -gt 0) { $seconds = [math]::Round(($ends[$ends.Count - 1] - $starts[0]).TotalSeconds, 1) }
        $scheduled = ''
        if ($rootRow.Count -gt 0) { $scheduled = $rootRow[0].Scheduled } elseif ($tasks.Count -gt 0) { $scheduled = $tasks[0].Scheduled }
        [pscustomobject]@{
            RunId = $key; State = $state; Scheduled = $scheduled
            Started = $(if ($starts.Count -gt 0) { $starts[0].ToString('s') } else { '' })
            Completed = $(if ($ends.Count -gt 0 -and $state -ne 'RUNNING') { $ends[$ends.Count - 1].ToString('s') } else { '' })
            Seconds = $seconds; Tasks = $tasks
        }
    }
}
