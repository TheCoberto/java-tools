---
name: suite-status
description: Show what still needs doing across all of TheCoberto's Java (Fabric) mods (uncommitted, unpushed, open PRs, unreleased changes, builds, installed in Minecraft). Use when the user asks if everything is up to date, released, built or installed.
---

Run from java-tools: `powershell -NoProfile -ExecutionPolicy Bypass -File status.ps1` (timeout 300000).

Exit code 0 means everything is committed, pushed, released, built and installed. Otherwise summarize only the rows that need attention and suggest the fix:
- Local not ok: commit on a branch, PR, merge (CLAUDE.md).
- Open PRs: ask whether to merge them.
- To do: release with `/release-mod <repo>`.
- Build missing or old: `/release-mod` downloads it; for an existing release, `gh release download <tag> -R <owner/repo> -D ..\builds -p *.jar`, rename it to `<Mod-Name>-<version>.jar` and remove the older version.
- Minecraft not up to date: `/install-mods`.

Don't repeat the whole table back to the user.
