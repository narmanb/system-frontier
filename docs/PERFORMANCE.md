# Performance benchmark

Script time per frame (Godot monitors) on this machine; compare relatively. Physics = 60 Hz simulation step.

| Scene | Avg process ms | Avg physics ms | Max process ms | Entities | _draw cost |
|---|---|---|---|---|---|
| (warm-up) | 100.60 | 0.47 | 128.15 | 2 ships, 5 bullets, 0 particles | world_view.gd 0.66 ms, hud.gd 0.21 ms |
| Sandbox threat 5 | 23.59 | 0.46 | 28.64 | 8 ships, 4 bullets, 0 particles | world_view.gd 0.61 ms, hud.gd 0.17 ms |
| Inner Demon (boss) | 14.14 | 0.47 | 21.64 | 5 ships, 6 bullets, 0 particles | world_view.gd 0.62 ms, hud.gd 0.17 ms |
| Duel threat 3 | 26.18 | 0.49 | 27.87 | 10 ships, 3 bullets, 5 particles | world_view.gd 0.72 ms, hud.gd 0.19 ms |
| Test range | 12.76 | 0.79 | 13.58 | 2 ships, 5 bullets, 0 particles | world_view.gd 0.71 ms, hud.gd 0.21 ms |
| Factory canvas 48×48, 3× zoom | 46.72 | 0.84 | 92.40 | 2304 cells | editor_canvas.gd 0.50 ms |

Pure simulation, Inner Demon directory, 1800 steps: **0.027 ms per 60 Hz step**.
Faction recolour (5 archetypes, uncached): **11.9 ms total** (cached afterwards).
