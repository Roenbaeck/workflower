# Talking to Snowflake. A session is either the SQL REST API with a token (nothing to install; a programmatic access token,
# an OAuth token or a key-pair JWT) or the Snowflake CLI (snow) with a connection profile, which is what to use for SSO.
# Both run one statement at a time and give back its rows as objects whose properties are the result's column names.

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function New-WfSession {
    <#
    .SYNOPSIS
        Makes the session that the other commands use.
    .DESCRIPTION
        With -Account and a token: the SQL REST API. The token is read from -Token, from the file -TokenFile, or from the
        environment variable SNOWFLAKE_TOKEN. With -Connection: the Snowflake CLI and the connection profile of that name.
    .EXAMPLE
        $s = New-WfSession -Account myorg-myaccount -TokenFile ~\.snowflake\pat.txt -Warehouse WH -Role SYSADMIN
    .EXAMPLE
        $s = New-WfSession -Connection default
    #>
    [CmdletBinding(DefaultParameterSetName = 'Api')]
    param(
        [Parameter(ParameterSetName = 'Api', Mandatory = $true)][string] $Account,
        [Parameter(ParameterSetName = 'Api')][string] $AccountUrl,
        [Parameter(ParameterSetName = 'Api')][string] $Token,
        [Parameter(ParameterSetName = 'Api')][string] $TokenFile,
        [Parameter(ParameterSetName = 'Api')][ValidateSet('PROGRAMMATIC_ACCESS_TOKEN', 'OAUTH', 'KEYPAIR_JWT')][string] $TokenType = 'PROGRAMMATIC_ACCESS_TOKEN',
        [Parameter(ParameterSetName = 'Cli', Mandatory = $true)][string] $Connection,
        [string] $Warehouse,
        [string] $Role
    )
    if ($PSCmdlet.ParameterSetName -eq 'Cli') {
        return [pscustomobject]@{ Backend = 'Cli'; Connection = $Connection; Warehouse = $Warehouse; Role = $Role }
    }
    if (-not $Token -and $TokenFile) { $Token = (Get-Content -LiteralPath $TokenFile -Raw).Trim() }
    if (-not $Token -and $env:SNOWFLAKE_TOKEN) { $Token = $env:SNOWFLAKE_TOKEN }
    if (-not $Token) { throw 'No token: give -Token or -TokenFile, or set SNOWFLAKE_TOKEN.' }
    if (-not $AccountUrl) { $AccountUrl = 'https://' + $Account.ToLowerInvariant().Replace('_', '-') + '.snowflakecomputing.com' }
    [pscustomobject]@{
        Backend = 'Api'; AccountUrl = $AccountUrl.TrimEnd('/'); Token = $Token; TokenType = $TokenType
        Warehouse = $Warehouse; Role = $Role
    }
}

function Invoke-WfSql {
    <#
    .SYNOPSIS
        Runs one SQL statement and returns its rows (objects whose properties are the columns; every value is text or null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Session,
        [Parameter(Mandatory = $true)][string] $Sql,
        [string] $Database,
        [string] $Schema,
        [int] $TimeoutSeconds = 300
    )
    if ($Session.Backend -eq 'Cli') { return (Invoke-WfCli $Session $Sql $Database $Schema) }
    Invoke-WfApi $Session $Sql $Database $Schema $TimeoutSeconds
}

function Read-WfResponse {
    param($Response)
    $ms = New-Object System.IO.MemoryStream
    $Response.RawContentStream.CopyTo($ms)
    [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Get-WfApiError {
    param($ErrorRecord)
    $resp = $null
    try { $resp = $ErrorRecord.Exception.Response } catch { }
    if (-not $resp) { return $ErrorRecord.Exception.Message }
    $text = ''
    try { $text = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch { }
    $code = [int]$resp.StatusCode
    $message = $text
    try {
        $o = ConvertFrom-WfJson $text
        if ($o -is [System.Collections.IDictionary] -and $o.ContainsKey("message")) { $message = [string]$o["message"] }
    } catch { }
    if ($code -eq 401) { $message = "$message (HTTP 401: the token was refused; for a programmatic access token check its network policy and that it has not expired)" }
    "Snowflake: $message"
}

function Invoke-WfApi {
    param($Session, [string] $Sql, [string] $Database, [string] $Schema, [int] $TimeoutSeconds)
    $body = @{ statement = $Sql; timeout = $TimeoutSeconds }
    if ($Session.Warehouse) { $body.warehouse = $Session.Warehouse }
    if ($Session.Role) { $body.role = $Session.Role }
    if ($Database) { $body.database = $Database }
    if ($Schema) { $body.schema = $Schema }
    $headers = @{
        Authorization = "Bearer $($Session.Token)"
        'X-Snowflake-Authorization-Token-Type' = $Session.TokenType
        Accept = 'application/json'
        'User-Agent' = 'Workflower/1.0'
    }
    $json = ConvertTo-Json $body -Depth 5 -Compress
    try {
        $r = Invoke-WebRequest -Uri ($Session.AccountUrl + '/api/v2/statements') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -UseBasicParsing
    } catch { throw (Get-WfApiError $_) }
    $o = (ConvertFrom-WfJson (Read-WfResponse $r))
    $waited = 0
    while ([int]$r.StatusCode -eq 202) {
        if ($waited -gt $TimeoutSeconds) { throw "Snowflake: the statement did not finish within $TimeoutSeconds seconds." }
        Start-Sleep -Milliseconds 1000; $waited++
        try {
            $r = Invoke-WebRequest -Uri ($Session.AccountUrl + [string]$o['statementStatusUrl']) -Headers $headers -UseBasicParsing
        } catch { throw (Get-WfApiError $_) }
        $o = (ConvertFrom-WfJson (Read-WfResponse $r))
    }
    $meta = $o['resultSetMetaData']
    if (-not $meta) { return ,@() }
    $names = @($meta['rowType'] | ForEach-Object { [string]$_['name'] })
    $data = New-Object System.Collections.Generic.List[object]
    if ($o['data']) { foreach ($row in $o['data']) { $data.Add($row) } }
    $partitions = 1
    if ($meta['partitionInfo']) { $partitions = @($meta['partitionInfo']).Count }
    for ($p = 1; $p -lt $partitions; $p++) {
        try {
            $pr = Invoke-WebRequest -Uri ($Session.AccountUrl + '/api/v2/statements/' + [string]$o['statementHandle'] + '?partition=' + $p) -Headers $headers -UseBasicParsing
        } catch { throw (Get-WfApiError $_) }
        $po = (ConvertFrom-WfJson (Read-WfResponse $pr))
        foreach ($row in $po['data']) { $data.Add($row) }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $data) {
        $h = [ordered]@{}
        for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $row[$i] }
        $rows.Add([pscustomobject]$h)
    }
    $array = $rows.ToArray()
    ,$array
}

$script:WfSnowExe = $null
function Get-WfSnowExe {
    if ($script:WfSnowExe) { return $script:WfSnowExe }
    $command = Get-Command snow -ErrorAction SilentlyContinue
    if ($command) { $script:WfSnowExe = $command.Source; return $script:WfSnowExe }
    foreach ($candidate in @((Join-Path $env:ProgramFiles 'Snowflake CLI\snow.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Snowflake CLI\snow.exe'))) {
        if ($candidate -and (Test-Path $candidate)) { $script:WfSnowExe = $candidate; return $script:WfSnowExe }
    }
    throw 'The Snowflake CLI (snow) was not found on PATH or in Program Files.'
}

function Invoke-WfCli {
    param($Session, [string] $Sql, [string] $Database, [string] $Schema)
    # through a file: `snow sql -q` mangles dollar signs, and task bodies are full of them
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + '.sql')
    [System.IO.File]::WriteAllText($file, $Sql, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $arguments = @('sql', '-c', $Session.Connection, '--enable-templating', 'NONE', '--format', 'JSON', '-f', $file)
        if ($Session.Warehouse) { $arguments += @('--warehouse', $Session.Warehouse) }
        if ($Session.Role) { $arguments += @('--role', $Session.Role) }
        if ($Database) { $arguments += @('--database', $Database) }
        if ($Schema) { $arguments += @('--schema', $Schema) }
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = & (Get-WfSnowExe) @arguments 2>&1; $exit = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
        $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ($exit -ne 0) { throw ('Snowflake CLI failed (exit ' + $exit + '):' + [Environment]::NewLine + $text) }
        if (-not $text.Trim()) { return ,@() }
        $parsed = (ConvertFrom-WfJson $text)
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($parsed)) {
            if ($item -is [System.Collections.IDictionary]) {
                $h = [ordered]@{}
                foreach ($k in $item.Keys) { $h[[string]$k] = $item[$k] }
                $rows.Add([pscustomobject]$h)
            }
        }
        $array = $rows.ToArray()
        ,$array
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}
