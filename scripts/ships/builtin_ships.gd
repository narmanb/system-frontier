class_name BuiltinShips
extends RefCounted
## Port of legacy `buildBuiltinShipGrid(kind)`: procedural 24×24 grids for the seven faction
## ships (dart/Red Falcon's old grid, skull, mantis, wedge, fuzz, lance, needle), kept as a
## procedure rather than baked PNGs. Output uses palette indices like the legacy grid; see
## `hex_grid`. Verified against tests/fixtures/builtin_grids.json.

const SCHEMES := {
	"dart": {"main": 0, "accent": 1, "cockpit": 8, "engine": 3, "trim": 7},
	"skull": {"main": 2, "accent": 1, "cockpit": 8, "engine": 6, "trim": 7},
	"mantis": {"main": 5, "accent": 1, "cockpit": 8, "engine": 4, "trim": 7},
	"wedge": {"main": 6, "accent": 1, "cockpit": 8, "engine": 3, "trim": 7},
	"fuzz": {"main": 3, "accent": 1, "cockpit": 8, "engine": 6, "trim": 7},
	"lance": {"main": 7, "accent": 1, "cockpit": 8, "engine": 0, "trim": 1},
	"needle": {"main": 4, "accent": 1, "cockpit": 8, "engine": 3, "trim": 7},
}
const ROWS := {
	"dart": [[2,0,0],[3,0,0],[4,0,1],[5,0,1],[6,0,2],[7,0,3],[8,1,4],[9,1,5],[10,1,5],[11,0,4],[12,0,4],[13,0,5],[14,1,5],[15,1,4],[16,1,3],[17,1,2],[18,2,2],[19,2,1]],
	"skull": [[3,0,1],[4,1,2],[5,1,3],[6,2,4],[7,2,5],[8,2,5],[9,1,5],[10,0,4],[11,0,4],[12,0,4],[13,1,5],[14,1,5],[15,2,4],[16,2,4],[17,2,3],[18,1,2],[19,0,1]],
	"mantis": [[2,0,0],[3,0,1],[4,0,1],[5,1,3],[6,2,5],[7,3,5],[8,2,4],[9,1,3],[10,1,5],[11,0,4],[12,0,4],[13,0,5],[14,1,6],[15,2,5],[16,2,5],[17,1,4],[18,1,3],[19,0,2]],
	"wedge": [[3,0,0],[4,0,1],[5,1,2],[6,2,3],[7,2,4],[8,3,5],[9,4,6],[10,3,5],[11,2,4],[12,1,4],[13,0,4],[14,0,4],[15,0,5],[16,1,5],[17,2,4],[18,2,4],[19,1,2]],
	"fuzz": [[4,0,1],[5,1,3],[6,2,4],[7,3,5],[8,3,5],[9,2,6],[10,2,6],[11,1,6],[12,1,6],[13,1,5],[14,2,5],[15,2,5],[16,2,4],[17,1,3],[18,1,3],[19,0,2]],
	"lance": [[1,0,0],[2,0,0],[3,0,1],[4,0,1],[5,1,2],[6,1,2],[7,2,3],[8,2,4],[9,1,4],[10,1,3],[11,0,3],[12,0,2],[13,0,2],[14,1,3],[15,1,4],[16,2,4],[17,2,3],[18,1,2],[19,1,2],[20,0,1]],
	"needle": [[1,0,0],[2,0,0],[3,0,0],[4,0,1],[5,0,1],[6,1,2],[7,1,2],[8,1,3],[9,1,3],[10,0,2],[11,0,2],[12,0,2],[13,0,2],[14,0,3],[15,1,3],[16,1,3],[17,1,2],[18,1,2],[19,0,1],[20,0,1],[21,0,0]],
}
## [kind, rect(a,b,y1,y2) or single(off,y), color key]
const DETAILS := {
	"dart": [["r",0,0,4,6,"accent"],["r",2,3,8,10,"accent"],["r",2,2,15,17,"trim"],["r",0,0,9,12,"cockpit"],["r",0,1,20,21,"engine"]],
	"skull": [["r",2,4,7,9,"accent"],["r",0,1,10,12,"cockpit"],["s",4,14,"trim"],["s",4,15,"trim"],["r",1,2,18,20,"engine"]],
	"mantis": [["r",3,5,6,7,"accent"],["r",0,1,9,12,"cockpit"],["r",3,4,14,16,"trim"],["r",1,2,20,21,"engine"]],
	"wedge": [["r",3,5,8,10,"accent"],["r",0,1,11,13,"cockpit"],["r",3,4,15,17,"trim"],["r",0,2,20,21,"engine"]],
	"fuzz": [["s",6,8,"trim"],["s",6,10,"trim"],["s",5,12,"trim"],["r",2,4,7,9,"accent"],["r",0,1,10,12,"cockpit"],["r",1,3,20,21,"engine"]],
	"lance": [["r",2,3,7,9,"accent"],["r",0,1,10,12,"cockpit"],["r",2,4,15,17,"trim"],["r",0,2,21,22,"engine"]],
	"needle": [["r",0,0,4,6,"accent"],["r",0,1,9,12,"cockpit"],["r",1,2,14,18,"trim"],["r",0,1,22,23,"engine"]],
}

static var _tex_cache := {}


static func _gset(g: Array, x: int, y: int, c) -> void:
	if x >= 0 and x < 24 and y >= 0 and y < 24:
		g[y * 24 + x] = c


static func _sym(g: Array, off: int, y: int, c) -> void:
	_gset(g, 11 - off, y, c)
	_gset(g, 12 + off, y, c)


static func grid(kind: String) -> Array:
	var g := []
	g.resize(576)
	g.fill(null)
	var s: Dictionary = SCHEMES.get(kind, SCHEMES["dart"])
	if ROWS.has(kind):
		for r in ROWS[kind]:
			for off in range(r[1], r[2] + 1):
				_sym(g, off, r[0], s["main"])
		for d in DETAILS[kind]:
			if d[0] == "r":
				for y in range(d[3], d[4] + 1):
					for off in range(d[1], d[2] + 1):
						_sym(g, off, y, s[d[5]])
			else:
				_sym(g, d[1], d[2], s[d[3]])
	for y in range(0, 2):          # gAbsRect(g,10,0,13,1,accent)
		for x in range(10, 14):
			_gset(g, x, y, s["accent"])
	# outlineShipGrid(g, 8)
	var copy := g.duplicate()
	for y in 24:
		for x in 24:
			if copy[y * 24 + x] != null:
				continue
			var hit := false
			for yy in range(-1, 2):
				for xx in range(-1, 2):
					if (xx != 0 or yy != 0) and not hit:
						var nx := x + xx
						var ny := y + yy
						if nx >= 0 and nx < 24 and ny >= 0 and ny < 24 and copy[ny * 24 + nx] != null:
							hit = true
			if hit:
				g[y * 24 + x] = 8
	return g


## Convert a grid of palette indices / hex strings / null to hex strings ("" = transparent).
static func hex_grid(g: Array) -> PackedStringArray:
	var pal: Array = Campaign.data()["palette"]
	var out := PackedStringArray()
	for v in g:
		if v == null:
			out.append("")
		elif v is String:
			out.append(v.to_lower())
		else:
			var i := int(v)
			out.append(str(pal[i]).to_lower() if i >= 0 and i < pal.size() else "#ffffff")
	return out


static func texture(kind: String) -> Texture2D:
	if not _tex_cache.has(kind):
		_tex_cache[kind] = ImageTexture.create_from_image(FactionPalette.grid_to_image(hex_grid(grid(kind)), 24))
	return _tex_cache[kind]
