# Parity matrix

Each row maps a legacy feature to its **effective** legacy function (final override; line
numbers refer to the frozen file) and to the native implementation and test.
Status values: **not started** · **partial** · **implemented** (code exists; not compared
numerically) · **verified** (compared against legacy-derived fixtures or behaviour tests) ·
**intentional change** (see DECISIONS.md).

## Core flight and engineering

| Feature | Legacy (effective) | Godot | Test | Status |
|---|---|---|---|---|
| Stat model, 10 stats, legacy alias migration (brake→inertia, armor→hull…) | `v6Stats` 1:1416 | `ShipPerformance.normalize_stats` | test_performance | verified |
| Module defaults / invalid-id fallback | `v6Modules` | `normalize_modules` | test_performance (starter hulls use `scanner:"advanced"`) | verified |
| Thruster / hardpoint normalisation | `normalizeThrusters` 0:~804, `v6NormalizeHardpoints` | `normalize_thrusters/hardpoints` | test_performance:test_red_falcon_mounts | verified |
| Performance + reactor overload | `v6Performance` **1:1678** (v6.1 override) | `ShipPerformance.compute` | 33 fixture cases incl. overload sweep, components, rare tech | verified |
| Campaign effective stats (upgrades ×0.8, components) | `v6EffectiveShip` 1:1636 | `effective_stats` | fixture `campaign-effective:redFalcon` | verified |
| Player flight: turn, thrust, speed cap, coast drag, wrap, fuel burn, out-of-fuel decay | `update` **1:1649** | `SimWorld._update_player` | test_flight (3 hulls, thrust/coast/turn/counter-thrust traces) | verified |
| No brake / down arrow | `update` 1:1649 (no ArrowDown) | no action bound | test_flight:test_no_brake_down_arrow | verified |
| Shield recharge, cloak rule, auto-repair after 5 s | `update` 1:1649 | `_update_player` | — | implemented |
| Damage to player (invuln, cloak evade, 85% shield absorb) | `damagePlayer` 1:1658 | `damage_player` | — | implemented |
| Hardpoint muzzle positions (96 px draw size) | `v6HardpointWorld` 1:1534, v7.2 96 px | `ShipPerformance.mount_world` | — | implemented |
| World 2600×1800 with wrap | `game` 0:935, `wrapObj` | `SimWorld.W/H`, `wrap_pos` | test_combat:test_long_simulation_is_stable | verified |
| Fixed timestep vs capped dt | `loop` (dt ≤ 0.033) | 60 Hz `_physics_process` | — | intentional change (D-003) |

## Weapons and projectiles

| Feature | Legacy | Godot | Test | Status |
|---|---|---|---|---|
| Player laser: interval, heat, overheat lockout, speed 480, damage + laserLevel×2, colours per module | `firePlayer` **8:2634** | `fire_player` | — | implemented |
| Missile: 0.8 s cooldown, nearest aggressive target, 240 speed, homing 1.25, damage 45×mult | `fireMissile` **11:3600** | `fire_missile` | — | implemented |
| NPC fire: cycle factor, 310 speed, faction-coloured bolts | `aiFire` **8:2658** | `ai_fire` | — | implemented |
| Projectile consumed on first collision | `updateBullets` **12:3823** | `_update_bullets` | test_combat:test_projectile_consumed_on_first_hit | verified |
| Dropped-cargo 2.5 s protection (pulse visual) | `destroyShip` 12:3774, `drawIcon` 12:3784 | `destroy_ship`, `WorldView._draw_icon` | test_combat:test_dropped_cargo_protected | verified |
| Icon destruction → crime 20 → Enforcer | `updateBullets` 12, `crime` 0:1124 | `crime`, `spawn_enforcer` | test_combat:test_icon_destruction_spawns_enforcer | verified |
| Beam weapon (charge, fire 1.75–2.05 s, DPS, segment hit test) | `v723FireBeam`, `updateBeams` 5:~2320 | `fire_beam`, `_update_beams` | — | implemented |
| Laser sprite tint (RGB replaced, alpha kept) | `v72TintLaser` 8 | white mask + modulate | — | implemented |

## AI and factions

| Feature | Legacy | Godot | Test | Status |
|---|---|---|---|---|
| Faction table and v7.2.4 colours | `FACTIONS` 0:721 + v7.2.4 `Object.assign` | data/factions.json | CI fixture diff | verified |
| Faction war: Pirates/Predators attack every other faction | `v723FactionWar` 11:3253 / `v724FactionWar` | `NpcAI.faction_war` | test_faction_war_rules, test_factions_fight_without_the_player | verified |
| Relations → spawn aggression, kill penalty | v7.2.2 `spawnAI`, `destroyShip` | `spawn_ai`, `destroy_ship` | test_hostile_relations_spawn_aggressive, test_killing_lowers_relations | verified |
| Relations view (R key) | `showRelations` | pause menu / R | — | implemented |
| Target choice: retaliation priority, faction-specific scoring and ranges | `v723ChooseTarget` 11:3281 | `choose_target`, `target_score` | test_retaliation_priority_and_invalidation | verified |
| Retaliation + one-time relation penalty | `v724Retaliate` | `NpcAI.retaliate` | test_player_attack_provokes_neutral | verified |
| Spawn chain (v6.9 archetype weights → v7.2.2 relations → v7.2.3 prepare) | `spawnAI` 11:3325 | `SimWorld.spawn_ai` | test_special_archetypes_spawn_by_threat | verified |
| Required skirmisher (threat ≥ 2) / beam (≥ 3), not in test range | `v723EnsureSpecialEnemies` 11:3351 | `ensure_special_enemies` | same test, 20 seeds | verified |
| Ship update loop: collector, carrier, escort, skirmisher, beam, enforcer, hostile; avoidance; drag; icon push; ramming | `updateShips` **11:3502** | `NpcAI.update_ships` | test_long_simulation_is_stable | implemented |
| Skirmisher state machine | `v723SkirmisherStep` | `skirmisher_step` | — | implemented |
| Beam state machine | `v723BeamStep` | `beam_step` | — | implemented |
| Collector pickup / carrier roam / cargo badge | v7.2.2 + `updateShips` 11 | `pickup_icon`, `carrier_roam` | test_dropped_cargo_protected | verified |
| Icon defenders → escorts | `makeDefender` 0:996, updateShips 11 | `_make_defender`, NpcAI defender/escort | test_defender_becomes_escort | verified |
| Boss (Inner Demon) | `spawnBoss` 0:1005, updateShips 11 boss branch | `spawn_boss`, NpcAI boss | test_missions:test_boss | verified |
| Faction recolor (v6.9 → v7.2.4 material) | `v69FactionRecolor`, `v724MaterialPixel` | `FactionPalette.recolor_grid` | test_recolor (20 grids, per pixel) | verified; runtime is an **intentional change** (D-007) |
| Enforcer cockpit flash (no floating siren) | `v724PoliceGrid`, `drawShipEntity` 12:3760 | `FactionPalette.police_texture` | — | implemented |

## World, pickups, mission

| Feature | Legacy | Godot | Test | Status |
|---|---|---|---|---|
| Icon spawn, drift, bounds, infected-icon effect, pickup radius, salvage multiplier | `spawnIcon` 0:993, `updateItems` 10:3028 | `spawn_icon`, `_update_items` | — | implemented |
| Fuel cells | `spawnFuel`, `updateItems` | `spawn_fuel` | — | implemented |
| Normal directory objective → exit gate | `updateMission` 0:1106 path | `_update_mission` | — | implemented |
| Test range (targets, telemetry) | `startWave(test)` 1:1637, `update` | `_setup_test_range`, HUD | — | implemented |
| Hazards (turret, virus, asteroid) | `spawnHazard` 0:995, `updateHazards` 0:1100 | `spawn_hazard`, `_update_hazards` | test_boss (count) | implemented |
| Ten mission families (icon, rescue, repair, race, courier, black hole, scan, duel, defrag, boss) | base `updateMission`, v6.4 `v64*`, v7.2.3 duel rule | `MissionController` | test_missions (one test per family) | verified |
| Campaign create/migrate, drives, directory builder, themes | `newCampaign` v6.6, `buildDirectories` v6.4, `ensureCampaignDefaults` chain | `Campaign` | test_campaign (fixture: directories, migration) | verified |
| Directory map, upgrade bay, relations | `renderMap` v6.6, `openUpgradeBay` v6/v6.6, `showRelations` | `directory_map.gd` | smoke run | implemented |
| Completion rewards and salvage (theme bonus) | `v64AwardCompletion` | `Campaign.award_completion` | test_completion_rewards_once_with_theme_bonus | verified |
| Discoveries, ambient programs | `v64TriggerDiscovery`, `v64UpdatePrograms` | `MissionController` | — | implemented |
| Dragon encounter | `dragonEncounter` | `resolve_dialog("dragon")` | test_black_hole_dragon | verified (D-022 fix) |
| Ambulance | `callAmbulance` | `ambulance_offers`/`buy_ambulance` | test_ambulance_and_strategy | verified |
| Strategy mode | `updateStrategy`, #strategyControls | `_update_strategy`, `StrategyBar` | test_ambulance_and_strategy | intentional change (D-023) |
| Saves, resets, legacy import | `saveCampaign`, `v68DoReset`, SAVE_KEY/SHIP_KEY | `SaveService` | test_saves | verified (D-027) |
| Built-in faction ships (procedural 24×24) | `buildBuiltinShipGrid`, `v6ApplyBuiltins`, `v68ApplyRedFalconDefault` | `BuiltinShips`, data/campaign.json | test_builtin_grids_match_legacy | verified |
| Black hole visual | v7.1 GIF at 160 px; collision r58 + 10 | sprite sheet (8 × 150 ms), `MissionController.black_hole` | — | implemented |
| Factory editor model: 24/32/48 canvases, nearest resize + mount scaling | `v61ApplyCanvasResize`, `v61ResizeGridNearest`, `v61ScalePoint` | `FactoryEditor.resize_canvas` | test_resize_scales_mounts | verified |
| Paint/erase with mirror, undo/redo (40) | `paintAt`, `v6PushHistory/Undo/Redo` | `FactoryEditor.paint`, history | test_paint_mirror_undo_redo | verified |
| Fill and pick tools | — (new) | `flood_fill`, `pick` | test_fill_and_replace | intentional change (D-029) |
| 48-colour palette, salvage unlocks, recent colours, replace/swap | v6.6 palette, v6.7 `selectColor`, `openColorOperation` | `FactoryEditor`, Paint tab | test_fill_and_replace | implemented |
| Stats (budget 50, cap 8), archetypes, modules, mount budget 4 | v6 `makeStats`, v6.5 cap, `v6ApplyArchetype`, thruster UI | `change_stat`, `toggle_thruster` | test_budgets | verified |
| Five presets | `preset(n)` | `apply_preset` | test_presets_match_legacy | verified |
| Starter hull templates, Red Falcon default | `v65LoadStarterHull`, `v70LoadTrueRedFalcon` | `load_starter` | test_resize_scales_mounts | verified |
| Stencils (Salvage Skiff, Archive Needle) | `v64ApplyStencil` | `apply_stencil` | — | implemented |
| Auto-Clean (conservative/symmetry/aggressive) + mount realignment | `v62RepairGrid`, `v62RealignMounts` | `repair_preview`, `apply_repair` | test_auto_clean_matches_legacy, test_auto_clean_realigns_mounts | verified |
| Thruster / hardpoint placement and overlays | thruster/hardpoint UI, `drawThrusterOverlay`, `v6DrawHardpointOverlay` | Engines/Hardpoints tabs, `EditorCanvas` | — | implemented |
| Telemetry cards, warnings, preview | `v6UpdateTelemetry`, `drawPreview` v6 | Telemetry tab, `FactoryEditor.warnings` | — | implemented |
| Library: save, duplicate, delete, import/export | `saveShipBtn`… | Library tab (clipboard JSON) | test_ship_data_roundtrip | intentional change (D-030) |
| Draft autosave, recent-colour persistence | `v6AutoSave`, `RECENT_KEY` | `SaveService.DRAFT/RECENT_COLORS` | — | implemented |
| Precision pad | v6.2 precision cursor/pad | Paint tab pad + cursor + Dab | — | intentional change (D-031) |
| Zoom / pan | `v6ApplyZoom` (1–4×) | pinch, wheel, buttons (1–6×), two-finger/right-drag pan | — | implemented |
| Test flight with options and telemetry summary | `testShipBtn`, `v6FinishTest` | Test tab → test range → back to Factory | smoke run | implemented |

## Presentation and platform

| Feature | Legacy | Godot | Status |
|---|---|---|---|
| 96 px ship draw size, sprite rotation (+90°), thruster glow per mount | `drawShipEntity` 8:2613, `drawThrusterGlow` | `WorldView._draw_ship/_draw_thrusters` | implemented |
| Starfield twinkle + cat constellations (single wrapped anchor) | `drawSpaceBackground` 10:3161 | `WorldView._draw_background` | implemented |
| Icons, fuel, gate (only when open), labels "name · team", health bars, charging arcs, cargo badge | various draw* | `WorldView` | implemented |
| Radar (desktop bottom-left; on touch, moved top-right) | `drawRadar` | `Hud._draw_radar` | implemented (legacy hid it on touch) |
| Tactical map + faction/cargo markers | `drawMap` 11:3631 | `TacticalMap` | implemented |
| Touch layout (turn left, thrust/fire right, missile mini, map) with slide-between buttons | `buildTouchButtons` 1:1670 | `TouchControls` | intentional change (mm sizing, D-006) |
| Portrait camera without forced rotation | `resizeCanvas` 1:1669 | `AppState._update_content_scale` | implemented (D-005) |
| Fullscreen without orientation lock | `toggleFullscreen` 1:1668 | `AppState.toggle_fullscreen` | implemented |
| Web Audio beeps | `beep` 0:705 | `Sfx` autoload | implemented (D-016) |
| Pause, focus-loss safety, Android back | `togglePause` | `mission.gd` | implemented (D-010) |
| Gamepad | — (new) | InputMap | implemented |

## Recovered historical requests (handoff §5)

| Item | Finding in v7.2.4 | Port status |
|---|---|---|
| Red Falcon as true 48×48 editable art | `RED_FALCON_GRID` is pixel-identical to `RED_FALCON_DATA_URL`; `v70LoadTrueRedFalcon` migrates the old 24×24 default | Uses that art as `assets/ships/red_falcon.png`; migration comes with the Factory (M4) |
| Enlarge starter previews, crop transparent padding | `v65RenderStarterPreviews` override in v7.0 crops to alpha bounds | Menu cards crop to `get_used_rect()` for preview only; mounts and art untouched |
| Wisp Needle, Blockade Ram, Cargo Warden + five retained presets | v6.9 replaced the art for those three and kept `redFalcon, novaSting, wispNeedle, blockadeRam, cargoWarden`; it removed silverArrow, tombGlider and salvageSkiff | Five starters shipped. The three removed hulls and the three superseded versions are kept in `legacy/unused_art/`. NPC art (grunt, skirmisher, beam, hunter, raider, police) is all used |
| Three aligned thrusters, four hardpoints | Red Falcon thrusters (24,43)/(17,41)/(31,41); hardpoints primary (24,12) … | verified (test_red_falcon_mounts); thruster glow drawn at mounts |
| Remove Brake; Inertia Stabilization / counter-thrust | Final `update` has no ArrowDown; `v6Stats` maps `brake`→`inertia` | verified |
| Reactor overload penalties, consistent telemetry | v6.1 `v6Performance` override | Formula verified; the menu telemetry reads from the same calculator |
| Preserve orientation in fullscreen | v6 `toggleFullscreen` has no orientation lock | Kept: sensor orientation, no lock |
| Black-hole asset size | v7.1 draws the GIF at 160 px. Collision is `r:58` with entry at `dist < r+10`, procedural fallback radius 72 | Not yet ported (M2). GIF kept in assets; provenance to confirm |
| Special enemy AI and faction warfare | v7.2.3 | verified (see AI table) |
| Faction palettes, cargo protection, Enforcer cockpit | v7.2.4 | verified / implemented (see above) |
| Desk OS integration | No spec | Deferred. The game stays standalone |
