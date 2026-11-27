# System Frontier — development handoff and native Godot migration

**For Claude / coding agents** · 26 November 2026  
**Project:** System Frontier (formerly Inner Core ’95), an original spiritual successor to Operation: Inner Space.  
**Repository:** https://github.com/narmanb/system-frontier (public; located via GitHub connector, reported empty at time of lookup). Verify checkout and branch before making changes.  
**Recovered baseline:** `inner_core_95_v7_2_4_faction_palettes_icon_safety_police_cockpit.html` (28 July 2026 UTC; 589,032 bytes).  
**SHA-256:** `405177fe6973ebede7a06e971fbef40d28a7648771e8445ec5bf2d79473a5036`

## 1. Objective and non-negotiable constraints

Rename the project **System Frontier** and migrate the existing working game to **native Godot 4 / GDScript**, retaining the feel, content and behavior of the recovered HTML version. The HTML build is the reference implementation, not disposable scaffolding. The owner explicitly permits the Godot port to differ somewhat from the HTML version if it improves the game. Use the original as a reference, not a strict pixel-perfect or behavior-identical specification. Preserve the distinctive core gameplay, Ship Factory, progression and factions; allow purposeful improvements to usability, controls, visuals, architecture and gameplay feel during migration. Document meaningful departures and seek input for major scope changes or removal of core features. Do not reduce the game to a generic space shooter.

- Target Android and Windows first (recommendation); preserve browser access as a secondary target using Godot Web export if practical. Do not use a WebView wrapper as the main port.
- Retain the retro computer/directory setting and pixel-art presentation, but remove the old title from user-facing branding. Do not replace old save keys blindly; keep backward migration aliases where useful.
- Use native 2D; no need to make it 3D. Recommend Godot 4 Compatibility renderer, GDScript, pinned stable editor and matching export templates. Verify the precise Godot release rather than using an unpinned `latest`.
- Preserve portrait and landscape support; landscape may be recommended but fullscreen must not forcibly rotate the device. Support touchscreen and keyboard, and add controller support where practical without breaking existing inputs.
- The repo is public. Do not commit private paths, secrets, tokens, personal files, unauthorized third-party game assets, or signing credentials. Audit embedded and supplied asset provenance before publishing them. Do not silently add a license the owner has not selected.
- Use GitHub Actions for deterministic build/test/export work, not repeated agent-driven manual builds. Standard hosted runner compute is free for public repos; artifact storage and third-party API use may be billed. AI-powered workflow steps are not automatically free.
- Desk OS integration is an optional future possibility, not a requirement for this port. Keep the game standalone, with interfaces that would allow launching it from Desk OS later. Do not spend time porting Feral Cats or the stock simulator.

## 2. Baseline audit — read this before implementing

The recovered HTML is a single-file Canvas/DOM JavaScript game: 3,876 lines, 13 script blocks, 327 named function declarations, eight canvas elements, 19 embedded PNG data URLs, Web Audio synthesized sound, and localStorage saves. Large embedded images account for part of the file size. It contains several generations of changes implemented as wrappers, reassignments and overrides. The later script blocks are critical: a literal sequential translation will revive superseded logic.

**Important:** v7.2.4 supersedes v7.2.3. It was recovered from the original July 28 UTC conversation and saved file. Searches of conversation history, file names, content, and 312 dated library source/archive entries found no newer Inner Core build; recursive Google Drive listing was not supported. Use this as the latest verified recoverable baseline, not proof that no other build ever existed.

### Audit procedure

1. Place the unmodified reference at `legacy/inner_core_95_v7_2_4_faction_palettes_icon_safety_police_cockpit.html` (provided separately). Confirm hash; preserve it unchanged. If asset rights are unclear, keep the reference locally and commit only permitted artifacts and the hash instead.
2. Run the HTML version and record representative gameplay, controls, mission progression, factory workflows and save behavior. Use browser automation (e.g., Playwright, if available) for reproducible snapshots and input traces. This handoff is a static inspection, not a completed playtest.
3. Extract each script block into numbered **analysis-only** files, using a local script outside the production runtime. Build a symbol/override map for functions redefined by later patches. Use actual final behavior, not old comments or names.
4. Extract embedded images by decoding data URLs without resizing, re-encoding or stripping alpha. Deduplicate by content hash; retain dimensions, source identifiers and intended use in an asset manifest. Some graphics are generated from editable color grids or Canvas drawing functions; preserve those as data/procedural implementations rather than treating every graphic as a static PNG.
5. Inventory the final data model, formulas, inputs and save schemas. Create `docs/PARITY_MATRIX.md`, mapping each feature to legacy function(s), Godot implementation, test, and status: not started / partial / implemented / verified / intentional change.
6. Produce compact fixtures for ship stats, factions, missions, weapon timing and sample saves. Capture expected numeric output from the *effective* browser code. These should become port regression tests.

### High-value source locations (original line numbers; verify if file changes)

| Legacy area | Function / identifier examples | Port destination |
|---|---|---|
| Core timing, movement | `loop`, `update`, `steerToward`, `wrapObj` (~1013 onward) | simulation, flight controller |
| Campaign and map | `newCampaign`, `buildDirectories`, `ensureCampaignDefaults`, `startWave` (~939 onward; later overrides) | campaign, directory generator, mission manager |
| Diplomacy | `FACTIONS` (~721), `crime`, `spawnEnforcer`, `showRelations` | faction/reputation/law systems |
| Ship engineering | `V6_STAT_ORDER` (~1353), `v6Performance` (~1472), `v6EffectiveShip`, `v6ModuleInfo` | ship definitions, stats calculator, modules |
| Factory | `v6Snapshot`, `v6Undo`, `v6Redo`, `v6AutoSave`, `v61ApplyCanvasResize`, `v62RepairGrid`, `v65LoadStarterHull` | editor model, factory scene, library |
| Mission expansion | `V64_TYPE_PLAN`, `V64_SPECIAL_TYPES` (~1759), `v64InitMission`, `v64UpdateSpecialMission`, `v64TriggerDiscovery` | mission controllers, salvage/discovery |
| Enemy variants | `v69BuildShip`, `v69FireBeam`, `v69SkirmisherStep`, `v69BeamStep` | AI controllers and weapons |
| Default ship fix | `v70LoadTrueRedFalcon`, `v70MigrateLegacyDefault` | asset loading and migration |
| Later visuals | `v72DrawLaserBullet`, `v721EnsureStarfield`, `v722EnsureConstellations` | sprite/particle/background layers |
| v7.2.3 faction patch | `v723FactionWar` (~3253), `v723ChooseTarget` (~3281), `v723EnsureSpecialEnemies` (~3351), `v723BeamStep`, `v723SkirmisherStep` | faction combat, target selection and spawning |
| v7.2.4 final patch | `v724ApplyFactionPalette`, `v724PoliceGrid`, `v724FactionWar`, `v724Retaliate`, `updateBullets` (script starts near line 3647) | faction visuals, police cockpit flash, hostility, projectile collision, dropped cargo protection |
| Saves | `SAVE_KEY="innerCore95Save"`, `SHIP_KEY="innerCore95Ships"`, factory draft / recent color keys | versioned persistence and optional legacy import |

## 3. Architecture recommendation

Start small and modular; avoid building an elaborate framework before proving the flight loop. This structure is a proposal, not a mandated implementation if a simpler equivalent works.

```text
legacy/                 # frozen HTML reference (only if publishable)
project.godot           # or godot/project.godot; choose one and keep CI consistent
scenes/
  main_menu/ campaign_map/ mission/ ship_factory/ hud/
scripts/
  core/                 # simulation clock, shared utilities, RNG, events
  campaign/             # progression, directories, factions, save data
  ships/                # ship data, engineering, editor model, flight
  combat/               # projectiles, damage, weapons, AI
  missions/             # distinct mission objectives and rewards
  ui/                   # input and presentation, separate from simulation
  persistence/          # schema, migration and serialization
assets/
  ships/ weapons/ effects/ ui/ audio/
data/                   # Resources / JSON for data-driven definitions
 tests/                 # automated regression fixtures and runners
 docs/                  # parity matrix, test notes, decisions, roadmap
.github/workflows/      # CI and exports
```

Use `Node2D` for world/entities, `Camera2D` for camera/zoom, `Control` scenes and containers for menus/HUD, `InputMap` with action names, native `Image` / `ImageTexture` for editable hulls, and signals between UI and systems. Keep gameplay state independent of UI and avoid a single giant global script. Use a small number of autoloads only where justified (e.g., SaveService and session state). Keep ship and module stats as data-driven Resources or validated dictionaries; use a stable ID for each item, hull, faction and directory.

A fixed simulation tick via `_physics_process` is a sensible choice, but tune and compare against the reference's capped frame delta (`Math.min(.033, ...)`). Preserve thrust/inertia, angular turning, speed caps, collision dimensions, fire intervals and world wrap. Do not assume Godot physics defaults reproduce the original. Explicit vector integration may preserve behavior better than RigidBody2D. Use seeded random generation for tests, not necessarily forced deterministic gameplay. Never depend on viewport size for simulated world coordinates.

### Translation map

| Browser implementation | Native replacement |
|---|---|
| Canvas draw calls, sprites, glow | Sprite2D, custom `_draw()`, shaders or particles; nearest-neighbor pixel filtering |
| Canvas pixel-grid editor | `Control`/custom drawing with `Image` RGBA backing data; zoom/pan independent of world camera |
| DOM, CSS, modal elements | reusable Control scenes, Theme resources, popups and responsive containers |
| JavaScript objects and arrays | typed GDScript models and Resources where appropriate |
| `requestAnimationFrame` | `_process` for visuals and `_physics_process` for gameplay |
| localStorage | `user://` versioned JSON, backup/atomic writes; optional legacy JSON import |
| Web Audio oscillators | generated audio samples or native audio nodes with matched sound cues |
| browser touch canvas | action-based input via InputMap plus touch Control nodes |
| file/directory picker | virtual drives first; native opt-in metadata-only import later, respecting Android scoped storage |

## 4. Porting sequence and acceptance gates

### Milestone 0 — repo and baseline

- Import the authorized baseline and docs, create a migration branch (e.g. `godot-port`), establish `.gitignore` and clean README with **System Frontier** branding, and set up a Godot project with CI. Keep the legacy build runnable independently.
- Establish source audit, asset manifest and parity matrix. Start with a small smoke scene and a test runner that exits nonzero on failure. Verify editor import and headless tests on CI.
- Do not merge an incomplete replacement over a playable baseline.

### Milestone 1 — playable flight and combat sandbox

- Native mission scene; player ship, Red Falcon, camera, world bounds/wrapping, inertia/thrust/turning, fuel, hull, radar, icons and pickups; laser/missile handling, damage and destruction; at least one simple NPC behavior. Use existing art.
- Port the effective ship performance formulas exactly and compare representative numerical fixtures. Do not replace the original ship handling with arbitrary arcade physics.
- Keyboard and responsive touch controls, pause, zoom, fullscreen, test arena. Validate a debug Android APK and Windows build. Do not claim Android performance until tested on device.
- Acceptance: stable gameplay at typical frame rates; reference-like acceleration, speed, fuel burn, firing cadence and damage; no stuck touch inputs on pause/focus loss.

### Milestone 2 — campaign, progression and all mission types

- Port virtual drives (SYSTEM, GAMES, ARCHIVE and optional custom metadata), directory map, setup/pilot/team/difficulty, normal and strategy modes, mission initialization/completion, upgrades, salvage/discovery/blueprints, repair services, reputation and save/resume/reset options.
- Preserve all ten mission families: icon recovery, rescue, repair, race, courier escort, dragon black hole, infection scan, locked duel, defragmentation, Inner Demon boss. Verify each against the reference; do not just mark a generic combat wave as complete.
- Save/load with explicit schema version, migration fixtures, separate campaign and factory saves, and reset confirmation. Old browser storage is sandboxed and cannot simply be read by a native app; optional JSON export/import or manual extraction is needed. Do not wipe existing progress by default.
- Acceptance: new campaign, all mission types playable, rewards/relationships saved, reload resumes correctly, separate reset choices behave as in legacy.

### Milestone 3 — faction warfare and complete combat AI

- Preserve Avengers, Pirates, Predators, Renegades, Fuzzy, Knights, Speed and non-playable Enforcers, their faction data, crime/warrants, retaliation and faction hostility logic. Validate final v7.2.4 rather than earlier AI patches.
- Include collectors, carriers, skirmishers, beam ships and other archetypes; preserve actual cargo interactions and combat priority. From v7.2.3 code, Pirates and Predators are hostile to other factions; valid retaliation takes priority; required skirmisher and beam archetypes spawn at threat >=2 and >=3 respectively in normal/duel/black-hole missions, excluding test missions. Check full code for other conditions and intended mission exceptions.
- Preserve beam collision/damage timing, avoidance, roaming, pickup/drop and distinct enemy silhouettes and faction recolors. Test allies, neutrals, NPC-vs-NPC battles, player-target selection, dead-target invalidation and spawn rules.
- Acceptance: faction fighting does not require the player to initiate every engagement; special enemies reliably appear under matching conditions; tests cover target changes and rewards without duplications.

### Milestone 4 — full native Ship Factory (largest individual UI task)

- Implement a separate editor data model with 24×24, 32×32 and 48×48 canvases, transparent pixels, palette, zoom, precision cursor, symmetry/repair/cleanup and color tools; history/undo/redo, save/duplicate/import and hull preview. Check the final build's defaults and blank canvas promotion rules.
- Preserve editable 48×48 hull assets, top-down / slight three-quarter game perspective, not frontal or isometric. Preserve Red Falcon as actual 48×48 default, correctly aligned three thruster mounts and four hardpoints. Compare real in-game scale with factory thumbnails and crop preview-only padding; do not destroy the editable transparent canvas or change mount coordinates to crop previews.
- Preserve starter hulls and existing custom ship library. Audit named Wisp Needle, Blockade Ram, Cargo Warden, five retained presets, and enemy/faction assets in the effective reference; do not recreate or discard any present asset. Earlier user request was to implement all supplied assets; completeness remains a verification task.
- Keep engineering budget, all ten modern stats, component/module slots, hardpoints, thrusters, telemetry, reactor capacity/overload and test flight. Use reference formulas and inspect latest effective behavior. Preserve Inertia Stabilization; the user previously approved removing the Brake stat in favor of inertia/counter-thrust. Do not blindly port obsolete `brake` fields from earlier JavaScript. Verify actual effective movement and any remaining down-arrow behavior before changing it.
- Responsive editor in portrait and landscape; no tiny hit targets, unreachable controls or cramped thumbnails. Support draft persistence and reset options. Avoid auto-applying repairs that corrupt custom designs.
- Acceptance: create/edit a custom ship, undo and redo, resize without unexpected corruption, align mounts, view correct preview, save and select it for a campaign, test-fly and reload; compare formula/overload outputs with reference fixtures.

### Milestone 5 — polish, platform verification and parity signoff

- Restore retro UI theme, visual effects, laser sprites, faction recolors, starfield/constellations, audio, black-hole visual, themes and all overlays. Use native assets/procedural rendering and sensible performance budgets. Preserve readable text and mobile layout rather than rigid pixel-perfect desktop sizing.
- Verify gamepad input, focus loss, Android back button, application background/resume and orientation changes. Pause safely and save when appropriate; avoid background simulation unless later requested.
- Compare representative play sessions to HTML; record discrepancies and intentional changes; obtain approval for major scope changes. Export Android debug APK and Windows artifact; optional Web export requires Compatibility renderer and appropriate browser hosting. Native Android/Windows are the main recommendation; web export is no longer a single standalone HTML file.
- Improve the port during implementation where useful; record intentional departures and defer major expansions until core systems are playable. Potential future expansion: living persistent faction world, deeper diplomacy, economy, better AI, new content and Desk OS integration. These are proposals, not previously approved features.

## 5. Recovered historical requests and unresolved verification

The following were recovered from prior development conversations. Some may already be implemented; do not label them new work without checking the latest baseline.

| Historical item | Current handoff status |
|---|---|
| Fix default Red Falcon using true 48×48 editable art | v7.0 reported fixed; loader/migration is present in later source; test regression |
| Enlarge cramped starter previews and crop transparent padding | v7.0 reported fixed; verify responsive native equivalents |
| Implement supplied Wisp Needle, Blockade Ram, Cargo Warden, enemy/faction ships and retain five presets | Requested before v6.9; audit v7.2.4 asset coverage; no assumption of remaining work |
| Three aligned thrusters, four hardpoints | Red Falcon loader present; preserve/test |
| Remove Brake stat; use Inertia Stabilization, counter-thrust | Earlier explicit user direction; inspect overrides and migration, do not reintroduce removed stat |
| Reactor overload penalties and consistent telemetry | v6.1 reported implemented; verify actual performance and display match |
| Preserve orientation in fullscreen | Earlier explicit user direction; retain |
| Assess black-hole asset size | v7.0 prior notes reported procedural art, about 144×144 visible / 72 px radius; confirm latest rendering and gameplay collision independently; resize if justified by gameplay/readability; document the change |
| Special enemy AI and faction warfare | v7.2.3 includes specific fixes; regression test against effective code |
| Faction palettes, cargo protection and Enforcer cockpit | v7.2.4 final patch: distinguish Avengers red/orange from Pirates rust/crimson; flash police cockpit instead of floating siren; consume projectile on first collision; protect newly dropped cargo for 2.5 seconds; test hostility and retaliation overrides |
| Desk OS integration | Discussed by user; no recovered finalized integration spec; defer |

No complete additional unfinished backlog was recovered. Treat missing documentation as unknown rather than inventing commitments. Document purposeful gameplay improvements during the port; consult the owner for major redesign decisions rather than requiring exact parity.

## 6. GitHub Actions — reduce Claude usage and improve reliability

Use Actions for the work that does not require language-model reasoning. Keep local scripts and CI commands identical where possible.

- **CI on PR/push:** check asset manifest and repository hygiene; import Godot project headlessly; run syntax/import checks and automated unit/integration regressions; upload concise logs only on failures. Add a short smoke-run job; bound all jobs with `timeout-minutes`.
- **Export on manual dispatch or version tag:** Android debug APK, Windows executable/archive, optional Web output; build with the same pinned engine and templates as CI. Publish artifact names with commit hash and version. Use short artifact retention (e.g. 7 days for intermediate builds) and release only verified builds.
- **Setup:** official Godot binaries/templates, verified checksums, pinned action versions (prefer audited full commit SHAs); Android SDK/build-tools/platform matching selected Godot docs and JDK 17 unless the pinned release requires otherwise. Cache downloads/SDK safely; use dedicated debug signing and store release signing material only as Actions secrets if release signing is later authorized.
- **Security:** default `permissions: contents: read`; explicitly scope release upload job permission; do not run untrusted PR code with secrets or privileged `pull_request_target`. Avoid paid larger runners or unnecessary external services. Never send secrets to AI logs.
- **Efficiency:** stop when a test fails, capture the failing test and actual/expected values; avoid endless automatic rebuild loops. Run narrow jobs on relevant path changes; cancel superseded runs for the same branch; cache large immutable dependencies. Claude should inspect condensed failure summaries rather than ingest all verbose logs. GitHub Actions cannot replace Claude's reasoning or make Anthropic API calls free.

Example command *shape* (adapt to project path/pinned version and create the test runner before enabling):

```bash
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --export-debug "Android" build/SystemFrontier-debug.apk
```

The export preset, Android SDK/editor settings, matching export templates and debug keystore must actually exist. These are design instructions, not a verified workflow or build. Configure a native Windows preset and optionally a Web preset separately. Verify CLI options against the pinned release. Do not mark a workflow green unless tests actually ran and required output files exist.

## 7. First assignment for Claude

1. Inspect the actual Git checkout, verify the recovered baseline SHA-256, confirm source/asset publishing rights and add the handoff/README. Preserve baseline byte-for-byte.
2. Build the compact override inventory, asset manifest, parity matrix and representative fixtures. Document whether each old request is implemented, missing, or unclear.
3. Create a small native Godot project and headless CI. Implement the first playable flight/combat sandbox with the original art and formula tests. Keep scope bounded to Milestones 0–1; do not attempt a wholesale monolithic translation in one response.
4. Commit incremental changes on a migration branch, with useful commit messages. Report actual tests and artifacts, remaining parity gaps and the next bounded milestone. Do not claim the full port is finished because a menu or one mission runs.

### Definition of done for the overall migration

A player can start a new campaign, pick or create a ship, play every existing mission family, participate in faction warfare, earn rewards and upgrades, save/resume, and use all important Factory tools on a native Android or Windows build. The previous HTML version remains available for reference, and discrepancies are documented. The game is consistently branded **System Frontier**. No known core feature is silently dropped.

## 8. Reference documentation

- Godot command-line/CI: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- Android export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
- System requirements: https://docs.godotengine.org/en/stable/about/system_requirements.html
- Web export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- GitHub Actions billing: https://docs.github.com/en/actions/concepts/billing-and-usage
- GitHub runner choice: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job

**Assessment limitations:** source was inspected statically; no browser playtest, Godot implementation, CI run or Android benchmark was performed in preparing this handoff. Repo was identified by name and connector permissions; no changes were pushed. Architecture, milestone order, platform priority and workflow choices above are recommendations for the owner to review. Preserve verified behavior and record intentional deviations.
