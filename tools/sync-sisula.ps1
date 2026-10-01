<#
    Brings the Sisula engine in this repository up to a chosen version of the sisula repository, or
    checks that the copy here is untouched.

    The engine is not edited here. webapp/sisula.js is a copy of core/sisula.js in the sisula
    repository, and the shared fixtures and the language reference are copied with it:

        sisula repository          this repository
        core/sisula.js        ->   webapp/sisula.js
        docs/LANGUAGE.md      ->   docs/SISULA.md
        tests/fixtures/*.json ->   tests/sisula-fixtures/*.json

    webapp/sisula.lock.json records which commit they came from and the SHA-256 of each file
    (computed with CRLF turned into LF, so a Windows checkout and a Linux one agree).
    The tests fail if any of the files differs from the lock, so a hand edit cannot go unnoticed.

    Usage:
      .\tools\sync-sisula.ps1                    update from origin/master of ..\sisula
      .\tools\sync-sisula.ps1 -Ref v1.2.0        update from a tag, a branch or a commit
      .\tools\sync-sisula.ps1 -Fetch             fetch the sisula checkout first
      .\tools\sync-sisula.ps1 -Check             verify the copies against the lock, change nothing

    Updating takes the files as committed, not as they are in the working tree of the sisula
    checkout, so it can only pin something that was committed. A commit that is not on
    origin/master is refused (-AllowUnpublished overrides), because nobody else has it.
    An update is a change to review: look at git diff, run npm test, then commit it.
#>
[CmdletBinding()]
param(
    [string] $Sisula,
    [string] $Ref = 'origin/master',
    [switch] $Fetch,
    [switch] $Check,
    [switch] $AllowUnpublished
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$lockPath = Join-Path $root 'webapp\sisula.lock.json'
$engineTo = 'webapp\sisula.js'
$languageTo = 'docs\SISULA.md'
$fixturesTo = 'tests\sisula-fixtures'
$latin1 = [Text.Encoding]::GetEncoding(28591)   # one char per byte, so bytes survive a round trip
$utf8 = New-Object Text.UTF8Encoding($false)

# SHA-256, as lower-case hex, of the bytes with CRLF replaced by LF.
function Get-Hash([byte[]] $bytes) {
    $lf = $latin1.GetBytes($latin1.GetString($bytes).Replace("`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ($sha.ComputeHash($lf) | ForEach-Object { $_.ToString('x2') }) -join '' } finally { $sha.Dispose() }
}

function Get-FileHashLf([string] $path) { Get-Hash ([IO.File]::ReadAllBytes($path)) }

function ConvertTo-JsonString([string] $s) {
    $sb = New-Object Text.StringBuilder
    [void] $sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"'  { [void] $sb.Append('\"') }
            '\'  { [void] $sb.Append('\\') }
            "`n" { [void] $sb.Append('\n') }
            "`r" { [void] $sb.Append('\r') }
            "`t" { [void] $sb.Append('\t') }
            default { if ([int] $ch -lt 32) { [void] $sb.AppendFormat('\u{0:x4}', [int] $ch) } else { [void] $sb.Append($ch) } }
        }
    }
    [void] $sb.Append('"')
    $sb.ToString()
}

# ---------------------------------------------------------------------------------------------
# -Check: compare what is here with the lock. Needs no git and no sisula checkout.
# ---------------------------------------------------------------------------------------------
if ($Check) {
    if (-not (Test-Path $lockPath)) { throw "No lock file: $lockPath" }
    $lock = [IO.File]::ReadAllText($lockPath, $utf8) | ConvertFrom-Json
    $bad = 0
    function Test-One([string] $label, [string] $relative, [string] $expected) {
        $path = Join-Path $root $relative
        if (-not (Test-Path $path)) { Write-Host "MISSING   $label"; $script:bad++; return }
        if ((Get-FileHashLf $path) -ne $expected) { Write-Host "CHANGED   $label"; $script:bad++; return }
        Write-Host "ok        $label"
    }
    Test-One $engineTo $engineTo $lock.engine.sha256
    Test-One $languageTo $languageTo $lock.language.sha256
    $locked = @($lock.fixtures.files.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($name in $locked) { Test-One "$fixturesTo\$name" "$fixturesTo\$name" $lock.fixtures.files.$name }
    if (Test-Path (Join-Path $root $fixturesTo)) {
        foreach ($f in Get-ChildItem (Join-Path $root $fixturesTo) -Filter *.json) {
            if ($locked -notcontains $f.Name) { Write-Host "UNLOCKED  $fixturesTo\$($f.Name)"; $bad++ }
        }
    }
    Write-Host ''
    Write-Host ("Sisula {0} ({1})" -f $lock.commit.Substring(0, 7), $lock.subject)
    if ($bad -gt 0) {
        Write-Host "$bad file(s) differ from the lock. Do not edit these files; run .\tools\sync-sisula.ps1 to restore them or to update."
        exit 1
    }
    Write-Host 'All files match the lock.'
    return
}

# ---------------------------------------------------------------------------------------------
# Update from a commit of the sisula repository.
# ---------------------------------------------------------------------------------------------
if (-not $Sisula) { $Sisula = Join-Path $root '..\sisula' }
if (-not (Test-Path (Join-Path $Sisula '.git'))) { throw "No sisula checkout at $Sisula; clone it next to this repository or pass -Sisula." }
$Sisula = (Resolve-Path $Sisula).Path

# Runs git in the sisula checkout and returns its standard output as bytes.
function Invoke-Git([string[]] $Arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $quoted = $Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
    $psi.Arguments = '-C "' + $Sisula + '" ' + ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
    $errors = $process.StandardError.ReadToEndAsync()
    $memory = New-Object IO.MemoryStream
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "git $($Arguments -join ' ') failed ($($process.ExitCode)): $($errors.Result.Trim())" }
    , $memory.ToArray()
}
function Get-GitText([string[]] $Arguments) { $utf8.GetString((Invoke-Git $Arguments)).Trim() }

if ($Fetch) { [void] (Invoke-Git @('fetch', '--tags', 'origin')) }
$commit = Get-GitText @('rev-parse', '--verify', "$Ref^{commit}")

# Pin only what has been published.
$published = $true
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = 'git'
$psi.Arguments = '-C "' + $Sisula + '" merge-base --is-ancestor ' + $commit + ' origin/master'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardError = $true
$ancestry = [Diagnostics.Process]::Start($psi); [void] $ancestry.StandardError.ReadToEnd(); $ancestry.WaitForExit()
if ($ancestry.ExitCode -ne 0) { $published = $false }
if (-not $published -and -not $AllowUnpublished) {
    throw "Commit $($commit.Substring(0, 7)) is not on origin/master of the sisula checkout, so it is not something anyone else has. Push it, run with -Fetch if the checkout is behind, or pass -AllowUnpublished."
}

$subject = Get-GitText @('log', '-1', '--format=%s', $commit)
$date = Get-GitText @('log', '-1', '--format=%cI', $commit)
$source = Get-GitText @('remote', 'get-url', 'origin')
$source = $source -replace '\.git$', ''

Write-Host "Sisula $($commit.Substring(0, 7)): $subject"
if (-not $published) { Write-Host 'WARNING: this commit is not on origin/master.' }

$changed = New-Object System.Collections.Generic.List[string]
function Write-Copy([string] $relativeTo, [byte[]] $bytes) {
    $path = Join-Path $root $relativeTo
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    if (-not (Test-Path $path) -or (Get-FileHashLf $path) -ne (Get-Hash $bytes)) { $script:changed.Add($relativeTo) }
    [IO.File]::WriteAllBytes($path, $bytes)
}

$engine = Invoke-Git @('cat-file', 'blob', "${commit}:core/sisula.js")
$language = Invoke-Git @('cat-file', 'blob', "${commit}:docs/LANGUAGE.md")
Write-Copy $engineTo $engine
Write-Copy $languageTo $language

$names = (Get-GitText @('ls-tree', '--name-only', $commit, 'tests/fixtures/')) -split "`n" |
    Where-Object { $_ -like '*.json' } | ForEach-Object { $_.Trim() -replace '^tests/fixtures/', '' } | Sort-Object
if (-not $names) { throw 'No fixtures found in tests/fixtures of that commit.' }
$fixtureHashes = [ordered]@{}
foreach ($name in $names) {
    $bytes = Invoke-Git @('cat-file', 'blob', "${commit}:tests/fixtures/$name")
    Write-Copy "$fixturesTo\$name" $bytes
    $fixtureHashes[$name] = Get-Hash $bytes
}
# A fixture that no longer exists upstream must not linger.
foreach ($f in @(Get-ChildItem (Join-Path $root $fixturesTo) -Filter *.json)) {
    if ($names -notcontains $f.Name) { Remove-Item $f.FullName; $changed.Add("$fixturesTo\$($f.Name) (removed)") }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('{')
$lines.Add('  "source": ' + (ConvertTo-JsonString $source) + ',')
$lines.Add('  "commit": ' + (ConvertTo-JsonString $commit) + ',')
$lines.Add('  "date": ' + (ConvertTo-JsonString $date) + ',')
$lines.Add('  "subject": ' + (ConvertTo-JsonString $subject) + ',')
$lines.Add('  "engine": { "from": "core/sisula.js", "to": "webapp/sisula.js", "sha256": "' + (Get-Hash $engine) + '" },')
$lines.Add('  "language": { "from": "docs/LANGUAGE.md", "to": "docs/SISULA.md", "sha256": "' + (Get-Hash $language) + '" },')
$lines.Add('  "fixtures": {')
$lines.Add('    "from": "tests/fixtures",')
$lines.Add('    "to": "tests/sisula-fixtures",')
$lines.Add('    "files": {')
$keys = @($fixtureHashes.Keys)
for ($i = 0; $i -lt $keys.Count; $i++) {
    $lines.Add('      ' + (ConvertTo-JsonString $keys[$i]) + ': "' + $fixtureHashes[$keys[$i]] + '"' + $(if ($i -lt $keys.Count - 1) { ',' } else { '' }))
}
$lines.Add('    }')
$lines.Add('  }')
$lines.Add('}')
$lockText = ($lines -join "`n") + "`n"
$previous = if (Test-Path $lockPath) { ([IO.File]::ReadAllText($lockPath, $utf8) -replace "`r`n", "`n") } else { '' }
if ($previous -ne $lockText) { $changed.Add('webapp\sisula.lock.json') }
[IO.File]::WriteAllText($lockPath, $lockText, $utf8)

Write-Host ''
if ($changed.Count -eq 0) {
    Write-Host 'Nothing changed: this repository already has that version.'
} else {
    Write-Host 'Changed:'
    $changed | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host 'Review it with git diff, run npm test, then commit. Redeploy the engine with .\deploy.ps1 for Snowflake to use it.'
}
