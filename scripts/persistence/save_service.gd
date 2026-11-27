class_name SaveService
extends RefCounted
## Versioned, atomic JSON persistence in user:// (replaces legacy localStorage keys
## `innerCore95Save`, `innerCore95Ships`, `innerCore95FactoryDraftV6`).
##
## File format: {"game":"System Frontier","schema":N,"kind":k,"savedAt":unix,"data":...}
## Writes go to <file>.tmp, the previous file is kept as <file>.bak, then the tmp file is
## renamed into place. Reads fall back to .bak if the main file is missing or corrupt.
## Campaign and factory data are separate files so they can be reset independently.

const SCHEMA := 1
const CAMPAIGN := "user://campaign.json"
const SHIPS := "user://ships.json"
const DRAFT := "user://factory_draft.json"
const RECENT_COLORS := "user://recent_colors.json"
const RECORDS := "user://records.json"

static var root := "user://"   ## overridable by tests


static func _p(path: String) -> String:
	return path.replace("user://", root) if root != "user://" else path


static func write_json(path: String, kind: String, payload: Variant) -> bool:
	var full := _p(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var wrapped := {"game": "System Frontier", "schema": SCHEMA, "kind": kind, "savedAt": Time.get_unix_time_from_system(), "data": payload}
	var tmp := full + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveService: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(wrapped))
	f.close()
	if FileAccess.file_exists(full):
		DirAccess.copy_absolute(full, full + ".bak")
	return DirAccess.rename_absolute(tmp, full) == OK


static func _read_file(full: String) -> Variant:
	if not FileAccess.file_exists(full):
		return null
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.has("schema") and parsed.has("data"):
		return parsed["data"]
	return parsed  # tolerate unwrapped (legacy-style) JSON


static func read_json(path: String) -> Variant:
	var full := _p(path)
	var v: Variant = _read_file(full)
	if v == null:
		v = _read_file(full + ".bak")
	return v


static func delete(path: String) -> void:
	var full := _p(path)
	for f in [full, full + ".bak", full + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# ---------------------------------------------------------------- campaign

static func has_campaign() -> bool:
	return load_campaign() != null


static func load_campaign() -> Variant:
	var c: Variant = read_json(CAMPAIGN)
	if not (c is Dictionary) or not (c.get("dirs") is Array):
		return null
	return Campaign.ensure_defaults(c)


static func save_campaign(c: Dictionary) -> bool:
	Campaign.ensure_defaults(c)
	return write_json(CAMPAIGN, "campaign", c)


# ---------------------------------------------------------------- factory

static func custom_ships() -> Array:
	var a: Variant = read_json(SHIPS)
	var out := []
	if a is Array:
		for s in a:
			if s is Dictionary:
				out.append(Campaign.normalize_ship(s))
	return out


static func save_custom_ships(ships: Array) -> bool:
	var out := []
	for s in ships:
		out.append(Campaign.normalize_ship(s))
	return write_json(SHIPS, "ships", out)


# ---------------------------------------------------------------- records (experimental)

static func records() -> Dictionary:
	var r: Variant = read_json(RECORDS)
	var out := {"best_score": 0, "best_wave": 0, "runs": 0}
	if r is Dictionary:
		for k in out:
			out[k] = int(r.get(k, 0))
	return out


## Records a Recycle Bin run; returns the updated records plus "new_best".
static func record_endless(score: int, wave_reached: int) -> Dictionary:
	var r := records()
	var new_best := score > int(r["best_score"])
	r["best_score"] = maxi(int(r["best_score"]), score)
	r["best_wave"] = maxi(int(r["best_wave"]), wave_reached)
	r["runs"] = int(r["runs"]) + 1
	write_json(RECORDS, "records", r)
	r["new_best"] = new_best
	return r


## kind: "campaign" | "factory" | "all" (legacy v68DoReset).
static func reset(kind: String) -> void:
	if kind == "campaign" or kind == "all":
		delete(CAMPAIGN)
	if kind == "factory" or kind == "all":
		delete(SHIPS)
		delete(DRAFT)
		delete(RECENT_COLORS)
	if kind == "all":
		delete(RECORDS)


## Import JSON exported from the legacy browser build (a campaign object from
## `innerCore95Save`, or the ship array from `innerCore95Ships`). Returns the kind imported,
## or "" if unrecognised. Existing data is backed up by the normal write path.
static func import_legacy(text: String) -> String:
	var v: Variant = JSON.parse_string(text.strip_edges())
	if v is Dictionary and v.has("schema") and v.has("data"):
		v = v["data"]
	if v is Dictionary and v.get("dirs") is Array:
		save_campaign(Campaign.ensure_defaults(v))
		return "campaign"
	if v is Array and not v.is_empty() and v[0] is Dictionary and (v[0].has("grid") or v[0].has("stats")):
		var merged := custom_ships()
		for s in v:
			var ship: Dictionary = s
			ship["custom"] = true
			if not ship.has("id"):
				ship["id"] = "custom_%d" % Time.get_ticks_usec()
			merged.append(ship)
		save_custom_ships(merged)
		return "ships"
	return ""
