function Start-Workflower {
    <#
    .SYNOPSIS
        Starts the web interface for task graphs: a page on this machine only (127.0.0.1) that shows the graphs of a schema, lets you
        edit one, shows the plan before anything is changed, and runs, starts and stops graphs.
    .DESCRIPTION
        The session stays in this process: the token or the connection never reaches the browser. Every request to the API must carry
        the secret that this process made up when it started and put in the page, and a request is refused if its Host is not this
        machine, so a page on another site cannot use the interface. Stop with Ctrl+C.
    .EXAMPLE
        Start-Workflower -Session (New-WfSession -Connection default)
    .EXAMPLE
        Start-Workflower -Session (New-WfSession -Demo)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Session,
        [int] $Port = 8765,
        [switch] $NoBrowser
    )
    $uiRoot = Join-Path $script:WfRoot 'ui'
    if (-not (Test-Path -LiteralPath (Join-Path $uiRoot 'index.html'))) { throw "The interface files are not in $uiRoot." }
    $secret = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    try { $listener.Start() } catch { throw "Cannot listen on port ${Port}: $($_.Exception.Message) (use -Port to choose another)." }
    $url = "http://127.0.0.1:$Port/"
    Write-Host "Workflower is at $url (Ctrl+C stops it)"
    if (-not $NoBrowser) { Start-Process $url }
    $types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.svg' = 'image/svg+xml'
                '.png' = 'image/png'; '.ico' = 'image/x-icon'; '.webmanifest' = 'application/manifest+json' }
    try {
        while ($listener.IsListening) {
            $pending = $listener.GetContextAsync()
            while (-not $pending.Wait(300)) { }
            $context = $pending.Result
            try { Invoke-WfRequest $context $Session $secret $uiRoot $types $Port }
            catch {
                try { Send-WfResponse $context 500 'application/json; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-WfJson ([ordered]@{ error = $_.Exception.Message })))) } catch { }
            }
        }
    } finally {
        $listener.Stop(); $listener.Close()
    }
}

function Send-WfResponse {
    param($Context, [int] $Status, [string] $ContentType, [byte[]] $Bytes, [hashtable] $Headers)
    $r = $Context.Response
    $r.StatusCode = $Status
    $r.ContentType = $ContentType
    $r.Headers.Add('Cache-Control', 'no-store')
    $r.Headers.Add('X-Content-Type-Options', 'nosniff')
    $r.Headers.Add('Referrer-Policy', 'no-referrer')
    if ($Headers) { foreach ($k in $Headers.Keys) { $r.Headers.Add($k, $Headers[$k]) } }
    $r.ContentLength64 = $Bytes.Length
    $r.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $r.OutputStream.Close()
}

function Invoke-WfRequest {
    param($Context, $Session, [string] $Secret, [string] $UiRoot, $Types, [int] $Port)
    $request = $Context.Request
    $hostHeader = [string]$request.Headers['Host']
    if ($hostHeader -ne "127.0.0.1:$Port" -and $hostHeader -ne "localhost:$Port") {
        Send-WfResponse $Context 403 'text/plain; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes('Forbidden')); return
    }
    $path = $request.Url.AbsolutePath
    if (-not $path.StartsWith('/api/')) {
        if ($request.HttpMethod -ne 'GET') { Send-WfResponse $Context 405 'text/plain; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes('Method not allowed')); return }
        $name = [System.IO.Path]::GetFileName($path)
        if (-not $name) { $name = 'index.html' }
        $file = Join-Path $UiRoot $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Send-WfResponse $Context 404 'text/plain; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes('Not found')); return }
        $type = $Types[[System.IO.Path]::GetExtension($file).ToLowerInvariant()]
        if (-not $type) { $type = 'application/octet-stream' }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $headers = $null
        if ($name -eq 'index.html') {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes).Replace('__WORKFLOWER_SECRET__', $Secret)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
            $headers = @{ 'Content-Security-Policy' = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" }
        }
        Send-WfResponse $Context 200 $type $bytes $headers
        return
    }
    if ([string]$request.Headers['X-Workflower-Secret'] -ne $Secret) {
        Send-WfResponse $Context 403 'application/json; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes('{"error":"Forbidden"}')); return
    }
    $query = @{}
    foreach ($k in $request.QueryString.AllKeys) { if ($k) { $query[$k] = $request.QueryString[$k] } }
    $body = $null
    if ($request.HasEntityBody) {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        if ($text) { $body = ConvertFrom-WfJson $text }
    }
    $status = 200
    try {
        $result = Invoke-WfRoute $Session $request.HttpMethod $path $query $body
    } catch {
        $status = 400
        $result = [ordered]@{ error = $_.Exception.Message }
    }
    Send-WfResponse $Context $status 'application/json; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-WfJson $result)))
}

function ConvertTo-WfProblemList {
    param($Graph)
    $list = @(Test-TaskGraph $Graph | ForEach-Object { [ordered]@{ severity = $_.Severity; task = $_.Task; code = $_.Code; message = $_.Message } })
    ,$list
}

function ConvertTo-WfPlanView {
    param($Plan)
    [ordered]@{
        database = $Plan.Database; schema = $Plan.Schema; root = $Plan.Root; exists = $Plan.Exists; isEmpty = $Plan.IsEmpty
        added = @($Plan.Added); removed = @($Plan.Removed); changed = @($Plan.Changed)
        executed = $(if ($Plan.psobject.Properties['Executed']) { $Plan.Executed } else { 0 })
        steps = @($Plan.Steps | ForEach-Object { [ordered]@{ phase = $_.Phase; task = $_.Task; sql = $_.Sql; reason = $_.Reason } })
    }
}

# The routes of the interface's API. A route that fails throws; the caller turns that into a 400 with the message.
function Invoke-WfRoute {
    param($Session, [string] $Method, [string] $Path, $Query, $Body)
    $q = { param($n) if ($Query.ContainsKey($n)) { [string]$Query[$n] } else { '' } }
    switch ($Path) {
        '/api/session' {
            $account = ''
            if ($Session.psobject.Properties['AccountUrl']) { $account = ([string]$Session.AccountUrl) -replace '^https://', '' -replace '\.snowflakecomputing\.com$', '' }
            elseif ($Session.psobject.Properties['Connection']) { $account = [string]$Session.Connection }
            elseif ($Session.psobject.Properties['Account']) { $account = [string]$Session.Account }
            return [ordered]@{ backend = $Session.Backend; account = $account; warehouse = $Session.Warehouse; role = $Session.Role }
        }
        '/api/databases' {
            $rows = @(Invoke-WfSql $Session 'SHOW DATABASES')
            return [ordered]@{ databases = @($rows | ForEach-Object { [string](Get-WfValue $_ 'name') } | Sort-Object) }
        }
        '/api/schemas' {
            $d = & $q 'database'
            if (-not $d) { throw 'Say which database.' }
            $rows = @(Invoke-WfSql $Session ('SHOW SCHEMAS IN DATABASE ' + (ConvertTo-WfIdentifier $d)))
            return [ordered]@{ schemas = @($rows | ForEach-Object { [string](Get-WfValue $_ 'name') } | Where-Object { $_ -ne 'INFORMATION_SCHEMA' } | Sort-Object) }
        }
        '/api/graphs' {
            $d = & $q 'database'; $s = & $q 'schema'
            if (-not $d -or -not $s) { throw 'Say which database and schema.' }
            $graphs = @(Get-TaskGraph $Session -Database $d -Schema $s -NoParameters)
            return [ordered]@{ graphs = @($graphs | ForEach-Object { ConvertTo-WfGraphView $_ }) }
        }
        '/api/graph' {
            $d = & $q 'database'; $s = & $q 'schema'; $r = & $q 'root'
            $found = @(Get-TaskGraph $Session -Database $d -Schema $s -Root $r)
            if ($found.Count -eq 0) { throw "There is no graph with the root '$r' in $d.$s (or the role cannot see it)." }
            return [ordered]@{ graph = (ConvertTo-WfGraphView $found[0]); problems = (ConvertTo-WfProblemList $found[0]) }
        }
        '/api/validate' {
            $g = ConvertTo-WfGraph (Get-WfValue $Body 'graph')
            return [ordered]@{ problems = (ConvertTo-WfProblemList $g) }
        }
        '/api/plan' {
            $g = ConvertTo-WfGraph (Get-WfValue $Body 'graph')
            $problems = ConvertTo-WfProblemList $g
            $plan = $null
            if (@($problems | Where-Object { $_.severity -eq 'error' }).Count -eq 0) { $plan = ConvertTo-WfPlanView (Compare-TaskGraph $g -Session $Session) }
            return [ordered]@{ problems = $problems; plan = $plan }
        }
        '/api/apply' {
            $g = ConvertTo-WfGraph (Get-WfValue $Body 'graph')
            $done = Publish-TaskGraph $g -Session $Session
            $after = @(Get-TaskGraph $Session -Database $g.database -Schema $g.schema -Root $g.root)
            $view = $null; $problems = @()
            if ($after.Count -gt 0) { $view = ConvertTo-WfGraphView $after[0]; $problems = ConvertTo-WfProblemList $after[0] }
            return [ordered]@{ plan = (ConvertTo-WfPlanView $done); graph = $view; problems = $problems }
        }
        '/api/sql' {
            $g = ConvertTo-WfGraph (Get-WfValue $Body 'graph')
            return [ordered]@{ sql = (ConvertTo-TaskGraphSql $g -AsScript -IncludeState) }
        }
        '/api/export' {
            $g = ConvertTo-WfGraph (Get-WfValue $Body 'graph')
            $name = ((@($g.database, $g.schema, $g.root) | Where-Object { $_ }) -join '.') -replace '[^\p{L}\p{N}_.\-]+', '_'
            return [ordered]@{ fileName = ($name + '.json'); text = (ConvertTo-WfGraphFileText $g) }
        }
        '/api/import' {
            $text = [string](Get-WfValue $Body 'text')
            try { $doc = ConvertFrom-WfJson $text } catch { throw "The file is not valid JSON." }
            if (-not ($doc -is [System.Collections.IDictionary]) -or -not (Test-WfHas $doc 'tasks')) { throw 'Not a task graph file: it has no "tasks".' }
            $g = ConvertTo-WfGraph $doc
            return [ordered]@{ graph = (ConvertTo-WfGraphView $g); problems = (ConvertTo-WfProblemList $g) }
        }
        '/api/operate' {
            $d = [string](Get-WfValue $Body 'database'); $s = [string](Get-WfValue $Body 'schema'); $r = [string](Get-WfValue $Body 'root'); $action = [string](Get-WfValue $Body 'action')
            switch ($action) {
                'resume' { Resume-TaskGraph -Session $Session -Database $d -Schema $s -Root $r }
                'suspend' { Suspend-TaskGraph -Session $Session -Database $d -Schema $s -Root $r }
                'run' { Start-TaskGraph -Session $Session -Database $d -Schema $s -Root $r }
                'retry' { Start-TaskGraph -Session $Session -Database $d -Schema $s -Root $r -Retry }
                default { throw "Unknown action '$action' (resume, suspend, run or retry)." }
            }
            $found = @(Get-TaskGraph $Session -Database $d -Schema $s -Root $r -NoParameters)
            $view = $null
            if ($found.Count -gt 0) { $view = ConvertTo-WfGraphView $found[0] }
            return [ordered]@{ graph = $view }
        }
        '/api/runs' {
            $d = & $q 'database'; $s = & $q 'schema'; $r = & $q 'root'
            $hours = 24
            if ((& $q 'hours') -match '^\d+$') { $hours = [int](& $q 'hours') }
            $runs = @(Get-TaskGraphRun -Session $Session -Database $d -Schema $s -Root $r -Hours $hours -Limit 50)
            return [ordered]@{ runs = @($runs | ForEach-Object {
                [ordered]@{ runId = $_.RunId; state = $_.State; scheduled = $_.Scheduled; started = $_.Started; completed = $_.Completed; seconds = $_.Seconds
                    tasks = @($_.Tasks | ForEach-Object { [ordered]@{ task = $_.Task; state = $_.State; started = $_.Started; completed = $_.Completed; error = $_.Error; errorCode = $_.ErrorCode; queryId = $_.QueryId; attempt = $_.Attempt } }) }
            }) }
        }
        default { throw "Unknown route $Path." }
    }
}
