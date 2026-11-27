extends Control
## Title screen (legacy layout): New Operation, Continue Saved Game, Ship Factory, Free
## Flight, Manual / Controls, Options / Reset.

const MANUAL := """[b]Goal[/b]
Fly through the machine's directories, recover clean icons and complete each directory's objective, then leave through the exit gate. Clear directories to earn credits and fabrication salvage. Recover four Noble Programs from dragon black holes to unlock the Inner Demon stronghold.

[b]Flight[/b]
←/→ turn, ↑ thrust, Space fire, X missile, A ambulance, M tactical map, Esc pause, +/- zoom. There is no brake: turn around and counter-thrust. Inertia Stabilization controls how quickly you lose speed while coasting. Gamepad: stick/d-pad turn, A thrust, X/RB fire, Y/LB missile, Start pause, Back map.
On touch screens turning is on the left, thrust/fire/missile on the right. Tap the radar for the tactical map; drag the radar by its title bar or minimise it.

[b]Directories[/b]
ICON RECOVERY — collect loose icons, avoid infected (crossed) ones.
PROGRAM RESCUE — fly close to stranded programs to release them.
SYSTEM REPAIR — hold position near damaged nodes until repaired.
DIRECTORY RACE — clear every checkpoint in order.
COURIER ESCORT — link with the courier and lead it to the terminal.
DRAGON BLACK HOLE — recover the icons, then enter the black hole for a Noble Program.
INFECTION SCAN — hold near each hidden signature until resolved.
LOCKED DUEL — destroy every hostile duelist.
DEFRAGMENTATION — touch the numbered fragments in order.
INNER DEMON — the final stronghold (needs four Noble Programs).

[b]Factions and the law[/b]
Pirates and Predators attack everyone. Shooting neutral ships makes them retaliate and lowers relations. Destroying a clean icon is a crime: build up a warrant and Enforcers arrive. The ambulance can clear warrants for credits.

[b]Strategy mode[/b]
Your ship flies itself. Choose a priority: Collect, Attack, Evade or Exit."""


func _ready() -> void:
	var buttons := [["sound", _toggle_sound]]
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		buttons.append(["fullscreen", AppState.toggle_fullscreen])
	if not OS.has_feature("web"):
		buttons.append(["close", func(): get_tree().quit()])
	var col := Win95.desktop(self, "SYSTEM FRONTIER", buttons, 640)
	col.add_child(Banner.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	var first := _btn(grid, "New Operation", func(): _go("res://scenes/setup/setup.tscn"))
	var cont := _btn(grid, "Continue Saved Game", _continue)
	cont.disabled = not SaveService.has_campaign()
	var factory := _btn(grid, "Ship Factory\n(coming soon)", func(): pass)
	factory.disabled = true
	_btn(grid, "Free Flight", func(): _go("res://scenes/free_flight/free_flight.tscn"))
	_btn(grid, "Manual / Controls", _manual)
	_btn(grid, "Options / Reset", _options)
	col.add_child(Win95.field("A from-scratch tribute to the directory-crawling action/strategy games of the Windows 3.x/95 era. Build %s." % ProjectSettings.get_setting("application/config/version"), 14))
	(cont if not cont.disabled else first).grab_focus()


func _btn(grid: GridContainer, text: String, cb: Callable) -> Button:
	var b := Win95.button(text, 70)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(cb)
	grid.add_child(b)
	return b


func _go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)


func _toggle_sound() -> void:
	AppState.set_setting("sound", not AppState.settings["sound"])
	for b in find_children("*", "Button", true, false):
		b.queue_redraw()


func _continue() -> void:
	if SaveService.has_campaign():
		_go("res://scenes/directory_map/directory_map.tscn")
	else:
		Win95.popup(self, "Continue", "No valid saved operation was found.", [["OK", func(): pass]])


func _manual() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(460, get_viewport_rect().size.y - 220))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var field := PanelContainer.new()
	field.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Win95.FIELD, 10, 8))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(field)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = MANUAL
	rt.add_theme_color_override("default_color", Win95.TEXT)
	rt.add_theme_font_override("bold_font", Win95.bold_font())
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 15)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(rt)
	Win95.popup(self, "Manual / Controls", "", [["Close", func(): pass]], scroll)


func _options() -> void:
	Win95.popup(self, "Options / Reset", "Use these tools if you want a clean start, or to bring in a save exported from the old browser version (copy its JSON to the clipboard first).", [
		["Delete Campaign Progress", func(): _confirm("campaign")],
		["Delete Ship Factory Progress", func(): _confirm("factory")],
		["Delete ALL Progress", func(): _confirm("all")],
		["Import Legacy Save from Clipboard", _import],
		["Close", func(): pass],
	])


func _confirm(kind: String) -> void:
	var labels := {"campaign": "Delete campaign progress", "factory": "Delete Ship Factory progress", "all": "Delete ALL progress"}
	var details := {"campaign": "This deletes your saved campaign and disables Continue Saved Game.",
		"factory": "This deletes saved custom ships, the Ship Factory draft, and recent paint colors.",
		"all": "This deletes campaign progress plus Ship Factory saves, draft data, and recent paint colors."}
	Win95.popup(self, "Confirm Reset", "%s?\n\n%s" % [labels[kind], details[kind]], [
		[labels[kind], func():
			SaveService.reset(kind)
			get_tree().reload_current_scene()],
		["Cancel", _options],
	])


func _import() -> void:
	var kind := SaveService.import_legacy(DisplayServer.clipboard_get())
	var text: String = {"campaign": "Legacy campaign imported. Use Continue Saved Game.", "ships": "Legacy custom ships imported into the Ship Factory library."}.get(kind,
		"The clipboard does not contain a legacy campaign or ship-library JSON.")
	Win95.popup(self, "Import", text, [["OK", func(): get_tree().reload_current_scene() if kind != "" else null]])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


## Black sunken banner with the chunky cyan/purple title, as in the legacy title screen.
class Banner:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(0, 140)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		Win95.bevel(self, r, "sunken", Color("#070a1c"))
		for y in range(3, int(size.y) - 3, 3):
			draw_rect(Rect2(2, y, size.x - 4, 1), Color(1, 1, 1, 0.025))
		var title := "SYSTEM FRONTIER"
		var fs := int(clampf(size.x / 11.5, 22, 60))
		var tw := Win95.text_width(title, fs, true)
		var p := Vector2((size.x - tw) / 2, size.y * 0.48)
		for i in range(4, 0, -1):
			Win95.text(self, p + Vector2(i, i), title, fs, Color("#5a3fd0").lerp(Color("#2a1a70"), i / 4.0), true)
		Win95.text(self, p, title, fs, Color("#9ff3ff"), true)
		var subs := ["Disinfect the machine. Capture the icons.", "Build your own ship."]
		var ss := int(clampf(size.x / 30.0, 13, 19))
		for i in subs.size():
			var sw := Win95.text_width(subs[i], ss)
			Win95.text(self, Vector2((size.x - sw) / 2, size.y * 0.7 + i * (ss + 5)), subs[i], ss, Color.WHITE)
