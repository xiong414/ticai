<#
.SYNOPSIS
    Sync the ticai skill from the git working copy into one or more host skill roots.

.DESCRIPTION
    A skill is just files. Each host (DSH / Codex / Claude Code / Cursor / Gemini CLI) scans its
    own user-level skill root, so the copies never follow each other. This script updates the
    requested roots and then verifies the content that a host would actually read, so a silent
    "edited but not in effect" mismatch cannot go unnoticed.

    Two link modes are supported, because the roots behave differently:

      Link (default)  Create a directory symlink/junction <root>/ticai -> <source>. Every host then
                      reads this single working copy, so no later sync is needed. Used for roots
                      that hold shared skills (~/.agents/skills) and for roots that already follow
                      that convention (~/.claude/skills, which junctions into ~/.agents/skills).
                      Falls back to a real copy when link creation is not permitted.

      Copy            Real copies, for roots that must keep self-contained files (~/.dsh/skills is
                      where DSH's session catalog actually resolved this skill, ~/.codex/skills is
                      the Codex CLI location).

    A root that already holds a real directory instead of a link is left untouched unless -Sync is
    passed, so an unexpected local variant is never deleted by accident. Only skill files are ever
    touched (SKILL.md, README.md, agents, references); .git and scripts are skipped.

    Script messages are ASCII on purpose: Windows PowerShell 5.1 decodes files without a BOM as
    ANSI, which corrupts non-ASCII text and can break parsing on other machines or editors.

.PARAMETER Source
    Path to the repository working copy. Defaults to the parent of this script's directory.

.PARAMETER Roots
    Skill roots to update; the skill appears as <root>/ticai in each one.
    Defaults to ~/.dsh/skills, ~/.codex/skills, ~/.agents/skills, ~/.claude/skills.

.PARAMETER LinkRoots
    Roots that get a symlink/junction instead of a copy.
    Defaults to ~/.agents/skills, ~/.claude/skills.
    Override with the TICAI_SYNC_LINKS environment variable: set it to "all" to link every root,
    or to a ";"-separated list of roots to link exactly those.

.PARAMETER All
    Also create and populate roots that do not exist yet.

.PARAMETER Sync
    Update roots that currently hold a real directory, replacing them with the requested mode.

.PARAMETER Check
    Verify only; report what each root currently serves. Changes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\sync.ps1 -Check
    Verify only; modify nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\sync.ps1
    Update every root that already exists.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\sync.ps1 -All -Sync
    Update every root, create missing ones, and replace stray real directories.
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string[]]$Roots,
    [string[]]$LinkRoots,
    [switch]$All,
    [switch]$Sync,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$SkillName = 'ticai'
$Manifest = @('SKILL.md', 'README.md', 'agents', 'references')

if (-not $Source) { $Source = Split-Path -Parent $PSScriptRoot }
$Source = (Resolve-Path -LiteralPath $Source).Path

if (-not $Roots -or $Roots.Count -eq 0) {
    $Roots = @(
        (Join-Path $HOME '.dsh\skills'),
        (Join-Path $HOME '.codex\skills'),
        (Join-Path $HOME '.agents\skills'),
        (Join-Path $HOME '.claude\skills')
    )
}
if (-not $LinkRoots -or $LinkRoots.Count -eq 0) {
    $fallback = @(
        (Join-Path $HOME '.agents\skills'),
        (Join-Path $HOME '.claude\skills')
    )
    $envLinks = $env:TICAI_SYNC_LINKS
    if ([string]::IsNullOrWhiteSpace($envLinks)) { $LinkRoots = $fallback }
    elseif ($envLinks.Trim() -ieq 'all') { $LinkRoots = $Roots }
    else { $LinkRoots = @($envLinks -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) }
}
$linkSet = @{}
foreach ($r in $LinkRoots) { $linkSet[[System.IO.Path]::GetFullPath($r).TrimEnd('\')] = $true }

function Get-SkillFiles {
    param([string]$Root)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Manifest) {
        $path = Join-Path $Root $entry
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $out.Add([pscustomobject]@{ Rel = $entry; File = (Get-Item -LiteralPath $path) })
        }
        else {
            Get-ChildItem -LiteralPath $path -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
                $out.Add([pscustomobject]@{ Rel = $rel; File = $_ })
            }
        }
    }
    return $out
}

# Compare normalized text so that CRLF vs LF is not reported as a difference.
function Get-ContentHash {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    $norm = ($text -replace "`r`n", "`n").TrimEnd("`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($norm)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

# Frontmatter contract: name must be kebab-case, description is required. A file that violates
# this is skipped with a warning by the host, so the model catalog never sees it.
function Test-Frontmatter {
    param([string]$Path)
    $problems = @()
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text -notmatch '^---\r?\n') {
        return @('missing frontmatter (file does not start with ---)')
    }
    $end = $text.IndexOf("`n---", 4)
    if ($end -lt 0) { return @('unterminated frontmatter (no closing ---)') }
    $block = $text.Substring(0, $end)

    $name = $null; $desc = $null
    foreach ($line in ($block -split "`r?`n")) {
        if ($line -match '^name:\s*(.+?)\s*$') { $name = $Matches[1].Trim('"', "'") }
        elseif ($line -match '^description:\s*(.+?)\s*$') { $desc = $Matches[1].Trim('"', "'") }
    }
    if (-not $name) { $problems += 'frontmatter has no name' }
    elseif ($name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $problems += "name '$name' is not kebab-case" }
    elseif ($name -ne $SkillName) { $problems += "name '$name' does not match directory name '$SkillName'" }
    if (-not $desc) { $problems += 'frontmatter has no description' }
    elseif ($desc.Length -gt 1024) { $problems += "description too long ($($desc.Length) chars > 1024)" }
    return $problems
}

function Get-LinkTarget {
    param([string]$Path)
    try { return [string](Get-Item -LiteralPath $Path -Force).Target } catch { return $null }
}

# Compare the files a host would read at <dest> against the source.
function Compare-ToSource {
    param([string]$Dest, [hashtable]$SrcHashes)
    $bad = @()
    if (-not (Test-Path -LiteralPath $Dest)) { return @('path does not exist') }
    $files = Get-SkillFiles -Root $Dest
    $found = @{}
    foreach ($f in $files) { $found[$f.Rel] = Get-ContentHash -Path $f.File.FullName }
    foreach ($rel in $SrcHashes.Keys) {
        if (-not $found.ContainsKey($rel)) { $bad += "missing $rel" }
        elseif ($found[$rel] -ne $SrcHashes[$rel]) { $bad += "content differs: $rel" }
    }
    foreach ($rel in $found.Keys) {
        if (-not $SrcHashes.ContainsKey($rel)) { $bad += "extra file: $rel" }
    }
    return $bad
}

Write-Output "Source: $Source"
$srcFiles = Get-SkillFiles -Root $Source
if ($srcFiles.Count -eq 0) { throw "No skill files found under: $Source" }

$fmProblems = Test-Frontmatter -Path (Join-Path $Source 'SKILL.md')
if ($fmProblems.Count -gt 0) {
    Write-Output 'Source frontmatter check FAILED:'
    $fmProblems | ForEach-Object { Write-Output "  - $_" }
    exit 2
}
Write-Output "Source frontmatter OK (name=$SkillName, $($srcFiles.Count) files)"

$srcHashes = @{}
foreach ($f in $srcFiles) { $srcHashes[$f.Rel] = Get-ContentHash -Path $f.File.FullName }

$failed = 0
$touched = 0

foreach ($root in $Roots) {
    $rootPath = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
    $dest = Join-Path $rootPath $SkillName
    $wantLink = $linkSet.ContainsKey($rootPath)
    $mode = if ($wantLink) { 'link' } else { 'copy' }

    Write-Output ''
    Write-Output "[$rootPath]  mode=$mode"

    if (-not (Test-Path -LiteralPath $rootPath)) {
        if (-not $All) {
            Write-Output '  skip: root does not exist (pass -All to create it)'
            continue
        }
        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        Write-Output '  created missing root'
    }

    $destExists = Test-Path -LiteralPath $dest
    $isLink = $false
    if ($destExists) { $isLink = ((Get-Item -LiteralPath $dest -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }

    if ($Check) {
        if (-not $destExists) { Write-Output '  MISSING'; $failed++; continue }
        $bad = Compare-ToSource -Dest $dest -SrcHashes $srcHashes
        $kind = if ($isLink) { "link -> $(Get-LinkTarget -Path $dest)" } else { 'real directory' }
        if ($bad.Count -eq 0) { Write-Output "  MATCH ($kind)" }
        else {
            Write-Output "  DIFFERS ($kind)"
            $bad | ForEach-Object { Write-Output "    - $_" }
            $failed++
        }
        continue
    }

    if ($destExists -and -not $isLink -and -not $Sync) {
        $bad = Compare-ToSource -Dest $dest -SrcHashes $srcHashes
        if ($bad.Count -eq 0) {
            Write-Output '  already up to date (real directory); pass -Sync to convert it to mode'
        }
        else {
            Write-Output '  STALE real directory, left untouched. Re-run with -Sync to replace it,'
            Write-Output '  or remove it manually if it is no longer wanted:'
            $bad | ForEach-Object { Write-Output "    - $_" }
            $failed++
        }
        continue
    }

    if ($destExists) {
        if ($wantLink -and $isLink) {
            $current = Get-LinkTarget -Path $dest
            if ($current -and ([System.IO.Path]::GetFullPath($current).TrimEnd('\')) -ieq $Source) {
                $bad = Compare-ToSource -Dest $dest -SrcHashes $srcHashes
                if ($bad.Count -eq 0) { Write-Output "  already linked -> $Source"; continue }
            }
        }
        Remove-Item -LiteralPath $dest -Recurse -Force
    }

    $usedLink = $false
    if ($wantLink) {
        try {
            New-Item -ItemType SymbolicLink -Path $dest -Target $Source -ErrorAction Stop | Out-Null
            $usedLink = $true
            Write-Output "  linked -> $Source"
        }
        catch {
            try {
                New-Item -ItemType Junction -Path $dest -Target $Source -ErrorAction Stop | Out-Null
                $usedLink = $true
                Write-Output "  junction -> $Source (symlink not permitted)"
            }
            catch {
                Write-Output "  link failed ($($_.Exception.Message.Trim())); falling back to copy"
            }
        }
    }

    if (-not $usedLink) {
        foreach ($f in $srcFiles) {
            $target = Join-Path $dest $f.Rel
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $f.File.FullName -Destination $target -Force
        }
        Write-Output "  copied $($srcFiles.Count) files"
    }
    $touched++

    # Re-read what a host would read, so a silent mismatch cannot pass.
    $bad = Compare-ToSource -Dest $dest -SrcHashes $srcHashes
    if ($bad.Count -eq 0) { Write-Output "  verified: $($srcFiles.Count) files identical" }
    else {
        Write-Output '  VERIFY FAILED:'
        $bad | ForEach-Object { Write-Output "    - $_" }
        $failed++
    }
}

Write-Output ''
if ($Check) {
    if ($failed -eq 0) { Write-Output 'All roots match the source.'; exit 0 }
    Write-Output "$failed root(s) do not match the source."
    exit 1
}
if ($failed -eq 0) {
    Write-Output "Done: updated $touched root(s)."
    Write-Output 'Hosts that cache their skill catalog may need a restart to reload.'
    exit 0
}
Write-Output "Finished with $failed root(s) unresolved."
exit 1
