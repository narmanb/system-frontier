class_name EditorCanvas
extends Control
## Ship Factory paint surface: draws the editable grid with mirror guide, thruster and
## hardpoint overlays and the precision cursor. One finger / left mouse paints; two
## fingers pan + pinch-zoom; mouse wheel zooms; right/middle drag pans. A second finger
## landing mid-stroke cancels that stroke (so zoom gestures never leave stray pixels).

signal stroke_finished
signal cell_hovered(x: int, y: int)

var editor: FactoryEditor
var zoom := 1.0
var pan := Vector2.ZERO               ## grid-space offset of the view centre (cells)
var show_thrusters := true
var show_hardpoints := true
var cursor := Vector2i(-1, -1)        ## precision cursor (-1 = hidden)
var _painting := false
var _stroke_snapshot := {}
var _touches := {}
var _gesture_dist := 0.0
var _gesture_mid := Vector2.ZERO
var _panning := false
var _last_cell := Vector2i(-1, -1)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _process(_dt: float) -> void:
	queue_redraw()


func cell_size() -> float:
	return minf(size.x, size.y) / editor.grid_size * zoom


func origin() -> Vector2:
	var cs := cell_size()
	return size / 2 - (Vector2(editor.grid_size, editor.grid_size) / 2 + pan) * cs


func cell_at(p: Vector2) -> Vector2i:
	var q := (p - origin()) / cell_size()
	return Vector2i(int(floor(q.x)), int(floor(q.y)))


func set_zoom(z: float) -> void:
	zoom = clampf(z, 1.0, 6.0)
	_clamp_pan()


func _clamp_pan() -> void:
	var lim := editor.grid_size / 2.0 * (1.0 - 1.0 / zoom)
	pan = Vector2(clampf(pan.x, -lim, lim), clampf(pan.y, -lim, lim))


func _begin_stroke(p: Vector2) -> void:
	_stroke_snapshot = editor.snapshot()
	editor.push_history()
	_painting = true
	_last_cell = Vector2i(-1, -1)
	_paint_at(p)


func _paint_at(p: Vector2) -> void:
	var c := cell_at(p)
	if c == _last_cell:
		return
	if c.x < 0 or c.y < 0 or c.x >= editor.grid_size or c.y >= editor.grid_size:
		return
	# fill a straight line between samples so fast strokes stay continuous
	if _last_cell.x >= 0 and editor.tool in ["paint", "erase"]:
		var steps := maxi(absi(c.x - _last_cell.x), absi(c.y - _last_cell.y))
		for i in range(1, steps):
			var t := float(i) / steps
			var q := Vector2(_last_cell).lerp(Vector2(c), t).round()
			editor.paint(int(q.x), int(q.y))
	editor.paint(c.x, c.y)
	_last_cell = c
	if editor.tool in ["fill", "pick", "thruster", "hardpoint"]:
		_end_stroke()


func _end_stroke() -> void:
	if _painting:
		_painting = false
		stroke_finished.emit()


func _cancel_stroke() -> void:
	if _painting:
		_painting = false
		editor.restore(_stroke_snapshot)
		if not editor.history.is_empty():
			editor.history.pop_back()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			_cancel_stroke()
			_start_gesture()
		accept_event()
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) / 2
			if _gesture_dist > 0:
				set_zoom(zoom * d / _gesture_dist)
				pan -= (mid - _gesture_mid) / cell_size()
				_clamp_pan()
			_gesture_dist = d
			_gesture_mid = mid
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(zoom * 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(zoom / 1.15)
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touches.size() < 2:
				_begin_stroke(mb.position)
			elif not mb.pressed:
				_end_stroke()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var c := cell_at(mm.position)
		cell_hovered.emit(c.x, c.y)
		if _panning:
			pan -= mm.relative / cell_size()
			_clamp_pan()
		elif _painting and _touches.size() < 2:
			_paint_at(mm.position)


func _start_gesture() -> void:
	var pts: Array = _touches.values()
	_gesture_dist = (pts[0] as Vector2).distance_to(pts[1])
	_gesture_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) / 2


func _draw() -> void:
	if editor == null:
		return
	var n := editor.grid_size
	var cs := cell_size()
	var o := origin()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#101522"))
	var pal := FactoryEditor.full_palette()
	for y in n:
		for x in n:
			var v = editor.grid[y * n + x]
			if v == null:
				continue
			var hx: String = v if v is String else str(pal[int(v)]) if int(v) < pal.size() else "#ffffff"
			draw_rect(Rect2(o + Vector2(x, y) * cs, Vector2(cs, cs) + Vector2(0.5, 0.5)), Color.html(hx))
	if cs >= 5:
		var gc := Color(0.7, 0.86, 1, 0.12)
		for i in n + 1:
			draw_line(o + Vector2(i * cs, 0), o + Vector2(i * cs, n * cs), gc, 1)
			draw_line(o + Vector2(0, i * cs), o + Vector2(n * cs, i * cs), gc, 1)
	draw_line(o + Vector2(n * cs / 2, 0), o + Vector2(n * cs / 2, n * cs), Color("#47d7ff"), 2)
	draw_rect(Rect2(o, Vector2(n, n) * cs), Color(0.3, 0.7, 1, 0.4), false, 1)
	var font := Win95.bold_font()
	if show_thrusters:
		for t in editor.thrusters:
			var enabled: bool = t["id"] == "center" or t["enabled"]
			var c := o + (Vector2(t["x"], t["y"]) + Vector2(0.5, 0.5)) * cs
			var r := maxf(7, cs * 1.2)
			var sel: bool = t["id"] == editor.selected_thruster
			draw_circle(c, r, Color(0.12, 0.75, 1, 0.24) if enabled else Color(0.4, 0.4, 0.4, 0.15))
			draw_arc(c, r, 0, TAU, 24, Color.WHITE if sel else (Color("#53f6ff") if enabled else Color("#777")), 3 if sel else 2)
			draw_line(c + Vector2(0, r), c + Vector2(0, r + maxf(15, cs * 3)), Color("#53f6ff") if enabled else Color("#777"), 2)
			var fs := int(maxf(10, cs * 0.9))
			var lab: String = str(t["id"]).substr(0, 1).to_upper()
			draw_string(font, c + Vector2(-fs * 0.32, fs * 0.36), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if enabled else Color("#aaa"))
	if show_hardpoints:
		var cols := {"primary": Color("#ffef65"), "secondary": Color("#ff8a4d"), "defense": Color("#7dffb8"), "utility": Color("#d68cff")}
		for h in editor.hardpoints:
			var c := o + (Vector2(h["x"], h["y"]) + Vector2(0.5, 0.5)) * cs
			var s := maxf(10, cs * 1.05)
			var sel: bool = h["id"] == editor.selected_hardpoint
			draw_rect(Rect2(c - Vector2(s, s) / 2, Vector2(s, s)), Color(0, 0, 0, 0.45))
			draw_rect(Rect2(c - Vector2(s, s) / 2, Vector2(s, s)), Color.WHITE if sel else cols[h["id"]], false, 3 if sel else 2)
			var fs := int(maxf(9, cs * 0.85))
			draw_string(font, c + Vector2(-fs * 0.32, fs * 0.36), str(h["id"]).substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[h["id"]])
	if cursor.x >= 0:
		var p := o + Vector2(cursor) * cs
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(cs - 2, cs - 2)), Color("#ffef65"), false, maxf(2, cs * 0.18))
		draw_line(p + Vector2(cs / 2, -cs * 0.4), p + Vector2(cs / 2, cs * 1.4), Color(1, 1, 1, 0.9), 1)
		draw_line(p + Vector2(-cs * 0.4, cs / 2), p + Vector2(cs * 1.4, cs / 2), Color(1, 1, 1, 0.9), 1)
