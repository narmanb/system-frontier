class_name TouchControls
extends Control
## On-screen flight controls. Multi-touch; a finger may slide between buttons (legacy
## `setTouchPointer` behaviour). Buttons press the same InputMap actions as keyboard and
## gamepad, so gameplay code has a single input path.
##
## Change from legacy: button sizes are computed in millimetres from the screen DPI rather
## than as a fraction of canvas size, so they stay thumb-sized on high-density phones.

signal map_pressed

var buttons: Array = []          ## {id, rect, action, label, round}
var bottom_inset := 0.0          ## space reserved below the pads (HUD status bar)
var _finger_button := {}         ## touch index -> button id
var _held := {}                  ## action -> count of fingers holding it


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(layout)
	layout()


func _logical_per_mm() -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0:
		dpi = 160
	var logical_w := get_viewport_rect().size.x
	var physical_w := float(DisplayServer.window_get_size().x)
	var stretch := physical_w / logical_w if logical_w > 0 else 1.0
	return dpi / 25.4 / maxf(0.01, stretch)


func layout() -> void:
	var size_v := get_viewport_rect().size
	var mm := _logical_per_mm()
	var w := size_v.x
	var h := size_v.y
	var portrait := h > w
	var pad := clampf(4.0 * mm, 14, 40)
	var gap := clampf(2.5 * mm, 8, 24)
	var turn := Vector2(clampf(17 * mm, 72, 190), clampf(14 * mm, 56, 160))
	var main := Vector2(clampf(17 * mm, 66, 190), clampf(14 * mm, 54, 160))
	var mini := Vector2(clampf(11 * mm, 44, 120), clampf(10 * mm, 40, 110))
	var map_s := clampf(10 * mm, 42, 100)
	if portrait:
		pad = maxf(pad, h * 0.02)
	var bottom := h - pad - bottom_inset
	var lx := pad
	var ly := bottom - turn.y
	var right_x := w - pad - main.x
	var thrust_y := bottom - main.y
	var fire_y := thrust_y - main.y - gap
	var mini_x := right_x - gap - mini.x
	buttons = [
		{"id": "left", "rect": Rect2(lx, ly, turn.x, turn.y), "action": "turn_left", "label": "◀"},
		{"id": "right", "rect": Rect2(lx + turn.x + gap, ly, turn.x, turn.y), "action": "turn_right", "label": "▶"},
		{"id": "map", "rect": Rect2(lx + turn.x + gap / 2 - map_s * 0.65, ly - map_s - gap, map_s * 1.3, map_s), "action": "", "label": "MAP"},
		{"id": "fire", "rect": Rect2(right_x, fire_y, main.x, main.y), "action": "fire", "label": "✦"},
		{"id": "thrust", "rect": Rect2(right_x, thrust_y, main.x, main.y), "action": "thrust", "label": "▲"},
		{"id": "missile", "rect": Rect2(mini_x, fire_y + (main.y - mini.y) / 2, mini.x, mini.y), "action": "missile", "label": "M"},
	]
	queue_redraw()


func _hit(pos: Vector2) -> String:
	for b in buttons:
		if b["rect"].grow(6).has_point(pos):
			return b["id"]
	return ""


func _button(id: String) -> Dictionary:
	for b in buttons:
		if b["id"] == id:
			return b
	return {}


func _set_finger(index: int, id: String) -> void:
	var old: String = _finger_button.get(index, "")
	if old == id:
		return
	if old != "":
		var ob := _button(old)
		if ob.get("action", "") != "":
			_release(ob["action"])
	if id == "":
		_finger_button.erase(index)
	else:
		_finger_button[index] = id
		var nb := _button(id)
		if nb.get("action", "") != "":
			_press(nb["action"])
		elif id == "map" and old == "":
			map_pressed.emit()
	queue_redraw()


func _press(action: String) -> void:
	_held[action] = int(_held.get(action, 0)) + 1
	Input.action_press(action)


func _release(action: String) -> void:
	_held[action] = maxi(0, int(_held.get(action, 0)) - 1)
	if _held[action] == 0:
		Input.action_release(action)


func release_all() -> void:
	for idx in _finger_button.keys():
		_set_finger(idx, "")
	_finger_button.clear()
	for a in _held:
		Input.action_release(a)
	_held.clear()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var id := _hit(event.position)
			if id != "":
				_set_finger(event.index, id)
				get_viewport().set_input_as_handled()
		elif _finger_button.has(event.index):
			_set_finger(event.index, "")
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _finger_button.has(event.index):
		var id := _hit(event.position)
		# Sliding onto another button switches to it; sliding off all buttons releases (legacy behaviour).
		if _button(_finger_button[event.index]).get("id") == "map":
			return
		_set_finger(event.index, id if id != "map" else "")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		release_all()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _draw() -> void:
	var active := {}
	for idx in _finger_button:
		active[_finger_button[idx]] = true
	for b in buttons:
		var r: Rect2 = b["rect"]
		var on: bool = active.has(b["id"])
		Win95.bevel(self, r, "pressed" if on else "raised", Color(Win95.FACE, 0.9) if not on else Color(Win95.LIGHT, 0.95))
		var c := r.get_center()
		var k := minf(r.size.x, r.size.y) * 0.22
		var ink := Win95.TEXT
		if on:
			c += Vector2(1, 1)
		match b["id"]:
			"left": draw_colored_polygon(PackedVector2Array([c + Vector2(-k, 0), c + Vector2(k * 0.8, -k), c + Vector2(k * 0.8, k)]), ink)
			"right": draw_colored_polygon(PackedVector2Array([c + Vector2(k, 0), c + Vector2(-k * 0.8, -k), c + Vector2(-k * 0.8, k)]), ink)
			"thrust": draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, k * 0.8), c + Vector2(-k, k * 0.8)]), ink)
			"fire":
				for i in 4:
					var ang := i * PI / 4
					draw_line(c - Vector2(cos(ang), sin(ang)) * k, c + Vector2(cos(ang), sin(ang)) * k, ink, 3)
				draw_circle(c, k * 0.35, ink)
			_:
				var fs := int(clampf(r.size.y * (0.34 if b["id"] == "map" else 0.42), 12, 56))
				var ts := Win95.bold_font().get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(Win95.bold_font(), c + Vector2(-ts.x / 2, fs * 0.36), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
