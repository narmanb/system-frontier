class_name FactionPalette
extends RefCounted
## Native port of the legacy NPC faction recolor chain:
##   1. v6.9 `v69FactionRecolor` luminance ramp (only archetypes with recolor:true), applied at spawn
##   2. v7.2.4 `v724MaterialPixel` faction material palette, applied to that result
## Enforcers and bosses are not recolored (v724ApplyFactionPalette skips them).
## `recolor_grid(..., v69=true)` reproduces the legacy chain exactly and is verified per-pixel
## against tests/fixtures/recolor.json.
##
## INTENTIONAL CHANGE (docs/DECISIONS.md D-007): at runtime the v7.2.4 material palette is
## applied to the original art without the v6.9 pre-pass. In the legacy chain, blue-ish v6.9
## ramps (Knights, Renegades) trip v7.2.4's cockpit mask so whole hulls turn cockpit-blue,
## defeating v7.2.4's goal of distinct faction identities.
const USE_LEGACY_V69_PREPASS := false

const V69_RAMPS := {
	"Avengers": ["#4b1219", "#8e2636", "#d94a56", "#ffd2d6"],
	"Pirates": ["#5c2713", "#a64a1a", "#e77a2b", "#ffd8a6"],
	"Predators": ["#253a14", "#4c7a1f", "#7dd84c", "#dfffcf"],
	"Renegades": ["#21424d", "#2f6d87", "#4fb9df", "#d6f7ff"],
	"Fuzzy": ["#5e4f19", "#9e8a2e", "#e5cf66", "#fff6bf"],
	"Knights": ["#2c3850", "#536a8d", "#8fb3e4", "#edf5ff"],
	"Speed": ["#154d3f", "#21856c", "#42d6ad", "#cffff1"],
	"Default": ["#303948", "#5d6f88", "#9db4d6", "#eff6ff"],
}
const NEUTRAL := {"dark": "#101720", "mid": "#2b3745", "light": "#718195"}
const COCKPIT := {"dark": "#063b68", "mid": "#087fbe", "light": "#32c8f0", "high": "#b9f5ff"}
const ENGINE := {"dark": "#743012", "mid": "#d36824", "light": "#ffae43", "high": "#fff0a0"}

static var _texture_cache: Dictionary = {}


static func _rgb(hex: String) -> Vector3i:
	var c := Color.html(hex)
	return Vector3i(c.r8, c.g8, c.b8)


static func _hex(v: Vector3) -> String:
	var r := int(clamp(floor(v.x + 0.5), 0, 255))
	var g := int(clamp(floor(v.y + 0.5), 0, 255))
	var b := int(clamp(floor(v.z + 0.5), 0, 255))
	return "#%02x%02x%02x" % [r, g, b]


static func _lum(c: Vector3i) -> float:
	return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z


static func _sat(c: Vector3i) -> float:
	var mx := maxi(c.x, maxi(c.y, c.z))
	var mn := mini(c.x, mini(c.y, c.z))
	return float(mx - mn) / mx if mx > 0 else 0.0


static func _mix(a: String, b: String, t: float) -> String:
	var ca := Vector3(_rgb(a))
	var cb := Vector3(_rgb(b))
	return _hex(ca + (cb - ca) * t)


## v69FactionRecolor for a single pixel (hex string or "" for transparent).
static func v69_pixel(px: String, team: String) -> String:
	if px == "":
		return ""
	var ramp: Array = V69_RAMPS.get(team, V69_RAMPS["Default"])
	var lum := _lum(_rgb(px))
	if lum < 24: return px
	if lum < 64: return _mix(ramp[0], ramp[1], 0.25)
	if lum < 108: return _mix(ramp[0], ramp[1], 0.7)
	if lum < 170: return _mix(ramp[1], ramp[2], 0.45)
	if lum < 225: return _mix(ramp[2], ramp[3], 0.3)
	return ramp[3]


static func _ramp(r: Dictionary, lum: float) -> String:
	if lum < 64: return r["dark"]
	if lum < 120: return r["mid"]
	if lum < 188: return r["light"]
	return r["high"]


static func _is_blue(c: Vector3i) -> bool:
	return c.z > c.x * 1.18 and c.z > c.y * 0.94 and _sat(c) > 0.22


static func _is_warm(c: Vector3i) -> bool:
	return c.x > c.z * 1.28 and c.x > c.y * 0.90 and _sat(c) > 0.30


static func _cockpit_mask(arch: String, x: int, y: int, c: Vector3i, lum: float) -> bool:
	if y < 35 and _is_blue(c): return true
	match arch:
		"grunt": return x >= 20 and x <= 27 and y >= 10 and y <= 28 and lum < 92
		"skirmisher": return x >= 20 and x <= 28 and y >= 7 and y <= 23 and (lum < 145 or _sat(c) > 0.28)
		"beam": return x >= 21 and x <= 28 and y >= 12 and y <= 27 and _sat(c) > 0.22
		"hunter": return x >= 20 and x <= 28 and y >= 15 and y <= 32 and _sat(c) > 0.22
		"raider": return x >= 20 and x <= 28 and ((y >= 5 and y <= 18) or (y >= 23 and y <= 34)) and _sat(c) > 0.30
	return false


## v724MaterialPixel for a 48-wide grid.
static func v724_pixel(px: String, index: int, team: String, arch: String) -> String:
	if px == "":
		return ""
	var c := _rgb(px)
	var x := index % 48
	var y := index / 48
	var lum := _lum(c)
	var sat := _sat(c)
	var factions := DataStore.factions()
	var style: Dictionary = factions[team]["style"] if factions.has(team) and factions[team]["style"] != null \
		else DataStore.load_json("res://data/factions.json")["defaultStyle"]
	if lum < 24: return px.to_lower()
	if _cockpit_mask(arch, x, y, c, lum): return _ramp(COCKPIT, lum + 24)
	var rear_glow := y >= 33 and sat > 0.25 and (_is_warm(c) or _is_blue(c) or lum > 195)
	if rear_glow: return _ramp(ENGINE, lum + 20)
	if lum < 58: return NEUTRAL["dark"]
	if sat < 0.16 and lum < 145 and ((x * 5 + y * 3) % 9 < 3):
		return NEUTRAL["mid"] if lum < 96 else NEUTRAL["light"]
	if sat > 0.38 and _is_warm(c):
		return style["trim"] if lum < 130 else style["high"]
	if sat > 0.38 and not _is_blue(c) and ((x + y) % 4 == 0):
		return style["trim"]
	return _ramp(style, lum)


static func image_to_grid(img: Image) -> PackedStringArray:
	var out := PackedStringArray()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			out.append("" if c.a8 < 24 else "#%02x%02x%02x" % [c.r8, c.g8, c.b8])
	return out


static func grid_to_image(grid: PackedStringArray, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for i in grid.size():
		if grid[i] != "":
			img.set_pixel(i % size, i / size, Color.html(grid[i]))
	return img


## Full effective recolor of an archetype's grid for a team.
static func recolor_grid(grid: PackedStringArray, team: String, arch: String, v69_recolor: bool) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(grid.size())
	for i in grid.size():
		var px := v69_pixel(grid[i], team) if v69_recolor else grid[i]
		out[i] = v724_pixel(px, i, team, arch)
	return out


## Cached faction texture for an NPC archetype.
static func npc_texture(arch: String, team: String) -> Texture2D:
	var key := "%s:%s" % [arch, team]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var def: Dictionary = DataStore.npc_archetypes()["archetypes"][arch]
	var base: Texture2D = load(def["art"])
	var tex: Texture2D = base
	if team != "Enforcers" and DataStore.factions().has(team):
		var img := base.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var grid := recolor_grid(image_to_grid(img), team, arch, USE_LEGACY_V69_PREPASS and bool(def.get("recolor", false)))
		tex = ImageTexture.create_from_image(grid_to_image(grid, img.get_width()))
	_texture_cache[key] = tex
	return tex


## v724PoliceGrid: Enforcer cockpit glass flashes red/blue instead of a floating siren.
const POLICE_GLASS := ["#0e87d8", "#8ff7ff", "#4fc3ff", "#00f6ff", "#d9eefc"]

static func police_texture(red: bool) -> Texture2D:
	var key := "police:%s" % ("red" if red else "blue")
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img: Image = (load("res://assets/ships/npc_police.png") as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	var grid := image_to_grid(img)
	for i in grid.size():
		var px := grid[i]
		if px == "" or not POLICE_GLASS.has(px):
			continue
		var lum := _lum(_rgb(px))
		if red:
			grid[i] = "#9d1725" if lum < 115 else ("#ff394d" if lum < 190 else "#ffd1d6")
		else:
			grid[i] = "#0875c1" if lum < 115 else ("#29b9ff" if lum < 190 else "#c9f5ff")
	var tex := ImageTexture.create_from_image(grid_to_image(grid, img.get_width()))
	_texture_cache[key] = tex
	return tex
