extends TestCase
## Ship Factory editor model vs legacy (presets, Auto-Clean passes) + editor behaviour.


func _norm(a: Array) -> Array:
	return a.map(func(v): return null if v == null else (int(v) if v is float else str(v).to_lower()))


func _diff(a: Array, b: Array) -> int:
	var n := 0
	for i in a.size():
		if str(a[i]) != str(b[i]):
			n += 1
	return n


func test_presets_match_legacy() -> void:
	var fx := fixture("factory.json")
	var e := FactoryEditor.new()
	for n in 5:
		e.preset_index = n - 1
		e.apply_preset(24)
		check(e.grid_size == 24, "preset is 24x24")
		var bad := _diff(_norm(e.grid), _norm(fx["presets"][n]))
		check(bad == 0, "preset %d: %d mismatched cells" % [n, bad])


func test_auto_clean_matches_legacy() -> void:
	var fx: Dictionary = fixture("factory.json")["repair"]
	var e := FactoryEditor.new()
	e.grid_size = 48
	e.grid = _norm(fx["input"])
	e.thrusters = ShipPerformance.normalize_thrusters(fx["thrusters"], 48)
	e.hardpoints = ShipPerformance.normalize_hardpoints(fx["hardpoints"], 48)
	var input := _norm(fx["input"])
	check(_diff(FactoryEditor.conservative_pass(input, 48), _norm(fx["conservative"])) == 0, "conservative pass")
	check(_diff(FactoryEditor.symmetry_pass(FactoryEditor.conservative_pass(input, 48), 48, "merge"), _norm(fx["symmetry_merge"])) == 0, "symmetry merge")
	check(_diff(FactoryEditor.symmetry_pass(FactoryEditor.conservative_pass(input, 48), 48, "left"), _norm(fx["symmetry_left"])) == 0, "symmetry left")
	var agg := e.aggressive_pass(input, 48, "right")
	check(_diff(agg, _norm(fx["aggressive_right"])) == 0, "aggressive right: %d diffs" % _diff(agg, _norm(fx["aggressive_right"])))


func test_paint_mirror_undo_redo() -> void:
	var e := FactoryEditor.new()
	e.new_blank(24, false)
	e.select_color(3)
	e.push_history()
	e.paint(2, 5)
	check(e.grid[5 * 24 + 2] == 3 and e.grid[5 * 24 + 21] == 3, "mirror paints both halves")
	e.undo()
	check(e.is_empty(), "undo restores blank")
	e.redo()
	check(e.grid[5 * 24 + 2] == 3, "redo")
	e.tool = "erase"
	e.paint(2, 5)
	check(e.is_empty(), "erase (mirrored)")
	check(e.recent[0] == 3, "recent colour recorded")


func test_fill_and_replace() -> void:
	var e := FactoryEditor.new()
	e.new_blank(24, false)
	e.mirror = false
	e.tool = "fill"
	e.select_color(1)
	e.paint(0, 0)
	check(not e.grid.has(null), "fill covers empty canvas")
	check(e.replace_color(1, 2) == 576, "replace all")
	e.grid[0] = 5
	check(e.swap_colors(2, 5) == 576, "swap")


func test_resize_scales_mounts() -> void:
	var e := FactoryEditor.new()
	e.load_starter("redFalcon")
	check(e.grid_size == 48 and e.mount("thruster", "center")["y"] == 43, "Red Falcon 48x48 with centre thruster at y43")
	check(e.resize_canvas(24), "resize")
	check(e.grid_size == 24 and e.grid.size() == 576, "resized grid")
	check(e.mount("thruster", "center")["x"] == 12 and e.mount("hardpoint", "primary")["y"] == 6, "mounts scaled with v61ScalePoint")
	e.undo()
	check(e.grid_size == 48, "undo resize")


func test_budgets() -> void:
	var e := FactoryEditor.new()
	e.new_blank(48, false)
	check(e.stat_sum() == 50, "balanced archetype uses the full budget")
	check(not e.change_stat("hull", 1), "budget blocks increase")
	check(e.change_stat("reactor", -1) and e.change_stat("hull", 1), "can move points")
	for i in 10:
		e.change_stat("hull", 1)
	check(e.stats["hull"] <= FactoryEditor.STAT_CAP, "factory cap 8")
	check(e.toggle_thruster("left") and e.toggle_thruster("right"), "two side engines fit the mount budget")
	check(e.mount_cost() == 4 and not e.toggle_thruster("center"), "centre always on")
	e.new_blank(24, false)
	check(e.validate() != "", "empty hull cannot be saved")


func test_ship_data_roundtrip() -> void:
	var e := FactoryEditor.new()
	e.load_starter("novaSting")
	e.name = "Sting II"
	var s := e.ship_data()
	check(s["custom"] and s["gridSize"] == 48 and s["name"] == "Sting II", "ship data")
	var e2 := FactoryEditor.new()
	e2.load_ship(s)
	check(e2.grid == e.grid and e2.selected_id == s["id"], "load back")
	var p := ShipPerformance.compute(s)
	check(p.maxSpeed > 0, "flyable")
	check(Campaign.ship_texture(s).get_width() == 48, "custom texture from grid")


func test_auto_clean_realigns_mounts() -> void:
	var e := FactoryEditor.new()
	e.load_starter("redFalcon")
	var g := e.grid.duplicate()
	var c := e.mount("thruster", "center")
	g[int(c["y"]) * 48 + int(c["x"])] = null
	var moved := e.apply_repair(g)
	check(moved >= 1, "mount on a removed pixel is moved onto the hull")
