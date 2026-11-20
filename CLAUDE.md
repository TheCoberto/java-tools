# Java mod suite

TheCoberto's Minecraft Java mods (Fabric, Minecraft 1.21.1). Each mod is its own GitHub repo next to this one in `..\`; `..\builds\` holds the built mod jars. Scripts here run in Windows PowerShell 5.1: `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`.

## Scripts (use these instead of doing the steps by hand)
- `status.ps1`: one table of what needs doing across every repo (uncommitted, unpushed, open PRs, unreleased changes, builds, installed). Start here.
- `release.ps1 -Repo <folder> -Part patch|minor|major -Notes "..."`: bump → PR → merge → GitHub release → download into builds → install. `-WhatIf` previews, `-NoBump` releases the current version.
- `install.ps1`: installs `builds\` into `.minecraft\mods`, plus Fabric API and Fabric Loader if missing. Needs Minecraft closed.
- `build-all.ps1`, `bump.ps1`: see README.md.

## Conventions
- Never commit to the default branch (`main`). Branch, push, open a PR, wait for checks, merge with a merge commit (`gh pr merge --merge --delete-branch`).
- Changes to READMEs or workflows don't need a release. Changes to the mod (src, Gradle files) do: bump the version (`release.ps1` does it).
- The version lives only in `mod_version` in `gradle.properties`; `fabric.mod.json` and the jar name pick it up at build time.
- Release title: `<Mod name> <version>` (like "Zoom 0.1.0"), tag `v<version>`. Notes: short player-facing bullets, no PR lists. Each repo's GitHub Actions build attaches the jar to the release.
- `builds\` holds only the latest version of each mod, named from `fabric.mod.json`'s `name`, like `Silk-Touch-Spawners-0.1.0.jar`.
- When a mod is folded into or replaced by another, add its mod id to `retired.json`, remove its build, and run `install.ps1`.
- Building needs JDK 25+ to run Gradle (Loom 1.18); the mods target Java 21, which Gradle downloads. The scripts find a JDK themselves, including the one in VS Code's Java extension.
- Other Claude sessions may be working in these repos at the same time. Branch from an up-to-date default branch and check `git log` before assuming a commit is yours.
- Minecraft data: `%APPDATA%\.minecraft` (`mods\`, `versions\`, `launcher_profiles.json`). The Bedrock add-ons and their tools are in `..\..\Minecraft Bedrock\`.
