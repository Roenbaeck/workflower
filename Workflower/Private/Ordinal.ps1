# Names are exact in Snowflake: a task called r is not the task called R, and their order does not depend on the machine. PowerShell's
# hashtables ignore case and Sort-Object follows the culture, so the module uses these instead wherever it keys or orders by a name.
# (The engine of the macOS and Linux version compares names exactly and orders them ordinally; the two must agree.)

# A map with exact (case-sensitive) text keys.
function New-WfMap {
    New-Object 'System.Collections.Generic.Dictionary[string,object]'
}

# Sorts by an ordinal comparison of text. -Key is a script block that gives the text to sort by, from $_; without it the items themselves
# are the text. -Unique drops items whose text is the same.
function Sort-WfOrdinal {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)] $InputObject, [scriptblock] $Key, [switch] $Unique)
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { $items.Add($InputObject) }
    end {
        if ($items.Count -eq 0) { return }
        $keys = New-Object 'string[]' $items.Count
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ($Key) { $keys[$i] = [string](, $items[$i] | ForEach-Object $Key) } else { $keys[$i] = [string]$items[$i] }
        }
        $sorted = $items.ToArray()
        [System.Array]::Sort([System.Array]$keys, [System.Array]$sorted, [System.Collections.IComparer][System.StringComparer]::Ordinal)
        $previous = $null
        for ($i = 0; $i -lt $sorted.Length; $i++) {
            if ($Unique -and $i -gt 0 -and $keys[$i] -ceq $previous) { continue }
            $previous = $keys[$i]
            , $sorted[$i]
        }
    }
}
