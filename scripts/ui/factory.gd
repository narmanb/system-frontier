extends Control
## Ship Factory (legacy Hull Painter + engineering tabs) in the Win95 style.
## Canvas + tool rows, then tabs: Paint, Hull, Engines, Hardpoints, Stats, Modules,
## Telemetry, Library, Test. The editor draft and recent colours auto-save; saved ships
## live in the separate factory save. Landscape puts the panels beside the canvas.

const TABS := ["Paint", "Hull", "Engines", "Hardpoints", "Stats", "Modules", "Telemetry", "Library", "Test"]

var editor := FactoryEditor.new()
var canvas: EditorCanvas
var body: BoxContainer
var left: VBoxContainer
var right_scroll: ScrollContainer
var panel_host: VBoxContainer
var tab_buttons := {}
var current_tab := "Paint"
var status: Label
var name_edit: LineEdit
var bar: TitleBar
var tool_buttons := {}
var undo_btn: Button
var redo_btn: Button
var mirror_btn: Button
var _draft_timer: Timer
var _campaign = null
var test_options := {"infinite": true, "moving": true}
var _precision := false
var pad_auto := false     ## precision: moving the cursor paints
var pad_fine := false     ## precision: 0.42× finger travel
var pad_speed := 1.0      ## precision: 1–3× finger travel
var pad_hold := false     ## precision: "Hold to Draw" button is held
var tool_row: HFlowContainer
var precision_btn: Button
var rcol: VBoxContainer


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
	bar = TitleBar.new()
	bar.title = "SHIP FACTORY — Hull Painter"
	bar.add_button("close", _back)
	var safe := Win95.safe_frame(outer, bar)
	body = BoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	safe.add_child(body)
	var margin_l := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin_l.add_theme_constant_override("margin_" + s, 6)
	body.add_child(margin_l)
	left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	margin_l.add_child(left)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Color("#101522"), 2, 2))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(frame)
	canvas = EditorCanvas.new()
	canvas.editor = editor
	canvas.custom_minimum_size = Vector2(240, 240)
	canvas.stroke_finished.connect(_on_stroke)
	frame.add_child(canvas)
	status = Win95.label("", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(status)
	_build_tool_rows(left)

	right_scroll = Win95.scroll_area()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.follow_focus = true
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_scroll)
	var rmargin := MarginContainer.new()
	rmargin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		rmargin.add_theme_constant_override("margin_" + s, 6)
	right_scroll.add_child(rmargin)
	rcol = VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmargin.add_child(rcol)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	rcol.add_child(tabs)
	for t in TABS:
		var b := Win95.button(t, 40)
		b.toggle_mode = true
		b.custom_minimum_size.x = 92
		b.pressed.connect(_show_tab.bind(t))
		tabs.add_child(b)
		tab_buttons[t] = b
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", Win95.BevelBox.new("window", Win95.FACE, 12, 10))
	rcol.add_child(win)
	panel_host = VBoxContainer.new()
	panel_host.add_theme_constant_override("separation", 8)
	win.add_child(panel_host)

	_draft_timer = Timer.new()
	_draft_timer.one_shot = true
	_draft_timer.wait_time = 0.5
	_draft_timer.timeout.connect(_save_draft)
	add_child(_draft_timer)
	editor.changed.connect(_on_changed)
	_campaign = SaveService.load_campaign()
	if _campaign:
		editor.unlocked = _campaign["blueprints"]
	var rc = SaveService.read_json(SaveService.RECENT_COLORS)
	if rc is Array:
		editor.recent = rc.map(func(v): return int(v)).slice(0, 6)
	var draft = SaveService.read_json(SaveService.DRAFT)
	if draft is Dictionary and draft.get("grid") is Array and not (draft["grid"] as Array).is_empty():
		editor.restore(draft)
	else:
		editor.load_starter("redFalcon")   # legacy default: the true 48×48 Red Falcon
		editor.history.clear()
	if AppState.using_gamepad:
		status.text = "Gamepad: Y precision cursor · D-pad/stick move · A paint · LB/RB tabs · LT/RT zoom · B back"
	if AppState.has_meta("last_test"):
		status.text = AppState.get_meta("last_test")
		AppState.remove_meta("last_test")
	resized.connect(_layout)
	_layout()
	_show_tab(str(AppState.settings.get("factory_tab", "Paint")))
	_refresh()


func _layout() -> void:
	var vs := get_viewport_rect().size
	var landscape := vs.x > vs.y * 1.1
	body.vertical = not landscape
	# Landscape: the canvas gets the full height and the tool buttons move into the
	# right-hand column above the tabs, so nothing is pushed off-screen.
	var want_parent: Node = rcol if landscape else left
	if tool_row.get_parent() != want_parent:
		tool_row.reparent(want_parent)
		want_parent.move_child(tool_row, 0 if landscape else want_parent.get_child_count() - 1)
	if landscape:
		var side := minf(vs.y - 70, vs.x * 0.5)
		canvas.custom_minimum_size = Vector2(side, side)
		left.custom_minimum_size.x = side
		right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		var side := minf(vs.x - 20, vs.y * 0.46)
		canvas.custom_minimum_size = Vector2(side, side)
		left.custom_minimum_size.x = 0
	bar.title = "SHIP FACTORY — %d×%d" % [editor.grid_size, editor.grid_size]


# ------------------------------------------------------------------ tool rows

func _build_tool_rows(host: VBoxContainer) -> void:
	var row := HFlowContainer.new()
	tool_row = row
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	host.add_child(row)
	for spec in [["paint", "Pencil"], ["erase", "Eraser"], ["fill", "Fill"], ["pick", "Pick"]]:
		var b := _small(row, spec[1], _set_tool.bind(spec[0]))
		b.toggle_mode = true
		tool_buttons[spec[0]] = b
	mirror_btn = _small(row, "Mirror: ON", func():
		editor.mirror = not editor.mirror
		_refresh())
	_small(row, "Rotate", func(): editor.rotate())
	undo_btn = _small(row, "Undo", func(): editor.undo())
	redo_btn = _small(row, "Redo", func(): editor.redo())
	_small(row, "- Zoom", func(): canvas.set_zoom(canvas.zoom / 1.4))
	_small(row, "+ Zoom", func(): canvas.set_zoom(canvas.zoom * 1.4))
	precision_btn = _small(row, "Precision", _toggle_precision)
	precision_btn.toggle_mode = true


func _small(row: Container, text: String, cb: Callable) -> Button:
	var b := Win95.button(text, 40)
	b.custom_minimum_size.x = 76
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	row.add_child(b)
	return b


func _set_tool(t: String) -> void:
	editor.tool = t
	_refresh()
	match t:
		"fill": status.text = "Fill: tap an area to flood it with the current colour (mirror applies)."
		"pick": status.text = "Pick: tap a hull pixel to use its colour."
		_: status.text = ""


func _toggle_precision() -> void:
	_precision = not _precision
	canvas.cursor = Vector2i(editor.grid_size / 2, editor.grid_size / 2) if _precision else Vector2i(-1, -1)
	if _precision:
		_show_tab("Paint")
	_rebuild_panel()


# ------------------------------------------------------------------ state

var _refresh_pending := false


func _on_changed() -> void:
	_draft_timer.start()
	if is_inside_tree() and not _refresh_pending:
		_refresh_pending = true
		_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_pending = false
	if not canvas._painting:   # panels rebuild when the stroke ends
		_refresh()


func _on_stroke() -> void:
	_refresh()
	if editor.tool in ["thruster", "hardpoint"]:
		status.text = "%s placed. Tap again to move it, or pick another tool." % ("Exhaust" if editor.tool == "thruster" else "Hardpoint")


func _save_draft() -> void:
	SaveService.write_json(SaveService.DRAFT, "factory_draft", editor.snapshot())
	SaveService.write_json(SaveService.RECENT_COLORS, "recent_colors", editor.recent)


func _refresh() -> void:
	for t in tool_buttons:
		tool_buttons[t].button_pressed = editor.tool == t
	mirror_btn.text = "Mirror: %s" % ("ON" if editor.mirror else "OFF")
	precision_btn.button_pressed = _precision
	undo_btn.disabled = editor.history.is_empty()
	redo_btn.disabled = editor.future.is_empty()
	bar.title = "SHIP FACTORY — %d×%d" % [editor.grid_size, editor.grid_size]
	if current_tab in ["Stats", "Telemetry", "Engines", "Hardpoints", "Paint", "Modules"]:
		_rebuild_panel()


func _show_tab(t: String) -> void:
	if not TABS.has(t):
		t = "Paint"
	current_tab = t
	AppState.settings["factory_tab"] = t
	for k in tab_buttons:
		tab_buttons[k].button_pressed = k == t
	if t == "Engines" and editor.tool == "hardpoint" or t == "Hardpoints" and editor.tool == "thruster":
		editor.tool = "paint"
	canvas.show_thrusters = true
	_rebuild_panel()


func _rebuild_panel() -> void:
	for ch in panel_host.get_children():
		ch.queue_free()
	match current_tab:
		"Paint": _panel_paint()
		"Hull": _panel_hull()
		"Engines": _panel_engines()
		"Hardpoints": _panel_hardpoints()
		"Stats": _panel_stats()
		"Modules": _panel_modules()
		"Telemetry": _panel_telemetry()
		"Library": _panel_library()
		"Test": _panel_test()


func _h(text: String) -> void:
	panel_host.add_child(Win95.label(text, 16, Win95.NAVY, true))


func _note(text: String) -> void:
	var l := Win95.label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel_host.add_child(l)


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	panel_host.add_child(f)
	return f


func _btn(host: Container, text: String, cb: Callable, w := 150.0) -> Button:
	var b := Win95.button(text, 44)
	b.custom_minimum_size.x = w
	b.pressed.connect(cb)
	host.add_child(b)
	return b


# ------------------------------------------------------------------ Paint

func _panel_paint() -> void:
	_h("Palette")
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	panel_host.add_child(grid)
	var pal := FactoryEditor.full_palette()
	for i in editor.visible_palette_indices():
		grid.add_child(_swatch(pal[i], i))
	var bp_total: int = Campaign.data()["paletteUnlocks"].size() * 2
	_note("%d of %d colours. Unlock the rest with fabrication salvage in Library." % [editor.visible_palette_indices().size(), 32 + bp_total] if editor.visible_palette_indices().size() < 32 + bp_total else "All 48 colours unlocked.")
	_h("Recent")
	var rec := HFlowContainer.new()
	panel_host.add_child(rec)
	if editor.recent.is_empty():
		rec.add_child(Win95.label("Colours you use appear here", 13, Win95.SHADOW))
	for i in editor.recent:
		if editor.visible_palette_indices().has(i):
			rec.add_child(_swatch(pal[i], i))
	var f := _flow()
	_btn(f, "Replace All", _replace_dialog.bind(false))
	_btn(f, "Swap Colors", _replace_dialog.bind(true))
	_btn(f, "Clear Hull", func():
		Win95.popup(self, "Clear Hull", "Erase every pixel? Undo is available.", [["Clear", func(): editor.clear()], ["Cancel", func(): pass]]))
	if _precision:
		_h("Precision Pad")
		_note("Drag inside the pad to move the yellow cursor one cell at a time. Dab paints that cell; hold \"Hold to Draw\" or turn on Auto Draw to paint while moving (uses the current tool, so Eraser erases).")
		var pad := PrecisionPad.new()
		pad.factory = self
		panel_host.add_child(pad)
		var pf := _flow()
		_btn(pf, "Dab", func():
			editor.push_history()
			editor.paint(canvas.cursor.x, canvas.cursor.y)
			_refresh(), 100)
		var hold := HoldButton.new()
		hold.text = "Hold to Draw"
		hold.custom_minimum_size = Vector2(130, 44)
		hold.held.connect(func(on):
			pad_hold = on
			if on:
				editor.push_history()
				editor.paint(canvas.cursor.x, canvas.cursor.y))
		pf.add_child(hold)
		var auto := _btn(pf, "Auto %s: %s" % ["Erase" if editor.tool == "erase" else "Draw", "ON" if pad_auto else "OFF"], func():
			pad_auto = not pad_auto
			if pad_auto:
				editor.push_history()
			_rebuild_panel(), 150)
		auto.toggle_mode = true
		auto.button_pressed = pad_auto
		var fine := _btn(pf, "Fine: %s" % ("ON" if pad_fine else "OFF"), func():
			pad_fine = not pad_fine
			_rebuild_panel(), 100)
		fine.toggle_mode = true
		fine.button_pressed = pad_fine
		_btn(pf, "Centre", func(): canvas.cursor = Vector2i(editor.grid_size / 2, editor.grid_size / 2), 100)
		_btn(pf, "Close Pad", _toggle_precision, 110)
		var sp := HBoxContainer.new()
		sp.add_child(Win95.label("Speed", 14, Win95.TEXT, true))
		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = 3
		slider.step = 0.5
		slider.value = pad_speed
		slider.custom_minimum_size = Vector2(180, 32)
		slider.value_changed.connect(func(v): pad_speed = v)
		sp.add_child(slider)
		panel_host.add_child(sp)


func _swatch(hex: String, idx: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(38, 38)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.html(hex)
	var sel: bool = (editor.color is int or editor.color is float) and int(editor.color) == idx
	sb.border_color = Color("#0000ff") if sel else Win95.DARK
	sb.set_border_width_all(4 if sel else 1)
	for k in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(k, sb)
	b.tooltip_text = hex
	b.pressed.connect(func():
		editor.select_color(idx)
		if editor.tool in ["erase", "pick", "thruster", "hardpoint"]:
			editor.tool = "paint"
		_refresh())
	return b


func _color_icon(v) -> ImageTexture:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color.html(FactoryEditor.cell_hex(v)))
	return ImageTexture.create_from_image(img)


func _replace_dialog(swap: bool) -> void:
	var hull := editor.distinct_colors()
	if hull.is_empty():
		Win95.popup(self, "Color Tools", "Draw or load a hull before using color replacement.", [["OK", func(): pass]])
		return
	var box := VBoxContainer.new()
	box.add_child(Win95.label("From colour", 15))
	var from := OptionButton.new()
	for v in hull:
		from.add_icon_item(_color_icon(v), FactoryEditor.cell_hex(v))
	box.add_child(from)
	box.add_child(Win95.label("Second colour" if swap else "New colour", 15))
	var to := OptionButton.new()
	var to_vals := hull if swap else editor.visible_palette_indices()
	for v in to_vals:
		to.add_icon_item(_color_icon(v), FactoryEditor.cell_hex(v))
	box.add_child(to)
	Win95.popup(self, "Swap Hull Colors" if swap else "Replace Hull Color",
		"Exchange every occurrence of two colours." if swap else "Replace every occurrence of one hull colour with another.", [
		["Swap Colors" if swap else "Replace All", func():
			var a = hull[from.selected]
			var b = to_vals[to.selected]
			var n := editor.swap_colors(a, b) if swap else editor.replace_color(a, b)
			status.text = "%s %d hull pixels. Undo is available." % ["Swapped" if swap else "Replaced", n]],
		["Cancel", func(): pass]], box)


# ------------------------------------------------------------------ Hull

func _panel_hull() -> void:
	_h("Canvas")
	_note("48×48 is recommended: it matches the starter hulls. 32×32 and 24×24 give chunkier sprites.")
	var sizes := OptionButton.new()
	for s in FactoryEditor.SIZES:
		sizes.add_item("%d×%d" % [s, s])
	sizes.select(FactoryEditor.SIZES.find(editor.grid_size))
	panel_host.add_child(sizes)
	var f := _flow()
	_btn(f, "New Blank Hull", func():
		var size: int = FactoryEditor.SIZES[sizes.selected]
		if editor.is_empty():
			editor.new_blank(size)
		else:
			Win95.popup(self, "New Blank Hull", "Replace the current artwork with a blank %d×%d hull? Undo is available." % [size, size], [["Create Blank Hull", func(): editor.new_blank(size)], ["Cancel", func(): pass]]))
	_btn(f, "Resize Artwork", func():
		var size: int = FactoryEditor.SIZES[sizes.selected]
		if size == editor.grid_size:
			Win95.popup(self, "Canvas Size", "The current hull already uses %d×%d." % [size, size], [["OK", func(): pass]])
		else:
			Win95.popup(self, "Resize Current Artwork", "Resize the %d×%d sprite to %d×%d using nearest-neighbour scaling? Pixel shapes and mount coordinates may shift slightly." % [editor.grid_size, editor.grid_size, size, size], [["Resize Artwork", func(): editor.resize_canvas(size); canvas.set_zoom(1.0)], ["Cancel", func(): pass]]))
	_btn(f, "Next Preset", func(): editor.apply_preset(FactoryEditor.SIZES[sizes.selected]))
	_btn(f, "Auto-Clean", _auto_clean)
	_h("Starter Hull Templates")
	_note("Editable 48×48 ships. Loading a template does not overwrite a saved ship until you press Save Ship.")
	var sf := _flow()
	for id in DataStore.starter_hulls()["order"]:
		var h := DataStore.starter_hull(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(112, 112)
		b.icon = _cropped(load(h["art"]))
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = h["name"]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func():
			editor.load_starter(id)
			status.text = "%s loaded as editable 48×48 artwork. Stats and modules are starting recommendations." % h["name"])
		sf.add_child(b)
	_h("Fabrication Stencils")
	var st := _flow()
	for key in Campaign.data()["stencils"]:
		var def: Dictionary = Campaign.data()["stencils"][key]
		var owned: bool = editor.unlocked.get(key, false)
		var b := _btn(st, ("Load " if owned else "") + def["name"], func(): editor.apply_stencil(key), 220)
		b.disabled = not owned
		if not owned:
			b.tooltip_text = "Unlock in Library with salvage"
	if not _any_stencil():
		_note("Stencils unlock in Library → Fabrication Salvage (requires a campaign).")


func _any_stencil() -> bool:
	for key in Campaign.data()["stencils"]:
		if editor.unlocked.get(key, false):
			return true
	return false


func _cropped(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(img.get_used_rect().grow(1)).intersection(Rect2(0, 0, img.get_width(), img.get_height()))
	return at


func _auto_clean() -> void:
	if editor.is_empty():
		Win95.popup(self, "Auto-Clean Ship", "Draw or load a ship before running Auto-Clean.", [["OK", func(): pass]])
		return
	var box := VBoxContainer.new()
	box.add_child(Win95.label("Auto-Clean uses pixel rules, not generative AI. Review the result before applying it.", 13))
	var mode := OptionButton.new()
	for t in ["Conservative — obvious defects only", "Symmetry Repair", "Aggressive Cleanup"]:
		mode.add_item(t)
	box.add_child(mode)
	var sym := OptionButton.new()
	for t in ["Merge missing pixels", "Use left half", "Use right half"]:
		sym.add_item(t)
	box.add_child(sym)
	var row := HBoxContainer.new()
	box.add_child(row)
	var before := TextureRect.new()
	var after := TextureRect.new()
	for tr in [before, after]:
		tr.custom_minimum_size = Vector2(150, 150)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Win95.WELL, 3, 3))
		p.add_child(tr)
		row.add_child(p)
	before.texture = editor.texture()
	var summary := Win95.label("", 13, Win95.TEXT, true)
	box.add_child(summary)
	var preview := {}
	var modes := ["conservative", "symmetry", "aggressive"]
	var syms := ["merge", "left", "right"]
	var refresh := func():
		preview = editor.repair_preview(modes[mode.selected], syms[sym.selected])
		sym.disabled = mode.selected == 0
		var tmp := FactoryEditor.new()
		tmp.grid_size = editor.grid_size
		tmp.grid = preview["grid"]
		after.texture = tmp.texture()
		summary.text = "%d pixels would change." % preview["changed"]
	mode.item_selected.connect(func(_i): refresh.call())
	sym.item_selected.connect(func(_i): refresh.call())
	refresh.call()
	Win95.popup(self, "Auto-Clean Ship", "", [
		["Apply Repair", func():
			var moved := editor.apply_repair(preview["grid"])
			status.text = "Auto-Clean changed %d pixels%s. Undo is available." % [preview["changed"], " and realigned %d mounts" % moved if moved else ""]],
		["Cancel", func(): pass]], box)


# ------------------------------------------------------------------ Engines / Hardpoints

func _panel_engines() -> void:
	_h("Thruster Mounts")
	_note("The centre engine is always active. Side engines cost 2 mount points each (budget %d): +14%% thrust and +8%% fuel use each." % FactoryEditor.MOUNT_BUDGET)
	var f := _flow()
	for id in ["center", "left", "right"]:
		var b := _btn(f, id.capitalize(), func():
			editor.selected_thruster = id
			_refresh(), 100)
		b.toggle_mode = true
		b.button_pressed = editor.selected_thruster == id
	var t := editor.mount("thruster", editor.selected_thruster)
	var g := _flow()
	var tb := _btn(g, "Always Active" if t["id"] == "center" else ("Remove (-2)" if t["enabled"] else "Buy (+2)"), func():
		if not editor.toggle_thruster(t["id"]):
			Win95.popup(self, "Mount Budget", "Both optional engine mounts already consume the available mount budget.", [["OK", func(): pass]]), 160)
	tb.disabled = t["id"] == "center"
	var place := _btn(g, "Place Exhaust", func():
		if t["id"] != "center" and not t["enabled"]:
			Win95.popup(self, "Thruster Mount", "Purchase that engine before placing its exhaust marker.", [["OK", func(): pass]])
			return
		editor.tool = "thruster"
		status.text = "Tap the exact %s exhaust nozzle on the sprite." % t["id"]
		_refresh(), 160)
	place.toggle_mode = true
	place.button_pressed = editor.tool == "thruster"
	_note("%s exhaust at %d,%d — %s. Mount use %d/%d." % [str(t["id"]).capitalize(), t["x"], t["y"], "active" if t["id"] == "center" or t["enabled"] else "not purchased", editor.mount_cost(), FactoryEditor.MOUNT_BUDGET])


func _panel_hardpoints() -> void:
	_h("Hardpoints")
	_note("Shots and effects come from these hull positions (primary weapon, secondary weapon, defence emitter, utility module).")
	var f := _flow()
	for id in ["primary", "secondary", "defense", "utility"]:
		var b := _btn(f, id.capitalize(), func():
			editor.selected_hardpoint = id
			_refresh(), 110)
		b.toggle_mode = true
		b.button_pressed = editor.selected_hardpoint == id
	var h := editor.mount("hardpoint", editor.selected_hardpoint)
	var g := _flow()
	var place := _btn(g, "Place Hardpoint", func():
		editor.tool = "hardpoint"
		status.text = "Tap the hull grid to place the %s hardpoint." % editor.selected_hardpoint
		_refresh(), 170)
	place.toggle_mode = true
	place.button_pressed = editor.tool == "hardpoint"
	var ov := _btn(g, "Overlays: %s" % ("ON" if canvas.show_hardpoints else "OFF"), func():
		canvas.show_hardpoints = not canvas.show_hardpoints
		canvas.show_thrusters = canvas.show_hardpoints
		_rebuild_panel(), 150)
	ov.toggle_mode = true
	ov.button_pressed = canvas.show_hardpoints
	_note("%s hardpoint at %d,%d." % [str(h["id"]).capitalize(), h["x"], h["y"]])


# ------------------------------------------------------------------ Stats / Modules / Telemetry

func _panel_stats() -> void:
	var used := editor.stat_sum()
	_h("Engineering: stats %d/%d · mounts %d/%d" % [used, FactoryEditor.STAT_BUDGET, editor.mount_cost(), FactoryEditor.MOUNT_BUDGET])
	_note("Each stat can reach %d in the factory. Campaign tuning, components and rare technology push effective performance further." % FactoryEditor.STAT_CAP)
	var labels: Dictionary = DataStore.engineering()["statLabels"]
	for k in DataStore.stat_order():
		var row := HBoxContainer.new()
		panel_host.add_child(row)
		var l := Win95.label(labels[k], 14, Win95.TEXT, true)
		l.custom_minimum_size.x = 150
		l.clip_text = true
		row.add_child(l)
		var minus := Win95.button("−", 38)
		minus.custom_minimum_size.x = 44
		minus.pressed.connect(func(): editor.change_stat(k, -1))
		row.add_child(minus)
		var meter := Meter.new()
		meter.frac = float(editor.stats[k]) / FactoryEditor.STAT_CAP
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(meter)
		row.add_child(Win95.label(" %d " % editor.stats[k], 15, Win95.TEXT, true))
		var plus := Win95.button("+", 38)
		plus.custom_minimum_size.x = 44
		plus.pressed.connect(func():
			if not editor.change_stat(k, 1):
				Sfx.beep(150, 0.08))
		row.add_child(plus)
	_h("Archetypes")
	var arch := OptionButton.new()
	var ids: Array = DataStore.engineering()["archetypes"].keys()
	for id in ids:
		arch.add_item(DataStore.engineering()["archetypes"][id]["name"])
	panel_host.add_child(arch)
	var f := _flow()
	_btn(f, "Apply Archetype", func(): editor.apply_archetype(ids[arch.selected]), 170)
	_btn(f, "Reset Balanced", func(): editor.apply_archetype("balanced"), 170)


func _panel_modules() -> void:
	_h("Modules")
	var mods := DataStore.modules()
	for slot in mods:
		panel_host.add_child(Win95.label(slot.capitalize(), 14, Win95.TEXT, true))
		var o := OptionButton.new()
		var keys: Array = mods[slot].keys()
		for k in keys:
			o.add_item("%s — %d mass / %d power" % [mods[slot][k]["name"], mods[slot][k]["mass"], mods[slot][k]["power"]])
		o.select(keys.find(editor.modules[slot]))
		o.item_selected.connect(func(i): editor.set_module(slot, keys[i]))
		panel_host.add_child(o)
		var d := Win95.label(mods[slot][editor.modules[slot]]["desc"], 12, Win95.SHADOW)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel_host.add_child(d)


func _panel_telemetry() -> void:
	var p := editor.performance()
	var prev := ShipPreview.new()
	prev.editor = editor
	panel_host.add_child(prev)
	var cards := [[str(roundi(p.mass)), "Calculated mass"], ["%d/%d" % [roundi(p.capacity), roundi(p.demand)], "Reactor capacity / demand"],
		[str(roundi(p.maxSpeed)), "Maximum speed"], ["%.1f/s²" % p.acceleration, "Effective acceleration"],
		["%.1f%%/s" % (p.passiveLoss * 100), "Passive speed loss"], ["%.2f s" % (PI / p.turnRate), "Time to rotate 180°"],
		[str(roundi(p.maxHull)), "Maximum hull"], [str(roundi(p.maxFuel)), "Fuel capacity"], ["%d s" % roundi(p.fuelSeconds), "Full-thrust endurance"],
		["%.1f" % p.damage, "Primary damage"], ["%.1f/s" % (1.0 / p.fireInterval), "Maximum fire rate"], ["%.1f/s" % p.cooling, "Weapon cooling"]]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	panel_host.add_child(grid)
	for c in cards:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Win95.FIELD, 6, 4))
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(Win95.label(c[0], 16, Win95.NAVY, true))
		var cl := Win95.label(c[1], 11, Win95.SHADOW)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(cl)
		pc.add_child(v)
		grid.add_child(pc)
	var w := editor.warnings()
	panel_host.add_child(Win95.field(("Design warnings\n• " + "\n• ".join(w)) if not w.is_empty() else "Design stable — mass, power and mount allocation are within recommended limits.", 13))


# ------------------------------------------------------------------ Library

func _panel_library() -> void:
	_h("Ship")
	name_edit = LineEdit.new()
	name_edit.text = editor.name
	name_edit.max_length = 28
	name_edit.custom_minimum_size.y = 44
	name_edit.text_changed.connect(func(t): editor.name = t; _draft_timer.start())
	panel_host.add_child(name_edit)
	var f := _flow()
	_btn(f, "Save Ship", _save_ship)
	_btn(f, "Duplicate", func():
		editor.push_history()
		editor.selected_id = ""
		editor.name = editor.name + " Copy"
		_rebuild_panel())
	_btn(f, "Delete", _delete_ship)
	_btn(f, "Export (Clipboard)", func():
		DisplayServer.clipboard_set(JSON.stringify(editor.ship_data(), "  "))
		status.text = "Ship JSON copied to the clipboard.", 190)
	_btn(f, "Import (Clipboard)", _import_ship, 190)
	if _campaign:
		_btn(f, "Use in Current Operation", _assign_to_campaign, 230)
	_h("Saved Ships")
	var ships := SaveService.custom_ships()
	if ships.is_empty():
		_note("No custom ships saved.")
	for s in ships:
		var p := ShipPerformance.compute(s)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.icon = Campaign.ship_texture(s)
		b.expand_icon = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s\nSpeed %d · Mass %d · Power %d/%d" % [s.get("name", "Ship"), "  (editing)" if s.get("id") == editor.selected_id else "", roundi(p.maxSpeed), roundi(p.mass), roundi(p.demand), roundi(p.capacity)]
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			editor.load_ship(s)
			_rebuild_panel())
		panel_host.add_child(b)
	_h("Fabrication Salvage")
	if _campaign == null:
		_note("Start or continue an operation to recover salvage. Missions and discoveries unlock palettes and hull stencils for that save.")
		return
	var sv: Dictionary = _campaign["salvage"]
	_note("%d alloy • %d circuitry • %d data cores" % [sv["alloy"], sv["circuitry"], sv["data"]])
	var cd := Campaign.data()
	var uf := _flow()
	for key in cd["paletteUnlocks"]:
		var def: Dictionary = cd["paletteUnlocks"][key]
		var owned: bool = _campaign["blueprints"].get(key, false)
		var b := _btn(uf, "%s\n%s" % [def["name"], "UNLOCKED" if owned else _cost_text(def["cost"])], _buy_blueprint.bind(key, def["cost"]), 200)
		b.disabled = owned
		b.custom_minimum_size.y = 56
		b.add_theme_font_size_override("font_size", 12)
	for key in cd["stencils"]:
		var def: Dictionary = cd["stencils"][key]
		var owned: bool = _campaign["blueprints"].get(key, false)
		var b := _btn(uf, "%s\n%s" % [def["name"], "LOAD HULL" if owned else _cost_text(def["cost"])],
			(func(): editor.apply_stencil(key)) if owned else _buy_blueprint.bind(key, def["cost"]), 200)
		b.custom_minimum_size.y = 56
		b.add_theme_font_size_override("font_size", 12)


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [cost[k], k])
	return " / ".join(parts)


func _buy_blueprint(key: String, cost: Dictionary) -> void:
	for k in cost:
		if int(_campaign["salvage"].get(k, 0)) < int(cost[k]):
			Win95.popup(self, "Insufficient Salvage", "Requires %s." % _cost_text(cost), [["OK", func(): pass]])
			return
	for k in cost:
		_campaign["salvage"][k] -= int(cost[k])
	_campaign["blueprints"][key] = true
	SaveService.save_campaign(_campaign)
	editor.unlocked = _campaign["blueprints"]
	Sfx.beep(880, 0.1)
	_rebuild_panel()


func _save_ship() -> void:
	var err := editor.validate()
	if err != "":
		Win95.popup(self, "Engineering Error", err, [["OK", func(): pass]])
		return
	var s := editor.ship_data()
	var ships := SaveService.custom_ships()
	var found := false
	for i in ships.size():
		if ships[i].get("id") == s["id"]:
			ships[i] = s
			found = true
	if not found:
		ships.append(s)
	editor.selected_id = s["id"]
	SaveService.save_custom_ships(ships)
	_save_draft()
	Sfx.beep(660, 0.1)
	Win95.popup(self, "Ship Factory", "%s was saved with ten stats, five modules and editable engine mounts." % s["name"], [["OK", func(): _rebuild_panel()]])


func _delete_ship() -> void:
	if editor.selected_id == "":
		Win95.popup(self, "Ship Factory", "Select a saved custom ship first.", [["OK", func(): pass]])
		return
	Win95.popup(self, "Delete Ship", "Delete %s from the library?" % editor.name, [["Delete", func():
		SaveService.save_custom_ships(SaveService.custom_ships().filter(func(x): return x.get("id") != editor.selected_id))
		editor.selected_id = ""
		_rebuild_panel()], ["Cancel", func(): pass]])


func _import_ship() -> void:
	var v = JSON.parse_string(DisplayServer.clipboard_get().strip_edges())
	if not (v is Dictionary) or not (v.get("grid") is Array) or not (v.get("stats") is Dictionary):
		Win95.popup(self, "Import Failed", "The clipboard does not contain a valid ship JSON.", [["OK", func(): pass]])
		return
	var n := int(round(sqrt((v["grid"] as Array).size())))
	if n * n != v["grid"].size() or n < 16 or n > 64:
		Win95.popup(self, "Import Failed", "The ship grid is not a square between 16 and 64 pixels.", [["OK", func(): pass]])
		return
	v["gridSize"] = n
	v["id"] = "custom_%d" % int(Time.get_unix_time_from_system() * 1000)
	v["custom"] = true
	var ships := SaveService.custom_ships()
	ships.append(v)
	SaveService.save_custom_ships(ships)
	editor.load_ship(v)
	Win95.popup(self, "Import Complete", "Imported %s and migrated its statistics." % v.get("name", "custom ship"), [["OK", func(): _rebuild_panel()]])


## Port addition: put the current design into the saved operation (legacy only allowed
## custom ships when starting a new campaign).
func _assign_to_campaign() -> void:
	var err := editor.validate()
	if err != "":
		Win95.popup(self, "Engineering Error", err, [["OK", func(): pass]])
		return
	Win95.popup(self, "Use in Current Operation", "Fly %s in your saved operation? Campaign upgrades and components stay installed." % editor.name, [["Assign Ship", func():
		var s := editor.ship_data()
		_campaign["ship"] = Campaign.normalize_ship(s)
		_campaign["shipId"] = s["id"]
		SaveService.save_campaign(_campaign)
		status.text = "%s assigned to the current operation." % editor.name], ["Cancel", func(): pass]])


# ------------------------------------------------------------------ Test

func _panel_test() -> void:
	_h("Test Flight")
	_note("Fly this design on the factory test range with a stationary and a moving target. Telemetry records peak speed, time to 90% speed, shots and duration.")
	for spec in [["infinite", "Infinite fuel and missiles"], ["moving", "Moving target"]]:
		var cb := CheckBox.new()
		cb.text = spec[1]
		cb.button_pressed = test_options[spec[0]]
		var key: String = spec[0]
		cb.toggled.connect(func(on): test_options[key] = on)
		cb.add_theme_font_size_override("font_size", 16)
		panel_host.add_child(cb)
	var f := _flow()
	_btn(f, "Start Test Flight", _test_flight, 220)


func _test_flight() -> void:
	var err := editor.validate()
	if err != "":
		Win95.popup(self, "Test Flight", "Build a non-empty hull within the stat and mount budgets.\n\n" + err, [["OK", func(): pass]])
		return
	_save_draft()
	AppState.launch = {"mode": "test", "threat": 1, "ship": editor.ship_data(), "return": "factory", "test_options": test_options.duplicate()}
	get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")


func _back() -> void:
	_save_draft()
	AppState.save_settings()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


## Gamepad editing (Retroid Pocket 5): Y toggles the precision cursor; with it on, the
## D-pad / left stick moves the cursor and A paints; LB/RB switch tabs; LT/RT zoom; B backs
## out of precision mode first, then the Factory.
func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or _popup_open():
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y:
				_toggle_precision()
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				var i := (TABS.find(current_tab) + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1) + TABS.size()) % TABS.size()
				_show_tab(TABS[i])
			JOY_BUTTON_B:
				if _precision:
					_toggle_precision()
				else:
					_back()
			JOY_BUTTON_A:
				if not _precision:
					return
				editor.push_history()
				editor.paint(canvas.cursor.x, canvas.cursor.y)
				_refresh()
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
				if not _precision:
					return
				var d: Vector2i = {JOY_BUTTON_DPAD_LEFT: Vector2i(-1, 0), JOY_BUTTON_DPAD_RIGHT: Vector2i(1, 0), JOY_BUTTON_DPAD_UP: Vector2i(0, -1), JOY_BUTTON_DPAD_DOWN: Vector2i(0, 1)}[event.button_index]
				_move_cursor(d)
				if Input.is_joy_button_pressed(event.device, JOY_BUTTON_A):
					editor.paint(canvas.cursor.x, canvas.cursor.y)
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		if event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.6:
			canvas.set_zoom(canvas.zoom * (1.1 if event.axis == JOY_AXIS_TRIGGER_RIGHT else 1 / 1.1))
			get_viewport().set_input_as_handled()
		elif _precision and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			get_viewport().set_input_as_handled()   # stick moves the cursor in _process


var _stick_acc := Vector2.ZERO


func _process(dt: float) -> void:
	if not _precision:
		return
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if v.length() < 0.35:
		_stick_acc = Vector2.ZERO
		return
	_stick_acc += v * dt * 14.0
	var step := Vector2i(int(_stick_acc.x), int(_stick_acc.y))
	if step != Vector2i.ZERO:
		_stick_acc -= Vector2(step)
		_move_cursor(step)
		if Input.is_joy_button_pressed(0, JOY_BUTTON_A):
			editor.paint(canvas.cursor.x, canvas.cursor.y)


func _move_cursor(d: Vector2i) -> void:
	var n := editor.grid_size
	canvas.cursor = Vector2i(clampi(canvas.cursor.x + d.x, 0, n - 1), clampi(canvas.cursor.y + d.y, 0, n - 1))


func _unhandled_input(event: InputEvent) -> void:
	if _gamepad_back(event):
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Z:
			editor.redo() if event.shift_pressed else editor.undo()
		elif event.keycode == KEY_Y:
			editor.redo()


class Meter:
	extends Control
	var frac := 0.5

	func _init() -> void:
		custom_minimum_size = Vector2(60, 22)

	func _draw() -> void:
		Win95.progress(self, Rect2(Vector2(0, 4), Vector2(size.x, size.y - 8)), frac, Win95.NAVY)


## Live ship preview with stats summary (legacy drawPreview v6).
class ShipPreview:
	extends Control
	var editor: FactoryEditor
	var _tex: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(0, 150)

	func _ready() -> void:
		_tex = editor.texture()

	func _draw() -> void:
		Win95.bevel(self, Rect2(Vector2.ZERO, size), "sunken", Color("#050713"))
		for i in 38:
			draw_rect(Rect2(fmod(i * 83.0, size.x), fmod(i * 47.0, size.y), 2 if i % 8 == 0 else 1, 2 if i % 8 == 0 else 1), Color(0.7, 0.88, 1, 0.25 + (i % 5) * 0.1))
		var c := Vector2(76, size.y * 0.53)
		var d := minf(108, size.y * 0.8)
		draw_set_transform(c, editor.rotation * PI / 2, Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-d / 2, -d / 2, d, d), false)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var p := editor.performance()
		var tx := 150.0
		var s := editor.stats
		Win95.text(self, Vector2(tx, 22), editor.name, 16, Color.WHITE, true, size.x - tx - 6)
		Win95.text(self, Vector2(tx, 44), "ACC %d  MAX %d  INERT %d" % [s.acceleration, s.maxSpeed, s.inertia], 12, Color.WHITE)
		Win95.text(self, Vector2(tx, 62), "TURN %d  HULL %d  FCAP %d" % [s.turn, s.hull, s.fuelCapacity], 12, Color.WHITE)
		Win95.text(self, Vector2(tx, 80), "FEFF %d  WPN %d  COOL %d" % [s.fuelEfficiency, s.weaponPower, s.weaponCooling], 12, Color.WHITE)
		Win95.text(self, Vector2(tx, 98), "REACT %d  MASS %d" % [s.reactor, roundi(p.mass)], 12, Color.WHITE)
		Win95.text(self, Vector2(tx, 118), "POWER %d/%d" % [roundi(p.demand), roundi(p.capacity)], 12, Color.WHITE)
		Win95.text(self, Vector2(tx, 138), "REACTOR OVERLOAD" if p.demand > p.capacity else "SYSTEMS NOMINAL", 12, Color("#ff7373") if p.demand > p.capacity else Color("#77ff9a"), true)


## Precision pad (legacy v6.2): a trackpad that nudges the canvas cursor one cell per
## ~8 px of finger travel; Dab paints the cursor cell.
class PrecisionPad:
	extends Control
	var factory
	var _acc := Vector2.ZERO

	func _init() -> void:
		custom_minimum_size = Vector2(0, 150)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		var rel := Vector2.ZERO
		if event is InputEventScreenDrag:
			rel = event.relative
		elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
			rel = event.relative
		if rel == Vector2.ZERO:
			return
		_acc += rel * factory.pad_speed * (0.42 if factory.pad_fine else 1.0)
		var n: int = factory.editor.grid_size
		var paint: bool = factory.pad_auto or factory.pad_hold
		while absf(_acc.x) >= 8 or absf(_acc.y) >= 8:
			var step := Vector2i(int(signf(_acc.x)) if absf(_acc.x) >= 8 else 0, int(signf(_acc.y)) if absf(_acc.y) >= 8 else 0)
			_acc -= Vector2(step) * 8
			var c: Vector2i = factory.canvas.cursor + step
			factory.canvas.cursor = Vector2i(clampi(c.x, 0, n - 1), clampi(c.y, 0, n - 1))
			if paint:
				factory.editor.paint(factory.canvas.cursor.x, factory.canvas.cursor.y)
		accept_event()

	func _draw() -> void:
		Win95.bevel(self, Rect2(Vector2.ZERO, size), "sunken", Color("#1a2333"))
		var c: Vector2i = factory.canvas.cursor
		var t := "Cursor %d,%d — drag here" % [c.x + 1, c.y + 1]
		Win95.text(self, size / 2 - Vector2(Win95.text_width(t, 14) / 2, -5), t, 14, Color("#cfe8ff"))

	func _process(_dt: float) -> void:
		queue_redraw()


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


## Button that reports press and release (legacy "Hold to Draw"), touch or mouse.
class HoldButton:
	extends Button
	signal held(on: bool)

	func _init() -> void:
		button_down.connect(func(): held.emit(true))
		button_up.connect(func(): held.emit(false))
