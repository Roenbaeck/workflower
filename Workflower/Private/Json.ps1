# JSON that does not stop at 2 MB. Windows PowerShell 5.1's ConvertFrom-Json refuses a larger text and a result from Snowflake
# can be larger, so the .NET serializer with its limit lifted is used where it exists (it does not in PowerShell 7, which has no limit).

$script:WfSerializer = $null
try {
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $script:WfSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $script:WfSerializer.MaxJsonLength = [int]::MaxValue
    $script:WfSerializer.RecursionLimit = 1000
} catch { $script:WfSerializer = $null }

# A parsed JSON text as dictionaries (objects), object arrays (arrays) and scalars. The comma keeps an array (an empty one too)
# from being unrolled into nothing on its way out of the function.
function ConvertFrom-WfJson {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Text)
    if ($script:WfSerializer) { $object = $script:WfSerializer.DeserializeObject($Text); return ,$object }
    $parsed = $Text | ConvertFrom-Json
    ,(ConvertTo-WfPlain $parsed)
}

function ConvertTo-WfPlain {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,object]'
        foreach ($p in $Value.psobject.Properties) { $d[$p.Name] = ConvertTo-WfPlain $p.Value }
        return $d
    }
    if ($Value -is [System.Array]) { return ,@($Value | ForEach-Object { ConvertTo-WfPlain $_ }) }
    $Value
}

# Indented JSON in a form that is the same on both editions (ConvertTo-Json's layout differs between them, and a file is diffed).
# Only ASCII is written: anything else is a \u escape.
function ConvertTo-WfJson {
    param($Value, [int] $Indent = 0)
    $pad = '  ' * $Indent
    $pad2 = '  ' * ($Indent + 1)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return (ConvertTo-WfJsonString $Value) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $d = [ordered]@{}
        foreach ($p in $Value.psobject.Properties) { $d[$p.Name] = $p.Value }
        return (ConvertTo-WfJson $d $Indent)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 0) { return '{}' }
        $items = @()
        foreach ($k in $Value.Keys) { $items += ($pad2 + (ConvertTo-WfJsonString ([string]$k)) + ': ' + (ConvertTo-WfJson $Value[$k] ($Indent + 1))) }
        return "{`n" + ($items -join ",`n") + "`n$pad}"
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $list = @($Value)
        if ($list.Count -eq 0) { return '[]' }
        $simple = $true
        foreach ($x in $list) { if ($x -is [System.Collections.IDictionary] -or ($x -is [System.Collections.IEnumerable] -and $x -isnot [string])) { $simple = $false } }
        if ($simple) { return '[' + (($list | ForEach-Object { ConvertTo-WfJson $_ ($Indent + 1) }) -join ', ') + ']' }
        $items = @($list | ForEach-Object { $pad2 + (ConvertTo-WfJson $_ ($Indent + 1)) })
        return "[`n" + ($items -join ",`n") + "`n$pad]"
    }
    ConvertTo-WfJsonString ([string]$Value)
}

function ConvertTo-WfJsonString {
    param([string] $Text)
    $backslash = [char]92
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        $code = [int]$c
        if ($code -eq 34) { [void]$sb.Append($backslash).Append('"') }
        elseif ($code -eq 92) { [void]$sb.Append($backslash).Append($backslash) }
        elseif ($code -eq 10) { [void]$sb.Append($backslash).Append('n') }
        elseif ($code -eq 13) { [void]$sb.Append($backslash).Append('r') }
        elseif ($code -eq 9) { [void]$sb.Append($backslash).Append('t') }
        elseif ($code -lt 32 -or $code -gt 126) { [void]$sb.Append($backslash).Append('u').Append($code.ToString('x4')) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}
