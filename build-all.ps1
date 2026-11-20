<#
.SYNOPSIS
  Builds every mod (or one) and puts the jars in the builds folder.

.DESCRIPTION
  Runs "gradlew build" in each mod repo next to java-tools and copies the jar
  into builds\ as <Mod-Name>-<version>.jar (like Zoom-0.1.0.jar), removing older
  versions of that mod. A mod that fails to build is listed at the end; the
  rest still build.

  Gradle needs JDK 25 or newer. JAVA_HOME is used if it's new enough, otherwise
  the newest JDK found on this PC (including the one VS Code's Java extension
  ships with).

    powershell -ExecutionPolicy Bypass -File build-all.ps1               # every mod
    powershell -ExecutionPolicy Bypass -File build-all.ps1 -Repo zoom-minecraft-java

  For a release, use release.ps1 instead: it puts the GitHub release's jar in builds\.

.PARAMETER Workspace
  The folder that holds the mod repos. Defaults to the folder java-tools is in.

.PARAMETER Repo
  Build only this mod: a folder name next to java-tools, or a path.

.PARAMETER OutDir
  Where to put the jars. Defaults to <Workspace>\builds.
#>
param(
  [string]$Workspace = (Split-Path $PSScriptRoot -Parent),
  [string]$Repo,
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
if (-not $OutDir) { $OutDir = Join-Path $Workspace 'builds' }

if ($Repo) {
  if (-not (Test-Path -LiteralPath $Repo)) { $Repo = Join-Path $Workspace $Repo }
  $repos = @((Resolve-Path -LiteralPath $Repo).Path)
  if (-not (Get-ModInfo $repos[0])) { throw "$($repos[0]) isn't a Fabric mod." }
} else {
  $repos = Get-ModRepos $Workspace
}

$jdk = Find-Jdk
if (-not $jdk) { throw 'No JDK 25 or newer found. Install one (like Temurin 25) or set JAVA_HOME.' }
Write-Host "Building $($repos.Count) mod(s) into $OutDir (JDK: $jdk)"

$failed = @()
foreach ($r in $repos) {
  $info = Get-ModInfo $r
  try {
    Invoke-Gradle $r @('build')
    $jar = Get-BuiltJar $r
    if (-not $jar) { throw 'no jar in build\libs' }
    Save-Build $jar.FullName $info $OutDir | Out-Null
    Write-Host "  built $($info.BuildName)" -ForegroundColor Green
  } catch {
    $failed += $info.Folder
    Write-Host "  FAILED $($info.Folder): $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host ''
$built = $repos.Count - $failed.Count
Write-Host "Built $built of $($repos.Count) mod(s)." -ForegroundColor $(if ($failed.Count) { 'Yellow' } else { 'Green' })
if ($failed.Count) { Write-Host "Failed to build: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
exit 0
