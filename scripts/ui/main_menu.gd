extends Control
## Title screen: choose a starter hull and launch the flight sandbox or the test range.
## Campaign, directory map and Ship Factory arrive in later milestones (see docs/ROADMAP.md).

var _cards := {}
var _detail: Label
var _threat := 3
var _threat_btn: Button


func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	scroll.add_child(margin)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := UiTheme.label("SYSTEM FRONTIER", 40, UiTheme.EDGE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiTheme.label("C:\\FRONTIER> flight sandbox build %s" % ProjectSettings.get_setting("application/config/version"), 15, UiTheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(UiTheme.label("SELECT HULL", 18, UiTheme.ACCENT))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	col.add_child(flow)
	var hulls := DataStore.starter_hulls()
	for id in hulls["order"]:
		flow.add_child(_hull_card(id, hulls["hulls"][id]))

	var detail_panel := PanelContainer.new()
	col.add_child(detail_panel)
	_detail = UiTheme.label("", 15)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail_panel.add_child(_detail)

	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 10)
	col.add_child(buttons)
	var launch := UiTheme.button("Launch Flight Sandbox", 60)
	launch.custom_minimum_size.x = 260
	launch.pressed.connect(_launch.bind("sandbox"))
	buttons.add_child(launch)
	_threat_btn = UiTheme.button("", 60)
	_threat_btn.custom_minimum_size.x = 170
	_threat_btn.pressed.connect(func(): _threat = _threat % 5 + 1; _update_threat())
	buttons.add_child(_threat_btn)
	var test := UiTheme.button("Factory Test Range", 60)
	test.custom_minimum_size.x = 220
	test.pressed.connect(_launch.bind("test"))
	buttons.add_child(test)

	var opts := HFlowContainer.new()
	opts.alignment = FlowContainer.ALIGNMENT_CENTER
	opts.add_theme_constant_override("h_separation", 10)
	col.add_child(opts)
	var snd := UiTheme.button("", 48)
	snd.custom_minimum_size.x = 150
	var upd := func(): snd.text = "Sound: %s" % ("on" if AppState.settings["sound"] else "off")
	upd.call()
	snd.pressed.connect(func(): AppState.set_setting("sound", not AppState.settings["sound"]); upd.call())
	opts.add_child(snd)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var fs := UiTheme.button("Fullscreen", 48)
		fs.custom_minimum_size.x = 150
		fs.pressed.connect(AppState.toggle_fullscreen)
		opts.add_child(fs)
		var quit := UiTheme.button("Quit", 48)
		quit.custom_minimum_size.x = 110
		quit.pressed.connect(func(): get_tree().quit())
		opts.add_child(quit)

	var help := UiTheme.label("Keys: ←/→ turn · ↑ thrust · Space fire · X missile · M map · Esc pause · +/- zoom. "
		+ "No brake: turn around and counter-thrust. Gamepad: stick/d-pad turn, A thrust, X/RB fire, Y/LB missile, Start pause.", 13, UiTheme.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(help)

	_update_threat()
	_select(str(AppState.settings["hull"]))
	launch.grab_focus()


func _update_threat() -> void:
	_threat_btn.text = "Threat level: %d" % _threat


func _hull_card(id: String, h: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(150, 170)
	b.pressed.connect(_select.bind(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8; box.offset_right = -8; box.offset_top = 8; box.offset_bottom = -8
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var tex := TextureRect.new()
	tex.texture = _cropped(load(h["art"]))
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tex)
	var n := UiTheme.label(h["name"], 15)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(n)
	var role := UiTheme.label(h["role"], 12, UiTheme.DIM)
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
