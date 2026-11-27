class_name ShipPerformance
extends RefCounted
## Native port of the legacy engineering model.
##
## Source of truth: the *final* `v6Performance` override (legacy v6.1 block, "selectable
## 24/32/48 custom canvases and full reactor-overload behavior") plus `v6Stats`,
## `v6Modules`, `normalizeThrusters`, `v6NormalizeHardpoints`, `v6EffectiveShip`.
## Verified against tests/fixtures/performance.json, generated from the legacy code.
##
## Note: the legacy "Brake" stat was removed by owner decision; old `brake` values migrate
## to `inertia` (Inertia Stabilization) exactly like v6Stats does.


static func _num(d: Dictionary, keys: Array, def: float) -> float:
	for k in keys:
		if d.has(k) and d[k] != null:
			return float(d[k])
	return def


## JS Math.round: rounds half up (towards +inf), unlike GDScript round() for negatives.
static func js_round(v: float) -> float:
	return floor(v + 0.5)


static func normalize_stats(input: Dictionary) -> Dictionary:
	var c := func(v: float) -> int: return int(clamp(js_round(v), 1, 10))
	return {
		"acceleration": c.call(_num(input, ["acceleration"], 5)),
		"maxSpeed": c.call(_num(input, ["maxSpeed", "speed"], 5)),
		"inertia": c.call(_num(input, ["inertia", "brake"], 5)),
		"turn": c.call(_num(input, ["turn", "turning"], 5)),
		"hull": c.call(_num(input, ["hull", "armor"], 5)),
		"fuelCapacity": c.call(_num(input, ["fuelCapacity", "fuel"], 5)),
		"fuelEfficiency": c.call(_num(input, ["fuelEfficiency"], 5)),
		"weaponPower": c.call(_num(input, ["weaponPower", "laser"], 5)),
		"weaponCooling": c.call(_num(input, ["weaponCooling"], 5)),
		"reactor": c.call(_num(input, ["reactor"], 5)),
	}


static func normalize_modules(input: Variant, special := "shield") -> Dictionary:
	var mods := DataStore.modules()
	var defense := special if special in ["shield", "cloak", "ram"] else "shield"
	var out := {
		"primary": "pulse", "secondary": "missile", "defense": defense,
		"utility": "tractor" if special == "tractor" else "repair", "scanner": "standard",
	}
	if input is Dictionary:
		for k in input:
			out[k] = input[k]
	for slot in mods:
		if not mods[slot].has(str(out.get(slot, ""))):
			out[slot] = mods[slot].keys()[0]  # JSON keeps legacy insertion order
	return out


static func default_thrusters(size := 24) -> Array:
	return [
		{"id": "center", "x": int(js_round(size * 0.5)), "y": int(js_round(size * 0.86)), "enabled": true, "cost": 0, "scale": 1.12},
		{"id": "left", "x": int(js_round(size * 0.32)), "y": int(js_round(size * 0.81)), "enabled": false, "cost": 2, "scale": 0.74},
		{"id": "right", "x": int(js_round(size * 0.68)), "y": int(js_round(size * 0.81)), "enabled": false, "cost": 2, "scale": 0.74},
	]


static func _merge_mounts(base: Array, src: Variant, size: int, is_thruster: bool) -> Array:
	var out := []
	var list: Array = src if src is Array else []
	for b in base:
		var found = null
		for t in list:
			if t is Dictionary and t.get("id") == b["id"]:
				found = t
				break
		if found == null:
			out.append(b.duplicate())
			continue
		var m: Dictionary = b.duplicate()
		for k in found:
			m[k] = found[k]
		m["x"] = int(clamp(js_round(float(found.get("x", b["x"]))), 0, size - 1))
		m["y"] = int(clamp(js_round(float(found.get("y", b["y"]))), 0, size - 1))
		if is_thruster:
			m["enabled"] = true if b["id"] == "center" else bool(found.get("enabled", false))
		out.append(m)
	return out


static func normalize_thrusters(list: Variant, size := 24) -> Array:
	return _merge_mounts(default_thrusters(size), list, size, true)


static func default_hardpoints(size := 24) -> Array:
	return [
		{"id": "primary", "x": int(js_round(size * 0.5)), "y": int(js_round(size * 0.18))},
		{"id": "secondary", "x": int(js_round(size * 0.34)), "y": int(js_round(size * 0.43))},
		{"id": "defense", "x": int(js_round(size * 0.66)), "y": int(js_round(size * 0.43))},
		{"id": "utility", "x": int(js_round(size * 0.5)), "y": int(js_round(size * 0.58))},
	]


static func normalize_hardpoints(list: Variant, size := 24) -> Array:
	return _merge_mounts(default_hardpoints(size), list, size, false)


## Legacy v6EffectiveShip: campaign upgrades add 0.8 per level, then component stat bonuses.
static func effective_stats(base_stats: Dictionary, upgrades: Dictionary, components: Dictionary) -> Dictionary:
	var base := normalize_stats(base_stats)
	var s := {}
	for k in DataStore.stat_order():
		s[k] = base[k] + float(upgrades.get(k, 0)) * 0.8
	var comps: Dictionary = DataStore.engineering()["components"]
	for k in components:
		if components[k] and comps.has(k) and comps[k].has("stat"):
			s[comps[k]["stat"]] = float(s.get(comps[k]["stat"], 0)) + float(comps[k]["amount"])
	return s


## Port of the final legacy v6Performance(shipLike, components, rare).
static func compute(ship: Dictionary, components: Dictionary = {}, rare: Dictionary = {}) -> Dictionary:
	var eng := DataStore.engineering()
	var M: Dictionary = eng["modules"]
	var raw_stats: Dictionary = ship.get("stats", ship) if ship.get("stats") is Dictionary else ship
	var stats := normalize_stats(raw_stats)
	var mods := normalize_modules(ship.get("modules"), str(ship.get("special", "shield")))
	var grid_size := int(ship.get("gridSize", 32)) if ship.get("gridSize") != null else 32
	var thrusters := normalize_thrusters(ship.get("thrusters"), grid_size)
	var side := 0
	for t in thrusters:
		if t["enabled"] and t["id"] != "center":
			side += 1
	var items := []
	var module_mass := 0.0
	var demand := 20.0
	for slot in M:
		var item: Dictionary = M[slot][mods[slot]]
		items.append(item)
		module_mass += float(item.get("mass", 0))
		demand += float(item.get("power", 0))
	var mass: float = 46.0 + stats.hull * 3.2 + stats.fuelCapacity * 1.4 + stats.weaponPower * 1.2 + module_mass + side * 4
	for k in components:
		if components[k] and eng["components"].has(k) and eng["components"][k].has("massMult"):
			mass *= float(eng["components"][k]["massMult"])
	var capacity: float = 22.0 + stats.reactor * 10
	var raw_power_ratio: float = capacity / max(1.0, demand)
	var power_factor := clampf(raw_power_ratio, 0.58, 1.0)
	var overload := maxf(0.0, 1.0 - power_factor)
	var mass_factor := clampf(82.0 / mass, 0.68, 1.12)
	var thruster_mult := 1.0 + side * 0.14
	var accel_pf := 1.0 - overload * 0.72
	var turn_pf := 1.0 - overload * 0.43
	var weapon_pf := 1.0 - overload * 0.72
	var module_pf := power_factor
	var critical := power_factor < 2.0 / 3.0
	var critical_depth := clampf(((2.0 / 3.0) - power_factor) / ((2.0 / 3.0) - 0.58), 0.0, 1.0)
	var speed_pf := 1.0 - critical_depth * 0.15
	var primary: Dictionary = M["primary"][mods["primary"]]
	var secondary: Dictionary = M["secondary"][mods["secondary"]]
	var defense: Dictionary = M["defense"][mods["defense"]]
	var utility: Dictionary = M["utility"][mods["utility"]]
	var scanner: Dictionary = M["scanner"][mods["scanner"]]
	var rare_def: Dictionary = eng["rareTech"]
	var comp_def: Dictionary = eng["components"]

	var max_speed: float = (150.0 + stats.maxSpeed * 27) * (float(rare_def["nobleOverdrive"]["speedMult"]) if rare.get("nobleOverdrive") else 1.0) * speed_pf
	var acceleration: float = (72.0 + stats.acceleration * 14) * mass_factor * thruster_mult * accel_pf
	var turn_rate: float = (1.45 + stats.turn * 0.205) * clampf(94.0 / mass, 0.72, 1.13) * turn_pf
	var passive_loss: float = (1.0 + stats.inertia * 0.6) / 100.0
	var max_hull: float = 65.0 + stats.hull * 15 + float(defense.get("hull", 0))
	var max_fuel: float = 70.0 + stats.fuelCapacity * 20
	var fuel_burn := maxf(0.42, (1.55 - stats.fuelEfficiency * 0.11) * float(utility.get("fuelMult", 1)) * (1 + side * 0.08) * (float(comp_def["recycler"]["fuelMult"]) if components.get("recycler") else 1.0))
	var damage: float = (5.0 + stats.weaponPower * 2.2) * float(primary.get("damage", 1))
	var base_fire := maxf(0.105, (0.36 - stats.weaponCooling * 0.022) * float(primary.get("cooldown", 1)))
	var fire_interval := base_fire / weapon_pf
	var cooling: float = (8.0 + stats.weaponCooling * 2.6) * weapon_pf
	if rare.get("demonCooling"):
		cooling *= float(rare_def["demonCooling"]["coolingMult"])
	return {
		"stats": stats, "mods": mods, "items": items, "moduleMass": module_mass, "mass": mass,
		"demand": demand, "capacity": capacity, "rawPowerRatio": raw_power_ratio, "powerFactor": power_factor,
		"overloadAmount": overload, "accelPowerFactor": accel_pf, "turnPowerFactor": turn_pf,
		"weaponPowerFactor": weapon_pf, "modulePowerFactor": module_pf, "criticalOverload": critical,
		"speedPowerFactor": speed_pf, "thrusterMult": thruster_mult, "maxSpeed": max_speed,
		"acceleration": acceleration, "turnRate": turn_rate, "passiveLoss": passive_loss,
		"coastDrag": pow(1.0 - passive_loss, 1.0 / 60.0), "maxHull": max_hull, "maxFuel": max_fuel,
		"fuelBurn": fuel_burn, "fuelSeconds": max_fuel / fuel_burn, "damage": damage,
		"fireInterval": fire_interval, "cooling": cooling, "heatPerShot": 14.0 * float(primary.get("heat", 1)),
		"missileBonus": float(secondary.get("missiles", 0)), "missileDamage": float(secondary.get("missileDamage", 1)),
		"shield": float(defense.get("shield", 0)) + (float(rare_def["dragonShield"]["shield"]) if rare.get("dragonShield") else 0.0),
		"shieldRechargeFactor": module_pf, "cloak": float(defense.get("cloak", 0)) * module_pf,
		"repair": float(utility.get("repair", 0)) * module_pf,
		"pickupRadius": 27.0 + float(utility.get("pickup", 0)) * module_pf,
		"salvageMult": 1.0 + (float(scanner.get("salvage", 1)) - 1.0) * module_pf,
		"scannerRange": 1.0 + (float(scanner.get("range", 1)) - 1.0) * module_pf,
	}


## Legacy v6HardpointWorld: mount position in world space for a ship drawn at `size` px.
static func mount_world(pos: Vector2, angle: float, mount: Dictionary, grid_size: int, size: float, quarter_turns := 0) -> Vector2:
	var local := Vector2(((mount["x"] + 0.5) / grid_size - 0.5) * size, ((mount["y"] + 0.5) / grid_size - 0.5) * size)
	return pos + local.rotated(angle + PI / 2 + quarter_turns * PI / 2)
