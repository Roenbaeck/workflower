function Export-TaskGraph {
    <#
    .SYNOPSIS
        Writes graphs to JSON files, one file for each graph, that can be kept in git and read back with Import-TaskGraph.
    .DESCRIPTION
        The file is <database>.<schema>.<root>.json. With -SplitDefinitions the SQL that each task runs is written to its own .sql file
        in a folder beside the JSON (and the JSON points to it), which makes a change to a task's SQL easy to read in a diff.
        Nothing is overwritten unless -Force is given. Read-only fields (owner, ids, times) are not written.
    .EXAMPLE
        Get-TaskGraph $s -Database ETL -Schema LOAD | Export-TaskGraph -Directory .\graphs -SplitDefinitions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] $Graph,
        [Parameter(Mandatory = $true)][string] $Directory,
        [switch] $SplitDefinitions,
        [switch] $NoState,
        [switch] $Force
    )
    process {
        if (-not (Test-Path -LiteralPath $Directory)) { New-Item -ItemType Directory -Path $Directory | Out-Null }
        $base = ((@($Graph.database, $Graph.schema, $Graph.root) | Where-Object { $_ }) -join '.') -replace '[^\p{L}\p{N}_.\-]+', '_'
        $path = Join-Path $Directory ($base + '.json')
        if ((Test-Path -LiteralPath $path) -and -not $Force) { throw "Refusing to overwrite $path (use -Force)." }
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $tasks = New-Object System.Collections.Generic.List[object]
        $folder = Join-Path $Directory ($base + '.d')
        foreach ($t in @($Graph.tasks)) {
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
            if ($SplitDefinitions) {
                if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
                $file = (($t.name -replace '[^\p{L}\p{N}_.\-]+', '_') + '.sql')
                $sqlPath = Join-Path $folder $file
                if ((Test-Path -LiteralPath $sqlPath) -and -not $Force) { throw "Refusing to overwrite $sqlPath (use -Force)." }
                [System.IO.File]::WriteAllText($sqlPath, (([string]$t.definition).TrimEnd() + "`n"), $utf8)
                $o.definitionFile = ($base + '.d/' + $file)
            } else { $o.definition = $t.definition }
            $tasks.Add($o)
        }
        $doc = [ordered]@{ format = 'workflower-graph'; version = 1; database = $Graph.database; schema = $Graph.schema; tasks = $tasks.ToArray() }
        [System.IO.File]::WriteAllText($path, ((ConvertTo-WfJson $doc) + "`n"), $utf8)
        Get-Item -LiteralPath $path
    }
}

function Import-TaskGraph {
    <#
    .SYNOPSIS
        Reads graphs from JSON files made by Export-TaskGraph (or written by hand), from a file or every .json file in a folder.
    .DESCRIPTION
        -Database, -Schema and -Warehouse replace what the file says, which is how one file is installed in development and in
        production: the warehouse is replaced on every task that has one. Names are exact: a name is written as Snowflake stores it.
    .EXAMPLE
        Import-TaskGraph .\graphs\ETL.LOAD.LOAD_ROOT.json -Database ETL_PROD -Warehouse PROD_WH | Publish-TaskGraph -Session $s
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)][string] $Path,
        [string] $Database,
        [string] $Schema,
        [string] $Warehouse
    )
    process {
        $files = @()
        if (Test-Path -LiteralPath $Path -PathType Container) { $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.json' -File | Sort-Object Name) }
        else { $files = @(Get-Item -LiteralPath $Path) }
        foreach ($file in $files) {
            $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $doc = (ConvertFrom-WfJson $text)
            if (-not ($doc -is [System.Collections.IDictionary]) -or -not (Test-WfHas $doc 'tasks')) { throw ($file.Name + ': not a task graph file (it has no "tasks").') }
            $format = Get-WfValue $doc 'format'
            if ($format -and $format -ne 'workflower-graph') { throw ($file.Name + ": unknown format '" + $format + "'.") }
            $tasks = New-Object System.Collections.Generic.List[object]
            foreach ($item in @(Get-WfValue $doc 'tasks')) {
                $copy = [ordered]@{}
                foreach ($k in $item.Keys) { $copy[$k] = $item[$k] }
                if ($copy.Contains('definitionFile')) {
                    $sqlPath = Join-Path $file.DirectoryName ([string]$copy['definitionFile'])
                    if (-not (Test-Path -LiteralPath $sqlPath)) { throw ($file.Name + ": task '" + $copy['name'] + "': the definition file " + $copy['definitionFile'] + ' is not there.') }
                    $copy['definition'] = [System.IO.File]::ReadAllText($sqlPath, [System.Text.Encoding]::UTF8).TrimEnd()
                    $copy.Remove('definitionFile')
                }
                try { $task = ConvertTo-WfTask $copy } catch { throw ($file.Name + ': ' + $_.Exception.Message) }
                if ($Warehouse -and $task.warehouse) { $task.warehouse = $Warehouse }
                $tasks.Add($task)
            }
            $db = [string](Get-WfValue $doc 'database'); $sc = [string](Get-WfValue $doc 'schema')
            if ($Database) { $db = $Database }
            if ($Schema) { $sc = $Schema }
            $g = New-WfGraphObject $db $sc $null $tasks.ToArray()
            Update-WfGraph $g
        }
    }
}
