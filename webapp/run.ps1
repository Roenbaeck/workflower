<#
    Start the Workflower editor.

    Usage: .\webapp\run.ps1 <connection_name> [-Port 8000]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection,
    [int] $Port = 8000
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $here 'Server.ps1') -Connection $Connection -Port $Port
