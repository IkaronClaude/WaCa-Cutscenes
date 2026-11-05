# Nexus Mods page - WaCa Cutscenes

<!-- Paste-ready text for the Nexus Mods upload form. Replace the TODO links once the pages exist. -->

**Name:** WaCa Cutscenes
**Version:** 0.2.0
**Category:** Gameplay / Modders resources
**Summary (short description, max 350 characters):**
Cutscenes from plain text: the cats of a scene in a premade shape (two sides facing, a ring, a clan meeting, a
ceremony), then a timeline - cats walk in, hiss, sit, speak their lines, the camera cuts between named shots. No
coordinates, no 3D work - for story writers.

---

## Description
Write a cutscene in a few lines of an ini file - who stands where, what happens when, and what the camera shows:

```
[Cutscene.Standoff]
Place = Here
Shape = Facing
A = Player, Deputy
B = Nearest, Nearest
Beat1 = 0 WalkIn: B
Beat2 = 4 Camera: Two = A1 & B1 ~2
Beat3 = 6 Say: B1 = You took your time.
Beat4 = 9 Pose: A2 = Growl
Beat5 = 9 Camera: Portrait = A2
Beat6 = 16 End
```

- **Shapes** - premade arrangements: two sides facing, a ring, a row, a pair, a clan meeting, a ceremony. Make your
  own in a few lines.
- **The cast by part** - your cat, the leader, the deputy, the medicine cat, a cat by name, the nearest clanmate.
- **Beats** - walk in, walk up to a cat, turn, the game's own animations (sit, hiss, growl, meow, groom ...), lines on
  screen with the cat's name.
- **Camera shots by name** - wide, high, a slow orbit, a portrait, over the shoulder, a two-shot - cut or moved to.
- Your keys and the HUD are off while it plays; afterwards every cat is back where it was.

Play them from **WaCa Clan Life**'s scenes (`Cutscene: <Name>`), from your own mod, or with a preview key while you
write.

## Requirements
- **UE4SS for Warrior Cats** - https://www.nexusmods.com/warriorcatsclansoftheforest/mods/2
- **WaCa Core** - TODO: Nexus link
- Optional: **WaCa Clan Life** (scenes that play cutscenes) - TODO: Nexus link

## Installation
1. Install UE4SS for Warrior Cats and WaCa Core (see their pages).
2. Extract this zip into the game's folder (Steam > right-click the game > Manage > Browse local files):
   `Wrc\Binaries\Win64\ue4ss\Mods\WaCaCutscenes` exists afterwards.
3. Write your cutscenes - see the README in that folder.

**Uninstall:** delete `ue4ss\Mods\WaCaCutscenes`. Vortex: untested - install manually.

## Compatibility
Tested with the Steam version of the game, October 2026 build. Experimental: tell us what your stories need.

## Source code & contributing
Open source (Apache 2.0): https://github.com/IkaronClaude/WaCa-Cutscenes - shapes, cutscenes and pull requests
are very welcome.

## AI disclosure
Much of this mod's code and documentation was written with AI assistance (Claude, by Anthropic), directed, tested and
released by the author.

## Permissions
Open source under the Apache License 2.0: use it, modify it, include it in modpacks, upload changed versions - keep
the licence and credit.

## Changelog
- 0.2.0 - a cutscene can bring your cat home after it (PutPlayerBack per scene); two-shots keep both cats in view; the
  writer is told when a place is too cramped to film; lines only show once you are in the world.
- 0.1.0 - first version: shapes, places, the cast by part, beats, named camera shots; Clan Life's `Cutscene:` step.
