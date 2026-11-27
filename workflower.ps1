<#
.SYNOPSIS
    Opens the Workflower interface: the task graphs of a Snowflake account in the browser.
.DESCRIPTION
    Connects with a token through the SQL REST API (-Account and -TokenFile, or the environment variables SNOWFLAKE_ACCOUNT and
    SNOWFLAKE_TOKEN), or through the Snowflake CLI and one of its connections (-Connection, which is what to use for SSO). With -Demo it
    uses invented graphs and no account. The page is served on this machine only; Ctrl+C stops it.
.EXAMPLE
    .\workflower.ps1 -Connection default
.EXAMPLE
    .\workflower.ps1 -Account myorg-myaccount -TokenFile ~\.snowflake\pat.txt -Warehouse ETL_WH -Role SYSADMIN
.EXAMPLE
    .\workflower.ps1 -Demo
#>
[CmdletBinding(DefaultParameterSetName = 'Api')]
param(
    [Parameter(ParameterSetName = 'Api')][string] $Account = $env:SNOWFLAKE_ACCOUNT,
    [Parameter(ParameterSetName = 'Api')][string] $TokenFile,
    [Parameter(ParameterSetName = 'Cli', Mandatory = $true)][string] $Connection,
    [Parameter(ParameterSetName = 'Demo', Mandatory = $true)][switch] $Demo,
    [string] $Warehouse,
    [string] $Role,
    [int] $Port = 8765,
    [switch] $NoBrowser
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Workflower\Workflower.psd1') -Force
if ($PSCmdlet.ParameterSetName -eq 'Demo') { $session = New-WfSession -Demo }
elseif ($PSCmdlet.ParameterSetName -eq 'Cli') { $session = New-WfSession -Connection $Connection -Warehouse $Warehouse -Role $Role }
else {
    if (-not $Account) { throw 'Say which account: -Account, or SNOWFLAKE_ACCOUNT; or use -Connection for the Snowflake CLI, or -Demo.' }
    $arguments = @{ Account = $Account; Warehouse = $Warehouse; Role = $Role }
    if ($TokenFile) { $arguments.TokenFile = $TokenFile }
    $session = New-WfSession @arguments
}
Start-Workflower -Session $session -Port $Port -NoBrowser:$NoBrowser
