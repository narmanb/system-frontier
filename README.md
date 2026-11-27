# System Frontier

A retro "directory space" flight, salvage and faction-warfare game: pilot a pixel-art ship
through a computer's file system, recover icons, and survive (or exploit) the factions
fighting over them. It's an original spiritual successor to the 1990s game *Operation: Inner Space*.

This repository holds the **native Godot 4 / GDScript port** of the earlier single-file HTML
build. The HTML build is kept under `legacy/` as the frozen reference implementation.

> **Status: campaign, saves, all ten mission families and the Ship Factory are ported.**
> What's left is platform polish and device sign-off (see the roadmap). See [docs/ROADMAP.md](docs/ROADMAP.md) and
> [docs/PARITY_MATRIX.md](docs/PARITY_MATRIX.md) for what's ported, what's tested, and what's left.

## What's playable now

The interface keeps the legacy build's Windows 95 look. In flight the HUD stays compact: a status window, an icon/missile chip bar with a pause button, and a draggable radar window. Tap the radar for the tactical map.


- Title screen with the five retained starter hulls (Red Falcon, Nova Sting, Wisp Needle,
  Blockade Ram, Cargo Warden). Each hull shows live engineering telemetry.
- **Flight sandbox**: icon recovery, fuel cells, exit gate, and NPC traffic from every faction.
  Pirates and Predators fight everyone. Skirmisher and beam archetypes appear at threat 2 and 3+.
  Collectors carry icons and drop them when destroyed. Destroying an icon summons an Enforcer
  whose cockpit flashes. Lasers, homing missiles, weapon heat, shield, cloak and auto-repair work.
- **Factory test range**: stationary and moving targets, with speed, peak, time-to-90% and heat
  telemetry.
- Keyboard, gamepad and multi-touch controls. Pause, tactical map, zoom (buttons, +/-, mouse
  wheel, pinch), and fullscreen on desktop. Portrait and landscape both work, and the game never
  forces an orientation.

### Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Turn | ← / → | Left stick or D-pad (analogue) | ◀ ▶ (bottom left) |
| Thrust | ↑ (or W) | A / right trigger | ▲ (bottom right) |
| Fire | Space | X / RB | ✳ |
| Missile | X | Y / LB / left trigger | M |
| Map | M | Back/Select | Tap the radar |
| Pause (zoom and map are in this menu too) | Esc / P | Start | ‖ chip (top centre) or Android Back |
| Zoom | + / − / wheel | — | Pinch, or the pause menu |

**Gamepad / Retroid Pocket 5 in menus:** D-pad or stick moves between buttons, A selects,
B goes back or closes a popup, and Start/B resumes from pause. In strategy mode, left/right
cycles the autopilot priority. **In the Ship Factory:** Y toggles the precision cursor,
D-pad or stick moves it, A paints (hold A while moving to draw lines), LB/RB switch tabs,
LT/RT zoom, and B leaves precision mode and then the Factory.

There's no brake (owner decision, carried over from the HTML build). Turn around and
counter-thrust instead. Inertia Stabilization sets how quickly you lose speed while coasting.

## Getting test builds (APK)

Every push that changes game files builds a debug APK. GitHub Actions publishes it as a plain
`.apk` at a fixed link, so there's no zip to unpack:

**https://github.com/narmanb/system-frontier/releases/download/dev-latest/SystemFrontier.apk**

The same file is on the repository's Releases page under "Latest test build". It works on
Android phones and on the Retroid Pocket 5. On the Retroid the built-in controls work as a
gamepad, and the on-screen pads hide automatically while you use them (set Touch pads to
"auto"). They come back when you touch the screen.

Windows, Linux and Web builds are only made on request: Actions → **Export builds** →
**Run workflow** → platforms: `all`. They're also made for version tags.

**Updating the APK in place:** Android only installs an update over an existing build when both
were signed with the same key. The workflow keeps a generated debug key in the Actions cache.
GitHub evicts that cache after 7 days without use, and after that you'd need to uninstall once.
For a permanent key, add a repository secret named `ANDROID_DEBUG_KEYSTORE_B64` that holds a
base64-encoded debug keystore (alias `androiddebugkey`, password `android`):

```bash
keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
base64 -w0 debug.keystore   # paste the output into the secret
```

## Developing

- **Engine:** Godot **4.7.2-stable** (pinned in `.godot-version`), Compatibility renderer,
  GDScript only. Open `project.godot` in the matching editor.
- **Tests:** `godot --headless --path . --editor --import`, then
  `godot --headless --path . res://tests/run_tests.tscn`. The run exits non-zero on failure.
  The tests compare the port against numeric fixtures generated from the legacy JavaScript.
- **Fixtures:** `node tools/gen_fixtures.mjs legacy/<file>.html tests/fixtures` evaluates the
  legacy build's *effective* (final-override) code and regenerates `tests/fixtures/*.json` and
  `data/*.json`. CI fails if the committed copies drift from that output.
- **Legacy audit:** `python3 -I tools/audit_legacy.py legacy/<file>.html build/analysis docs/OVERRIDE_INVENTORY.md`
  writes the script blocks, decoded images, a symbol map and the override inventory.
- **Repo check:** `python3 -I tools/check_repo.py` checks the legacy hash, the asset manifest,
  file sizes, and that no secrets or build outputs are committed.

```text
project.godot          Godot project (repo root)
scenes/                main_menu/, mission/
scripts/core/          DataStore (data access), AppState + Sfx autoloads
scripts/ships/         ShipPerformance (engineering formulas), FactionPalette (recolors)
scripts/combat/        SimWorld (simulation), SimShip, NpcAI (faction AI)
scripts/ui/            WorldView (rendering), Hud, TouchControls, TacticalMap, menus
data/                  JSON definitions extracted from the legacy code
assets/                ship/effect art (see assets/manifest.json for provenance)
tests/                 headless runner, tests, legacy-derived fixtures
tools/                 audit, fixture generation, repo checks, visual capture
legacy/                frozen HTML reference build + superseded art
docs/                  handoff, parity matrix, decisions, override inventory, roadmap
```

The gameplay simulation (`SimWorld`, `NpcAI`, `ShipPerformance`) doesn't depend on UI or
viewport size. World coordinates are fixed at 2600×1800 and wrap at the edges. The simulation
advances on a fixed 60 Hz physics tick.

## Licensing and assets

The owner hasn't chosen a license yet, so none is included. All rights are reserved by the owner
until one is added. The ship and effect art was supplied by the owner during earlier development.
`assets/manifest.json` records the source, provenance and hash of every binary asset.
