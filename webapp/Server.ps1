<#
    Local HTTP server for the Workflower editor.

    A single-user administrative tool: it binds to the loopback address, serves only an
    explicit list of browser assets, and rejects cross-origin writes. It has no
    authentication and must not be exposed to a network.

    There is no connection pool. Each request shells out to `snow`, which authenticates
    from the named profile in config.toml, so there is no shared session to lease,
    validate or lose.

    Usage: .\Server.ps1 <connection_name> [-Port 8000]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string] $Connection,
    [int] $Port = 8000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Snow.ps1')
. (Join-Path $here 'Workflows.ps1')

# Only browser assets are public; never serve scripts or config files.
$PublicFiles = @{
    'index.html' = 'text/html; charset=utf-8'
    'editor.css' = 'text/css; charset=utf-8'
    'LayoutEngine.js' = 'application/javascript; charset=utf-8'
    'sisula.js' = 'application/javascript; charset=utf-8'
    'Snowflower.svg' = 'image/svg+xml'
    'site.webmanifest' = 'application/manifest+json'
    'favicon.ico' = 'image/x-icon'
    'favicon-16x16.png' = 'image/png'
    'favicon-32x32.png' = 'image/png'
    'apple-touch-icon.png' = 'image/png'
    'android-chrome-192x192.png' = 'image/png'
    'android-chrome-512x512.png' = 'image/png'
    'templates/CreateTaskGraph.sql' = 'text/plain; charset=utf-8'
    'templates/CreateTypedTables.sql' = 'text/plain; charset=utf-8'
}

function Write-Response {
    param($Context, [int] $Status, $Body, [string] $ContentType = 'application/json; charset=utf-8')
    $response = $Context.Response
    $response.StatusCode = $Status
    $response.ContentType = $ContentType
    $response.Headers['Cache-Control'] = 'no-store'
    # Blunts both the CDN script and the innerHTML use in the editor.
    $response.Headers['Content-Security-Policy'] =
        "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com; " +
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; " +
        "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
    $response.Headers['X-Content-Type-Options'] = 'nosniff'
    $response.Headers['Referrer-Policy'] = 'no-referrer'

    if ($Body -is [byte[]]) { $bytes = $Body }
    elseif ($Body -is [string]) { $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body) }
    else {
        # -InputObject rather than the pipeline: piping unrolls a one-element array and
        # ConvertTo-Json then emits an object where the editor expects a list.
        # -Depth 100 because the 5.1 default of 2 silently truncates nested structures.
        $json = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
        # An empty array serialises to nothing at all.
        if ($null -eq $json) { $json = $(if ($Body -is [System.Array]) { '[]' } else { 'null' }) }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function Read-RequestBody {
    param($Context)
    $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, [System.Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Invoke-Route {
    param($Context, [string] $Method, [string] $Path)

    if ($Path -eq '/api/workflows' -and $Method -eq 'GET') {
        return Get-WorkflowList -Connection $Connection
    }
    if ($Path -eq '/api/workflows' -and $Method -eq 'PUT') {
        # ?previous=<cf_id> retires the configuration this save renames away from.
        $previous = $Context.Request.QueryString['previous']
        return Save-Workflow -Connection $Connection -Body (Read-RequestBody $Context) -PreviousCfId $previous
    }
    if ($Path -eq '/api/connection/status' -and $Method -eq 'GET') {
        return Get-ConnectionStatus -Connection $Connection
    }
    if ($Path -match '^/api/workflows/(\d+)$') {
        if ($Method -eq 'GET')    { return Get-Workflow -Connection $Connection -CfId $Matches[1] }
        if ($Method -eq 'DELETE') { return Remove-Workflow -Connection $Connection -CfId $Matches[1] }
    }
    if ($Path -match '^/api/workflows/(\d+)/install$' -and $Method -eq 'POST') {
        return Install-Workflow -Connection $Connection -CfId $Matches[1]
    }
    if ($Path -match '^/api/rendered/([0-9a-fA-F-]{36})$' -and $Method -eq 'GET') {
        return Get-RenderedSql -Connection $Connection -RunId $Matches[1]
    }
    if ($Path.StartsWith('/api/')) {
        return New-ApiError -Status 404 -Detail 'Not found'
    }

    # Static assets.
    if ($Method -ne 'GET') { return New-ApiError -Status 405 -Detail 'Method not allowed' }
    $relative = $Path.TrimStart('/')
    if (-not $relative) { $relative = 'index.html' }
    if (-not $PublicFiles.ContainsKey($relative)) { return New-ApiError -Status 404 -Detail 'Not found' }
    $file = Join-Path $here $relative
    if (-not (Test-Path -LiteralPath $file)) { return New-ApiError -Status 404 -Detail 'Not found' }
    return [pscustomobject]@{
        Status = 200
        Body = [System.IO.File]::ReadAllBytes($file)
        ContentType = $PublicFiles[$relative]
    }
}

$prefix = "http://127.0.0.1:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() }
catch {
    throw "Could not listen on $prefix. A non-administrator account needs a URL reservation: " +
          "netsh http add urlacl url=$prefix user=$env:USERDOMAIN\$env:USERNAME"
}

Write-Host "Workflower editor on http://localhost:$Port/"
Write-Host "Snowflake connection: $Connection"
Write-Host 'Press Ctrl+C to stop.'

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $method = $context.Request.HttpMethod
            $path = $context.Request.Url.AbsolutePath

            # This is a local, privileged tool. Reject writes initiated by other sites.
            if ($method -in @('POST', 'PUT', 'PATCH', 'DELETE')) {
                $origin = $context.Request.Headers['Origin']
                $fetchSite = $context.Request.Headers['Sec-Fetch-Site']
                if (($origin -and $origin -ne "http://localhost:$Port" -and $origin -ne "http://127.0.0.1:$Port") -or
                    $fetchSite -eq 'cross-site') {
                    Write-Response -Context $context -Status 403 -Body ([pscustomobject]@{ detail = 'Cross-origin writes are not allowed' })
                    continue
                }
            }

            $result = Invoke-Route -Context $context -Method $method -Path $path
            $contentType = 'application/json; charset=utf-8'
            if ($result.psobject.Properties.Name -contains 'ContentType') { $contentType = $result.ContentType }
            Write-Response -Context $context -Status $result.Status -Body $result.Body -ContentType $contentType
        }
        catch {
            Write-Host "[error] $($_.Exception.Message)"
            try { Write-Response -Context $context -Status 500 -Body ([pscustomobject]@{ detail = $_.Exception.Message }) } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
