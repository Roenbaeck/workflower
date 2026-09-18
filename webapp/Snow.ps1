# Shared Snowflake CLI access. Dot-source this from launchers and from the server.
#
# Every statement goes through a temporary .sql file. `snow sql -q` corrupts dollar signs
# ("SELECT $$a;b$$" fails as session variable $A, and --enable-templating NONE does not
# help), and this project's template language is built on $token$ while its procedures are
# delimited by doubled dollars. Only -f is safe.
#
# Targets Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

$script:SnowExe = $null

function Get-SnowExe {
    if ($script:SnowExe) { return $script:SnowExe }
    $command = Get-Command snow -ErrorAction SilentlyContinue
    if ($command) { $script:SnowExe = $command.Source; return $script:SnowExe }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Snowflake CLI\snow.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Snowflake CLI\snow.exe')
    )) {
        if ($candidate -and (Test-Path $candidate)) { $script:SnowExe = $candidate; return $script:SnowExe }
    }
    throw 'Snowflake CLI (snow) was not found on PATH or in Program Files.'
}

function New-TempFile {
    param([Parameter(Mandatory = $true)][string] $Content,
          [string] $Extension = '.sql')
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + $Extension)
    # UTF-8 without a BOM. Out-File and Set-Content default to encodings that either add a
    # BOM or emit UTF-16, and a BOM breaks the first statement of the file.
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function New-RunId {
    return [guid]::NewGuid().ToString()
}

# The only values this codebase ever interpolates into SQL. Anything else must travel as a
# staged file, because `snow sql` has no bind variables.
function Assert-RunId {
    param([Parameter(Mandatory = $true)][string] $Value)
    if ($Value -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "Refusing to build SQL with a non-GUID run id: '$Value'"
    }
    return $Value
}

function Assert-Id {
    param([Parameter(Mandatory = $true)] $Value)
    $text = [string]$Value
    if ($text -notmatch '^[0-9]+$') {
        throw "Refusing to build SQL with a non-integer id: '$text'"
    }
    return $text
}

# ConvertFrom-Json emits a JSON array as a single pipeline item on PowerShell 7 but
# enumerates it on 5.1, so neither @() nor the pipeline yields a real array on both. An
# empty array is the dangerous case: wrapped, it has Count 1 and reads as "not empty".
# The leading comma on every return matters: PowerShell unrolls a returned array, so
# `return @()` yields nothing at all and the caller sees $null rather than an empty array.
function ConvertFrom-JsonArray {
    param([string] $Json)
    # Materialise into a fresh array rather than returning what ConvertFrom-Json gave back:
    # that value can carry a PSObject wrapper which ConvertTo-Json then renders as
    # {"value":[...],"Count":n} instead of a plain list.
    $list = New-Object System.Collections.Generic.List[object]
    if ($Json) {
        $parsed = ConvertFrom-Json -InputObject $Json
        if ($null -ne $parsed) {
            if ($parsed -is [System.Array]) { foreach ($item in $parsed) { $list.Add($item) } }
            else { $list.Add($parsed) }
        }
    }
    # The leading comma stops PowerShell unrolling the array back into nothing.
    return ,$list.ToArray()
}

# The single scalar a CALL returns, whatever the procedure was named.
function Get-CallResult {
    param($Json)
    $row = @($Json)[0]
    if (-not $row) { return $null }
    return ($row.psobject.Properties | Select-Object -First 1).Value
}

function Invoke-SnowSql {
    <#
        Runs SQL and returns a result object rather than throwing, so callers can map a
        failure onto an HTTP status. Trust ExitCode, not the output: on failure the CLI's
        JSON can be truncated and unparseable.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Sql,
        [Parameter(Mandatory = $true)][string] $Connection
    )
    $file = New-TempFile -Content $Sql
    try {
        # The CLI frames errors on stderr. With 2>&1 those arrive as error records, and a
        # caller running with $ErrorActionPreference = 'Stop' would throw on the first
        # border line instead of returning the failure. Keep it local to this call.
        $ErrorActionPreference = 'Continue'
        $output = & (Get-SnowExe) sql -c $Connection --enable-templating NONE --format JSON -f $file 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        $json = $null
        if ($exitCode -eq 0 -and $text.Trim()) {
            try { $json = $text | ConvertFrom-Json } catch { $json = $null }
        }
        return [pscustomobject]@{
            Success  = ($exitCode -eq 0)
            ExitCode = $exitCode
            Text     = $text
            Json     = $json
        }
    }
    finally {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SnowSqlChecked {
    param(
        [Parameter(Mandatory = $true)][string] $Sql,
        [Parameter(Mandatory = $true)][string] $Connection,
        [string] $Activity = 'Snowflake statement'
    )
    $result = Invoke-SnowSql -Sql $Sql -Connection $Connection
    if (-not $result.Success) {
        throw "$Activity failed (exit $($result.ExitCode)):" + [Environment]::NewLine + $result.Text
    }
    return $result
}

function Copy-ToStage {
    param(
        [Parameter(Mandatory = $true)][string] $LocalPath,
        [Parameter(Mandatory = $true)][string] $StagePath,
        [Parameter(Mandatory = $true)][string] $Connection
    )
    $ErrorActionPreference = 'Continue'
    # --no-auto-compress: EXECUTE IMMEDIATE FROM requires uncompressed UTF-8, and the raw
    # file format reads the bytes back verbatim.
    $output = & (Get-SnowExe) stage copy $LocalPath $StagePath --no-auto-compress --overwrite -c $Connection --format JSON 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        throw "Upload to $StagePath failed (exit $exitCode):" + [Environment]::NewLine + $text
    }
    return $text
}

function Copy-FromStage {
    param(
        [Parameter(Mandatory = $true)][string] $StagePath,
        [Parameter(Mandatory = $true)][string] $LocalDirectory,
        [Parameter(Mandatory = $true)][string] $Connection
    )
    $ErrorActionPreference = 'Continue'
    $output = & (Get-SnowExe) stage copy $StagePath $LocalDirectory -c $Connection --format JSON 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        throw "Download from $StagePath failed (exit $exitCode):" + [Environment]::NewLine + $text
    }
    return $text
}
