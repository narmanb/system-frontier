# Roadmap

Milestones follow docs/HANDOFF_v724.md §4. A milestone counts as done only when its
acceptance checks are verified on device. Passing CI alone isn't enough.

## Milestone 0 — repo and baseline ✅ (this branch)
- [x] Frozen legacy reference, SHA-256 verified in CI
- [x] Script-block extraction, symbol and override inventory, image extraction with a manifest
- [x] Fixtures generated from the *effective* legacy JS (performance, flight, recolor) plus extracted data JSON
- [x] Godot 4.7.2 project, headless test runner, CI (hygiene + tests), export workflow

## Milestone 1 — flight and combat sandbox 🟡 (implemented; needs device verification)
- [x] Exact ship-performance formulas (33 fixture cases) and flight integration (3 hulls × 9 s traces)
- [x] Player flight, fuel, heat, shield, cloak, repair, lasers, homing missiles, damage and destruction
- [x] NPC traffic with v7.2.3/v7.2.4 AI: collectors and carriers, hostile, skirmisher, beam, Enforcer, faction war, retaliation
- [x] Keyboard, gamepad, multi-touch, pause, zoom, map, fullscreen, test range
- [ ] **Owner check on a phone and the RPi5**: feel, touch button size, frame rate, no stuck inputs
- [ ] Measure Android performance on a real device (not claimed yet)

## Milestone 2 — campaign, saves, all mission families ✅ (implemented; device check pending)
- [x] New Operation setup (pilot, drive incl. CUSTOM names, action/strategy, difficulty, faction, ship)
- [x] Directory map (12 directories, themes, rewards), upgrade bay (tuning, components, rare tech), relations
- [x] SaveService (versioned, atomic, backups), continue, three separate resets, legacy JSON import
- [x] Every mission family: icon recovery, rescue, repair, race, courier, black hole + dragon, scan, duel, defrag, Inner Demon
- [x] Hazards, icon defenders → escorts, boss, discoveries, talking programs, ambulance, strategy autopilot
- [x] Tests for every mission family, campaign migration and saves; the smoke run enters all 12 directories

## Next — Milestone 4: native Ship Factory (in progress)
Editor model (24/32/48), 48-colour palette with salvage unlocks, paint/erase/fill/mirror/rotate,
undo/redo, mounts (3 thrusters, 4 hardpoints), stats/modules with budgets and telemetry,
save/duplicate/delete/import/export library, starter templates, stencils, test flight, draft
persistence.

Then Milestone 3 (deeper faction world checks) and Milestone 5 (polish, platform sign-off).
