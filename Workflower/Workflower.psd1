@{
    RootModule        = 'Workflower.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5d6c8a0e-3f4b-4f7e-9a41-1b6a0c7d2e55'
    Author            = 'Workflower'
    Description       = 'Read, check, compare, change and run Snowflake task graphs, whoever made them.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-WfSession', 'Invoke-WfSql',
        'Get-TaskGraph', 'Test-TaskGraph', 'ConvertTo-TaskGraphSql', 'Compare-TaskGraph', 'Publish-TaskGraph',
        'Export-TaskGraph', 'Import-TaskGraph',
        'Resume-TaskGraph', 'Suspend-TaskGraph', 'Start-TaskGraph', 'Get-TaskGraphRun', 'Start-Workflower'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
