<#
.SYNOPSIS
  Installs the mods in the builds folder into Minecraft Java on this PC.

.DESCRIPTION
  Copies every mod in builds\ into .minecraft\mods:
    - Each mod replaces the installed jar with the same mod id (from its
      fabric.mod.json), whatever that jar is called, instead of being added
      next to it.
    - Mods that already match the build are left alone.
    - If builds holds several versions of a mod, only the newest is used.
    - Every replaced or removed jar is backed up first, to <Workspace>\mod-backups.
    - Mods listed in retired.json (replaced by another mod) are removed.
  Jars that aren't in builds or retired.json are never touched.

  It also makes sure the mods can load:
    - Fabric API: downloaded from Modrinth into mods\ if it isn't there.
    - Fabric Loader: if the launcher has no Fabric profile for the mods'
      Minecraft version, the official Fabric installer adds one.
  Pass -NoFabric to skip both.

  Close Minecraft first: Windows locks jars while the game is running.

    powershell -ExecutionPolicy Bypass -File install.ps1            # from java-tools
    powershell -ExecutionPolicy Bypass -File install.ps1 -WhatIf    # show what would change

.PARAMETER Workspace
  The folder that holds the mod repos. Defaults to the folder java-tools is in.

.PARAMETER BuildsDir
  Where the mod jars are. Defaults to <Workspace>\builds.

.PARAMETER MinecraftDir
  The .minecraft folder. Defaults to %APPDATA%\.minecraft.

.PARAMETER NoFabric
  Don't install Fabric API or Fabric Loader.

.PARAMETER WhatIf
  Show what would change without changing anything.

.PARAMETER Force
  Install even while Minecraft is running.
#>
param(
  [string]$Workspace = (Split-Path $PSScriptRoot -Parent),
  [string]$BuildsDir,
  [string]$MinecraftDir,
  [switch]$NoFabric,
  [switch]$WhatIf,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
if (-not $BuildsDir) { $BuildsDir = Join-Path $Workspace 'builds' }
if (-not (Test-Path -LiteralPath $BuildsDir)) { throw "No builds folder at $BuildsDir. Run build-all.ps1 first." }
if (-not $MinecraftDir) { $MinecraftDir = Get-MinecraftDir }
if (-not (Test-Path -LiteralPath $MinecraftDir)) { throw "Couldn't find $MinecraftDir. Install Minecraft Java and start it once, or pass -MinecraftDir." }
$modsDir = Join-Path $MinecraftDir 'mods'
Write-Host "Minecraft folder: $MinecraftDir"

$running = Get-MinecraftProcess
if ($running.Count -and -not $Force -and -not $WhatIf) {
  throw 'Minecraft Java is running. Close it first (Windows locks mod jars while it runs), or pass -Force.'
}

$backupDir = Join-Path (Join-Path $Workspace 'mod-backups') (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
$counts = @{ same = 0; replaced = 0; installed = 0; removed = 0 }

function Backup-Jar([string]$Path) {
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  Move-Item -LiteralPath $Path -Destination (Join-Path $backupDir (Split-Path $Path -Leaf))
}

# Installed mods, by mod id. A mod can be installed more than once (old copies).
$installed = @{}
foreach ($jar in Get-ChildItem -LiteralPath $modsDir -Filter '*.jar' -File -ErrorAction SilentlyContinue) {
  $mod = Read-JarMod $jar.FullName
  if (-not $mod) { continue }
  if (-not $installed.ContainsKey($mod.Id)) { $installed[$mod.Id] = New-Object System.Collections.ArrayList }
  [void]$installed[$mod.Id].Add($mod)
}

# The newest build of each mod.
$newest = @{}
foreach ($jar in Get-ChildItem -LiteralPath $BuildsDir -Filter '*.jar' -File) {
  $mod = Read-JarMod $jar.FullName
  if (-not $mod) { Write-Host "  ERROR $($jar.Name) isn't a Fabric mod (no fabric.mod.json)." -ForegroundColor Red; continue }
  if ($newest.ContainsKey($mod.Id) -and (ConvertTo-Version $newest[$mod.Id].Version) -ge (ConvertTo-Version $mod.Version)) { continue }
  $newest[$mod.Id] = $mod
}

foreach ($id in $newest.Keys | Sort-Object) {
  $build = $newest[$id]
  $label = "$($build.Name) $($build.Version)  [$(Split-Path $build.Path -Leaf)]"
  $old = @(if ($installed.ContainsKey($id)) { $installed[$id] })
  $target = Join-Path $modsDir (Split-Path $build.Path -Leaf)

  $hash = Get-FileHashString $build.Path
  if ($old.Count -eq 1 -and $old[0].Path -eq $target -and (Get-FileHashString $old[0].Path) -eq $hash) {
    $counts.same++
    continue
  }

  if ($old.Count) {
    Write-Host "  update   $label (replaces $(@($old | ForEach-Object { Split-Path $_.Path -Leaf }) -join ', '))" -ForegroundColor Cyan
    $counts.replaced++
  } else {
    Write-Host "  install  $label" -ForegroundColor Green
    $counts.installed++
  }
  if ($WhatIf) { continue }

  foreach ($o in $old) { Backup-Jar $o.Path }
  New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
  Copy-Item -LiteralPath $build.Path -Destination $target -Force
}

# Retired mods: replaced by another mod.
$retiredFile = Join-Path $PSScriptRoot 'retired.json'
if (Test-Path -LiteralPath $retiredFile) {
  foreach ($r in @(([IO.File]::ReadAllText($retiredFile) | ConvertFrom-Json).mods)) {
    if (-not $r -or -not $installed.ContainsKey($r.id) -or $newest.ContainsKey($r.id)) { continue }
    foreach ($o in $installed[$r.id]) {
      Write-Host "  remove   $(Split-Path $o.Path -Leaf) ($($r.reason))" -ForegroundColor Magenta
      $counts.removed++
      if (-not $WhatIf) { Backup-Jar $o.Path }
    }
  }
}

# Fabric API and Fabric Loader, for the Minecraft version the mods are built for.
if (-not $NoFabric -and $newest.Count) {
  $versions = @($newest.Values | ForEach-Object { $_.Minecraft } | Where-Object { $_ } | Sort-Object -Unique)
  if ($versions.Count -gt 1) { Write-Host "  warn  The mods are built for different Minecraft versions: $($versions -join ', '). Using $($versions[-1])." -ForegroundColor Yellow }
  $mc = if ($versions.Count) { $versions[-1] } else { $null }

  if ($mc -and -not $installed.ContainsKey('fabric-api')) {
    $query = 'loaders=' + [uri]::EscapeDataString('["fabric"]') + '&game_versions=' + [uri]::EscapeDataString("[`"$mc`"]")
    $headers = @{ 'User-Agent' = 'java-tools-mod-installer' }
    # Windows PowerShell passes a JSON array down the pipeline as one object, so store it first.
    $list = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/project/fabric-api/version?$query" -Headers $headers
    $api = $list | Where-Object { $_.version_type -eq 'release' } | Select-Object -First 1
    if (-not $api) { Write-Host "  warn  Couldn't find a Fabric API release for Minecraft $mc on Modrinth." -ForegroundColor Yellow }
    else {
      $file = @($api.files | Where-Object { $_.primary }) + @($api.files) | Select-Object -First 1
      Write-Host "  install  Fabric API $($api.version_number)  [from Modrinth]" -ForegroundColor Green
      $counts.installed++
      if (-not $WhatIf) {
        New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
        Invoke-WebRequest -Uri $file.url -Headers $headers -OutFile (Join-Path $modsDir $file.filename) -UseBasicParsing
      }
    }
  }

  $hasLoader = $mc -and @(Get-ChildItem -LiteralPath (Join-Path $MinecraftDir 'versions') -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "^fabric-loader-.+-$([regex]::Escape($mc))$" }).Count -gt 0
  if ($mc -and -not $hasLoader) {
    Write-Host "  install  Fabric Loader for Minecraft $mc  [adds a 'fabric-loader-$mc' launcher profile]" -ForegroundColor Green
    $counts.installed++
    if (-not $WhatIf) {
      $java = Find-Jdk 8
      if (-not $java) { throw 'Installing Fabric Loader needs Java. Install a JDK or set JAVA_HOME.' }
      $installers = Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer'
      $installer = $installers | Where-Object { $_.stable } | Select-Object -First 1
      $jar = Join-Path ([IO.Path]::GetTempPath()) "fabric-installer-$($installer.version).jar"
      Invoke-WebRequest -Uri $installer.url -OutFile $jar -UseBasicParsing
      try {
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & (Join-Path $java 'bin\java.exe') -jar $jar client -dir $MinecraftDir -mcversion $mc 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE; $ErrorActionPreference = $saved
        if ($code) { $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }; throw 'The Fabric installer failed.' }
      } finally { Remove-Item -LiteralPath $jar -ErrorAction SilentlyContinue }
    }
  }
}

Write-Host ''
$summary = "$($counts.replaced) updated, $($counts.installed) installed, $($counts.removed) removed, $($counts.same) already up to date."
if ($WhatIf) { Write-Host "Would change: $summary (nothing was changed)" -ForegroundColor Yellow; exit 0 }
Write-Host $summary -ForegroundColor Green
if (Test-Path -LiteralPath $backupDir) { Write-Host "Old copies are in $backupDir" }
if ($running.Count) { Write-Host 'Restart Minecraft to load the changes.' -ForegroundColor Yellow }
exit 0
