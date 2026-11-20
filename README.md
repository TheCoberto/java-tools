# java-tools

Shared tools for TheCoberto's Minecraft Java (Fabric) mods. Clone it next to the mod repos:

```
C:\Repos\Mods\Minecraft Java\
  java-tools\                          <- this repo
  builds\                              <- every built mod jar ends up here
  silk-touch-spawners-minecraft-java\
  zoom-minecraft-java\
  ...
```

In VS Code, open the `minecraft-java-mod-suite.code-workspace` workspace and use **Ctrl+Shift+P → Tasks: Run Task** to run any of these without typing commands. "This mod" tasks use the mod of the file you have open.

| Script | What it does |
| --- | --- |
| `build-all.ps1` | Builds every mod (or one) into `builds` |
| `install.ps1` | Installs everything in `builds` into Minecraft on this PC, plus Fabric if it's missing |
| `status.ps1` | One table of what still needs doing across every mod |
| `release.ps1` | Releases a mod start to finish: bump, PR, merge, release, build, install |
| `bump.ps1` | Updates a mod's version |

From a terminal, run them with `powershell -ExecutionPolicy Bypass -File <script>`.

**Java:** Gradle needs JDK 25 or newer (Fabric Loom 1.18 requires it). The scripts use `JAVA_HOME` if it's new enough, otherwise the newest JDK they find in the usual install folders or in VS Code's Java extension. The mods themselves target Java 21, which Gradle downloads when needed.

## build-all.ps1

```powershell
.\build-all.ps1                              # every mod, from java-tools
.\build-all.ps1 -Repo zoom-minecraft-java    # one mod
```

Runs `gradlew build` in each mod and copies the jar into `builds\` as `<Mod-Name>-<version>.jar` (the name comes from `fabric.mod.json`, the version from `gradle.properties`), removing older versions of that mod. A mod that fails to build is listed at the end; the rest still build.

## install.ps1

```powershell
.\install.ps1              # from java-tools
.\install.ps1 -WhatIf      # show what would change
.\install.ps1 -NoFabric    # don't install Fabric API or Fabric Loader
.\install.ps1 -Force       # install even while Minecraft is running
```

Installs every mod in `builds\` into `%APPDATA%\.minecraft\mods`:

- Each mod **replaces** any installed jar with the same mod id (read from the jar's `fabric.mod.json`), whatever it's called, instead of being added next to it.
- Mods that already match the build are left alone.
- If `builds\` holds several versions of a mod, only the newest is installed.
- Every replaced or removed jar is backed up to `mod-backups\<date>` next to the repos.
- Mods listed in `retired.json` are removed. List a mod there when another one replaces it.
- Jars that aren't in `builds\` or `retired.json` are never touched.

It also makes sure the mods can load:

- **Fabric API:** if no version of it is in `mods\`, the newest release for the mods' Minecraft version is downloaded from Modrinth. An installed Fabric API is never changed.
- **Fabric Loader:** if the launcher has no `fabric-loader-*-<version>` installation for that Minecraft version, the official Fabric installer adds one. Pick it in the Minecraft Launcher to play with the mods.

Close Minecraft first: Windows locks mod jars while the game runs, so the script stops if it's running (unless you pass `-Force`). Test games started with `gradlew runClient` don't count; they use the repo's own `run\` folder.

## status.ps1

```powershell
.\status.ps1            # from java-tools
.\status.ps1 -NoFetch   # skip fetching from GitHub (faster)
```

One row per repo: uncommitted or unpushed work, open PRs, the latest release, mod changes since that release, and whether `builds\` has the current version. Then whether Minecraft has everything in `builds\` installed. READMEs, other Markdown files, `.github` and git settings don't count as changes. Exits with code 1 when something needs doing.

## release.ps1

```powershell
.\release.ps1 -Repo zoom-minecraft-java -Part minor -Notes "- Adds a zoom key."
.\release.ps1 -Repo zoom-minecraft-java -Part minor -Notes "..." -WhatIf   # show the plan only
.\release.ps1 -Repo zoom-minecraft-java -NoBump -Notes "..."               # release the version already in gradle.properties
```

Commit and merge the change first; this does the rest:

1. Checks the repo is on its default branch, clean, and pushed, and pulls.
2. Bumps the version on a `release-<version>` branch and adds the notes to the mod's `changelog.txt`/`.md` if it has one (in that file's style; an `Unreleased` heading is renamed to the version instead). Opens a PR, waits for the checks and merges it.
3. Creates the GitHub release `v<version>`, titled `<Mod name> <version>`.
4. Waits for the release build (each repo's GitHub Actions workflow attaches the jar), downloads the jar into `builds\` and removes older versions of that mod.
5. Runs `install.ps1`, unless Minecraft is running or you pass `-NoInstall`.

`-CommitTrailer` and `-PrFooter` add lines to the end of the bump commit and PR description.

## bump.ps1

```powershell
..\java-tools\bump.ps1                  # 0.1.0 -> 0.1.1 (from inside a mod repo)
..\java-tools\bump.ps1 -Part minor      # 0.1.0 -> 0.2.0
..\java-tools\bump.ps1 -Part major      # 0.1.0 -> 1.0.0
..\java-tools\bump.ps1 -Version 2.0.0
..\java-tools\bump.ps1 -Part minor -WhatIf
```

Sets `mod_version` in `gradle.properties`. That's the only place the version lives: `fabric.mod.json` and the jar name pick it up when the mod is built. Add a changelog entry afterwards if the mod has one.

## GitHub Actions

Every mod repo has its own `.github/workflows/build.yml`, which builds the mod on every push and pull request (the jar is saved with the run under Actions → the run → Artifacts) and attaches the jar to every published release. It runs Gradle on JDK 25.

## Working with Claude Code

Start Claude Code in this folder. `CLAUDE.md` holds the suite's conventions, and `.claude/skills/` adds three commands:

| Command | What it does |
| --- | --- |
| `/suite-status` | Runs `status.ps1` and lists only what needs doing |
| `/release-mod <repo> [patch\|minor\|major]` | Writes release notes and runs `release.ps1` |
| `/install-mods` | Runs `install.ps1` after checking Minecraft is closed |
