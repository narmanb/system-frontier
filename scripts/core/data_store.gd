class_name DataStore
extends RefCounted
## Static, lazily-loaded access to the data-driven definitions in res://data.
## Usable from autoload-free contexts (headless tests) as well as gameplay.

static var _cache: Dictionary = {}


static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataStore: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("DataStore: invalid JSON in %s" % path)
	_cache[path] = parsed
	return parsed


static func engineering() -> Dictionary:
	return load_json("res://data/engineering.json")


static func modules() -> Dictionary:
	return engineering()["modules"]


static func stat_order() -> Array:
	return engineering()["statOrder"]


static func starter_hulls() -> Dictionary:
	return load_json("res://data/starter_hulls.json")


static func starter_hull(id: String) -> Dictionary:
	var h: Dictionary = starter_hulls()["hulls"].get(id, {})
	var copy := h.duplicate(true)
	copy["id"] = id
	return copy


static func npc_archetypes() -> Dictionary:
	return load_json("res://data/npc_archetypes.json")


static func factions() -> Dictionary:
	return load_json("res://data/factions.json")["factions"]


static func faction_color(team: String, fallback := Color.WHITE) -> Color:
	var f: Dictionary = factions().get(team, {})
	return Color.html(f["color"]) if f.has("color") else fallback
