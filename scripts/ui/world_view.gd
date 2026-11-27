class_name WorldView
extends Node2D
## Draws a SimWorld around the player. Rendering only — never mutates gameplay state.
## Positioned at the viewport centre and scaled by the zoom factor; all draw coordinates
## are wrapped offsets from the player (legacy `screenPos`).

var world: SimWorld
var zoom := 1.0
var _stars: Array = []
var _constellations: Array = []
var _laser_white: Texture2D
var _font: Font
var _vis_rng := RandomNumberGenerator.new()

const CAT_POINTS := [Vector2(-52, 2), Vector2(-36, -32), Vector2(-18, -52), Vector2(0, -24), Vector2(18, -52), Vector2(36, -32), Vector2(52, 2), Vector2(-26, 18), Vector2(0, 28), Vector2(26, 18), Vector2(-44, 14), Vector2(-60, 22), Vector2(44, 14), Vector2(60, 22)]
const CAT_LINES := [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [0, 7], [7, 8], [8, 9], [9, 6], [10, 7], [12, 9], [10, 11], [12, 13]]
const STAR_COLORS := ["#ffffff", "#c7e5ff", "#fff2b4", "#9ab7d7", "#b8c7ff"]


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_vis_rng.randomize()
	# Legacy laser sprite is tinted by replacing RGB and keeping alpha: build a white mask once.
	var img: Image = (load("res://assets/effects/laser.png") as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, c.a))
	_laser_white = ImageTexture.create_from_image(img)
	for i in 640:
		_stars.append({
			"p": Vector2(_vis_rng.randf() * SimWorld.W, _vis_rng.randf() * SimWorld.H),
			"s": _vis_rng.randf_range(0.45, 2.4), "c": Color(STAR_COLORS[_vis_rng.randi() % STAR_COLORS.size()]),
			"tw": _vis_rng.randf() * TAU,
		})
	for i in 2:
		_constellations.append({
			"p": Vector2(_vis_rng.randf_range(0.15, 0.85) * SimWorld.W, _vis_rng.randf_range(0.12, 0.58) * SimWorld.H),
			"scale": _vis_rng.randf_range(0.9, 1.25), "phase": _vis_rng.randf() * TAU, "alpha": 0.26 if i == 0 else 0.16,
		})


func _process(_dt: float) -> void:
	var vp := get_viewport_rect().size
	position = vp / 2
	scale = Vector2(zoom, zoom)
	queue_redraw()


func rel(p: Vector2) -> Vector2:
	return SimWorld.wrapped_delta(world.player.pos, p)


func _half_view() -> Vector2:
	return get_viewport_rect().size / 2 / zoom + Vector2(140, 140)


func _visible(p: Vector2, half: Vector2) -> bool:
	return absf(p.x) < half.x and absf(p.y) < half.y


func _draw() -> void:
	if world == null or world.player == null:
		return
	var half := _half_view()
	var now := Time.get_ticks_msec() / 1000.0
	_draw_background(half, now)
	for f in world.fuel_cells:
		var p := rel(f.pos)
		if _visible(p, half):
			_draw_fuel(p, f)
	for o in world.icons:
		if o.carrier:
			continue
		var p := rel(o.pos)
		if _visible(p, half):
			_draw_icon(p, o, now)
	if world.gate_open:
		_draw_gate(rel(world.gate_pos), now)
	for s in world.ships:
		var p := rel(s.pos)
		if _visible(p, half):
			_draw_ship(p, s, now)
	_draw_ship(Vector2.ZERO, world.player, now)
	for bm in world.beams:
		_draw_beam(bm)
	for b in world.bullets:
		var p := rel(b.pos)
		if _visible(p, half):
			_draw_bullet(p, b)
	for q in world.particles:
		var p := rel(q.pos)
		var c := q.color
		c.a = clampf(q.life * 2, 0, 1)
		draw_rect(Rect2(p, Vector2(q.size, q.size)), c)


func _draw_background(half: Vector2, now: float) -> void:
	var t := now * 1.5
	for s in _stars:
		var p := rel(s.p)
		if not _visible(p, half):
			continue
		var tw := 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.7 + s.tw))
		var size := maxf(1.0, roundf(s.s))
		var c: Color = s.c
		c.a = 0.18 + 0.7 * tw
		draw_rect(Rect2(p.round(), Vector2(size, size)), c)
		if size > 1 and tw > 0.72:
			c.a = 0.10 + 0.18 * tw
			draw_rect(Rect2(p.round() + Vector2(-1, 0), Vector2(size + 2, 1)), c)
			draw_rect(Rect2(p.round() + Vector2(0, -1), Vector2(1, size + 2)), c)
	for cat in _constellations:
		var anchor := rel(cat.p)
		if not _visible(anchor, half):
			continue
		var pts := []
		for pt in CAT_POINTS:
			pts.append(anchor + pt * cat.scale)
		var line_c := Color(0.49, 0.725, 1.0, 0.75 * cat.alpha)
		for ln in CAT_LINES:
			draw_line(pts[ln[0]], pts[ln[1]], line_c, 1.2)
		var pulse := 0.75 + 0.25 * sin(t + cat.phase)
		for p in pts:
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color(0.86, 0.94, 1, cat.alpha * pulse + 0.08))


func _ship_texture(s: SimShip, now: float) -> Texture2D:
	if s.archetype == "police" and (s.flash_police or s.ai == "enforcer"):
		return FactionPalette.police_texture(int(now * 1000.0 / 190.0) % 2 == 1)
	return s.texture


func _draw_ship(p: Vector2, s: SimShip, now: float) -> void:
	var size := SimWorld.SHIP_DRAW_SIZE
	var rot := s.a + PI / 2 + int(s.hull_def.get("rotation", 0)) * PI / 2
	var alpha := 0.25 if s.cloak else 1.0
	draw_set_transform(p, rot, Vector2.ONE)
	if s.thrusting:
		_draw_thrusters(s, size)
	var tex := _ship_texture(s, now)
	if tex:
		draw_texture_rect(tex, Rect2(-size / 2, -size / 2, size, size), false, Color(1, 1, 1, alpha))
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -size * 0.5), Vector2(size * 0.38, size * 0.4), Vector2(0, size * 0.24), Vector2(-size * 0.38, size * 0.4)]), s.color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if s.cloak:
		draw_arc(p, size * 0.39, 0, TAU, 32, Color(0.7, 0.86, 1, 0.12), 1.5)
	if s.is_player:
		if s.invuln > 0 and int(now * 8) % 2 == 0:
			draw_arc(p, size * 0.42, 0, TAU, 32, Color(0.35, 1, 0.86, 0.35), 2)
		return
	if s.ai == "beam" and s.beam_state == "charging":
		var pct := clampf(1 - s.beam_charge / maxf(0.01, s.beam_charge_start), 0, 1)
		var r := 24 + pct * 24
		var c := s.color
		c.a = 0.35 + 0.5 * pct
		for i in 3:
			draw_arc(p, r + i * 7, -PI * 0.68 + pct * 0.5, PI * 0.68 + pct * 0.5, 24, c, 2.5)
		_text(p + Vector2(0, -size * 0.67), "CHARGING", 9, s.color)
	if s.hull < s.max_hull:
		draw_rect(Rect2(p + Vector2(-22, -size * 0.62), Vector2(44, 4)), Color("#350711"))
		draw_rect(Rect2(p + Vector2(-22, -size * 0.62), Vector2(44 * clampf(s.hull / s.max_hull, 0, 1), 4)), Color("#52ff79"))
	if s.team != world.player.team:
		var label := s.name if s.team in ["Target", "Enforcers"] else "%s · %s" % [s.name, s.team]
		_text(p + Vector2(0, size * 0.70), label, 10, Color("#e8f7ff"))
		draw_rect(Rect2(p + Vector2(-14, size * 0.72 + 3), Vector2(28, 2)), s.color)
	if s.cargo_icon:
		var y := p.y - 61
		draw_rect(Rect2(p.x - 13, y - 13, 26, 26), Color(0, 0, 0, 0.68))
		draw_rect(Rect2(p.x - 13, y - 13, 26, 26), Color("#ffe568"), false, 2)
		draw_colored_polygon(PackedVector2Array([Vector2(p.x, y - 9), Vector2(p.x + 9, y), Vector2(p.x, y + 9), Vector2(p.x - 9, y)]), Color("#ffe568"))


func _draw_thrusters(s: SimShip, size: float) -> void:
	var n := s.grid_size()
	for t in ShipPerformance.normalize_thrusters(s.hull_def.get("thrusters"), n):
		if not t["enabled"]:
			continue
		var lx: float = ((t["x"] + 0.5) / n - 0.5) * size
		var ly: float = ((t["y"] + 0.5) / n - 0.5) * size
		var sc: float = t.get("scale", 1.0)
		var length := size * (0.15 + (1.0 if s.is_player else 0.82) * 0.18) * sc * (0.9 + randf() * 0.2)
		var w := size * 0.055 * sc
		var mid: float = ly + length * 0.4
		draw_polygon(PackedVector2Array([Vector2(lx - w, ly), Vector2(lx + w, ly), Vector2(lx + w * 0.7, mid), Vector2(lx - w * 0.7, mid)]),
			PackedColorArray([Color(1, 0.98, 0.82, 0.98), Color(1, 0.98, 0.82, 0.98), Color(0.43, 0.86, 1, 0.9), Color(0.43, 0.86, 1, 0.9)]))
		draw_polygon(PackedVector2Array([Vector2(lx - w * 0.7, mid), Vector2(lx + w * 0.7, mid), Vector2(lx + w * 0.35, ly + length), Vector2(lx - w * 0.35, ly + length)]),
			PackedColorArray([Color(0.43, 0.86, 1, 0.9), Color(0.43, 0.86, 1, 0.9), Color(0.16, 0.24, 0.63, 0), Color(0.16, 0.24, 0.63, 0)]))


func _draw_bullet(p: Vector2, b: SimWorld.Bullet) -> void:
	if b.missile:
		draw_line(p - b.vel * 0.065, p, Color(1, 0.7, 0.24, 0.8), 3)
		draw_circle(p, 5, b.color)
		draw_circle(p, 2, Color("#fff5a0"))
		return
	draw_set_transform(p, b.vel.angle(), Vector2.ONE)
	draw_texture_rect(_laser_white, Rect2(-16, -8, 32, 16), false, b.color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_beam(bm: SimWorld.Beam) -> void:
	if bm.owner == null:
		return
	var a := rel(bm.p1)
	var b := a + (bm.p2 - bm.p1)
	var glow := bm.color
	glow.a = 0.32
	var core := bm.color
	core.a = 0.94
	draw_line(a, b, glow, bm.width * 2.4)
	draw_line(a, b, core, bm.width)
	draw_line(a, b, Color(1, 0.98, 0.82, 0.9), maxf(2, bm.width * 0.28))


func _draw_gate(p: Vector2, now: float) -> void:
	var glow := Color("#61f2ff")
	for i in 6:
		draw_circle(p, 29 - i * 4, Color(0.27, 0.86, 1, 0.07 + i * 0.03))
	draw_arc(p, 42, 0, TAU, 48, glow, 5)
	for i in 4:
		var base := now + i * TAU / 4
		draw_arc(p, 31, base - 0.55, base + 0.55, 12, glow, 2)


func _draw_fuel(p: Vector2, f: SimWorld.FuelCell) -> void:
	draw_set_transform(p, f.spin, Vector2.ONE)
	var pulse := 0.7 + 0.3 * sin(f.spin * 4)
	draw_rect(Rect2(-14, -17, 28, 34), Color(1, 0.9, 0.35, 0.18 * pulse))
	draw_rect(Rect2(-11, -14, 22, 28), Color("#e6bd2f"))
	draw_rect(Rect2(-7, -10, 14, 17), Color("#fff28b"))
	draw_rect(Rect2(-5, -19, 10, 5), Color("#222a35"))
	draw_rect(Rect2(-4, -5, 8, 3), Color("#5adfff"))
	draw_rect(Rect2(-11, -14, 22, 28), Color.WHITE, false, 2)
	draw_string(_font, Vector2(-4, 11), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#7a5b00"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_icon(p: Vector2, o: SimWorld.Icon, now: float) -> void:
	var alpha := 1.0
	if o.drop_protected_until > world.time:
		alpha = 0.72 + 0.28 * (0.5 + 0.5 * sin(now * 22.0))
	draw_set_transform(p, sin(o.spin) * 0.05, Vector2.ONE)
	var inf := o.infected
	var stroke := Color("#ff4cff") if inf else Color("#63cfff")
	stroke.a = alpha
	var a := func(c: Color) -> Color: return Color(c, c.a * alpha)
	if o.kind in ["FOLDER", "DAT", "INI"]:
		var pts := PackedVector2Array([Vector2(-20, -8), Vector2(-6, -8), Vector2(-2, -14), Vector2(12, -14), Vector2(18, -8), Vector2(20, -8), Vector2(20, 16), Vector2(-20, 16)])
		draw_colored_polygon(pts, a.call(Color("#7b3fb0") if inf else Color("#f2cf58")))
		pts.append(pts[0])
		draw_polyline(pts, stroke, 2.5)
		draw_rect(Rect2(-20, -7, 40, 6), a.call(Color("#2c0e42") if inf else Color("#c89f2c")))
		_text(Vector2(-1, 8), o.kind, 8, a.call(Color.WHITE if inf else Color("#3b2f0f")))
	else:
		var pts := PackedVector2Array([Vector2(-16, -18), Vector2(8, -18), Vector2(18, -8), Vector2(18, 18), Vector2(-16, 18)])
		draw_colored_polygon(pts, a.call(Color("#cda4ff") if inf else Color("#f4f9ff")))
		pts.append(pts[0])
		draw_polyline(pts, stroke, 2.5)
		draw_colored_polygon(PackedVector2Array([Vector2(8, -18), Vector2(18, -8), Vector2(8, -8)]), a.call(Color("#e9d8ff") if inf else Color("#d7ebff")))
		match o.kind:
			"BMP":
				draw_rect(Rect2(-10, -4, 20, 13), a.call(Color("#6d3ea8") if inf else Color("#90c95c")))
				draw_circle(Vector2(-4, -1), 3, a.call(Color("#ff79ff") if inf else Color("#59b0ff")))
			"EXE":
				draw_rect(Rect2(-10, -9, 20, 15), a.call(Color("#5a2c86") if inf else Color("#3c8dd9")))
				draw_rect(Rect2(-8, -7, 16, 10), a.call(Color("#dfefff")))
			"ICO":
				draw_circle(Vector2(0, 2), 8, a.call(Color("#7a34c7") if inf else Color("#3eb4ff")))
				draw_circle(Vector2(-2, 0), 2, a.call(Color.WHITE))
			"WAV":
				var wc: Color = a.call(Color.WHITE if inf else Color("#2460b8"))
				draw_polyline(PackedVector2Array([Vector2(-8, 6), Vector2(-3, 6), Vector2(3, 11), Vector2(3, 1), Vector2(-3, 6)]), wc, 2)
				draw_arc(Vector2(6, 6), 4, -0.8, 0.8, 8, wc, 2)
				draw_arc(Vector2(7, 6), 7, -0.7, 0.7, 8, wc, 2)
			_:
				var lc: Color = a.call(Color("#4e2176") if inf else Color("#3a78b9"))
				draw_rect(Rect2(-9, -2, 18, 2), lc)
				draw_rect(Rect2(-9, 3, 15, 2), lc)
				draw_rect(Rect2(-9, 8, 12, 2), lc)
		_text(Vector2(0, 16), o.kind, 8, a.call(Color("#1c002d") if inf else Color("#003b73")))
	if inf:
		draw_line(Vector2(-16, -14), Vector2(16, 14), Color(1, 0, 1, 0.7 * alpha), 2.5)
		draw_line(Vector2(16, -14), Vector2(-16, 14), Color(1, 0, 1, 0.7 * alpha), 2.5)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _text(center: Vector2, text: String, size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, center - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
