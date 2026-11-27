extends TestCase
## Randomised play through every directory: random controls, dialog choices and ambulance
## purchases must never break invariants (finite state, sane bounds, no stuck dialogs).


func test_random_play_keeps_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for dir_index in 12:
		for mode in ["action", "strategy"]:
			var c := Campaign.create({"mode": mode, "difficulty": 1.28})
			c["noble"] = 4
			c["credits"] = rng.randi_range(0, 400)
			var w := track(SimWorld.new())
			var pending := []
			w.dialog.connect(func(k, p): pending.append([k, p]))
			w.setup_directory(c, c["dirs"][dir_index], rng.randi())
			var tag := "%s/%s" % [c["dirs"][dir_index]["type"], mode]
			var choices := {"dragon": ["bomb", "fight", "retreat"], "vendor": ["repair", "trade", "decline"], "quarantine": ["purge", "leave"]}
			for i in 60 * 25:
				if not pending.is_empty():
					var d: Array = pending.pop_front()
					var opts: Array = choices.get(d[0], ["decline"])
					if not w.resolve_dialog(d[0], opts[rng.randi() % opts.size()], d[1]):
						w.resolve_dialog(d[0], opts[-1], d[1])
				if rng.randf() < 0.01:
					w.buy_ambulance(["fuel", "hull", "missiles", "laser", "armor", "warrant"][rng.randi() % 6])
				if mode == "strategy" and rng.randf() < 0.02:
					w.strategy = ["collect", "attack", "evade", "exit"][rng.randi() % 4]
				w.step(1.0 / 60, {"turn": rng.randf_range(-1, 1), "thrust": rng.randf() < 0.6, "fire": rng.randf() < 0.5, "missile": rng.randf() < 0.02})
				if w.over:
					break
			var p := w.player
			check(not w.blocked, "%s: no dialog left blocking" % tag)
			check(is_finite(p.pos.x) and is_finite(p.vel.x) and is_finite(p.hull) and is_finite(p.a), "%s: player state finite" % tag)
			check(p.fuel >= 0 and p.fuel <= p.max_fuel + 1e-3, "%s: fuel in range (%.2f/%.2f)" % [tag, p.fuel, p.max_fuel])
			check(p.hull <= p.max_hull + 1e-3, "%s: hull <= max" % tag)
			check(p.shield_hp >= 0 and p.shield_hp <= p.max_shield + 1e-3, "%s: shield in range" % tag)
			check(int(c["credits"]) >= 0 and int(c["missiles"]) >= 0, "%s: credits/missiles non-negative" % tag)
			check(int(c["noble"]) <= 4, "%s: noble capped" % tag)
			for k in c["salvage"]:
				check(int(c["salvage"][k]) >= 0, "%s: salvage %s non-negative" % [tag, k])
			for s in w.ships:
				check(is_finite(s.pos.x) and s.pos.x >= 0 and s.pos.x <= SimWorld.W and s.pos.y >= 0 and s.pos.y <= SimWorld.H, "%s: ship in world" % tag)
			check(w.mission != null and w.mission.objective_text() is String, "%s: mission alive" % tag)
			w.dispose()
