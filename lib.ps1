# Shared helpers for the java-tools scripts. Load with:  . "$PSScriptRoot/lib.ps1"
# Written for Windows PowerShell 5.1. Keep this file plain ASCII: Windows
# PowerShell misreads non-ASCII characters in .ps1 files saved without a BOM.

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Windows PowerShell 5.1 doesn't enable TLS 1.2 by default.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:NotMods = @('java-tools', 'builds', 'mod-backups')

function Get-RelativePath([string]$Root, [string]$Path) {
  return $Path.Substring($Root.TrimEnd('\', '/').Length).TrimStart('\', '/')
}

# --- Mods -----------------------------------------------------------------------

# A Java .properties file (like gradle.properties) as a hashtable.
function Read-Properties([string]$Path) {
  $props = @{}
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match '^\s*([^#!\s][^=:]*?)\s*[=:]\s*(.*)$') { $props[$matches[1]] = $matches[2].Trim() }
  }
  return $props
}

# "Silk Touch Spawners" -> "Silk-Touch-Spawners", for file names in builds\.
function Get-CleanName([string]$Name) {
  return (($Name -replace '[\\/:*?"<>|]', '').Trim() -replace '\s+', '-')
}

# Name, id and version of the mod in a repo, or $null if the folder isn't a Fabric mod.
function Get-ModInfo([string]$Repo) {
  $propsFile = Join-Path $Repo 'gradle.properties'
  $modJson = Join-Path $Repo 'src\main\resources\fabric.mod.json'
  if (-not (Test-Path -LiteralPath $propsFile) -or -not (Test-Path -LiteralPath $modJson)) { return $null }
  $props = Read-Properties $propsFile
  $mod = [IO.File]::ReadAllText($modJson) | ConvertFrom-Json
  $clean = Get-CleanName $mod.name
  [pscustomobject]@{
    Repo = $Repo; Folder = Split-Path $Repo -Leaf
    Id = [string]$mod.id; Display = [string]$mod.name; CleanName = $clean
    Version = $props['mod_version']; Minecraft = $props['minecraft_version']
    BuildName = "$clean-$($props['mod_version']).jar"
  }
}

# Every mod repo next to java-tools.
function Get-ModRepos([string]$Workspace) {
  @(Get-ChildItem -LiteralPath $Workspace -Directory |
    Where-Object { $_.Name -notin $script:NotMods -and $_.Name -notmatch '^\.' } |
    Where-Object { Get-ModInfo $_.FullName } |
    ForEach-Object { $_.FullName })
}

# fabric.mod.json from inside a mod jar, or $null if it isn't a Fabric mod.
function Read-JarMod([string]$Jar) {
  $zip = $null
  try {
    $zip = [IO.Compression.ZipFile]::OpenRead($Jar)
    $entry = $zip.GetEntry('fabric.mod.json')
    if (-not $entry) { return $null }
    $reader = New-Object IO.StreamReader($entry.Open())
    try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $mod = $json | ConvertFrom-Json
    $mc = $null
    if ($mod.depends -and $mod.depends.minecraft) {
      $m = [regex]::Match([string](@($mod.depends.minecraft)[0]), '\d+\.\d+(\.\d+)?')
      if ($m.Success) { $mc = $m.Value }
    }
    [pscustomobject]@{ Id = [string]$mod.id; Name = [string]$mod.name; Version = [string]$mod.version; Minecraft = $mc; Path = $Jar }
  } catch { return $null }
  finally { if ($zip) { $zip.Dispose() } }
}

# "0.1.0+1.21.1" -> [version]0.1.0, for comparing versions.
function ConvertTo-Version([string]$Text) {
  $m = [regex]::Match($Text, '^\d+(\.\d+){1,3}')
  if ($m.Success) { return [version]$m.Value }
  return [version]'0.0'
}

function Get-FileHashString([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# The mod jar Gradle built (not the -sources jar).
function Get-BuiltJar([string]$Repo) {
  Get-ChildItem -LiteralPath (Join-Path $Repo 'build\libs') -Filter '*.jar' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '-(sources|dev|javadoc)\.jar$' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# Copies a jar into builds\ as <Clean-Name>-<version>.jar and removes older versions of that mod.
function Save-Build([string]$Jar, $Info, [string]$BuildsDir) {
  New-Item -ItemType Directory -Path $BuildsDir -Force | Out-Null
  $pattern = "^$([regex]::Escape($Info.CleanName))-\d+\.\d+\.\d+\.jar$"
  Get-ChildItem -LiteralPath $BuildsDir -Filter '*.jar' -File |
    Where-Object { $_.Name -match $pattern -and $_.Name -ne $Info.BuildName } |
    ForEach-Object { Write-Host "  removed old build $($_.Name)"; Remove-Item -LiteralPath $_.FullName }
  Copy-Item -LiteralPath $Jar -Destination (Join-Path $BuildsDir $Info.BuildName) -Force
  return (Join-Path $BuildsDir $Info.BuildName)
}

# --- Java and Gradle ------------------------------------------------------------

# The newest JDK on this PC with at least the given major version, or $null.
# Loom 1.18 needs Gradle to run on JDK 25. Looks at JAVA_HOME, the usual install
# folders, and the JDK that ships with VS Code's Java extension.
function Find-Jdk([int]$Min = 25) {
  $dirs = New-Object System.Collections.ArrayList
  if ($env:JAVA_HOME) { [void]$dirs.Add($env:JAVA_HOME) }
  $java = Get-Command java -ErrorAction SilentlyContinue
  if ($java) { [void]$dirs.Add((Split-Path (Split-Path $java.Source -Parent) -Parent)) }
  $roots = @(
    (Join-Path $env:ProgramFiles 'Java'), (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
    (Join-Path $env:ProgramFiles 'Microsoft'), (Join-Path $env:ProgramFiles 'Zulu'),
    (Join-Path $env:ProgramFiles 'BellSoft'), (Join-Path $env:ProgramFiles 'Amazon Corretto'),
    (Join-Path $env:USERPROFILE '.jdks'), (Join-Path $env:USERPROFILE '.gradle\jdks')
  )
  foreach ($r in $roots) { Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | ForEach-Object { [void]$dirs.Add($_.FullName) } }
  Get-ChildItem -Path (Join-Path $env:USERPROFILE '.vscode\extensions\redhat.java-*\jre\*') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { [void]$dirs.Add($_.FullName) }

  $best = $null; $bestVersion = 0
  foreach ($d in $dirs | Select-Object -Unique) {
    $release = Join-Path $d 'release'
    if (-not (Test-Path -LiteralPath (Join-Path $d 'bin\javac.exe')) -or -not (Test-Path -LiteralPath $release)) { continue }
    $line = Get-Content -LiteralPath $release | Where-Object { $_ -match '^JAVA_VERSION=' } | Select-Object -First 1
    $m = [regex]::Match([string]$line, '"(1\.)?(\d+)')
    if (-not $m.Success) { continue }
    $major = [int]$m.Groups[2].Value
    if ($major -ge $Min -and $major -gt $bestVersion) { $best = $d; $bestVersion = $major }
  }
  return $best
}

# Runs Gradle in a mod repo with a JDK it can use. Shows the end of the output on failure.
function Invoke-Gradle([string]$Repo, [string[]]$Tasks) {
  $jdk = Find-Jdk
  if (-not $jdk) { throw 'No JDK 25 or newer found. Install one (like Temurin 25) or set JAVA_HOME.' }
  $savedHome = $env:JAVA_HOME; $savedEap = $ErrorActionPreference
  $env:JAVA_HOME = $jdk; $ErrorActionPreference = 'Continue'
  Push-Location -LiteralPath $Repo
  try {
    $out = & (Join-Path $Repo 'gradlew.bat') @Tasks --console=plain 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally { Pop-Location; $env:JAVA_HOME = $savedHome; $ErrorActionPreference = $savedEap }
  if ($code) {
    $out | Select-Object -Last 30 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    throw "gradlew $($Tasks -join ' ') failed in $(Split-Path $Repo -Leaf)."
  }
}

# --- Minecraft ------------------------------------------------------------------

function Get-MinecraftDir { return (Join-Path $env:APPDATA '.minecraft') }

# Minecraft Java started from the launcher (not a runClient test game, which uses the repo's run\ folder).
function Get-MinecraftProcess {
  @(Get-CimInstance Win32_Process -Filter "Name = 'javaw.exe' OR Name = 'java.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '\\\.minecraft\b' -and $_.CommandLine -notmatch 'GradleDaemon|GradleWrapperMain' })
}
