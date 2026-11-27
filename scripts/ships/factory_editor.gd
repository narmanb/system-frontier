class_name FactoryEditor
extends RefCounted
## Ship Factory editor model, independent of UI. Port of the effective legacy editor:
##   v6 stats/modules/mount budgets, v6.1 24/32/48 canvases + nearest-neighbour resize,
##   v6.2 Auto-Clean passes + mount realignment, v6.5 factory stat cap (8), starter hulls,
##   v6.6/v6.7 48-colour palette with salvage unlocks, recent colours, replace/swap,
##   presets, v6.4 stencils, undo/redo (40 snapshots), draft data.
## Grid cells hold a palette index (int), a "#rrggbb" string (imported art) or null.

signal changed

const STAT_BUDGET := 50
const MOUNT_BUDGET := 4
const STAT_CAP := 8
const HISTORY := 40
const SIZES := [24, 32, 48]

var grid_size := 48
var grid: Array = []
var stats: Dictionary = {}
var modules: Dictionary = {}
var thrusters: Array = []
var hardpoints: Array = []
var rotation := 0
var name := "Custom 48"
var selected_id := ""            ## id of the saved ship being edited ("" = new)
var color = 0                    ## palette index (int) or hex string
var tool := "paint"              ## paint | erase | fill | pick | thruster | hardpoint
var mirror := true
var selected_thruster := "center"
var selected_hardpoint := "primary"
var preset_index := 0
var history: Array = []
var future: Array = []
var recent: Array = []           ## recent palette indices (max 6)
var unlocked: Dictionary = {}    ## blueprint key -> bool (campaign salvage unlocks)


func _init() -> void:
	new_blank(48, false)


# ------------------------------------------------------------------ palette

static func base_palette() -> Array:
	return Campaign.data()["palette"]


## Full 48-entry palette: 32 base colours + unlock-group colours in legacy order.
static func full_palette() -> Array:
	var out: Array = base_palette().duplicate()
	for key in Campaign.data()["paletteUnlocks"]:
		for c in Campaign.data()["paletteUnlocks"][key]["colors"]:
			if not out.has(c):
				out.append(c)
	return out


func visible_palette_indices() -> Array:
	var out := []
	for i in base_palette().size():
		out.append(i)
	var offset := base_palette().size()
	for key in Campaign.data()["paletteUnlocks"]:
		var n: int = Campaign.data()["paletteUnlocks"][key]["colors"].size()
		if unlocked.get(key, false):
			for i in n:
				out.append(offset + i)
		offset += n
	return out


static func cell_hex(v) -> String:
	if v == null:
		return ""
	if v is String:
		return v.to_lower()
	var pal := full_palette()
	var i := int(v)
	return str(pal[i]).to_lower() if i >= 0 and i < pal.size() else "#ffffff"


func select_color(c, record := true) -> void:
	color = c
	if record and (c is int or c is float):
		var idx := int(c)
		recent.erase(idx)
		recent.push_front(idx)
		recent = recent.slice(0, 6)
	changed.emit()


# ------------------------------------------------------------------ snapshots

func snapshot() -> Dictionary:
	return {"grid": grid.duplicate(), "gridSize": grid_size, "stats": stats.duplicate(), "modules": modules.duplicate(),
		"thrusters": thrusters.duplicate(true), "hardpoints": hardpoints.duplicate(true), "rotation": rotation,
		"name": name, "selectedId": selected_id}


func restore(s: Dictionary) -> void:
	grid_size = int(s.get("gridSize", 48))
	grid = []
	for v in s.get("grid", []):
		grid.append(_norm_cell(v))
	grid.resize(grid_size * grid_size)
	stats = _capped(ShipPerformance.normalize_stats(s.get("stats", {})))
	modules = ShipPerformance.normalize_modules(s.get("modules"))
	thrusters = ShipPerformance.normalize_thrusters(s.get("thrusters"), grid_size)
	hardpoints = ShipPerformance.normalize_hardpoints(s.get("hardpoints"), grid_size)
	rotation = int(s.get("rotation", 0))
	name = str(s.get("name", "Custom Mark I"))
	selected_id = str(s.get("selectedId", s.get("selected_id", "")))
	changed.emit()


static func _norm_cell(v):
	if v == null:
		return null
	if v is float:
		return int(v)
	if v is String and v == "":
		return null
	return v


func push_history() -> void:
	var s := snapshot()
	if history.is_empty() or JSON.stringify(history[-1]) != JSON.stringify(s):
		history.append(s)
		if history.size() > HISTORY:
			history.pop_front()
	future.clear()


func undo() -> void:
	if history.is_empty():
		return
	future.append(snapshot())
	restore(history.pop_back())


func redo() -> void:
	if future.is_empty():
		return
	history.append(snapshot())
	restore(future.pop_back())


# ------------------------------------------------------------------ hulls

func new_blank(size := 48, record := true) -> void:
	if record:
		push_history()
	size = size if SIZES.has(size) else 48
	grid_size = size
	grid = []
	grid.resize(size * size)
	var arch: Dictionary = DataStore.engineering()["archetypes"]["balanced"]
	stats = _capped(ShipPerformance.normalize_stats(arch["stats"]))
	modules = ShipPerformance.normalize_modules(arch["modules"])
	thrusters = ShipPerformance.default_thrusters(size)
	hardpoints = ShipPerformance.default_hardpoints(size)
	selected_thruster = "center"
	selected_hardpoint = "primary"
	selected_id = ""
	rotation = 0
	name = "Custom %d" % size
	changed.emit()


func is_empty() -> bool:
	for v in grid:
		if v != null:
			return false
	return true


func clear() -> void:
	push_history()
	grid = []
	grid.resize(grid_size * grid_size)
	changed.emit()


static func resize_nearest(src: Array, old_size: int, new_size: int) -> Array:
	var out := []
	out.resize(new_size * new_size)
	for y in new_size:
		for x in new_size:
			var ox := clampi(int(floor((x + 0.5) * old_size / new_size)), 0, old_size - 1)
			var oy := clampi(int(floor((y + 0.5) * old_size / new_size)), 0, old_size - 1)
			out[y * new_size + x] = src[oy * old_size + ox]
	return out


static func scale_point(v: float, old_size: int, new_size: int) -> int:
	return clampi(int(Campaign.js_round(((v + 0.5) * new_size / old_size) - 0.5)), 0, new_size - 1)


## v61ApplyCanvasResize: nearest-neighbour artwork + scaled mount coordinates.
func resize_canvas(new_size: int) -> bool:
	if not SIZES.has(new_size) or new_size == grid_size:
		return false
	push_history()
	var old := grid_size
	grid = resize_nearest(grid, old, new_size)
	for m in thrusters + hardpoints:
		m["x"] = scale_point(m["x"], old, new_size)
		m["y"] = scale_point(m["y"], old, new_size)
	grid_size = new_size
	changed.emit()
	return true


## preset(n): the five procedural 24×24 presets (cycled), resized to `target` like v6.1.
func apply_preset(target := 0) -> void:
	push_history()
	preset_index += 1
	var c := preset_index % 5
	var g := []
	g.resize(576)
	var px := func(x: int, y: int, v: int) -> void:
		if x >= 0 and x < 24 and y >= 0 and y < 24:
			g[y * 24 + x] = v
	match c:
		0:
			for y in range(4, 21):
				var w := maxi(1, (y - 2) / 3)
				for x in range(12 - w, 12 + w + 1):
					px.call(x, y, 1 if y % 4 == 0 else 0)
			for y in range(12, 20):
				for x in [5, 6, 18, 19]:
					px.call(x, y, 0)
		1:
			for y in range(6, 19):
				for x in range(5, 19):
					if pow(x - 12, 2) / 52.0 + pow(y - 12, 2) / 45.0 < 1:
						px.call(x, y, 2 if x < 12 else 0)
			for x in range(8, 16):
				px.call(x, 4, 1)
		2:
			for y in range(3, 22):
				px.call(11, y, 4)
				px.call(12, y, 4)
				if y > 8:
					px.call(10, y, 0)
					px.call(13, y, 0)
				if y > 14:
					px.call(7, y, 4)
					px.call(16, y, 4)
		3:
			for y in range(5, 20):
				for x in range(4, 20):
					if absi(x - 12) + absi(y - 12) < 10:
						px.call(x, y, 3 if (x + y) % 5 == 0 else 6)
		4:
			for y in range(6, 19):
				for x in range(3, 21):
					if y > absf(x - 12) / 2.0 + 5 and y < 20 - absf(x - 12) / 3.0:
						px.call(x, y, 1 if x == 11 or x == 12 else 5)
	grid_size = 24
	grid = g
	thrusters = ShipPerformance.default_thrusters(24)
	var t := target if SIZES.has(target) else 24
	if t != 24:
		grid = resize_nearest(grid, 24, t)
		for m in thrusters:
			m["x"] = scale_point(m["x"], 24, t)
			m["y"] = scale_point(m["y"], 24, t)
		grid_size = t
	hardpoints = ShipPerformance.default_hardpoints(grid_size)
	selected_id = ""
	changed.emit()


## Load a starter hull template (v6.5 v65LoadStarterHull / v7.0 true Red Falcon).
func load_starter(id: String) -> void:
	push_history()
	var h := DataStore.starter_hull(id)
	var img: Image = (load(h["art"]) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	grid_size = img.get_width()
	grid = []
	for v in FactionPalette.image_to_grid(img):
		grid.append(null if v == "" else v)
	stats = _capped(ShipPerformance.normalize_stats(h["stats"]))
	modules = ShipPerformance.normalize_modules(h["modules"])
	thrusters = ShipPerformance.normalize_thrusters(h["thrusters"], grid_size)
	hardpoints = ShipPerformance.normalize_hardpoints(h["hardpoints"], grid_size)
	selected_thruster = "center"
	selected_hardpoint = "primary"
	rotation = 0
	selected_id = ""
	name = h["name"]
	changed.emit()


## v64ApplyStencil: Salvage Skiff / Archive Needle 32×32 hulls (stats/modules preserved).
func apply_stencil(kind: String) -> void:
	push_history()
	var n := 32
	var g := []
	g.resize(n * n)
	var sym := func(x: int, y: int, c: int) -> void:
		for xx in [15 - x, 16 + x]:
			if xx >= 0 and xx < n and y >= 0 and y < n:
				g[y * n + xx] = c
	if kind == "salvageSkiff":
		for y in range(5, 28):
			var w := (y - 3) / 2 if y < 11 else (6 if y < 22 else maxi(2, 9 - (y - 20) / 2))
			for x in range(0, w + 1):
				sym.call(x, y, 7 if y % 5 == 0 else 6)
		for y in range(13, 24):
			sym.call(8, y, 7)
			sym.call(9, y, 7)
		for y in range(8, 14):
			sym.call(1, y, 1)
		for y in range(25, 29):
			sym.call(0, y, 3)
			sym.call(5, y, 3)
		thrusters = ShipPerformance.normalize_thrusters([{"id": "center", "x": 16, "y": 28, "enabled": true, "cost": 0, "scale": 1.1}, {"id": "left", "x": 10, "y": 27, "enabled": true, "cost": 2, "scale": 0.74}, {"id": "right", "x": 21, "y": 27, "enabled": true, "cost": 2, "scale": 0.74}], n)
		name = "Salvage Skiff"
	else:
		for y in range(3, 29):
			var w := (y - 1) / 3 if y < 9 else (2 if y < 22 else maxi(0, 4 - (y - 22) / 2))
			for x in range(0, w + 1):
				sym.call(x, y, 1 if y % 6 == 0 else 5)
		for y in range(11, 23):
			sym.call(5, y, 5)
			if y > 16:
				sym.call(7, y, 7)
		for y in range(7, 13):
			sym.call(0, y, 0)
		for y in range(26, 30):
			sym.call(1, y, 3)
		thrusters = ShipPerformance.normalize_thrusters([{"id": "center", "x": 16, "y": 29, "enabled": true, "cost": 0, "scale": 1.1}, {"id": "left", "x": 11, "y": 27, "enabled": false, "cost": 2, "scale": 0.74}, {"id": "right", "x": 20, "y": 27, "enabled": false, "cost": 2, "scale": 0.74}], n)
		name = "Archive Needle"
	grid_size = n
	grid = g
	hardpoints = ShipPerformance.default_hardpoints(n)
	selected_id = ""
	changed.emit()


func load_ship(s: Dictionary) -> void:
	var ship := Campaign.normalize_ship(s)
	push_history()
	if ship.get("grid") is Array and not (ship["grid"] as Array).is_empty():
		restore({"grid": ship["grid"], "gridSize": ship["gridSize"], "stats": ship["stats"], "modules": ship["modules"],
			"thrusters": ship["thrusters"], "hardpoints": ship["hardpoints"], "rotation": ship.get("rotation", 0),
			"name": ship.get("name", "Custom Ship"), "selectedId": ship.get("id", "")})
	selected_thruster = "center"
	selected_hardpoint = "primary"


## shipDataFromEditor.
func ship_data() -> Dictionary:
	return {"id": selected_id if selected_id != "" else "custom_%d" % int(Time.get_unix_time_from_system() * 1000),
		"name": name.strip_edges() if name.strip_edges() != "" else "Unnamed Ship", "team": "Custom",
		"desc": "User-built Ship Factory hull using the ten-stat and module system.", "stats": stats.duplicate(),
		"modules": modules.duplicate(), "special": _special(), "grid": grid.duplicate(), "gridSize": grid_size,
		"thrusters": thrusters.duplicate(true), "hardpoints": hardpoints.duplicate(true), "custom": true, "rotation": rotation,
		"coastDrag": performance()["coastDrag"]}


func _special() -> String:
	if modules.get("defense") == "cloak": return "cloak"
	if modules.get("defense") in ["ram", "plating"]: return "ram"
	if modules.get("utility") == "tractor": return "tractor"
	return "shield"


# ------------------------------------------------------------------ painting

func paint(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= grid_size or y >= grid_size:
		return
	match tool:
		"thruster":
			var t := mount("thruster", selected_thruster)
			if t.is_empty() or (not t["enabled"] and t["id"] != "center"):
				return
			t["x"] = x
			t["y"] = y
		"hardpoint":
			var h := mount("hardpoint", selected_hardpoint)
			h["x"] = x
			h["y"] = y
		"fill":
			flood_fill(x, y, color)
		"pick":
			var v = grid[y * grid_size + x]
			if v != null:
				select_color(v)
				tool = "paint"
		_:
			var v = null if tool == "erase" else color
			grid[y * grid_size + x] = v
			if mirror:
				grid[y * grid_size + (grid_size - 1 - x)] = v
	changed.emit()


## Port addition: bucket fill (4-connected), honouring mirror.
func flood_fill(x: int, y: int, value) -> void:
	var n := grid_size
	var target = grid[y * n + x]
	if typeof(target) == typeof(value) and target == value:
		return
	var stack := [Vector2i(x, y)]
	var seen := {}
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= n or p.y >= n or seen.has(p):
			continue
		seen[p] = true
		var cur = grid[p.y * n + p.x]
		if not (typeof(cur) == typeof(target) and cur == target):
			continue
		grid[p.y * n + p.x] = value
		if mirror:
			grid[p.y * n + (n - 1 - p.x)] = value
		stack.append_array([Vector2i(p.x + 1, p.y), Vector2i(p.x - 1, p.y), Vector2i(p.x, p.y + 1), Vector2i(p.x, p.y - 1)])


func rotate() -> void:
	push_history()
	rotation = (rotation + 1) % 4
	changed.emit()


func distinct_colors() -> Array:
	var seen := {}
	var out := []
	for v in grid:
		if v == null:
			continue
		var hx := cell_hex(v)
		if not seen.has(hx):
			seen[hx] = true
			out.append(v)
	return out


func replace_color(from, to) -> int:
	if typeof(from) == typeof(to) and from == to:
		return 0
	push_history()
	var n := 0
	for i in grid.size():
		if grid[i] != null and typeof(grid[i]) == typeof(from) and grid[i] == from:
			grid[i] = to
			n += 1
	changed.emit()
	return n


func swap_colors(a, b) -> int:
	push_history()
	var n := 0
	for i in grid.size():
		var v = grid[i]
		if v == null:
			continue
		if typeof(v) == typeof(a) and v == a:
			grid[i] = b
			n += 1
		elif typeof(v) == typeof(b) and v == b:
			grid[i] = a
			n += 1
	changed.emit()
	return n


# ------------------------------------------------------------------ stats / modules / mounts

func _capped(s: Dictionary) -> Dictionary:
	for k in s:
		s[k] = clampi(int(s[k]), 1, STAT_CAP)
	return s


func stat_sum() -> int:
	var n := 0
	for k in stats:
		n += int(stats[k])
	return n


## Returns false (and does nothing) when the change would exceed the cap or the budget.
func change_stat(key: String, delta: int) -> bool:
	var old := int(stats[key])
	var nv := clampi(old + delta, 1, STAT_CAP)
	if nv == old or (delta > 0 and stat_sum() + delta > STAT_BUDGET):
		return false
	push_history()
	stats[key] = nv
	changed.emit()
	return true


func apply_archetype(id: String) -> void:
	var a: Dictionary = DataStore.engineering()["archetypes"].get(id, DataStore.engineering()["archetypes"]["balanced"])
	push_history()
	stats = _capped(ShipPerformance.normalize_stats(a["stats"]))
	modules = ShipPerformance.normalize_modules(a["modules"])
	changed.emit()


func set_module(slot: String, id: String) -> void:
	push_history()
	modules[slot] = id
	modules = ShipPerformance.normalize_modules(modules)
	changed.emit()


func mount(kind: String, id: String) -> Dictionary:
	for m in (thrusters if kind == "thruster" else hardpoints):
		if m["id"] == id:
			return m
	return {}


func mount_cost() -> int:
	var n := 0
	for t in thrusters:
		if t["enabled"]:
			n += int(t.get("cost", 0))
	return n


## Buy/remove an optional side engine (mount budget 4, 2 each). Centre is always on.
func toggle_thruster(id: String) -> bool:
	var t := mount("thruster", id)
	if t.is_empty() or id == "center":
		return false
	if not t["enabled"] and mount_cost() + int(t["cost"]) > MOUNT_BUDGET:
		return false
	push_history()
	t["enabled"] = not t["enabled"]
	changed.emit()
	return true


func performance() -> Dictionary:
	return ShipPerformance.compute({"stats": stats, "modules": modules, "thrusters": thrusters, "gridSize": grid_size})


## Save validation (legacy saveShipBtn). Returns "" when valid, else the error message.
func validate() -> String:
	if stat_sum() > STAT_BUDGET:
		return "This ship uses %d of %d stat points." % [stat_sum(), STAT_BUDGET]
	if mount_cost() > MOUNT_BUDGET:
		return "Optional engines exceed the mount budget."
	if is_empty():
		return "The hull cannot be completely empty."
	return ""


func warnings() -> Array:
	var p := performance()
	var w := []
	if stat_sum() < STAT_BUDGET:
		w.append("%d stat points remain unallocated." % (STAT_BUDGET - stat_sum()))
	if p.demand > p.capacity:
		var t := "Reactor overload %d: acceleration %d%%, turning %d%%, weapon cycle %d%%, powered modules %d%%" % [roundi(p.demand - p.capacity),
			roundi(p.accelPowerFactor * 100), roundi(p.turnPowerFactor * 100), roundi(p.weaponPowerFactor * 100), roundi(p.modulePowerFactor * 100)]
		if p.criticalOverload:
			t += ", top speed %d%%" % roundi(p.speedPowerFactor * 100)
		w.append(t + ".")
	if p.mass > 110:
		w.append("High mass is reducing acceleration and turning.")
	if mount_cost() > MOUNT_BUDGET:
		w.append("Thruster mount budget exceeded.")
	return w


# ------------------------------------------------------------------ Auto-Clean (v6.2)

static func _cell(g: Array, n: int, x: int, y: int):
	return g[y * n + x] if x >= 0 and x < n and y >= 0 and y < n else null


static func _neighbors(g: Array, n: int, x: int, y: int) -> Array:
	var out := []
	for yy in range(y - 1, y + 2):
		for xx in range(x - 1, x + 2):
			if (xx != x or yy != y) and xx >= 0 and xx < n and yy >= 0 and yy < n:
				out.append(g[yy * n + xx])
	return out


static func _key(v) -> String:
	return "" if v == null else ("i%d" % int(v) if (v is int or v is float) else "s" + str(v))


static func _dominant(values: Array) -> Array:
	var counts := {}
	var order := []
	var first := {}
	for v in values:
		if v == null:
			continue
		var k := _key(v)
		if not counts.has(k):
			counts[k] = 0
			order.append(k)
			first[k] = v
		counts[k] += 1
	var best = null
	var count := 0
	for k in order:  # Map iteration order = insertion order; ties keep the first seen
		if counts[k] > count:
			best = first[k]
			count = counts[k]
	return [best, count]


static func _same(a, b) -> bool:
	return _key(a) == _key(b)


static func conservative_pass(src: Array, n: int) -> Array:
	var out := src.duplicate()
	for y in n:
		for x in n:
			var i := y * n + x
			var c = src[i]
			var near := _neighbors(src, n, x, y)
			var non := near.filter(func(v): return v != null)
			var dom := _dominant(near)
			var l = _cell(src, n, x - 1, y)
			var r = _cell(src, n, x + 1, y)
			var u = _cell(src, n, x, y - 1)
			var d = _cell(src, n, x, y + 1)
			if c == null:
				if l != null and _same(l, r):
					out[i] = l
				elif u != null and _same(u, d):
					out[i] = u
				elif non.size() >= 7 and dom[1] >= 5:
					out[i] = dom[0]
			else:
				if non.is_empty():
					out[i] = null
				elif dom[0] != null and not _same(dom[0], c) and dom[1] >= 6:
					out[i] = dom[0]
	return out


static func symmetry_pass(src: Array, n: int, source := "merge") -> Array:
	var out := src.duplicate()
	var half := n / 2
	for y in n:
		for x in half:
			var li := y * n + x
			var ri := y * n + (n - 1 - x)
			var a = src[li]
			var b = src[ri]
			if source == "left":
				out[ri] = a
			elif source == "right":
				out[li] = b
			elif a == null and b != null:
				out[li] = b
			elif b == null and a != null:
				out[ri] = a
	return out


static func _rgb(v):
	if not (v is String) or not (v as String).begins_with("#") or (v as String).length() != 7:
		return null
	var c := Color.html(v)
	return Vector3(c.r8, c.g8, c.b8)


static func consolidate_colors(src: Array) -> Array:
	var counts := {}
	var order := []
	var vals := {}
	for c in src:
		if c == null:
			continue
		var k := _key(c)
		if not counts.has(k):
			counts[k] = 0
			order.append(k)
			vals[k] = c
		counts[k] += 1
	var common_keys := order.filter(func(k): return counts[k] >= 4)
	# stable sort by count desc (JS Array.sort is stable)
	var idx := {}
	for i in common_keys.size():
		idx[common_keys[i]] = i
	common_keys.sort_custom(func(a, b): return counts[a] > counts[b] or (counts[a] == counts[b] and idx[a] < idx[b]))
	var mapping := {}
	for k in order:
		if counts[k] >= 4 or _rgb(vals[k]) == null:
			continue
		var best = null
		var dist := 29.0
		for ck in common_keys:
			var cr = _rgb(vals[ck])
			if cr == null:
				continue
			var dd: float = (_rgb(vals[k]) as Vector3).distance_to(cr)
			if dd < dist:
				dist = dd
				best = vals[ck]
		if best != null:
			mapping[k] = best
	return src.map(func(c): return mapping.get(_key(c), c) if c != null else null)


func _protected(x: int, y: int) -> bool:
	for p in thrusters + hardpoints:
		if p.has("enabled") and p["id"] != "center" and not p["enabled"]:
			continue
		if absi(int(p["x"]) - x) <= 1 and absi(int(p["y"]) - y) <= 1:
			return true
	return false


func aggressive_pass(src: Array, n: int, sym_source: String) -> Array:
	var out := conservative_pass(conservative_pass(src, n), n)
	var nxt := out.duplicate()
	for y in n:
		for x in n:
			var i := y * n + x
			var c = out[i]
			var near := _neighbors(out, n, x, y)
			var non := near.filter(func(v): return v != null)
			var dom := _dominant(near)
			if c == null and non.size() >= 5 and dom[1] >= 4:
				nxt[i] = dom[0]
			elif c != null and non.size() <= 1 and not _protected(x, y):
				nxt[i] = null
	return symmetry_pass(consolidate_colors(nxt), n, sym_source)


## v62RepairGrid: returns {grid, changed}. mode: conservative | symmetry | aggressive.
func repair_preview(mode := "conservative", sym_source := "merge") -> Dictionary:
	var after: Array
	match mode:
		"symmetry": after = symmetry_pass(conservative_pass(grid, grid_size), grid_size, sym_source)
		"aggressive": after = aggressive_pass(grid, grid_size, sym_source)
		_: after = conservative_pass(grid, grid_size)
	var n := 0
	for i in after.size():
		if not _same(after[i], grid[i]):
			n += 1
	return {"grid": after, "changed": n}


## Apply a repair and realign mounts that ended up off-hull (v62RealignMounts).
func apply_repair(new_grid: Array) -> int:
	push_history()
	grid = new_grid.duplicate()
	var moved := 0
	for p in thrusters + hardpoints:
		if p["id"] != "center" and p.has("enabled") and not p["enabled"]:
			continue
		if _cell(grid, grid_size, p["x"], p["y"]) == null:
			var q = _nearest_solid(int(p["x"]), int(p["y"]))
			if q != null:
				p["x"] = q.x
				p["y"] = q.y
				moved += 1
	changed.emit()
	return moved


func _nearest_solid(x: int, y: int, max_r := 6):
	for r in range(1, max_r + 1):
		for yy in range(y - r, y + r + 1):
			for xx in range(x - r, x + r + 1):
				if maxi(absi(xx - x), absi(yy - y)) != r:
					continue
				if _cell(grid, grid_size, xx, yy) != null:
					return Vector2i(xx, yy)
	return null


func texture() -> Texture2D:
	var img := Image.create(grid_size, grid_size, false, Image.FORMAT_RGBA8)
	for i in grid.size():
		if grid[i] != null:
			img.set_pixel(i % grid_size, i / grid_size, Color.html(cell_hex(grid[i])))
	return ImageTexture.create_from_image(img)
