extends TestCase
## Ship engineering formulas vs. legacy v6Performance output (tests/fixtures/performance.json).


func test_fixture_cases_match_legacy() -> void:
	var fx := fixture("performance.json")
	check(fx["cases"].size() >= 20, "expected >=20 fixture cases")
	for c in fx["cases"]:
		var inp: Dictionary = c["input"]
		var ship: Dictionary = inp["ship"]
		if c.has("effectiveStats"):
			var camp: Dictionary = inp["campaign"]
			var eff := ShipPerformance.effective_stats(camp["ship"]["stats"], camp["upgrades"], camp["components"])
			for k in c["effectiveStats"]:
				near(eff[k], c["effectiveStats"][k], 1e-9, "%s effective %s" % [c["name"], k])
		var p := ShipPerformance.compute(ship, inp["components"], inp["rare"])
		var exp: Dictionary = c["expected"]
		for k in exp:
			if k == "mods" or k == "stats":
				for kk in exp[k]:
					var a: Variant = p[k][kk]
					var e: Variant = exp[k][kk]
					var same: bool = (str(a) == str(e)) if e is String else is_equal_approx(float(a), float(e))
					check(same, "%s %s.%s: %s != %s" % [c["name"], k, kk, a, e])
			elif exp[k] is bool:
				check(p[k] == exp[k], "%s %s: %s != %s" % [c["name"], k, p[k], exp[k]])
			else:
				near(float(p[k]), float(exp[k]), 1e-9, "%s %s" % [c["name"], k])


func test_brake_migrates_to_inertia() -> void:
	var s := ShipPerformance.normalize_stats({"brake": 7, "armor": 9, "laser": 2, "fuel": 3})
	check(s["inertia"] == 7 and s["hull"] == 9 and s["weaponPower"] == 2 and s["fuelCapacity"] == 3, "legacy alias migration: %s" % s)
	check(not s.has("brake"), "brake stat must not exist in normalized stats")


func test_red_falcon_mounts() -> void:
	var h := DataStore.starter_hull("redFalcon")
	var thr := ShipPerformance.normalize_thrusters(h["thrusters"], 48)
	var enabled := thr.filter(func(t): return t["enabled"])
	check(enabled.size() == 3, "Red Falcon has three enabled thrusters")
	check(thr[0]["x"] == 24 and thr[0]["y"] == 43, "center thruster at 24,43")
	var hp := ShipPerformance.normalize_hardpoints(h["hardpoints"], 48)
	check(hp.size() == 4, "four hardpoints")
	check(hp[0]["x"] == 24 and hp[0]["y"] == 12, "primary hardpoint at 24,12")
