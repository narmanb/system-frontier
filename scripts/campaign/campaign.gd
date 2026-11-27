class_name Campaign
extends RefCounted
## Campaign model helpers — native port of the effective legacy campaign code:
##   newCampaign (v6.6), buildDirectories + v64ThemeFor (v6.4), ensureCampaignDefaults chain
##   (v6 → v6.4 → v6.6, including old-save migration), upgradeCost, v64AwardCompletion,
##   v6EffectiveShip. Campaign state is a plain Dictionary with the legacy field names so
##   legacy JSON saves import without translation.

const STAT_KEYS := ["acceleration", "maxSpeed", "inertia", "turn", "hull", "fuelCapacity", "fuelEfficiency", "weaponPower", "weaponCooling", "reactor"]
const CONTENT_VERSION := 66


static func data() -> Dictionary:
	return DataStore.load_json("res://data/campaign.json")


static func js_round(v: float) -> float:
	return floor(v + 0.5)


# ------------------------------------------------------------------ directories

static func theme_for(name: String, drive: String, index: int) -> String:
	var n := name.to_upper()
	var d := drive.to_upper()
	var rx := func(p: String, s: String) -> bool:
		var r := RegEx.new()
		r.compile(p)
		return r.search(s) != null
	if rx.call("WINDOWS|SYSTEM|DRIVER|FONT|PROGRAM|TOOLS", n): return "system"
	if rx.call("GAME|ARCADE|RPG|SIM|STRATEGY|MOD|DEMO|CLASSIC|INDIE|BOSS", n) or d == "GAMES": return "games"
	if rx.call("MUSIC|MEDIA|PHOTO|MOVIE|SCREEN|SAMPLE|WAV|BMP|VIDEO", n): return "media"
	if rx.call("ARCHIVE|BACKUP|ZIP|BOOK|OLD|VAULT|PROJECT", n) or d == "ARCHIVE": return "archive"
	if rx.call("RECYC|TEMP|TRASH|MISC", n): return "recycle"
	if rx.call("CACHE|WEB|INTERNET|DOWNLOAD|DESKTOP", n): return "internet"
	return ["system", "games", "media", "archive", "recycle", "internet"][index % 6]


## Legacy final `buildDirectories`. `custom_names` are file paths ("DIR/file") or bare
## folder names; only names are used (never file contents), as in the legacy build.
static func build_directories(drive: String, custom_names: Array = []) -> Array:
	var base: Array = []
	var cd := data()
	if drive == "CUSTOM" and not custom_names.is_empty():
		var seen := {}
		for p in custom_names:
			var parts: PackedStringArray = str(p).split("/")
			var dir := "\\".join(parts.slice(0, parts.size() - 1))
			if dir == "":
				dir = "ROOT"
			if not seen.has(dir):
				seen[dir] = true
				base.append(dir)
		base = base.slice(0, 12)
		while base.size() < 12:
			base.append("SECTOR_%02d" % (base.size() + 1))
	else:
		base = cd["drives"].get(drive, cd["drives"]["SYSTEM"])
	var out := []
	var plan: Array = cd["typePlan"]
	for i in base.size():
		var type: String = plan[i] if i < plan.size() else "normal"
		out.append({"name": base[i], "type": type, "diff": 1 + i / 3,
			"icons": 0 if cd["specialTypes"].has(type) else 4 + i / 2, "theme": theme_for(base[i], drive, i)})
	return out


static func normalize_dir(d: Dictionary, index: int, c: Dictionary) -> Dictionary:
	if not d.has("theme") or str(d["theme"]) == "":
		d["theme"] = theme_for(str(d.get("name", "")), str(c.get("drive", "")), index)
	if not d.has("type") or str(d["type"]) == "":
		d["type"] = "normal"
	d["difficulty"] = int(d.get("difficulty", 1)) if float(d.get("difficulty", 0)) > 0 else 1
	if not d.has("icons") or d["icons"] == null:
		d["icons"] = 4 + index / 2
	if data()["specialTypes"].has(d["type"]):
		d["icons"] = 0
	d["id"] = int(d.get("id", index))
	d["cleared"] = bool(d.get("cleared", false))
	return d


# ------------------------------------------------------------------ ships

static func builtin_ships() -> Array:
	var out := []
	for s in data()["builtinShips"]:
		var ship: Dictionary = s.duplicate(true)
		ship["builtin"] = true
		out.append(ship)
	return out


static func builtin_ship(id: String) -> Dictionary:
	for s in builtin_ships():
		if s["id"] == id:
			return s
	return builtin_ships()[0]


## Legacy normalizeShip (v6): merge builtin base by id, normalise stats/modules/mounts.
static func normalize_ship(ship: Variant) -> Dictionary:
	var src: Dictionary = ship if ship is Dictionary else {}
	var base := {}
	for b in builtin_ships():
		if b["id"] == src.get("id", ""):
			base = b
	var out: Dictionary = base.duplicate(true)
	for k in src:
		out[k] = src[k]
	out["stats"] = ShipPerformance.normalize_stats(src.get("stats", base.get("stats", {})) if src.get("stats") is Dictionary else base.get("stats", {}))
	out["modules"] = ShipPerformance.normalize_modules(src.get("modules", base.get("modules")), str(src.get("special", base.get("special", "shield"))))
	var n := int(out.get("gridSize", 0))
	if n <= 0:
		var g = out.get("grid")
		n = int(round(sqrt((g as Array).size()))) if g is Array and not (g as Array).is_empty() else 24
	out["gridSize"] = n
	out["thrusters"] = ShipPerformance.normalize_thrusters(out.get("thrusters"), n)
	out["hardpoints"] = ShipPerformance.normalize_hardpoints(out.get("hardpoints"), n)
	out["rotation"] = int(out.get("rotation", 0))
	if not out.has("name"):
		out["name"] = "Custom Ship"
	return out


## Ships selectable when starting an operation: the faction's built-in ship (legacy), plus
## the five starter hulls and saved custom ships (port addition: starters were factory-only).
static func selectable_ships(team: String, custom: Array) -> Array:
	var out := []
	for b in builtin_ships():
		if b["team"] == team:
			out.append(normalize_ship(b))
	for id in DataStore.starter_hulls()["order"]:
		var h := DataStore.starter_hull(id)
		h["id"] = "starter_" + id
		h["desc"] = h.get("description", "")
		h["team"] = team
		out.append(normalize_ship(h))
	for s in custom:
		out.append(normalize_ship(s))
	return out


## Texture for any ship dictionary (starter art, built-in procedural grid, or custom grid).
static func ship_texture(ship: Dictionary) -> Texture2D:
	if ship.has("art") and ship["art"] != null and str(ship["art"]) != "" and not ship.has("grid"):
		return load(str(ship["art"]))
	if ship.get("grid") is Array and not (ship["grid"] as Array).is_empty():
		var n := int(ship.get("gridSize", 24))
		return ImageTexture.create_from_image(FactionPalette.grid_to_image(BuiltinShips.hex_grid(ship["grid"]), n))
	if ship.get("builtin", false) or ship.has("shape"):
		return BuiltinShips.texture(str(ship.get("id", "dart")) if BuiltinShips.ROWS.has(str(ship.get("id", ""))) else str(ship.get("shape", "dart")))
	return load("res://assets/ships/red_falcon.png")


# ------------------------------------------------------------------ create / migrate

static func create(opts: Dictionary) -> Dictionary:
	var team: String = opts.get("team", "Avengers")
	var fac := DataStore.factions()
	var rel := {}
	for f in fac:
		rel[f] = float(fac[team]["bias"].get(f, 0))
	rel[team] = 100.0
	var drive: String = opts.get("drive", "SYSTEM")
	var dirs := []
	var names := build_directories(drive, opts.get("custom_names", []))
	for i in names.size():
		var n: Dictionary = names[i]
		dirs.append({"id": i, "name": n["name"], "type": n["type"], "theme": n["theme"], "cleared": false, "difficulty": n["diff"], "icons": n["icons"]})
	var blueprints := {}
	for k in blueprint_keys():
		blueprints[k] = false
	var ship: Dictionary = normalize_ship(opts.get("ship", builtin_ship("dart")))
	var c := {
		"pilot": str(opts.get("pilot", "")).strip_edges() if str(opts.get("pilot", "")).strip_edges() != "" else "Operator",
		"team": team, "shipId": ship.get("id", "dart"), "ship": ship, "mode": opts.get("mode", "action"), "drive": drive,
		"difficulty": float(opts.get("difficulty", 1.0)), "credits": 0, "missiles": 5, "laserLevel": 1, "armorLevel": 1,
		"noble": 0, "wavesCleared": 0, "warrant": 0, "upgrades": _zero_upgrades(), "components": {}, "rareTech": {},
		"salvage": {"alloy": 0, "circuitry": 0, "data": 0}, "blueprints": blueprints, "discoveries": 0,
		"contentVersion": CONTENT_VERSION, "relations": rel, "dirs": dirs, "created": Time.get_unix_time_from_system() * 1000.0,
	}
	return c


static func _zero_upgrades() -> Dictionary:
	var u := {}
	for k in STAT_KEYS:
		u[k] = 0
	return u


static func blueprint_keys() -> Array:
	return data()["paletteUnlocks"].keys() + data()["stencils"].keys()


static func _n(d: Dictionary, k: String) -> float:
	var v = d.get(k)
	return float(v) if (v is float or v is int) else (float(v) if v is String and str(v).is_valid_float() else 0.0)


## Legacy ensureCampaignDefaults chain (v6 → v6.4 → v6.6). Accepts old v5 saves.
static func ensure_defaults(c: Variant) -> Variant:
	if not (c is Dictionary):
		return c
	var d: Dictionary = c
	d["difficulty"] = float(d.get("difficulty", 1)) if _n(d, "difficulty") != 0 else 1.0
	d["missiles"] = int(d["missiles"]) if (d.get("missiles") is float or d.get("missiles") is int) else 5
	d["laserLevel"] = int(d.get("laserLevel", 1)) if _n(d, "laserLevel") != 0 else 1
	d["armorLevel"] = int(d.get("armorLevel", 1)) if _n(d, "armorLevel") != 0 else 1
	d["ship"] = normalize_ship(d.get("ship", builtin_ship("dart")))
	var raw: Dictionary = d.get("upgrades", {}) if d.get("upgrades") is Dictionary else {}
	var pick := func(a: String, b: String) -> int:
		var v := _n(raw, a)
		return int(v if v != 0 else _n(raw, b))
	d["upgrades"] = {
		"acceleration": pick.call("acceleration", "engine"), "maxSpeed": pick.call("maxSpeed", "engine"),
		"inertia": pick.call("inertia", "brake"), "turn": pick.call("turn", "turning"), "hull": pick.call("hull", "armor"),
		"fuelCapacity": pick.call("fuelCapacity", "fuel"), "fuelEfficiency": int(_n(raw, "fuelEfficiency")),
		"weaponPower": pick.call("weaponPower", "laser"), "weaponCooling": int(_n(raw, "weaponCooling")), "reactor": int(_n(raw, "reactor")),
	}
	if not (d.get("components") is Dictionary): d["components"] = {}
	if not (d.get("rareTech") is Dictionary): d["rareTech"] = {}
	# v6.4
	var salvage := {"alloy": 0, "circuitry": 0, "data": 0}
	if d.get("salvage") is Dictionary:
		for k in d["salvage"]:
			salvage[k] = int(d["salvage"][k])
	d["salvage"] = salvage
	d["discoveries"] = int(_n(d, "discoveries"))
	if not d.has("relations") or not (d["relations"] is Dictionary): d["relations"] = {}
	for k in ["noble", "wavesCleared", "warrant", "credits"]:
		d[k] = int(_n(d, k))
	if not d.has("team"): d["team"] = "Avengers"
	if not d.has("pilot"): d["pilot"] = "Operator"
	if not d.has("mode"): d["mode"] = "action"
	if d.get("dirs") is Array:
		var migrate := _n(d, "contentVersion") < 64
		var plan: Array = data()["typePlan"]
		for i in d["dirs"].size():
			var dir: Dictionary = d["dirs"][i]
			if migrate and not dir.get("cleared", false) and dir.get("type", "normal") == "normal" and i in [1, 2, 4, 6, 8]:
				dir["type"] = plan[i]
			normalize_dir(dir, i, d)
		d["contentVersion"] = 64
	else:
		d["dirs"] = []
	# v6.6
	var bp := {}
	for k in blueprint_keys():
		bp[k] = false
	if d.get("blueprints") is Dictionary:
		for k in d["blueprints"]:
			bp[k] = bool(d["blueprints"][k])
	d["blueprints"] = bp
	if _n(d, "contentVersion") < 66:
		d["contentVersion"] = 66
	return d


# ------------------------------------------------------------------ economy

static func upgrade_cost(key: String, level: int) -> int:
	return int(js_round(float(data()["upgrades"][key]["base"]) * pow(1.55, level)))


static func difficulty_label(v: float) -> String:
	return "Relaxed" if v < 0.9 else ("Veteran" if v > 1.15 else "Standard")


static func reward_text(b: Dictionary) -> String:
	var parts := []
	if b.get("credits", 0): parts.append("%d credits" % b["credits"])
	if b.get("alloy", 0): parts.append("%d alloy" % b["alloy"])
	if b.get("circuitry", 0): parts.append("%d circuitry" % b["circuitry"])
	if b.get("data", 0): parts.append("%d data core%s" % [b["data"], "" if b["data"] == 1 else "s"])
	return " • ".join(parts) if not parts.is_empty() else "standard salvage"


static func add_salvage(c: Dictionary, bundle: Dictionary) -> void:
	for k in ["alloy", "circuitry", "data"]:
		c["salvage"][k] = int(c["salvage"].get(k, 0)) + int(bundle.get(k, 0))


## v64AwardCompletion: once per directory; theme bonus for archive/system/recycle.
static func award_completion(c: Dictionary, d: Dictionary) -> Dictionary:
	if d.get("v64Rewarded", false):
		return {}
	var base: Dictionary = data()["rewards"].get(d.get("type", "normal"), data()["rewards"]["normal"]).duplicate()
	var bonus := {}
	match d.get("theme", ""):
		"archive": bonus = {"data": 1}
		"system": bonus = {"circuitry": 1}
		"recycle": bonus = {"alloy": 1}
	for k in ["alloy", "circuitry", "data"]:
		base[k] = int(base.get(k, 0)) + int(bonus.get(k, 0))
	c["credits"] = int(c["credits"]) + int(base.get("credits", 0))
	add_salvage(c, base)
	d["v64Rewarded"] = true
	return base


## endWave(win): mark the directory cleared once and award completion salvage.
static func complete_directory(c: Dictionary, dir_id: int) -> Dictionary:
	for d in c["dirs"]:
		if int(d["id"]) == dir_id:
			var reward := award_completion(c, d)
			if not d.get("cleared", false):
				d["cleared"] = true
				c["wavesCleared"] = int(c["wavesCleared"]) + 1
			return reward
	return {}


static func directory(c: Dictionary, dir_id: int) -> Dictionary:
	for d in c["dirs"]:
		if int(d["id"]) == dir_id:
			return d
	return {}


static func is_locked(c: Dictionary, d: Dictionary) -> bool:
	return d.get("type") == "boss" and int(c.get("noble", 0)) < 4


## v6EffectiveShip: ship with upgrade (+0.8/level) and component stat bonuses applied.
static func effective_ship(c: Dictionary) -> Dictionary:
	var ship: Dictionary = c["ship"].duplicate(true)
	ship["stats"] = ShipPerformance.effective_stats(ship["stats"], c.get("upgrades", {}), c.get("components", {}))
	return ship
