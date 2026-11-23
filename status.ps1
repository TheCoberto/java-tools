<#
.SYNOPSIS
  One table showing what still needs doing across every mod.

.DESCRIPTION
  For each mod repo (and java-tools), shows:
    - Local:     uncommitted files, commits not pushed, or behind GitHub
    - PRs:       open pull requests
    - Release:   the latest GitHub release
    - To do:     mod changes since that release, or a version that isn't released yet
    - Build:     whether builds\fabric\ has the current version's jar
  Then whether Minecraft has everything in builds\fabric\ installed.

  READMEs, other Markdown files, .github, git settings and paper-plugin\ (the
  Paper plugin version) don't count as changes: they aren't part of the Fabric
  mod, so they don't need a release.

    powershell -ExecutionPolicy Bypass -File status.ps1            # from java-tools
    powershell -ExecutionPolicy Bypass -File status.ps1 -NoFetch   # skip git fetch (faster)

  Exits with code 1 when something needs doing.

.PARAMETER Workspace
  The folder that holds the mod repos. Defaults to the folder java-tools is in.

.PARAMETER NoFetch
  Don't fetch from GitHub first. Faster, but Local and To do may be out of date.
#>
param(
  [string]$Workspace = (Split-Path $PSScriptRoot -Parent),
  [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$buildsDir = Join-Path $Workspace 'builds\fabric'
$repos = @(Get-ModRepos $Workspace) + @($PSScriptRoot) | Where-Object { Test-Path (Join-Path $_ '.git') }

# Windows PowerShell turns redirected error output into a failure, so relax that here.
function Invoke-Git([string]$Repo) {
  $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { return (& git -C $Repo @args 2>$null) } finally { $ErrorActionPreference = $saved }
}

# Local state of every repo.
$rows = foreach ($repo in $repos) {
  if (-not $NoFetch) { Invoke-Git $repo fetch --quiet --prune --tags | Out-Null }
  $url = (Invoke-Git $repo remote get-url origin) | Select-Object -First 1
  $slug = if ($url -match 'github\.com[:/](.+?)(\.git)?$') { $matches[1] } else { $null }
  # Repos that were pushed rather than cloned don't know GitHub's default branch yet.
  $headRef = Invoke-Git $repo symbolic-ref --short refs/remotes/origin/HEAD
  if (-not $headRef -and -not $NoFetch) {
    Invoke-Git $repo remote set-head origin --auto | Out-Null
    $headRef = Invoke-Git $repo symbolic-ref --short refs/remotes/origin/HEAD
  }
  $default = ([string]$headRef) -replace '^origin/', ''
  if (-not $default) { $default = 'main' }
  $branch = Invoke-Git $repo branch --show-current
  $dirty = @(Invoke-Git $repo status --porcelain).Count
  $counts = (Invoke-Git $repo rev-list --left-right --count "HEAD...origin/$default") -split '\s+'
  $unpushed = @(Invoke-Git $repo log --branches --not --remotes --oneline).Count

  $local = @()
  if ($branch -ne $default) { $local += "on $branch" }
  if ($dirty) { $local += "$dirty uncommitted" }
  if ($unpushed) { $local += "$unpushed unpushed" }
  if ($counts.Count -eq 2 -and [int]$counts[1] -gt 0) { $local += "$($counts[1]) behind" }

  $isTools = ($repo -eq $PSScriptRoot)
  $info = if (-not $isTools) { Get-ModInfo $repo } else { $null }

  [pscustomobject]@{
    Name = Split-Path $repo -Leaf; Repo = $repo; Slug = $slug; Default = $default; IsTools = $isTools; Info = $info
    Local = if ($local) { $local -join ', ' } else { 'ok' }
    PRs = '?'; Release = '?'; Todo = ''; Build = ''
  }
}

# Open PRs and latest release for every repo, in one GitHub query.
$withSlug = @($rows | Where-Object Slug)
$parts = for ($i = 0; $i -lt $withSlug.Count; $i++) {
  $owner, $name = $withSlug[$i].Slug -split '/', 2
  "r$i`: repository(owner: `"$owner`", name: `"$name`") { pullRequests(states: OPEN) { totalCount } latestRelease { tagName } releases(first: 1, orderBy: {field: CREATED_AT, direction: DESC}) { nodes { tagName isPrerelease } } }"
}
$github = $null
# The query goes through a file: Windows PowerShell mangles quotes in arguments to other programs.
$queryFile = [IO.Path]::GetTempFileName()
try {
  [IO.File]::WriteAllText($queryFile, "{ $($parts -join ' ') }")
  $ErrorActionPreference = 'Continue'
  $json = & gh api graphql -F "query=@$queryFile" 2>$null
  if ($LASTEXITCODE -eq 0) { $github = ($json -join "`n" | ConvertFrom-Json).data }
} catch {} finally { $ErrorActionPreference = 'Stop'; Remove-Item -LiteralPath $queryFile -ErrorAction SilentlyContinue }
if (-not $github) { Write-Host 'Could not reach GitHub; PRs and releases are unknown.' -ForegroundColor Yellow }

for ($i = 0; $i -lt $withSlug.Count; $i++) {
  $row = $withSlug[$i]
  if (-not $github) { continue }
  $r = $github."r$i"
  if (-not $r) { continue }
  $row.PRs = [string]$r.pullRequests.totalCount
  $tag = if ($r.latestRelease) { $r.latestRelease.tagName } elseif ($r.releases.nodes) { $r.releases.nodes[0].tagName + ' (pre)' } else { $null }
  $row.Release = if ($tag) { $tag } elseif ($row.IsTools) { '-' } else { 'none' }
}

# What still needs releasing, and whether builds\fabric\ has the current version.
foreach ($row in $rows | Where-Object { -not $_.IsTools }) {
  $tag = ($row.Release -replace ' \(pre\)$', '')
  $todo = @()
  if ($tag -and $tag -notin @('?', 'none')) {
    if ($row.Info.Version -and ($tag -replace '^v', '') -ne $row.Info.Version) { $todo += "$($row.Info.Version) not released" }
    $changed = @(Invoke-Git $row.Repo diff --name-only $tag "origin/$($row.Default)" |
      Where-Object { $_ -notmatch '(^|/)README|\.md$|^\.github/|^\.git(attributes|ignore)$|^LICENSE|^paper-plugin/' })
    if ($changed.Count) { $todo += "$($changed.Count) file(s) changed since $tag" }
  } elseif ($tag -eq 'none') { $todo += 'never released' }
  $row.Todo = if ($todo) { $todo -join ', ' } else { '-' }

  $info = $row.Info
  $have = Test-Path -LiteralPath (Join-Path $buildsDir $info.BuildName)
  $old = @(Get-ChildItem -LiteralPath $buildsDir -Filter "$($info.CleanName)-*.jar" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $info.BuildName -and $_.Name -match "^$([regex]::Escape($info.CleanName))-\d+\.\d+\.\d+\.jar$" })
  $row.Build = if (-not $have) { "missing $($info.BuildName)" } elseif ($old) { "old: $($old.Name -join ', ')" } else { 'ok' }
}

$rows | Sort-Object { $_.IsTools }, Name |
  Format-Table @{ n = 'Mod'; e = { $_.Name } }, Local, PRs, Release, @{ n = 'To do'; e = { $_.Todo } }, Build -AutoSize |
  Out-String -Width 200 | Write-Host

# Installed in Minecraft?
$install = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'install.ps1') -Workspace $Workspace -WhatIf 2>&1 |
  ForEach-Object { "$_" } | Where-Object { $_ -match 'Would change|update|install |remove|ERROR|warn' }
$installLine = ($install | Where-Object { $_ -match 'Would change' }) -replace '\s*\(nothing was changed\)', ''
$installOk = $installLine -match '^Would change: 0 updated, 0 installed, 0 removed'
if ($installOk) { Write-Host 'Minecraft: everything in builds\fabric is installed.' -ForegroundColor Green }
else { Write-Host 'Minecraft: not up to date. Run install.ps1:' -ForegroundColor Yellow; $install | ForEach-Object { Write-Host "  $($_.Trim())" } }

$needs = @($rows | Where-Object {
  $_.Local -ne 'ok' -or ($_.PRs -notin @('0', '?')) -or ($_.Todo -notin @('', '-')) -or ($_.Build -notin @('', 'ok'))
})
if ($needs.Count -or -not $installOk) {
  if ($needs.Count) { Write-Host "Needs attention: $(@($needs.Name) -join ', ')" -ForegroundColor Yellow }
  exit 1
}
Write-Host 'Everything is committed, pushed, released, built and installed.' -ForegroundColor Green
exit 0
