class_name RadarWindow
extends TouchRegion
## Minimap as a small Win95 window: drag it by its caption, minimize it to the caption with
## the caption button, tap the map to open the full tactical map. Position and minimized
## state persist in settings.

signal open_map

var world: SimWorld
var minimized := false
var _cap_h := 22.0
var _drag_from := Vector2.ZERO
var _dragging := false
var _moved := false
var _press_zone := ""


func _ready() -> void:
	minimized = bool(AppState.settings.get("radar_min", false))
	get_viewport().size_changed.connect(_clamp_to_screen)
	_resize()
	var saved = AppState.settings.get("radar_pos", null)
	var vs := get_viewport_rect().size
	if saved is Array and saved.size() == 2:
		position = Vector2(float(saved[0]) * vs.x, float(saved[1]) * vs.y)
	else:
		var ins := AppState.safe_insets()
		position = Vector2(vs.x - size.x - 6 - ins.right, 6 + ins.top)
	_clamp_to_screen()


func _resize() -> void:
	var vs := get_viewport_rect().size
	var w := clampf(minf(vs.x, vs.y) * 0.27, 130, 190)
	_cap_h = 22.0 if not AppState.is_touch_ui() else 26.0
	size = Vector2(w, _cap_h + 6 if minimized else _cap_h + 6 + w * 0.66 + 8)


func _clamp_to_screen() -> void:
	_resize()
	var vs := get_viewport_rect().size
	var ins := AppState.safe_insets()
	position = Vector2(clampf(position.x, ins.left, maxf(ins.left, vs.x - size.x - ins.right)), clampf(position.y, ins.top, maxf(ins.top, vs.y - size.y - ins.bottom)))


func _save() -> void:
	var vs := get_viewport_rect().size
	AppState.settings["radar_pos"] = [position.x / vs.x, position.y / vs.y]
	AppState.settings["radar_min"] = minimized


func _min_button_rect() -> Rect2:
	var s := _cap_h - 4
	return Rect2(size.x - s - 5, 5, s, s - 2)


func _on_press(p: Vector2) -> void:
	_drag_from = p
	_moved = false
	_press_zone = "min" if _min_button_rect().grow(4).has_point(p) else ("caption" if p.y < _cap_h + 3 else "map")
	_dragging = _press_zone == "caption"
	queue_redraw()


func _on_drag(p: Vector2) -> void:
	if _dragging:
		var d := p - _drag_from
		if d.length() > 4 or _moved:
			_moved = true
			position += d
			_clamp_to_screen()


func _on_release(p: Vector2) -> void:
	if _press_zone == "min" and _min_button_rect().grow(6).has_point(p):
		minimized = not minimized
		_clamp_to_screen()
		_save()
	elif _press_zone == "map" and not _moved:
		open_map.emit()
	elif _moved:
		_save()
	_dragging = false
	_press_zone = ""
	queue_redraw()


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or world.player == null:
		return
	var fs := 13 if AppState.is_touch_ui() else 12
	Win95.bevel(self, Rect2(Vector2.ZERO, size), "window", Win95.FACE)
	var cap := Rect2(3, 3, size.x - 6, _cap_h)
	Win95.caption(self, cap, "", fs)
	Win95.text(self, Vector2(cap.position.x + _cap_h + 2, cap.position.y + _cap_h / 2 + fs * 0.36), "Radar", fs, Win95.HILITE, true)
	var mb := _min_button_rect()
	Win95.bevel(self, mb, "pressed" if _press_zone == "min" else "raised", Win95.FACE)
	var mc := mb.get_center()
	if minimized:  # "restore" glyph
		draw_rect(Rect2(mc - Vector2(4, 3), Vector2(8, 6)), Win95.TEXT, false, 1.5)
	else:
		draw_rect(Rect2(mc + Vector2(-4, 2), Vector2(8, 2)), Win95.TEXT)
	if minimized:
		return
	var well := Rect2(6, _cap_h + 7, size.x - 12, size.y - _cap_h - 13)
	Win95.bevel(self, well, "sunken", Color("#001010"))
	var inner := well.grow(-2)
	var c := inner.get_center()
	draw_line(Vector2(inner.position.x, c.y), Vector2(inner.end.x, c.y), Color(0.2, 0.8, 0.7, 0.18))
	draw_line(Vector2(c.x, inner.position.y), Vector2(c.x, inner.end.y), Color(0.2, 0.8, 0.7, 0.18))
	var k := Vector2(inner.size.x / SimWorld.W, inner.size.y / SimWorld.H)
	var dot := func(wp: Vector2, col: Color, s := 3.0) -> void:
		draw_rect(Rect2(c + SimWorld.wrapped_delta(world.player.pos, wp) * k - Vector2(s, s) / 2, Vector2(s, s)), col)
	for o in world.icons:
		dot.call(o.pos, Color("#f4f") if o.infected else Color("#5ff"))
	for s in world.ships:
		dot.call(s.pos, Color("#ff4040") if NpcAI.aggressive_to_player(world, s) else s.color)
		if s.cargo_icon:   # icon carrier: cyan ring
			var cp := c + SimWorld.wrapped_delta(world.player.pos, s.pos) * k
			draw_rect(Rect2(cp - Vector2(4, 4), Vector2(8, 8)), Color("#5ff"), false, 1.5)
	if world.gate_open:
		dot.call(world.gate_pos, Color("#9ff"), 6.0)
	if world.mission:
		var obj = world.mission.objective_point()
		if obj != null:
			dot.call(obj, Color("#ffe56b"), 5.0)
	draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
