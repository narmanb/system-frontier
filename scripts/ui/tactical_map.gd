class_name TacticalMap
extends TouchRegion
## Full-screen tactical map (legacy `drawMap` + v7.2.2/v7.2.3 faction/cargo markers).
## Tap anywhere (outside the flight pads) to close.

signal closed

var world: SimWorld


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _on_release(_p: Vector2) -> void:
	closed.emit()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Win95.DESKTOP)
	var top := 46.0
	var margin := 16.0
	var avail := vs - Vector2(margin * 2 + 16, top + margin * 2 + 60)
	var k := minf(avail.x / SimWorld.W, avail.y / SimWorld.H)
	var map_size := Vector2(SimWorld.W, SimWorld.H) * k
	var win := Rect2(Vector2((vs.x - map_size.x) / 2 - 8, top), map_size + Vector2(16, 44))
	Win95.bevel(self, win, "window", Win95.FACE)
	Win95.caption(self, Rect2(win.position + Vector2(3, 3), Vector2(win.size.x - 6, 24)), "Tactical Map — tap to close", 13)
	var origin := win.position + Vector2(8, 34)
	Win95.bevel(self, Rect2(origin - Vector2(2, 2), map_size + Vector2(4, 4)), "sunken", Color("#06101c"))
	var m := func(p: Vector2) -> Vector2: return origin + p * k
	for o in world.icons:
		draw_rect(Rect2(m.call(o.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#f4f") if o.infected else Color("#5ff"))
	for f in world.fuel_cells:
		draw_rect(Rect2(m.call(f.pos) - Vector2(1, 1), Vector2(3, 3)), Color("#ff5"))
	for s in world.ships:
		var p: Vector2 = m.call(s.pos)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), s.color)
		if s.cargo_icon:
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color("#ffe568"), false, 2)
	var ms := world.mission
	if ms:
		for pr in ms.programs:
			draw_rect(Rect2(m.call(pr.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#65f49d"))
		for n in ms.nodes:
			if not n.complete:
				draw_rect(Rect2(m.call(n.pos) - Vector2(3, 3), Vector2(6, 6)), Color("#ffe56b"))
		for o in ms.discoveries:
			draw_rect(Rect2(m.call(o.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#ff83df"))
		if ms.race_active:
			for i in range(ms.race_next, ms.race_checkpoints.size()):
				draw_arc(m.call(ms.race_checkpoints[i]), 5, 0, TAU, 12, Color("#ffff4a"), 1.5)
		if ms.black_hole != null:
			draw_circle(m.call(ms.black_hole), 6, Color("#ff9a20"))
		if ms.type == "courier":
			draw_rect(Rect2(m.call(ms.destination) - Vector2(5, 4), Vector2(10, 8)), Color("#73ffca"), false, 2)
	for h in world.hazards:
		draw_rect(Rect2(m.call(h.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#d65cff"))
	var g: Vector2 = m.call(world.gate_pos)
	draw_rect(Rect2(g - Vector2(5, 5), Vector2(10, 10)), Color("#5ff") if world.gate_open else Color("#555"), false, 2)
	draw_circle(m.call(world.player.pos), 5, Color.WHITE)
