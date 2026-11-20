<#
.SYNOPSIS
  Updates a mod's version (mod_version in gradle.properties).

.DESCRIPTION
  fabric.mod.json and the jar name pick the version up from gradle.properties
  when the mod is built, so that's the only place it's set. Everything else in
  the file, including line endings, stays as it was.

    ..\java-tools\bump.ps1                  # 0.1.0 -> 0.1.1 (from inside a mod repo)
    ..\java-tools\bump.ps1 -Part minor      # 0.1.0 -> 0.2.0
    ..\java-tools\bump.ps1 -Version 1.0.0
    ..\java-tools\bump.ps1 -Part minor -WhatIf

.PARAMETER Repo
  The mod repo. Defaults to the current folder.

.PARAMETER Part
  Which part of the version to increase: major, minor or patch (default).

.PARAMETER Version
  Set an exact version instead, like 1.0.0.

.PARAMETER WhatIf
  Show the change without making it.
#>
param(
  [string]$Repo = (Get-Location).Path,
  [ValidateSet('major', 'minor', 'patch')][string]$Part = 'patch',
  [string]$Version,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$workspace = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath $Repo)) { $Repo = Join-Path $workspace $Repo }
$Repo = (Resolve-Path -LiteralPath $Repo).Path
$info = Get-ModInfo $Repo
if (-not $info) { throw "$Repo isn't a Fabric mod (no gradle.properties and src\main\resources\fabric.mod.json)." }
if ($info.Version -notmatch '^\d+\.\d+\.\d+$') { throw "mod_version in gradle.properties is '$($info.Version)', not three numbers like 1.0.0." }

if ($Version) {
  if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "-Version must be three numbers, like 1.0.0." }
  $new = $Version
} else {
  $v = @($info.Version.Split('.') | ForEach-Object { [int]$_ })
  $new = switch ($Part) { 'major' { "$($v[0] + 1).0.0" } 'minor' { "$($v[0]).$($v[1] + 1).0" } 'patch' { "$($v[0]).$($v[1]).$($v[2] + 1)" } }
}

Write-Host "$($info.Display): $($info.Version) -> $new"
if ($WhatIf) { Write-Host '  (nothing was changed)' -ForegroundColor Yellow; exit 0 }

$file = Join-Path $Repo 'gradle.properties'
$text = [IO.File]::ReadAllText($file)
$updated = [regex]::Replace($text, '(?m)^(\s*mod_version\s*[=:]\s*)\S+', "`${1}$new")
[IO.File]::WriteAllText($file, $updated, $script:Utf8NoBom)
Write-Host '  gradle.properties updated'
exit 0
