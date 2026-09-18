# Endpoint handlers for the local editor.
#
# Workflows are addressed by CF_ID, not by name, so nothing a user typed is ever
# interpolated into SQL. Save uploads the document to the stage and Snowflake reads the
# name out of it. The only values that reach SQL from here are integers and GUIDs, and
# both Assert-Id and Assert-RunId refuse anything else.
#
# Targets Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

function New-ApiResult {
    param([int] $Status = 200, $Body = $null)
    return [pscustomobject]@{ Status = $Status; Body = $Body }
}

function New-ApiError {
    param([int] $Status, [string] $Detail)
    return New-ApiResult -Status $Status -Body ([pscustomobject]@{ detail = $Detail })
}

# A Snowflake failure is reported, never retried: a partly applied install must not be
# replayed automatically.
function ConvertTo-ApiError {
    param([string] $Text, [int] $Status = 502)
    # The CLI frames errors in a box. Drop the box-drawing block outright rather than
    # trying to recognise border lines, then collapse what is left into one message.
    $clean = $Text -replace '[─-╿]', ' '
    $detail = (($clean -split "`r?`n") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -ne 'Error' } ) -join ' '
    $detail = ($detail -replace '\s{2,}', ' ').Trim()
    if (-not $detail) { $detail = 'Snowflake reported an error.' }
    return New-ApiError -Status $Status -Detail $detail
}

function Get-WorkflowList {
    param([Parameter(Mandatory = $true)][string] $Connection)
    $sql = @'
SELECT CF_ID, CF_NAM_Configuration_Name AS NAME, CF_TYP_CFT_ConfigurationType AS TYPE
FROM metadata.lCF_Configuration
WHERE CF_TYP_CFT_ConfigurationType = 'Workflow'
ORDER BY CF_NAM_Configuration_Name;
'@
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }

    $rows = @()
    foreach ($row in @($result.Json)) {
        if ($null -eq $row) { continue }
        $rows += [pscustomobject]@{ cf_id = $row.CF_ID; name = $row.NAME; type = $row.TYPE }
    }
    return New-ApiResult -Body $rows
}

function Get-Workflow {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId,
          [ValidateSet('Workflow', 'Environment')][string] $ConfigType = 'Workflow')
    $id = Assert-Id $CfId
    $sql = @"
SELECT CF_ID, CF_NAM_Configuration_Name AS NAME, CF_CNT_Configuration_Content AS CONTENT
FROM metadata.lCF_Configuration
WHERE CF_ID = $id AND CF_TYP_CFT_ConfigurationType = '$ConfigType';
"@
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }

    $row = @($result.Json)[0]
    if ($null -eq $row) { return New-ApiError -Status 404 -Detail "$ConfigType not found" }
    return New-ApiResult -Body ([pscustomobject]@{
        cf_id = $row.CF_ID; name = $row.NAME; content = $row.CONTENT
    })
}

function Save-Workflow {
    <#
        $Body is the raw request text, written to the stage exactly as received. It is not
        parsed and re-serialised here: Snowflake stores the original bytes, and passing it
        through ConvertTo-Json would reorder keys and, at the 5.1 default depth, silently
        truncate the document.
    #>
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)][string] $Body,
          $PreviousCfId = $null,
          [ValidateSet('Workflow', 'Environment')][string] $ConfigType = 'Workflow')

    try { $Body | ConvertFrom-Json | Out-Null }
    catch { return New-ApiError -Status 400 -Detail "Workflow JSON is invalid: $($_.Exception.Message)" }

    $runId = Assert-RunId (New-RunId)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "$runId.json"
    [System.IO.File]::WriteAllText($path, $Body, (New-Object System.Text.UTF8Encoding($false)))
    try {
        Copy-ToStage -LocalPath $path -StagePath '@metadata.WORKFLOWER/in/' -Connection $Connection | Out-Null
    }
    catch { return New-ApiError -Status 502 -Detail $_.Exception.Message }
    finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }

    $previous = 'NULL'
    if ($PreviousCfId) { $previous = Assert-Id $PreviousCfId }
    $result = Invoke-SnowSql -Sql "CALL metadata._ConfigurationUpsertFromStage('$runId', $previous, '$ConfigType');" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }

    $row = @($result.Json)[0]
    $payload = $null
    if ($row) { $payload = ($row.psobject.Properties | Select-Object -First 1).Value | ConvertFrom-Json }
    return New-ApiResult -Body $payload
}

function Remove-Workflow {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId)
    $id = Assert-Id $CfId
    $result = Invoke-SnowSql -Sql "CALL metadata._ConfigurationDeleteById($id);" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    return New-ApiResult -Body ([pscustomobject]@{ status = 'deleted'; cf_id = [int]$id })
}

# The client executes the DDL, so it is the only thing that knows the outcome. Recording it
# must never turn a successful install into a reported failure, nor mask the real error on a
# failed one, so this reports its own problems and returns.
function Write-InstallationOutcome {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)][string] $RunId,
          [Parameter(Mandatory = $true)][ValidateSet('Installed', 'Failed')][string] $Status,
          [string] $ErrorText)

    $runId = Assert-RunId $RunId
    $sql = "CALL metadata._InstallationCompleted('$runId', '$Status', NULL);"
    if ($ErrorText) {
        # The only place a message crosses into SQL. Snowflake literals need both the quote
        # and the backslash escaped.
        $escaped = $ErrorText.Replace('\', '\\').Replace("'", "''")
        if ($escaped.Length -gt 2000) { $escaped = $escaped.Substring(0, 2000) }
        $sql = "CALL metadata._InstallationCompleted('$runId', '$Status', '$escaped');"
    }
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    if (-not $result.Success) {
        Write-Host "[warn] Could not record the installation outcome for $runId"
    }
}

function Install-Workflow {
    <#
        Render to the stage, then EXECUTE IMMEDIATE FROM that file. Execution stops at the
        first failing statement and leaves earlier ones applied, so a failure is reported
        with the rendered file's run id and the line Snowflake named.
    #>
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId,
          [string] $Template = 'CreateTaskGraph',
          $EnvironmentCfId = $null)

    $id = Assert-Id $CfId
    $runId = Assert-RunId (New-RunId)
    $env = 'NULL'
    if ($EnvironmentCfId) { $env = Assert-Id $EnvironmentCfId }

    # Validate first, so a cycle or a missing predecessor is reported as a list of problems
    # rather than as a half-applied install.
    $check = Invoke-SnowSql -Sql "CALL metadata._ValidateWorkflowById($id, $env);" -Connection $Connection
    if ($check.Success) {
        $problems = ConvertFrom-JsonArray (Get-CallResult $check.Json)
        if ($problems.Count -gt 0) {
            return New-ApiResult -Status 400 -Body ([pscustomobject]@{
                detail   = 'The workflow graph is not valid'
                problems = $problems
            })
        }
    }

    $result = Invoke-SnowSql -Sql "CALL metadata._RenderToStage($id, '$Template', '$runId', $env);" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }

    $render = $null
    $row = @($result.Json)[0]
    if ($row) { $render = ($row.psobject.Properties | Select-Object -First 1).Value | ConvertFrom-Json }

    $result = Invoke-SnowSql -Sql "EXECUTE IMMEDIATE FROM @metadata.WORKFLOWER/out/$runId.sql;" -Connection $Connection
    if (-not $result.Success) {
        # $error is an automatic variable in PowerShell; do not shadow it.
        $apiError = ConvertTo-ApiError -Text $result.Text
        $line = $null
        if ($result.Text -match 'on line (\d+)') { $line = [int]$Matches[1] }
        Write-InstallationOutcome -Connection $Connection -RunId $runId -Status 'Failed' -ErrorText $apiError.Body.detail
        $apiError.Body = [pscustomobject]@{
            detail  = $apiError.Body.detail
            run_id  = $runId
            line    = $line
            partial = $true
        }
        return $apiError
    }

    Write-InstallationOutcome -Connection $Connection -RunId $runId -Status 'Installed'

    return New-ApiResult -Body ([pscustomobject]@{
        cf_id  = [int]$id
        run_id = $runId
        lines  = $(if ($render) { $render.lines } else { $null })
        bytes  = $(if ($render) { $render.bytes } else { $null })
        status = 'installed'
    })
}

function Get-RenderedSql {
    # The rendered SQL is kept on the stage as an audit trail; the editor fetches it to
    # show the statement that failed.
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)][string] $RunId)
    $runId = Assert-RunId $RunId
    $result = Invoke-SnowSql -Sql "CALL metadata._StageReadText('out/$runId.sql');" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $row = @($result.Json)[0]
    $sql = $null
    if ($row) { $sql = ($row.psobject.Properties | Select-Object -First 1).Value }
    if (-not $sql) { return New-ApiError -Status 404 -Detail 'Rendered SQL not found' }
    return New-ApiResult -Body ([pscustomobject]@{ run_id = $runId; sql = $sql })
}

function Import-TaskGraphs {
    <#
        Reverse engineers native task graphs. Read-only with respect to Snowflake tasks.
        The schema and root are user-supplied identifiers, so they travel to Snowflake as a
        staged parameter file rather than in the SQL.
    #>
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)][string] $Schema,
          [string] $Root)

    $paramsRunId = Assert-RunId (New-RunId)
    $outRunId = Assert-RunId (New-RunId)

    $params = @{ schema = $Schema }
    if ($Root) { $params['root'] = $Root }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "$paramsRunId.json"
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $params -Compress), (New-Object System.Text.UTF8Encoding($false)))
    try {
        Copy-ToStage -LocalPath $path -StagePath '@metadata.WORKFLOWER/in/' -Connection $Connection | Out-Null
    }
    catch { return New-ApiError -Status 502 -Detail $_.Exception.Message }
    finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }

    $result = Invoke-SnowSql -Sql "CALL metadata._ExportTaskGraphs('$paramsRunId', '$outRunId');" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }

    $row = @($result.Json)[0]
    $json = $null
    if ($row) { $json = ($row.psobject.Properties | Select-Object -First 1).Value }
    if (-not $json) { return New-ApiError -Status 502 -Detail 'The export produced no output' }
    $payload = $json | ConvertFrom-Json

    return New-ApiResult -Body ([pscustomobject]@{ run_id = $outRunId; graphs = $payload.export })
}

# Returns the array of problems, empty when the graph is sound.
function Test-Workflow {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId,
          $EnvironmentCfId = $null)
    $id = Assert-Id $CfId
    $env = 'NULL'
    if ($EnvironmentCfId) { $env = Assert-Id $EnvironmentCfId }
    $result = Invoke-SnowSql -Sql "CALL metadata._ValidateWorkflowById($id, $env);" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $problems = ConvertFrom-JsonArray (Get-CallResult $result.Json)
    return New-ApiResult -Body ([pscustomobject]@{ cf_id = [int]$id; valid = ($problems.Count -eq 0); problems = $problems })
}

# --- Operating an installed workflow ---------------------------------------------------
# Installing a graph is not running one. These report and change what the tasks are doing.

function Get-WorkflowTaskStates {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId)
    $id = Assert-Id $CfId
    $result = Invoke-SnowSql -Sql "CALL metadata._WorkflowTaskStates($id);" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $states = ConvertFrom-JsonArray (Get-CallResult $result.Json)
    return New-ApiResult -Body ([pscustomobject]@{ cf_id = [int]$id; tasks = $states })
}

function Set-WorkflowState {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId,
          [Parameter(Mandatory = $true)][ValidateSet('running', 'suspended')][string] $State)
    $id = Assert-Id $CfId
    $result = Invoke-SnowSql -Sql "CALL metadata._SetWorkflowState($id, '$State');" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $row = @($result.Json)[0]
    $payload = $null
    if ($row) { $payload = ($row.psobject.Properties | Select-Object -First 1).Value | ConvertFrom-Json }
    return New-ApiResult -Body $payload
}

function Start-WorkflowRun {
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId)
    $id = Assert-Id $CfId
    $result = Invoke-SnowSql -Sql "CALL metadata._ExecuteWorkflow($id);" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $row = @($result.Json)[0]
    $payload = $null
    if ($row) { $payload = ($row.psobject.Properties | Select-Object -First 1).Value | ConvertFrom-Json }
    # EXECUTE TASK needs a privilege the role may not hold; the procedure reports that
    # rather than failing, so surface it as a real status.
    if ($payload -and -not $payload.executed) {
        return New-ApiResult -Status 403 -Body ([pscustomobject]@{
            detail = $payload.error; task = $payload.task
        })
    }
    return New-ApiResult -Body $payload
}

function Get-Environments {
    param([Parameter(Mandatory = $true)][string] $Connection)
    $sql = @'
SELECT CF_ID, CF_NAM_Configuration_Name AS NAME
FROM metadata.lCF_Configuration
WHERE CF_TYP_CFT_ConfigurationType = 'Environment'
ORDER BY CF_NAM_Configuration_Name;
'@
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $rows = @()
    foreach ($row in @($result.Json)) {
        if ($null -eq $row) { continue }
        $rows += [pscustomobject]@{ cf_id = $row.CF_ID; name = $row.NAME }
    }
    return New-ApiResult -Body $rows
}

function Get-Report {
    # The model has always collected runs, lineage and row counts; nothing surfaced them.
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)][ValidateSet('TaskRuns', 'GraphRuns', 'Lineage', 'ContainerFlow', 'Installations')][string] $View,
          [int] $Limit = 100)
    if ($Limit -lt 1 -or $Limit -gt 1000) { $Limit = 100 }
    $order = @{ TaskRuns = 'STARTED_AT'; GraphRuns = 'STARTED_AT'; Lineage = 'STARTED_AT'
                ContainerFlow = 'LAST_SEEN'; Installations = 'RENDERED_AT' }[$View]
    $result = Invoke-SnowSql -Sql "SELECT * FROM metadata.$View ORDER BY $order DESC NULLS LAST LIMIT $Limit;" -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }
    $rows = @()
    foreach ($row in @($result.Json)) { if ($null -ne $row) { $rows += $row } }
    return New-ApiResult -Body $rows
}

function Get-ConnectionStatus {
    param([Parameter(Mandatory = $true)][string] $Connection)
    $result = Invoke-SnowSql -Sql 'SELECT CURRENT_ACCOUNT() AS ACCOUNT, CURRENT_USER() AS USER, CURRENT_ROLE() AS ROLE, CURRENT_WAREHOUSE() AS WAREHOUSE, CURRENT_DATABASE() AS DATABASE;' -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text -Status 503 }
    $row = @($result.Json)[0]
    return New-ApiResult -Body ([pscustomobject]@{
        status    = 'connected'
        account   = $row.ACCOUNT
        user      = $row.USER
        role      = $row.ROLE
        warehouse = $row.WAREHOUSE
        database  = $row.DATABASE
    })
}
