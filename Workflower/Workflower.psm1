# Workflower: read, check, compare, change and run Snowflake task graphs, whoever made them. Windows PowerShell 5.1 or later.
Set-StrictMode -Version 2.0

foreach ($file in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' | Sort-Object Name)) { . $file.FullName }
foreach ($file in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' | Sort-Object Name)) { . $file.FullName }

Export-ModuleMember -Function @(
    'New-WfSession', 'Invoke-WfSql',
    'Get-TaskGraph', 'Test-TaskGraph', 'ConvertTo-TaskGraphSql', 'Compare-TaskGraph', 'Publish-TaskGraph',
    'Export-TaskGraph', 'Import-TaskGraph',
    'Resume-TaskGraph', 'Suspend-TaskGraph', 'Start-TaskGraph', 'Get-TaskGraphRun'
)
