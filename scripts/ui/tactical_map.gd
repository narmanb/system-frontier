class_name TacticalMap
extends Control
## Full-screen tactical map (legacy `drawMap` + v7.2.2/v7.2.3 faction/cargo markers).

var world: SimWorld


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color("#06101c"))
	var margin := 24.0
	var avail := vs - Vector2(margin * 2, margin * 2 + 30)
	var k := minf(avail.x / SimWorld.W, avail.y / SimWorld.H)
	var origin := Vector2((vs.x - SimWorld.W * k) / 2, margin + 30)
	var m := func(p: Vector2) -> Vector2: return origin + p * k
	draw_rect(Rect2(origin, Vector2(SimWorld.W, SimWorld.H) * k), Color(0.3, 0.75, 1, 0.35), false, 1)
	for o in world.icons:
		draw_rect(Rect2(m.call(o.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#f4f") if o.infected else Color("#5ff"))
	for f in world.fuel_cells:
		draw_rect(Rect2(m.call(f.pos) - Vector2(1, 1), Vector2(3, 3)), Color("#ff5"))
	for s in world.ships:
		var p: Vector2 = m.call(s.pos)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), s.color)
		if s.cargo_icon:
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color("#ffe568"), false, 2)
	var g: Vector2 = m.call(world.gate_pos)
	draw_rect(Rect2(g - Vector2(5, 5), Vector2(10, 10)), Color("#5ff") if world.gate_open else Color("#555"), false, 2)
	draw_circle(m.call(world.player.pos), 5, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(margin, margin + 10), "TACTICAL MAP — press M / MAP to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
