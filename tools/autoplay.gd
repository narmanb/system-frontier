extends Node
## Dev-only automated playtester. Flies every campaign directory with a scripted pilot
## through the real simulation (no rendering) and reports outcomes, so softlocks,
## impossible objectives and balance problems show up without a human.
##
##   godot --headless --path . res://tools/autoplay.tscn -- [--seeds=3] [--minutes=4] [--out=path] [--strict]
## --strict exits non-zero if any mission family has no wins (softlock regression check, CI).
##
## The pilot is deliberately ordinary: it flies to the current objective with
## counter-thrust braking, shoots aggressive ships in front of it, buys fuel/repairs from
## the ambulance when low, and always chooses "fight" in the dragon encounter.

const DT := 1.0 / 60

var seeds := 3
var minutes := 4.0
var out_path := "res://docs/PLAYTEST_REPORT.md"
var strict := false
var strategy := false   ## --strategy: campaign in strategy mode; the bot only picks autopilot priorities
var endless := false    ## --endless: Recycle Bin survival balance runs (experimental)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="): seeds = int(a.substr(8))
		if a.begins_with("--minutes="): minutes = float(a.substr(10))
		if a.begins_with("--out="): out_path = a.substr(6)
		if a == "--strict": strict = true
		if a == "--strategy": strategy = true
		if a == "--endless": endless = true
	if endless:
		_endless_runs()
		get_tree().quit(0)
		return
	var rows := []
	var t0 := Time.get_ticks_msec()
	for drive in ["SYSTEM"]:
		for dir_index in 12:
			for diff in [0.78, 1.0, 1.28]:
				for s in seeds:
					rows.append(_run(drive, dir_index, diff, 1000 + s * 7 + dir_index))
	var failed := _report(rows, Time.get_ticks_msec() - t0)
	get_tree().quit(1 if strict and not failed.is_empty() else 0)


func _run(drive: String, dir_index: int, diff: float, seed_value: int) -> Dictionary:
	var c := Campaign.create({"team": "Avengers", "drive": drive, "difficulty": diff, "mode": "strategy" if strategy else "action"})
	c["noble"] = 4
	c["credits"] = 150
	var d: Dictionary = c["dirs"][dir_index]
	var w := SimWorld.new()
	var dialogs := []
	w.dialog.connect(func(k, p): dialogs.append([k, p]))
	var result := {"outcome": "timeout", "reason": ""}
	w.finished.connect(func(won, reason):
		result["outcome"] = "won" if won else "lost"
		result["reason"] = reason)
	w.setup_directory(c, d, seed_value)
	var stats := {"dir": d["name"], "type": d["type"], "threat": int(d["difficulty"]), "difficulty": diff, "seed": seed_value,
		"time": 0.0, "hull_min": w.player.hull / w.player.max_hull, "ambulance": 0, "shots": 0, "kills_credits": 0, "stuck": 0.0}
	var credits0: int = c["credits"]
	var last_pos := w.player.pos
	var still := 0.0
	var steps := int(minutes * 60.0 / DT)
	for i in steps:
		if not dialogs.is_empty():
			var dlg: Array = dialogs.pop_front()
			var choice: String = {"dragon": "fight", "vendor": "repair", "quarantine": "purge"}.get(dlg[0], "decline")
			if not w.resolve_dialog(dlg[0], choice, dlg[1]):
				w.resolve_dialog(dlg[0], "decline" if dlg[0] == "vendor" else "retreat", dlg[1])
		if w.over:
			break
		var p := w.player
		if (p.fuel < p.max_fuel * 0.15 or p.hull < p.max_hull * 0.3) and c["credits"] > 30 and stats["ambulance"] < 6:
			stats["ambulance"] += 1
			w.buy_ambulance("fuel")
			w.buy_ambulance("hull")
		if strategy:
			var hostile_near := false
			for sh in w.ships:
				if NpcAI.aggressive_to_player(w, sh) and sh.pos.distance_to(p.pos) < 300:
					hostile_near = true
			w.strategy = "exit" if w.gate_open else ("attack" if hostile_near or w.dir_type in ["duel", "boss"] else "collect")
			w.step(DT, {})
		else:
			w.step(DT, _pilot(w))
		stats["hull_min"] = minf(stats["hull_min"], maxf(0, p.hull) / p.max_hull)
		if i % 60 == 0:
			if p.pos.distance_to(last_pos) < 20:
				still += 1.0
			else:
				still = 0.0
			stats["stuck"] = maxf(stats["stuck"], still)
			last_pos = p.pos
	stats["time"] = w.time
	stats["outcome"] = result["outcome"]
	stats["reason"] = result["reason"]
	stats["credits_gained"] = int(c["credits"]) - credits0
	stats["objective"] = w.mission.objective_text() if w.mission else ""
	stats["icons_left"] = w.icons.size()
	stats["gate_open"] = w.gate_open
	stats["shots"] = w.telemetry.shots
	w.dispose()
	return stats


func _endless_runs() -> void:
	var lines := ["# Recycle Bin balance (bot pilot, %d-minute cap)" % int(minutes), "", "| Hull | Seed | Waves cleared | Score | Kills | Time | Ambulance |", "|---|---|---|---|---|---|---|"]
	for hull_id in ["redFalcon", "blockadeRam", "wispNeedle"]:
		for s in seeds:
			var w := SimWorld.new()
			w.setup_endless(DataStore.starter_hull(hull_id), 500 + s)
			var amb := 0
			for i in int(minutes * 60.0 / DT):
				if w.over:
					break
				var p := w.player
				if w.mission.wave_state == "intermission" and (p.hull < p.max_hull * 0.6 or p.fuel < p.max_fuel * 0.4) and int(w.campaign["credits"]) > 30:
					w.buy_ambulance("hull")
					w.buy_ambulance("fuel")
					amb += 1
				w.step(DT, _pilot(w))
			var m := w.mission
			lines.append("| %s | %d | %d | %d | %d | %ds | %d |" % [hull_id, s, m.wave - (0 if m.wave_state == "intermission" else 1), m.score, w.player_kills, int(w.time), amb])
			w.dispose()
	var text := "\n".join(lines) + "\n"
	print(text)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(text)


## Scripted pilot → the same input dictionary the player's controls produce.
func _pilot(w: SimWorld) -> Dictionary:
	var p := w.player
	var target = null
	var hold := false
	if w.gate_open:
		target = w.gate_pos
	elif w.mission:
		var mt = w.mission.objective_point()
		if mt != null:
			target = mt
			hold = w.mission.type in ["repair", "scan"]
	if target == null:
		var best := INF
		for o in w.icons:
			if o.carrier == null and not o.infected and p.pos.distance_to(o.pos) < best:
				best = p.pos.distance_to(o.pos)
				target = o.pos
	var carrier: SimShip = null
	if target == null:
		for o in w.icons:   # only infected or carried icons left: chase anything
			target = o.carrier.pos if o.carrier else o.pos
			carrier = o.carrier
			break
	var enemy: SimShip = null
	var ed := INF
	for s in w.ships:
		if NpcAI.aggressive_to_player(w, s) and p.pos.distance_to(s.pos) < ed:
			ed = p.pos.distance_to(s.pos)
			enemy = s
	if carrier and (enemy == null or p.pos.distance_to(carrier.pos) < ed):
		enemy = carrier   # shoot the carrier to make it drop the icon
		ed = p.pos.distance_to(carrier.pos)
	if target == null and enemy:
		target = enemy.pos
	var inp := {"turn": 0.0, "thrust": false, "fire": false, "missile": false}
	if enemy and ed < 420:
		var aim := NpcAI.norm_angle((enemy.pos - p.pos).angle() - p.a)
		if absf(aim) < 0.25:
			inp["fire"] = p.weapon_heat < 85
			inp["missile"] = enemy.boss or ed < 250
	if target == null:
		return inp
	var steer := w.arrive_input(target, hold)
	inp["turn"] = steer["turn"]
	inp["thrust"] = steer["thrust"]
	if enemy and ed < 420 and not inp["thrust"]:
		inp["turn"] = clampf(NpcAI.norm_angle((enemy.pos - p.pos).angle() - p.a) * 3.0, -1, 1)
	return inp


## Returns the mission families with zero wins.
func _report(rows: Array, ms: int) -> Array:
	var by_type := {}
	for r in rows:
		var k: String = r["type"]
		if not by_type.has(k):
			by_type[k] = {"runs": 0, "won": 0, "lost": 0, "timeout": 0, "time": 0.0, "hull": 0.0, "examples": []}
		var b: Dictionary = by_type[k]
		b["runs"] += 1
		b[r["outcome"]] += 1
		if r["outcome"] == "won":
			b["time"] += r["time"]
		b["hull"] += r["hull_min"]
		if r["outcome"] != "won" and b["examples"].size() < 3:
			b["examples"].append("%s diff %.2f seed %d: %s — %s (objective %s, icons left %d, gate %s, stuck %ds)" % [r["dir"], r["difficulty"], r["seed"], r["outcome"], r["reason"], r["objective"], r["icons_left"], r["gate_open"], int(r["stuck"])])
	var lines := ["# Automated playtest report — %s mode" % ("strategy (autopilot)" if strategy else "action"), "",
		"Generated by `tools/autoplay.tscn` (scripted pilot, real simulation, no rendering). %d runs, %d s wall time, %.0f simulated minutes max per run." % [rows.size(), ms / 1000, minutes],
		"The pilot is a simple bot (fly to objective, counter-thrust brake, shoot what is in front, ambulance when low); failures point at softlocks or hard spots, not human difficulty.", "",
		"| Mission | Runs | Won | Lost | Timeout | Avg win time | Avg lowest hull |", "|---|---|---|---|---|---|---|"]
	for k in by_type:
		var b: Dictionary = by_type[k]
		lines.append("| %s | %d | %d | %d | %d | %s | %d%% |" % [k, b["runs"], b["won"], b["lost"], b["timeout"],
			("%.0f s" % (b["time"] / b["won"])) if b["won"] > 0 else "—", roundi(b["hull"] / b["runs"] * 100)])
	lines.append("")
	lines.append("## Non-wins (first few per mission)")
	for k in by_type:
		for e in by_type[k]["examples"]:
			lines.append("- **%s**: %s" % [k, e])
	var text := "\n".join(lines) + "\n"
	print(text)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(text)
	var failed := []
	for k in by_type:
		if by_type[k]["won"] == 0:
			failed.append(k)
	if not failed.is_empty():
		print("AUTOPLAY FAIL: no wins for ", failed)
	else:
		print("AUTOPLAY OK")
	return failed
