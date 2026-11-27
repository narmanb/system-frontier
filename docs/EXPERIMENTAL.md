# Experimental: RECYCLE BIN (endless survival)

Branch `experimental/recycle-bin`. This is new content, not part of the legacy port. Its APK
gets its own link and never replaces the normal test build:
https://github.com/narmanb/system-frontier/releases/download/experimental-recycle-bin-latest/SystemFrontier.apk

**How to play:** Main menu → Free Flight → pick a hull → **Recycle Bin (Endless)**.

Hostile programs from every faction are trying to empty the Recycle Bin. Survive as long as
you can.
- A 4-second "get ready" countdown before wave 1.
- Wave *n* brings 1 + *n* hostiles (up to 14) at threat 1 + *n*/2 (up to 6).
  Skirmishers join from wave 3 and beam ships from wave 5. A hazard is added every second wave.
- **Every fifth wave a PURGE DAEMON appears.** It's an orange mini Inner Demon with
  220 + 60·level hull that fires rapid bolts and seeds virus clouds.
- Each wave also drops two bonus files worth extra points.
- **Between waves (8 s):** +25% hull, +2 missiles, two fuel cells, and the ambulance shop is
  open (✚ / A key / pause menu). Credits come from kills.
- **Score:** 25 × wave per kill, (20 + 10 × wave) per recovered file, and 100 × wave per
  cleared wave. Best score, best wave and run count are saved (`user://records.json`). The
  Free Flight button shows your best.

The bot pilot (`autoplay.tscn -- --endless`) usually clears 2–6 waves. A careful human should
do better.

Code: `SimWorld.setup_endless`, `spawn_purge_daemon`, the endless section of
`MissionController`, and `SaveService.record_endless`. Tests: `tests/test_endless.gd`.
