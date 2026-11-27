# Overnight work report

All of this is on branch `ccr-61cb5a6c-ktfovg`. Each push rebuilt the APK at
https://github.com/narmanb/system-frontier/releases/download/dev-latest/SystemFrontier.apk

## 1. Automated playtester (`tools/autoplay.tscn`)
A scripted pilot flies every campaign directory at three difficulties through the real
simulation, with no rendering: 144 runs in about 25 seconds. CI runs it in action and strategy
mode and fails if any mission family becomes impossible.
- **Found and fixed:** an NPC collector can take the last clean icon and flee, and nothing told
  you why the counter said 3/4. Now a message names the carrier ("destroy it to drop the icon")
  and the radar rings carriers in cyan.
- **Found and fixed:** strategy (autopilot) mode could not finish rescue, repair, scan, race
  or courier. It never braked, so it orbited past objectives until the fuel ran out. The
  autopilot now uses arrival steering: it brakes, holds still on nodes, stands off to aim, and
  shoots icon carriers.
- Results: every mission family is completable in both modes. Locked Duel is the only one
  where the bot sometimes dies. See `docs/PLAYTEST_REPORT.md` and
  `docs/PLAYTEST_REPORT_STRATEGY.md`.

## 2. Gamepad / Retroid Pocket 5
- Every menu and popup works with buttons: D-pad/stick to move, A to select, B to go back or
  close a popup. Lists scroll to the focused item.
- In flight: Start pauses and resumes, B resumes from pause, Select opens the map and B
  closes it, and the R key / pause menu shows faction relations. In strategy mode, left/right
  cycles the autopilot priority.
- Ship Factory: Y turns on the precision cursor, D-pad/stick moves it, A paints (hold A while
  moving to draw lines), LB/RB switch tabs, LT/RT zoom, and B backs out.
- The touch pads hide automatically while you use the gamepad.
- `tools/gamepad_check.tscn` presses simulated buttons through the real screens. It runs in CI.

## 3. Visual audit at phone and Retroid sizes (`tools/audit_capture.tscn`)
Every screen and popup was captured at 1200×540, 540×1200 and 960×540. Fixed:
- Factory in landscape: the tool buttons were pushed off-screen. They now sit beside the canvas.
- In flight on narrow phones: the icon/missile chips collided with the radar. They now tuck
  under the status window.
- The directory map opens at the top with the first directory selected. The tactical map is
  centred on tall screens.
- The HUD, radar, touch pads and menus now avoid camera cutouts and rounded corners (safe area).

## 4. Performance (`tools/bench.tscn`, `docs/PERFORMANCE.md`)
Simulation is about 0.03 ms per step. Per frame, drawing costs about 0.6 ms for the space view,
0.2 ms for the HUD and 0.5 ms for the Factory canvas. There are no hot spots worth optimising
for a Snapdragon-class device.

## 5. More tests and parity
- Faction-world tests: Pirates attack other factions without the player getting involved,
  hostile relations make spawns aggressive, and kills cost relation.
- Fuzz test: random play in all 12 directories in both modes keeps state sane (no NaN,
  nothing negative, no stuck dialogs).
- The precision pad now matches the full legacy version (Hold to Draw, Auto Draw, Fine, speed).
- Release notes on the APK page list the recent changes.
- Tests: 52 unit/behaviour tests, plus the smoke run, autoplay (both modes) and the gamepad
  check, all in CI.

## Still needs you
- A real-device playtest on your phone and the Retroid: touch sizes, feel, frame rate.
- Decisions when convenient: the real-drive feature (later), moving the legacy HTML out of
  the public repo once you're happy with the port.
