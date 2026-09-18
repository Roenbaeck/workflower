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
          [Parameter(Mandatory = $true)] $CfId)
    $id = Assert-Id $CfId
    $sql = @"
SELECT CF_ID, CF_NAM_Configuration_Name AS NAME, CF_CNT_Configuration_Content AS CONTENT
FROM metadata.lCF_Configuration
WHERE CF_ID = $id AND CF_TYP_CFT_ConfigurationType = 'Workflow';
"@
    $result = Invoke-SnowSql -Sql $sql -Connection $Connection
    if (-not $result.Success) { return ConvertTo-ApiError -Text $result.Text }

    $row = @($result.Json)[0]
    if ($null -eq $row) { return New-ApiError -Status 404 -Detail 'Workflow not found' }
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
          $PreviousCfId = $null)

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
    $result = Invoke-SnowSql -Sql "CALL metadata._ConfigurationUpsertFromStage('$runId', $previous);" -Connection $Connection
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

function Install-Workflow {
    <#
        Render to the stage, then EXECUTE IMMEDIATE FROM that file. Execution stops at the
        first failing statement and leaves earlier ones applied, so a failure is reported
        with the rendered file's run id and the line Snowflake named.
    #>
    param([Parameter(Mandatory = $true)][string] $Connection,
          [Parameter(Mandatory = $true)] $CfId,
          [string] $Template = 'CreateTaskGraph')

    $id = Assert-Id $CfId
    $runId = Assert-RunId (New-RunId)

    $result = Invoke-SnowSql -Sql "CALL metadata._RenderToStage($id, '$Template', '$runId');" -Connection $Connection
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
        $apiError.Body = [pscustomobject]@{
            detail  = $apiError.Body.detail
            run_id  = $runId
            line    = $line
            partial = $true
        }
        return $apiError
    }

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
