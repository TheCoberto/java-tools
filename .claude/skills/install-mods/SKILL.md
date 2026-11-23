---
name: install-mods
description: Install the mods in builds\fabric into Minecraft Java on this PC (.minecraft\mods), replacing old versions, removing retired mods and setting up Fabric if needed. Use when the user wants to play or test the Java mods.
---

1. From java-tools, preview: `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -WhatIf`.
2. If nothing would change, say so and stop.
3. If Minecraft Java is running, ask the user to close it first (Windows locks mod jars while it runs). Don't use `-Force` unless they ask.
4. Run `install.ps1` (timeout 300000), then report what was updated, installed or removed in one or two lines, and where the backups went.

To play, pick the `fabric-loader-<version>` installation in the Minecraft Launcher.
