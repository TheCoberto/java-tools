---
name: release-mod
description: Release a Java (Fabric) mod end to end (version bump PR, merge, GitHub release, download the jar, install into Minecraft). Use when the user asks to release, publish or ship a Java mod.
argument-hint: <repo folder> [patch|minor|major]
---

Release the mod named in the arguments ($ARGUMENTS). Default bump: patch for fixes, minor for new features.

1. Make sure the change being released is already merged to the default branch. If it's still uncommitted or on a branch, commit it on a branch, open a PR and merge it first (see CLAUDE.md).
2. Write the notes: 1-4 short player-facing bullets from `git log <last tag>..HEAD` in that repo. Match the style of the previous release (`gh release view -R <owner/repo>`).
3. Preview, then run, from java-tools:
   `powershell -NoProfile -ExecutionPolicy Bypass -File release.ps1 -Repo <folder> -Part <part> -Notes "<notes>" -CommitTrailer "<commit attribution line>" -PrFooter "<PR attribution line>" -WhatIf`
   Use the commit and PR attribution lines Claude Code currently gives you. Drop `-WhatIf` for the real run (timeout 600000).
4. Report the release URL and whether it was installed. If Minecraft was running, say to close it and run `/install-mods`.

If the script stops partway, read its message: it says what to fix and how to resume (usually `-NoBump`).
