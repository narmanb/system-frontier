extends Control
## Free Flight: pick a starter hull and fly the sandbox (a normal directory at a chosen
## threat) or the factory test range, outside the campaign.

var _cards := {}
var _detail: Label
var _threat := 3
var _threat_btn: Button


func _ready() -> void:
	theme = Win95.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Win95.DESKTOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)
	var bar := TitleBar.new()
	bar.title = "FREE FLIGHT"
	bar.add_button("sound", func(): AppState.set_setting("sound", not AppState.settings["sound"]); bar.queue_redraw(); _redraw_bar(bar))
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		bar.add_button("fullscreen", AppState.toggle_fullscreen)
	bar.add_button("close", _back)
	outer.add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(margin)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(center)

	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", Win95.BevelBox.new("window", Win95.FACE, 14, 14))
	win.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win.custom_minimum_size.x = 0
	center.add_child(win)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	win.add_child(col)
	# Cap the window width on wide screens so it reads as a dialog, not a page.
	resized.connect(func(): win.custom_minimum_size.x = minf(760.0, size.x - 28); win.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if size.x > 800 else Control.SIZE_EXPAND_FILL)
	win.custom_minimum_size.x = minf(760.0, get_viewport_rect().size.x - 28)


	col.add_child(Win95.label("Select hull", 16, Win95.TEXT, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	col.add_child(flow)
	var hulls := DataStore.starter_hulls()
	for id in hulls["order"]:
		flow.add_child(_hull_card(id, hulls["hulls"][id]))

	var detail := Win95.field("", 14)
	_detail = detail.get_child(0)
	col.add_child(detail)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var launch := _grid_button(grid, "Flight Sandbox", _launch.bind("sandbox"))
	_grid_button(grid, "Test Range", _launch.bind("test"))
	_threat_btn = _grid_button(grid, "", func(): _threat = _threat % 5 + 1; _update_threat())
	_grid_button(grid, "Back to Menu", _back)
	var touch_btn := _grid_button(grid, "", func(): pass)
	var upd_touch := func(): touch_btn.text = "Touch pads: %s" % AppState.settings["show_touch"]
	upd_touch.call()
	touch_btn.pressed.connect(func():
		var order := ["auto", "on", "off"]
		AppState.set_setting("show_touch", order[(order.find(str(AppState.settings["show_touch"])) + 1) % 3])
		upd_touch.call())

	col.add_child(Win95.field("Keys: ←/→ turn · ↑ thrust · Space fire · X missile · M map · Esc pause · +/- zoom. "
		+ "No brake: turn around and counter-thrust. Gamepad: stick/d-pad turn, A thrust, X/RB fire, Y/LB missile, Start pause.\n"
		+ "", 13))

	_update_threat()
	_select(str(AppState.settings["hull"]))
	launch.grab_focus()


func _redraw_bar(bar: TitleBar) -> void:
	for b in bar.find_children("*", "Button", true, false):
		b.queue_redraw()


func _grid_button(grid: GridContainer, text: String, cb: Callable) -> Button:
	var b := Win95.button(text, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	grid.add_child(b)
	return b


func _update_threat() -> void:
	_threat_btn.text = "Threat level: %d" % _threat


func _hull_card(id: String, h: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(124, 150)
	b.pressed.connect(_select.bind(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8; box.offset_right = -8; box.offset_top = 8; box.offset_bottom = -6
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Win95.WELL, 4, 4))
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(well)
	var tex := TextureRect.new()
	tex.texture = _cropped(load(h["art"]))
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(tex)
	var n := Win95.label(h["name"], 14, Win95.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(n)
	var role := Win95.label(h["role"], 12, Win95.SHADOW)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(role)
	_cards[id] = b
	return b


## Preview-only crop to the visible alpha bounds (legacy v7.0 preview fix); the 48×48
## editable art and mount coordinates are untouched.
func _cropped(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	var used := img.get_used_rect()
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(used.grow(1)).intersection(Rect2(0, 0, img.get_width(), img.get_height()))
	return at


func _select(id: String) -> void:
	if not _cards.has(id):
		id = "redFalcon"
	for k in _cards:
		_cards[k].button_pressed = k == id
	AppState.set_setting("hull", id)
	var h := DataStore.starter_hull(id)
	var p := ShipPerformance.compute(h)
	var mods: Dictionary = DataStore.modules()
	_detail.text = "%s — %s\nTop speed %d · accel %.0f/s² · 180° turn %.2fs · coast loss %.1f%%/s\nHull %d · shield %d · fuel %d (%ds thrust) · damage %.1f · %.1f shots/s\nReactor %d/%d%s · %s · %s · %s" % [
		h["name"], h["description"], roundi(p.maxSpeed), p.acceleration, PI / p.turnRate, p.passiveLoss * 100,
		roundi(p.maxHull), roundi(p.shield), roundi(p.maxFuel), roundi(p.fuelSeconds), p.damage, 1.0 / p.fireInterval,
		roundi(p.capacity), roundi(p.demand), "  OVERLOAD" if p.demand > p.capacity else "",
		mods["primary"][p.mods.primary]["name"], mods["defense"][p.mods.defense]["name"], mods["utility"][p.mods.utility]["name"]]


func _launch(mode: String) -> void:
	AppState.launch = {"mode": mode, "threat": _threat}
	get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _gamepad_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") and not _popup_open():
		get_viewport().set_input_as_handled()
		_back()
		return true
	return false


func _popup_open() -> bool:
	for ch in get_children():
		if ch is Win95.PopupOverlay:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	_gamepad_back(event)
