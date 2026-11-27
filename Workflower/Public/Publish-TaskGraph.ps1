function Publish-TaskGraph {
    <#
    .SYNOPSIS
        Makes the installed graph the graph that is wanted: plans the change, shows it, and runs the steps.
    .DESCRIPTION
        The steps are those of Compare-TaskGraph, run one by one; the first that fails stops the rest, and the error says which steps
        were done, because Snowflake has no transaction for DDL. With -WhatIf nothing is run and the plan is returned. A graph that is
        already as wanted is left alone. Pass a plan that you have looked at with -Plan, to run exactly that.
    .EXAMPLE
        Import-TaskGraph .\load.json | Publish-TaskGraph -Session $s -WhatIf
    .EXAMPLE
        Import-TaskGraph .\load.json | Publish-TaskGraph -Session $s
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Graph')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Graph')] $Graph,
        [Parameter(Mandatory = $true, ParameterSetName = 'Plan')] $Plan,
        [Parameter(Mandatory = $true)] $Session,
        [switch] $SkipValidation
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Graph') {
            if (-not $SkipValidation) {
                $errors = @(Test-TaskGraph $Graph | Where-Object { $_.Severity -eq 'error' })
                if ($errors.Count -gt 0) { throw ("The graph is not valid:`n" + (($errors | ForEach-Object { '  ' + $_.Message }) -join "`n")) }
            }
            $Plan = Compare-TaskGraph $Graph -Session $Session
        }
        if ($Plan.IsEmpty) { return $Plan }
        if (-not $PSCmdlet.ShouldProcess(($Plan.Database + '.' + $Plan.Schema + ' ' + $Plan.Root), ('run ' + @($Plan.Steps).Count + ' steps'))) { return $Plan }
        $done = 0
        foreach ($s in @($Plan.Steps)) {
            try {
                Invoke-WfSql $Session $s.Sql | Out-Null
            } catch {
                $applied = ''
                if ($done -gt 0) { $applied = " Steps 1 to $done were done:`n" + ((@($Plan.Steps)[0..($done - 1)] | ForEach-Object { '  ' + ($_.Sql -split "`n")[0] }) -join "`n") }
                throw ("Step " + ($done + 1) + " of " + @($Plan.Steps).Count + " failed (" + ($s.Sql -split "`n")[0] + '): ' + $_.Exception.Message + '.' + $applied + "`nThe graph is left as it is; run the command again to continue from here.")
            }
            $done++
        }
        $Plan | Add-Member -MemberType NoteProperty -Name Executed -Value $done -Force
        $Plan
    }
}
