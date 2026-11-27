extends Node
## Dev/CI check: drives the real menu screens with simulated finger touches (the Android
## path: InputEventScreenTouch/Drag with mouse emulation) and verifies that
##   - a vertical drag over buttons and window panels scrolls the screen,
##   - that drag does not press the button it started on,
##   - a plain tap still presses a button.
##   godot --headless --path . res://tools/touch_check.tscn

var failures := []


func _ready() -> void:
	# Headless reports no touchscreen; this makes Godot behave as on a phone.
	Input.emulate_touch_from_mouse = true
	var placeholder := Node.new()
	get_tree().root.add_child.call_deferred(placeholder)
	await _f(1)
	get_tree().current_scene = placeholder
	reparent(get_tree().root)
	SaveService.root = "user://touch_check/"
	SaveService.reset("all")
	SaveService.save_campaign(Campaign.create({}))
	# phone landscape, phone portrait (the shapes from the bug report), Retroid Pocket 5
	for win in [Vector2i(2000, 923), Vector2i(923, 2000), Vector2i(1920, 1080)]:
		get_window().size = win
		await _f(3)
		for path in ["res://scenes/setup/setup.tscn", "res://scenes/directory_map/directory_map.tscn",
				"res://scenes/free_flight/free_flight.tscn", "res://scenes/main_menu/main_menu.tscn"]:
			await _scene(path)
			await _check_screen("%dx%d %s" % [win.x, win.y, path.get_file().get_basename()])
	SaveService.reset("all")
	if failures.is_empty():
		print("TOUCH OK")
	else:
		print("TOUCH FAIL")
		for f in failures:
			print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_screen(name: String) -> void:
	var scene := get_tree().current_scene
	var sc: ScrollContainer = null
	for s in scene.find_children("*", "ScrollContainer", true, false):
		if s.is_visible_in_tree() and (sc == null or s.get_v_scroll_bar().max_value > sc.get_v_scroll_bar().max_value):
			sc = s
	if sc == null:
		failures.append("%s: no scroll area" % name)
		return
	var r := sc.get_global_rect()
	var vr := get_viewport().get_visible_rect()
	for b in scene.find_children("*", "CaptionButton", true, false):
		_check(vr.grow(0.5).encloses(b.get_global_rect()), "%s: caption button '%s' fully on screen (%s in %s)" % [name, b.glyph, b.get_global_rect(), vr.size])
	var overflow := sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page
	print("  %s: window %s, canvas %s, overflow %d" % [name, get_window().size, get_viewport().get_visible_rect().size, overflow])
	# a tap on a button inside the scroll area must still press it
	var btn := _button_in(sc, r)
	if btn:
		var hits := [0]
		var cb := func(): hits[0] += 1
		# swap the button's handlers out so the tap does not change screens
		var conns := btn.pressed.get_connections()
		for c in conns:
			btn.pressed.disconnect(c["callable"])
		btn.pressed.connect(cb)
		var at := btn.get_global_rect().get_center()
		_touch(at, true)
		await _f(2)
		_touch(at, false)
		await _f(2)
		_check(hits[0] == 1, "%s: tapping '%s' presses it (pressed %d times)" % [name, btn.text.get_slice("\n", 0), hits[0]])
		# a drag that starts on the button scrolls and does not press it
		if overflow > 40:
			hits[0] = 0
			sc.scroll_vertical = 0
			await _f(2)
			var p := btn.get_global_rect().get_center()
			_touch(p, true)
			await _f(1)
			for i in 15:
				p.y -= 12
				_drag(p, Vector2(0, -12))
				await _f(1)
			_touch(p, false)
			await _f(30)
			_check(sc.scroll_vertical > 60, "%s: dragging over a button scrolls (scroll %d, overflow %d)" % [name, sc.scroll_vertical, overflow])
			_check(hits[0] == 0, "%s: the drag did not press '%s'" % [name, btn.text.get_slice("\n", 0)])
		btn.pressed.disconnect(cb)
		for c in conns:
			btn.pressed.connect(c["callable"])
	# dragging on the window panel itself (between controls, e.g. its border) also scrolls
	if overflow > 40:
		sc.scroll_vertical = 0
		await _f(2)
		var panel_x := r.position.x + 30
		for pc in sc.find_children("*", "PanelContainer", true, false):
			panel_x = (pc as Control).get_global_rect().position.x + 6   # inside the window's bevel padding
			break
		var q := Vector2(panel_x, r.end.y - 30)
		_touch(q, true)
		await _f(1)
		for i in 15:
			q.y -= 12
			_drag(q, Vector2(0, -12))
			await _f(1)
		_touch(q, false)
		await _f(30)
		_check(sc.scroll_vertical > 60, "%s: dragging on the window background scrolls (scroll %d)" % [name, sc.scroll_vertical])
	_check(get_tree().current_scene == scene, "%s: no screen change during the drags" % name)


func _button_in(sc: ScrollContainer, r: Rect2) -> Button:
	for b in sc.find_children("*", "Button", true, false):
		var br: Rect2 = b.get_global_rect()
		if b.is_visible_in_tree() and not b.disabled and not b is OptionButton and r.encloses(br) and br.size.y >= 24 and br.get_center().y < r.position.y + r.size.y * 0.6:
			return b
	return null


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = _screen(p)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = _screen(p)
	e.relative = _screen(p) - _screen(p - rel)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Canvas (logical) position -> window pixels, which is what touch events carry.
func _screen(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await _f(8)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)
