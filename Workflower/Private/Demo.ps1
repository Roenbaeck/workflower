# A session that is not Snowflake: it answers the few statements that reading and operating a graph use from fixtures, and remembers
# the rest in Session.Log. It is for trying the interface and for testing it without an account.

function New-WfDemoSession {
    $state = [ordered]@{ Rows = (New-WfDemoTaskRows); Log = (New-Object System.Collections.Generic.List[string]) }
    [pscustomobject]@{ Backend = 'Demo'; Warehouse = 'DEMO_WH'; Role = 'DEMO'; Account = 'demo'; State = $state; Log = $state.Log }
}

function New-WfDemoRow {
    param([string] $Name, [string] $Definition = 'SELECT 1', [string[]] $After = @(), [string] $FinalizerOf, [string] $Schedule,
          [string] $Warehouse = 'DEMO_WH', [string] $State = 'started', [string] $Condition, [string] $Id, [string] $Db = 'SALES', [string] $Sc = 'LOAD')
    $rel = [ordered]@{ Predecessors = @($After | ForEach-Object { $Db + '.' + $Sc + '.' + $_ }) }
    if ($FinalizerOf) { $rel.FinalizedRootTask = $Db + '.' + $Sc + '.' + $FinalizerOf }
    [pscustomobject]@{
        created_on = '2026-11-20 08:00:00'; name = $Name; id = $Id; database_name = $Db; schema_name = $Sc; owner = 'DEMO'; comment = ''
        warehouse = $Warehouse; schedule = $Schedule; predecessors = ''; state = $State; definition = $Definition; condition = $Condition
        allow_overlapping_execution = 'null'; error_integration = 'null'; last_committed_on = '2026-11-25 10:00:00'; last_suspended_on = ''
        owner_role_type = 'ROLE'; config = ''; budget = ''; task_relations = (ConvertTo-Json -InputObject $rel -Compress); last_suspended_reason = ''
    }
}

function New-WfDemoTaskRows {
    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add((New-WfDemoRow 'NIGHTLY_ROOT' -Id '101' -Schedule 'USING CRON 0 2 * * * Europe/Stockholm'))
    $rows.Add((New-WfDemoRow 'LOAD_CUSTOMERS' -Id '102' -After 'NIGHTLY_ROOT' -Definition 'CALL load_customers()'))
    $rows.Add((New-WfDemoRow 'LOAD_ORDERS' -Id '103' -After 'NIGHTLY_ROOT' -Definition "INSERT INTO orders SELECT * FROM staging.orders WHERE loaded = FALSE"))
    $rows.Add((New-WfDemoRow 'LOAD_PRODUCTS' -Id '104' -After 'NIGHTLY_ROOT' -Definition 'CALL load_products()' -Warehouse ''))
    $rows.Add((New-WfDemoRow 'BUILD_FACTS' -Id '105' -After 'LOAD_CUSTOMERS', 'LOAD_ORDERS', 'LOAD_PRODUCTS' -Definition 'CALL build_facts()'))
    $rows.Add((New-WfDemoRow 'PUBLISH' -Id '106' -After 'BUILD_FACTS' -Definition 'CALL publish_marts()'))
    $rows.Add((New-WfDemoRow 'NOTIFY_DONE' -Id '107' -FinalizerOf 'NIGHTLY_ROOT' -Definition "CALL notify('nightly finished')"))
    $rows.Add((New-WfDemoRow 'EVENT_ROOT' -Id '201' -State 'suspended' -Condition "SYSTEM`$STREAM_HAS_DATA('EVENTS_STREAM')" -Definition 'CALL handle_events()'))
    $rows.Add((New-WfDemoRow 'CLEAN_UP' -Id '301' -Schedule '1440 MINUTE' -Definition 'DELETE FROM audit WHERE ts < DATEADD(day, -90, CURRENT_TIMESTAMP())'))
    $rows.ToArray()
}

function New-WfDemoHistory {
    param([string] $Root)
    $rows = New-Object System.Collections.Generic.List[object]
    $names = @('NIGHTLY_ROOT', 'LOAD_CUSTOMERS', 'LOAD_ORDERS', 'LOAD_PRODUCTS', 'BUILD_FACTS', 'PUBLISH', 'NOTIFY_DONE')
    for ($day = 0; $day -lt 4; $day++) {
        $date = (Get-Date '2026-11-26').AddDays(-$day).ToString('yyyy-MM-dd')
        $i = 0
        foreach ($n in $names) {
            $state = 'SUCCEEDED'; $err = $null; $code = $null
            if ($day -eq 1 -and $n -eq 'LOAD_ORDERS') { $state = 'FAILED'; $err = 'SQL compilation error: Object ORDERS does not exist or not authorized.'; $code = '2003' }
            if ($day -eq 1 -and ($n -eq 'BUILD_FACTS' -or $n -eq 'PUBLISH')) { $state = 'SKIPPED' }
            $start = (Get-Date ($date + ' 02:00:00')).AddSeconds(20 * $i)
            $rows.Add([pscustomobject]@{
                GRAPH_RUN_GROUP_ID = ('run-' + $date); NAME = $n; STATE = $state; SCHEDULED_TIME = ($date + ' 02:00:00.000'); QUERY_START_TIME = $start.ToString('yyyy-MM-dd HH:mm:ss.fff')
                COMPLETED_TIME = $start.AddSeconds(15).ToString('yyyy-MM-dd HH:mm:ss.fff'); ERROR_MESSAGE = $err; ERROR_CODE = $code; QUERY_ID = ('q-' + $date + '-' + $i)
                ATTEMPT_NUMBER = '1'; SCHEDULED_FROM = 'SCHEDULE'
            })
            $i++
        }
    }
    $rows.ToArray()
}

function Invoke-WfDemo {
    param($Session, [string] $Sql)
    $text = $Sql.Trim()
    $rows = $Session.State.Rows
    if ($text -match '^SHOW TASKS') {
        $scope = $text
        $out = @($rows | Where-Object { ($scope -match 'SCHEMA') -eq $false -or $scope -match ('"' + $_.schema_name + '"') })
        return $out
    }
    if ($text -match '^SHOW PARAMETERS IN TASK') {
        $name = [regex]::Match($text, '"([^"]+)"\s*$').Groups[1].Value
        if ($name -eq 'NIGHTLY_ROOT') {
            return @([pscustomobject]@{ key = 'USER_TASK_TIMEOUT_MS'; value = '3600000'; default = '3600000'; level = 'TASK'; description = '' },
                      [pscustomobject]@{ key = 'SUSPEND_TASK_AFTER_NUM_FAILURES'; value = '3'; default = '10'; level = 'TASK'; description = '' })
        }
        return @([pscustomobject]@{ key = 'USER_TASK_TIMEOUT_MS'; value = '3600000'; default = '3600000'; level = ''; description = '' })
    }
    if ($text -match '^SHOW DATABASES') { return @([pscustomobject]@{ name = 'SALES' }, [pscustomobject]@{ name = 'FINANCE' }) }
    if ($text -match '^SHOW SCHEMAS') { return @([pscustomobject]@{ name = 'LOAD' }, [pscustomobject]@{ name = 'MAINTENANCE' }, [pscustomobject]@{ name = 'INFORMATION_SCHEMA' }) }
    if ($text -match 'TASK_HISTORY') { return @(New-WfDemoHistory) }
    $Session.Log.Add($Sql)
    if ($text -match '^ALTER TASK\s+(.+?)\s+(RESUME|SUSPEND)\s*$') {
        $name = (Get-WfLastPart $Matches[1])
        foreach ($r in $rows) { if ($r.name -ceq $name) { $r.state = $(if ($Matches[2] -eq 'RESUME') { 'started' } else { 'suspended' }) } }
    }
    return
}
