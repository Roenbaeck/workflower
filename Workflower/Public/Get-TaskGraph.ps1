function Get-TaskGraph {
    <#
    .SYNOPSIS
        Reads the task graphs of a schema, a database or the whole account, whoever made them.
    .DESCRIPTION
        Uses SHOW TASKS, and SHOW PARAMETERS IN TASK for what is set on a task, and never changes anything. A graph is the tasks that
        are connected by AFTER or FINALIZE; a task that stands alone is a graph of one. Only the tasks that the session's role can
        see are read, and a graph with a task that is hidden from the role is reported as incomplete (Incomplete = $true on it).
    .EXAMPLE
        Get-TaskGraph $session -Database ETL -Schema LOAD
    .EXAMPLE
        Get-TaskGraph $session -Database ETL -Schema LOAD -Root LOAD_ROOT | Export-TaskGraph -Directory .\graphs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)] $Session,
        [string] $Database,
        [string] $Schema,
        [string] $Root,
        [switch] $NoParameters
    )
    if ($Schema -and -not $Database) { throw '-Schema needs -Database.' }
    if ($Schema) { $scope = 'SCHEMA ' + (ConvertTo-WfIdentifier $Database) + '.' + (ConvertTo-WfIdentifier $Schema) }
    elseif ($Database) { $scope = 'DATABASE ' + (ConvertTo-WfIdentifier $Database) }
    else { $scope = 'ACCOUNT' }
    $rows = @(Invoke-WfSql $Session ("SHOW TASKS IN " + $scope))
    $graphs = ConvertFrom-WfTaskRows $rows
    if ($Root) { $graphs = @($graphs | Where-Object { $_.root -ceq $Root }) }
    if (-not $NoParameters) {
        foreach ($g in $graphs) {
            foreach ($t in @($g.tasks)) {
                $q = ConvertTo-WfQualified $g.database $g.schema $t.name
                $params = @(Invoke-WfSql $Session ("SHOW PARAMETERS IN TASK " + $q))
                foreach ($p in $params) {
                    if ((Get-WfValue $p 'level') -eq 'TASK') {
                        $t.parameters[[string](Get-WfValue $p 'key')] = [string](Get-WfValue $p 'value')
                    }
                }
                $sorted = [ordered]@{}
                foreach ($k in ($t.parameters.Keys | Sort-WfOrdinal)) { $sorted[$k] = $t.parameters[$k] }
                $t.parameters = $sorted
            }
        }
    }
    $graphs
}

# The rows of SHOW TASKS as graphs.
function ConvertFrom-WfTaskRows {
    param($Rows)
    $bySchema = [ordered]@{}
    foreach ($row in @($Rows)) {
        $db = [string](Get-WfValue $row 'database_name'); $sc = [string](Get-WfValue $row 'schema_name')
        $key = $db + [char]0 + $sc
        if (-not $bySchema.Contains($key)) { $bySchema[$key] = New-Object System.Collections.Generic.List[object] }
        $bySchema[$key].Add($row)
    }
    $graphs = New-Object System.Collections.Generic.List[object]
    foreach ($key in $bySchema.Keys) {
        $rows = $bySchema[$key].ToArray()
        $db = [string](Get-WfValue $rows[0] 'database_name'); $sc = [string](Get-WfValue $rows[0] 'schema_name')
        $tasks = New-WfMap
        $links = New-Object System.Collections.Generic.List[object]
        $missing = New-WfMap
        foreach ($row in $rows) {
            $t = New-WfTaskObject ([string](Get-WfValue $row 'name'))
            $t.definition = [string](Get-WfValue $row 'definition')
            $t.schedule = ConvertTo-WfNullIfEmpty (Get-WfValue $row 'schedule')
            $t.warehouse = ConvertTo-WfNullIfEmpty (Get-WfValue $row 'warehouse')
            $t.condition = ConvertTo-WfNullIfEmpty (Get-WfValue $row 'condition')
            $t.allowOverlappingExecution = ConvertTo-WfBool (Get-WfValue $row 'allow_overlapping_execution')
            $ei = ConvertTo-WfNullIfEmpty (Get-WfValue $row 'error_integration')
            if ($ei -and $ei -ine 'null') { $t.errorIntegration = $ei }
            $t.comment = ConvertTo-WfNullIfEmpty (Get-WfValue $row 'comment')
            $cfg = ConvertTo-WfNullIfEmpty (Get-WfValue $row 'config')
            if ($cfg -and $cfg -ine 'null') { $t.config = $cfg }
            $st = ([string](Get-WfValue $row 'state')).ToLowerInvariant()
            if ($st -in @('started', 'suspended')) { $t.state = $st }
            $info = [ordered]@{
                id = [string](Get-WfValue $row 'id'); owner = [string](Get-WfValue $row 'owner'); createdOn = [string](Get-WfValue $row 'created_on')
                lastCommittedOn = [string](Get-WfValue $row 'last_committed_on'); lastSuspendedOn = [string](Get-WfValue $row 'last_suspended_on')
                lastSuspendedReason = [string](Get-WfValue $row 'last_suspended_reason'); budget = [string](Get-WfValue $row 'budget')
            }
            $t | Add-Member -MemberType NoteProperty -Name info -Value $info
            $tasks[$t.name] = $t
            $relations = $null
            $text = [string](Get-WfValue $row 'task_relations')
            if ($text) { try { $relations = (ConvertFrom-WfJson $text) } catch { $relations = $null } }
            $after = @()
            $pred = Get-WfValue $relations 'Predecessors'
            if ($null -ne $pred) { $after = @(@($pred) | ForEach-Object { [string]$_ }) }
            else {
                $pt = [string](Get-WfValue $row 'predecessors')
                if ($pt.TrimStart().StartsWith('[')) { $after = @(@((ConvertFrom-WfJson $pt)) | ForEach-Object { [string]$_ }) }
                elseif ($pt.Trim()) { $after = @($pt.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            }
            $links.Add([pscustomobject]@{ Task = $t.name; After = $after; FinalizerOf = [string](Get-WfValue $relations 'FinalizedRootTask') })
        }
        # the names in the relations are qualified; they are task names in this schema
        $names = @($tasks.Keys)
        $resolve = {
            param($text)
            $last = Get-WfLastPart $text
            if ($tasks.ContainsKey($last)) { return $last }
            $hit = @($names | Where-Object { $_ -ieq $last })
            if ($hit.Count -eq 1) { return $hit[0] }
            $null
        }
        $parent = New-WfMap
        foreach ($n in $names) { $parent[$n] = $n }
        $find = { param($x) while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; $x }
        $incomplete = New-WfMap
        foreach ($l in $links) {
            $t = $tasks[$l.Task]
            $after = New-Object System.Collections.Generic.List[string]
            foreach ($a in $l.After) {
                $r = & $resolve $a
                if ($r) { $after.Add($r); $ra = & $find $r; $rb = & $find $t.name; if ($ra -ne $rb) { $parent[$ra] = $rb } }
                else { $after.Add((Get-WfLastPart $a)); $incomplete[$t.name] = $true }
            }
            $t.after = $after.ToArray()
            if ($l.FinalizerOf) {
                $r = & $resolve $l.FinalizerOf
                if ($r) { $t.finalize = $r; $ra = & $find $r; $rb = & $find $t.name; if ($ra -ne $rb) { $parent[$ra] = $rb } }
                else { $t.finalize = (Get-WfLastPart $l.FinalizerOf); $incomplete[$t.name] = $true }
            }
        }
        $groups = [ordered]@{}
        foreach ($n in ($names | Sort-WfOrdinal)) {
            $c = & $find $n
            if (-not $groups.Contains($c)) { $groups[$c] = New-Object System.Collections.Generic.List[object] }
            $groups[$c].Add($tasks[$n])
        }
        foreach ($c in $groups.Keys) {
            $g = New-WfGraphObject $db $sc $null $groups[$c].ToArray()
            Update-WfGraph $g | Out-Null
            $isIncomplete = $false
            foreach ($t in $g.tasks) { if ($incomplete.ContainsKey($t.name)) { $isIncomplete = $true } }
            $g | Add-Member -MemberType NoteProperty -Name Incomplete -Value $isIncomplete
            $graphs.Add($g)
        }
    }
    @($graphs | Sort-WfOrdinal -Key { [string]$_.database + [char]0 + [string]$_.schema + [char]0 + [string]$_.root })
}
