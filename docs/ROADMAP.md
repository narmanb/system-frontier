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

## Next bounded milestone — Milestone 2a (proposed)
1. Persistence: `SaveService` (versioned JSON in `user://`, atomic writes, backups), separate
   campaign and factory saves, optional import of legacy `innerCore95Save` / `innerCore95Ships`
   JSON exports.
2. Campaign shell: new campaign (pilot, team, ship, difficulty, mode), virtual drives and the
   directory map (`buildDirectories`, `renderMap`), mission start and finish, credits and relations.
3. Remaining "normal directory" content: icon defenders → escorts, hazards (turret, virus,
   asteroid), ambulance service, crime and warrant clearing.
4. Then the mission families one at a time, each with its own legacy-derived test: race, duel,
   black hole (with the GIF or procedural art), boss, then rescue, repair, courier, scan and defrag.

Later: Milestone 3 (full faction world), Milestone 4 (native Ship Factory, the biggest UI task),
and Milestone 5 (polish, platform signoff).
