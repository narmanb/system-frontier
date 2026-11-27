extends Node
## Dev-only performance benchmark. Measures script cost per frame in the busiest scenes.
##   godot --path . res://tools/bench.tscn -- [--frames=300]   (run under a display)
## Also runs a pure-simulation benchmark (no rendering) so the sim cost is isolated.

var frames := 300


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="): frames = int(a.substr(9))
	var placeholder := Node.new()
	get_tree().root.add_child.call_deferred(placeholder)
	await _f(1)
	get_tree().current_scene = placeholder
	reparent(get_tree().root)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var lines := ["# Performance benchmark", "", "Script time per frame (Godot monitors) on this machine; compare relatively. Physics = 60 Hz simulation step.", "",
		"| Scene | Avg process ms | Avg physics ms | Max process ms | Entities | _draw cost |", "|---|---|---|---|---|---|"]
	SaveService.root = "user://bench_saves/"
	var c := Campaign.create({})
	c["noble"] = 4
	c["difficulty"] = 1.28
	SaveService.save_campaign(c)
	for spec in [["(warm-up)", {"mode": "test", "threat": 1}], ["Sandbox threat 5", {"mode": "sandbox", "threat": 5}], ["Inner Demon (boss)", {"mode": "campaign", "dir_id": 11}],
			["Duel threat 3", {"mode": "campaign", "dir_id": 7}], ["Test range", {"mode": "test", "threat": 1}]]:
		AppState.launch = spec[1]
		get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")
		await _f(30)
		Input.action_press("fire")
		Input.action_press("thrust")
		Input.action_press("turn_left")
		var r := await _measure()
		Input.action_release("fire")
		Input.action_release("thrust")
		Input.action_release("turn_left")
		var w: SimWorld = get_tree().current_scene.world
		var ents := "%d ships, %d bullets, %d particles" % [w.ships.size(), w.bullets.size(), w.particles.size()]
		lines.append("| %s | %.2f | %.2f | %.2f | %s | %s |" % [spec[0], r[0], r[1], r[2], ents, draw_report])
	AppState.settings["factory_tab"] = "Paint"
	get_tree().change_scene_to_file("res://scenes/factory/factory.tscn")
	await _f(20)
	var fac := get_tree().current_scene
	fac.canvas.set_zoom(3.0)
	var r2 := await _measure()
	lines.append("| Factory canvas 48×48, 3× zoom | %.2f | %.2f | %.2f | 2304 cells | %s |" % [r2[0], r2[1], r2[2], draw_report])
	# pure simulation (no rendering)
	var w2 := SimWorld.new()
	var c2 := Campaign.create({})
	w2.setup_directory(c2, c2["dirs"][11], 7)
	var t0 := Time.get_ticks_usec()
	for i in 1800:
		w2.step(1.0 / 60, {"turn": 0.3, "thrust": true, "fire": true})
	var per := (Time.get_ticks_usec() - t0) / 1800.0 / 1000.0
	w2.dispose()
	lines.append("")
	lines.append("Pure simulation, Inner Demon directory, 1800 steps: **%.3f ms per 60 Hz step**." % per)
	var t1 := Time.get_ticks_usec()
	FactionPalette._texture_cache.clear()
	for arch in ["grunt", "skirmisher", "beam", "hunter", "raider"]:
		FactionPalette.npc_texture(arch, "Knights")
	lines.append("Faction recolour (5 archetypes, uncached): **%.1f ms total** (cached afterwards)." % ((Time.get_ticks_usec() - t1) / 1000.0))
	SaveService.reset("all")
	SaveService.root = "user://"
	var text := "\n".join(lines) + "\n"
	print(text)
	var f := FileAccess.open("res://docs/PERFORMANCE.md", FileAccess.WRITE)
	f.store_string(text)
	get_tree().quit()


var draw_report := ""


func _measure() -> Array:
	var proc := 0.0
	var phys := 0.0
	var mx := 0.0
	var draws := {}
	for i in frames:
		await get_tree().process_frame
		var p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		proc += p
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		mx = maxf(mx, p)
		for n in get_tree().current_scene.find_children("*", "", true, false):
			if "draw_us" in n:
				draws[n.get_class() + ":" + str(n.get_script().resource_path.get_file())] = draws.get(n.get_class() + ":" + str(n.get_script().resource_path.get_file()), 0.0) + n.draw_us
	var parts := []
	for k in draws:
		parts.append("%s %.2f ms" % [k.get_slice(":", 1), draws[k] / frames / 1000.0])
	draw_report = ", ".join(parts)
	return [proc / frames, phys / frames, mx]


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame
