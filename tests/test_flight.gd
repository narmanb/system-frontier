extends TestCase
## Player flight integration vs. the legacy final `update()` (tests/fixtures/flight.json).
## Godot Vector2 is 32-bit, so positions are compared with a small absolute tolerance.


func test_flight_matches_legacy_update() -> void:
	var fx := fixture("flight.json")
	for run in fx["runs"]:
		var w := SimWorld.new()
		w.rng.seed = 1
		var hull := DataStore.starter_hull(run["hull"])
		w.player = w.make_player(hull)
		w.player.pos = Vector2(1300, 900)
		var dt: float = run["dt"]
		var samples: Array = run["samples"]
		var si := 0
		for i in range(0, 9 * 60 + 1):
			var t := i * dt
			if i % 15 == 0:
				var s: Dictionary = samples[si]
				si += 1
				var p := w.player
				var tag := "%s t=%.2f" % [run["hull"], t]
				if absf(p.pos.x - s["x"]) > 0.05 or absf(p.pos.y - s["y"]) > 0.05:
					errors.append("%s pos (%.3f,%.3f) expected (%.3f,%.3f)" % [tag, p.pos.x, p.pos.y, s["x"], s["y"]])
				if absf(p.vel.length() - s["speed"]) > 0.01:
					errors.append("%s speed %.4f expected %.4f" % [tag, p.vel.length(), s["speed"]])
				if absf(p.fuel - s["fuel"]) > 1e-6 * 200:
					errors.append("%s fuel %.5f expected %.5f" % [tag, p.fuel, s["fuel"]])
				if absf(NpcAI.norm_angle(p.a - s["a"])) > 1e-4:
					errors.append("%s heading %.5f expected %.5f" % [tag, p.a, s["a"]])
			var inp := {"thrust": t < 3 or (t >= 7 and t < 9), "turn": 1.0 if (t >= 6 and t < 7) else 0.0}
			w.time += dt
			w._update_player(dt, inp)
		check(si == samples.size(), "%s sampled %d of %d" % [run["hull"], si, samples.size()])


func test_no_brake_down_arrow() -> void:
	check(not InputMap.has_action("brake"), "no brake action is registered")
