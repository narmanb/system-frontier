extends TestCase
## Campaign model vs legacy (directories, built-in grids, migration, economy).


func test_directories_match_legacy() -> void:
	var fx := fixture("directories.json")
	for drive in fx["drives"]:
		var got := Campaign.build_directories(drive)
		var exp: Array = fx["drives"][drive]
		check(got.size() == exp.size(), "%s count" % drive)
		for i in exp.size():
			for k in ["name", "type", "diff", "icons", "theme"]:
				var same: bool = is_equal_approx(float(got[i][k]), float(exp[i][k])) if k in ["diff", "icons"] else str(got[i][k]) == str(exp[i][k])
				check(same, "%s[%d].%s: %s != %s" % [drive, i, k, got[i][k], exp[i][k]])
	var cg := Campaign.build_directories("CUSTOM", fx["custom"]["input"])
	for i in fx["custom"]["output"].size():
		for k in ["name", "type", "theme"]:
			check(str(cg[i][k]) == str(fx["custom"]["output"][i][k]), "custom[%d].%s: %s != %s" % [i, k, cg[i][k], fx["custom"]["output"][i][k]])


func test_builtin_grids_match_legacy() -> void:
	var fx := fixture("builtin_grids.json")
	for kind in fx["grids"]:
		var got := BuiltinShips.hex_grid(BuiltinShips.grid(kind))
		var exp: Array = fx["grids"][kind]
		var bad := 0
		for i in exp.size():
			if got[i] != ("" if exp[i] == null else str(exp[i]).to_lower()):
				bad += 1
		check(bad == 0, "%s: %d mismatched pixels" % [kind, bad])


func test_upgrade_cost_formula() -> void:
	# Legacy: Math.round(base * 1.55^level)
	check(Campaign.upgrade_cost("hull", 0) == 70, "hull L0")
	check(Campaign.upgrade_cost("hull", 3) == 261, "hull L3 = round(70*3.723875)")
	check(Campaign.upgrade_cost("reactor", 4) == 462, "reactor L4 = round(80*5.77200625)")


func test_create_campaign() -> void:
	var c := Campaign.create({"pilot": "  ", "team": "Pirates", "drive": "GAMES", "difficulty": 1.28, "ship": Campaign.builtin_ship("skull")})
	check(c["pilot"] == "Operator", "blank pilot -> Operator")
	check(c["dirs"].size() == 12 and c["dirs"][11]["type"] == "boss", "12 dirs, boss last")
	check(c["relations"]["Pirates"] == 100.0 and c["relations"]["Knights"] == -55.0, "relations from faction bias")
	check(c["missiles"] == 5 and c["blueprints"].size() == 10, "defaults")
	check(Campaign.is_locked(c, c["dirs"][11]), "boss locked without 4 Noble Programs")


func test_migrates_old_save() -> void:
	var old := {"pilot": "Ace", "team": "Avengers", "ship": {"id": "dart"}, "credits": 120,
		"upgrades": {"engine": 2, "brake": 1, "turning": 3, "armor": 2, "laser": 1, "fuel": 4},
		"dirs": [{"id": 0, "name": "A", "type": "normal"}, {"id": 1, "name": "B", "type": "normal"}, {"id": 2, "name": "C", "type": "normal", "cleared": true}]}
	var c: Dictionary = Campaign.ensure_defaults(old)
	var u: Dictionary = c["upgrades"]
	check(u["acceleration"] == 2 and u["maxSpeed"] == 2 and u["inertia"] == 1 and u["turn"] == 3 and u["hull"] == 2 and u["weaponPower"] == 1 and u["fuelCapacity"] == 4, "v5 upgrade mapping: %s" % u)
	check(not u.has("brake") and not u.has("engine"), "legacy keys dropped")
	check(c["dirs"][1]["type"] == "rescue", "pre-v6.4 uncleared normal dir 1 becomes rescue")
	check(c["dirs"][2]["type"] == "normal", "cleared dir untouched")
	check(c["contentVersion"] == 66 and c["salvage"]["alloy"] == 0 and c["blueprints"].has("chrome"), "v6.4/v6.6 defaults")
	check(c["ship"]["stats"].has("inertia"), "ship normalised to v6 stats")


func test_completion_rewards_once_with_theme_bonus() -> void:
	var c := Campaign.create({"team": "Avengers"})
	var d: Dictionary = c["dirs"][0]   # WINDOWS: normal, theme system
	var r := Campaign.complete_directory(c, 0)
	check(r["credits"] == 18 and r["alloy"] == 1 and r["circuitry"] == 1, "normal reward + system circuitry bonus: %s" % r)
	check(c["credits"] == 18 and c["wavesCleared"] == 1 and d["cleared"], "applied once")
	var r2 := Campaign.complete_directory(c, 0)
	check(r2.is_empty() and c["credits"] == 18 and c["wavesCleared"] == 1, "no double reward")


func test_selectable_ships() -> void:
	var list := Campaign.selectable_ships("Avengers", [])
	check(list[0]["name"] == "Red Falcon", "faction ship first")
	check(list.size() == 6, "faction ship + five starter hulls")
	var tex := Campaign.ship_texture(Campaign.builtin_ship("mantis"))
	check(tex != null and tex.get_width() == 24, "built-in procedural texture 24px")
