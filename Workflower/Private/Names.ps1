# Identifiers, literals and qualified names. Every identifier the module writes is double quoted, because the
# names it reads from Snowflake are the exact stored names (a task called Load Root or load_root is not LOAD_ROOT).

function ConvertTo-WfIdentifier {
    param([Parameter(Mandatory = $true)][string] $Name)
    '"' + $Name.Replace('"', '""') + '"'
}

function ConvertTo-WfQualified {
    param([string] $Database, [string] $Schema, [Parameter(Mandatory = $true)][string] $Name)
    $parts = @()
    if ($Database) { $parts += (ConvertTo-WfIdentifier $Database) }
    if ($Schema) { $parts += (ConvertTo-WfIdentifier $Schema) }
    $parts += (ConvertTo-WfIdentifier $Name)
    $parts -join '.'
}

# A string literal. Snowflake treats a backslash in a single-quoted string as an escape, so both it and the quote are doubled.
function ConvertTo-WfLiteral {
    param([AllowNull()][string] $Text)
    if ($null -eq $Text) { return 'NULL' }
    $backslash = [string][char]92
    "'" + $Text.Replace($backslash, $backslash + $backslash).Replace("'", "''") + "'"
}

# The value of a parameter in a SET: numbers and TRUE/FALSE as they are, anything else as a string.
function ConvertTo-WfParameterValue {
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return 'NULL' }
    if ($Value -is [bool]) { if ($Value) { return 'TRUE' } else { return 'FALSE' } }
    $text = [string]$Value
    if ($text -match '^-?\d+(\.\d+)?$') { return $text }
    if ($text -match '^(?i:true|false)$') { return $text.ToUpperInvariant() }
    ConvertTo-WfLiteral $text
}

# Splits a dotted name such as DB.SCH.T or "My Db"."s"."t" into its parts; a quoted part may hold dots.
function Split-WfQualified {
    param([Parameter(Mandatory = $true)][string] $Text)
    $parts = New-Object System.Collections.Generic.List[string]
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        if ($Text[$i] -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $i++
            while ($i -lt $n) {
                if ($Text[$i] -eq '"') {
                    if ($i + 1 -lt $n -and $Text[$i + 1] -eq '"') { [void]$sb.Append('"'); $i += 2; continue }
                    $i++; break
                }
                [void]$sb.Append($Text[$i]); $i++
            }
            $parts.Add($sb.ToString())
        } else {
            $start = $i
            while ($i -lt $n -and $Text[$i] -ne '.') { $i++ }
            $parts.Add($Text.Substring($start, $i - $start).Trim())
        }
        if ($i -lt $n -and $Text[$i] -eq '.') { $i++ }
    }
    $array = $parts.ToArray()
    ,$array
}

# The last part of a name, which is the task's own name.
function Get-WfLastPart {
    param([Parameter(Mandatory = $true)][string] $Text)
    $parts = Split-WfQualified $Text
    if ($parts.Count -eq 0) { return $Text }
    $parts[$parts.Count - 1]
}
