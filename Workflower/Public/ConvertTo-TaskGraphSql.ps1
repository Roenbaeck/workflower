function ConvertTo-TaskGraphSql {
    <#
    .SYNOPSIS
        The SQL that makes a graph: one CREATE TASK for every task, in an order in which each task comes after its predecessors.
    .DESCRIPTION
        Returns the statements one by one (without a closing semicolon, which a task's own body may need); -AsScript gives them as one
        script. Every identifier is double quoted, so names are exact. A task is made suspended, as Snowflake does; with
        -IncludeState a task whose state is started is resumed afterwards, the children before the root.
    .EXAMPLE
        Import-TaskGraph .\load.json | ConvertTo-TaskGraphSql -AsScript | Set-Content load.sql
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] $Graph,
        [switch] $NoReplace,
        [switch] $IncludeState,
        [switch] $AsScript
    )
    process {
        $order = Get-WfTaskOrder @($Graph.tasks)
        $tasks = @($order.Order) + @($order.Unplaced)
        $statements = New-Object System.Collections.Generic.List[string]
        foreach ($t in $tasks) { $statements.Add((ConvertTo-WfCreateTask $Graph $t (-not $NoReplace))) }
        if ($IncludeState) {
            $reverse = @($tasks)
            [array]::Reverse($reverse)
            foreach ($t in $reverse) {
                if ($t.state -eq 'started') { $statements.Add('ALTER TASK ' + (ConvertTo-WfQualified $Graph.database $Graph.schema $t.name) + ' RESUME') }
            }
        }
        if ($AsScript) {
            $text = New-Object System.Text.StringBuilder
            foreach ($s in $statements) {
                [void]$text.Append($s)
                if (-not $s.TrimEnd().EndsWith(';')) { [void]$text.Append(';') }
                [void]$text.Append("`n`n")
            }
            return $text.ToString()
        }
        $statements.ToArray()
    }
}

# The properties of a task as they are written in CREATE TASK, in the order that the statement has them.
function ConvertTo-WfCreateTask {
    param($Graph, $Task, [bool] $Replace)
    $db = $Graph.database; $sc = $Graph.schema
    $lines = New-Object System.Collections.Generic.List[string]
    if ($Replace) { $lines.Add('CREATE OR REPLACE TASK ' + (ConvertTo-WfQualified $db $sc $Task.name)) }
    else { $lines.Add('CREATE TASK ' + (ConvertTo-WfQualified $db $sc $Task.name)) }
    if ($Task.warehouse) { $lines.Add('  WAREHOUSE = ' + (ConvertTo-WfIdentifier $Task.warehouse)) }
    if ($Task.schedule) { $lines.Add('  SCHEDULE = ' + (ConvertTo-WfLiteral $Task.schedule)) }
    if ($Task.config) { $lines.Add('  CONFIG = ' + (ConvertTo-WfLiteral $Task.config)) }
    if ($null -ne $Task.allowOverlappingExecution) { $lines.Add('  ALLOW_OVERLAPPING_EXECUTION = ' + $(if ($Task.allowOverlappingExecution) { 'TRUE' } else { 'FALSE' })) }
    foreach ($k in $Task.parameters.Keys) { $lines.Add('  ' + $k + ' = ' + (ConvertTo-WfParameterValue $Task.parameters[$k])) }
    if ($Task.errorIntegration) { $lines.Add('  ERROR_INTEGRATION = ' + (ConvertTo-WfIdentifier $Task.errorIntegration)) }
    if ($Task.comment) { $lines.Add('  COMMENT = ' + (ConvertTo-WfLiteral $Task.comment)) }
    if ($Task.finalize) { $lines.Add('  FINALIZE = ' + (ConvertTo-WfQualified $db $sc $Task.finalize)) }
    if (@($Task.after).Count -gt 0) {
        $lines.Add('  AFTER ' + ((@($Task.after) | ForEach-Object { ConvertTo-WfQualified $db $sc $_ }) -join ', '))
    }
    if ($Task.condition) { $lines.Add('  WHEN ' + $Task.condition) }
    $lines.Add('AS')
    $lines.Add(([string]$Task.definition).TrimEnd())
    $lines -join "`n"
}
