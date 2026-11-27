extends Control
## New Operation Setup (legacy setup screen): pilot, drive profile, optional custom folder
## names, control mode, difficulty, faction, starting ship → builds the directory map.
## CUSTOM drives use typed folder names (legacy read selected filenames only, never file
## contents; typing names avoids storage permissions on Android).

var pilot: LineEdit
var drive: OptionButton
var custom_names: LineEdit
var mode: OptionButton
var difficulty: OptionButton
var team: OptionButton
var team_desc: Label
var ship: OptionButton
var ship_desc: Label
var ship_preview: TextureRect
var _ships: Array = []


func _ready() -> void:
	var col := Win95.desktop(self, "SYSTEM FRONTIER", [["close", _back]], 640)
	col.add_child(Win95.heading("New Operation Setup"))
	pilot = LineEdit.new()
	pilot.text = "Operator"
	pilot.max_length = 24
	_field(col, "Pilot name", pilot)
	drive = _options(col, "Drive profile", ["SYSTEM (virtual Windows drive)", "GAMES (virtual game library)", "ARCHIVE (virtual media drive)", "CUSTOM (your own folder names)"])
	custom_names = LineEdit.new()
	custom_names.placeholder_text = "e.g. MUSIC, PHOTOS, WORK, GAMES/DOOM"
	custom_names.visible = false
	col.add_child(custom_names)
	var hint := Win95.label("Folder names only name the directories; nothing on your device is read.", 13, Win95.SHADOW)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.visible = false
	col.add_child(hint)
	drive.item_selected.connect(func(i): custom_names.visible = i == 3; hint.visible = i == 3)
	mode = _options(col, "Control mode", ["Action — direct flight", "Strategy — command autopilot"])
	var diffs: Array = Campaign.data()["difficulties"]
	difficulty = _options(col, "Combat difficulty", diffs.map(func(d): return d["label"]))
	difficulty.select(1)
	var teams := []
	for f in DataStore.factions():
		if DataStore.factions()[f]["playable"]:
			teams.append(f)
	team = _options(col, "Faction", teams)
	team_desc = Win95.field("", 15).get_child(0)
	col.add_child(team_desc.get_parent())
	team.item_selected.connect(func(_i): _refresh_team())
	ship = _options(col, "Starting ship", [])
	var row := HBoxContainer.new()
	col.add_child(row)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Win95.WELL, 4, 4))
	well.custom_minimum_size = Vector2(96, 96)
	row.add_child(well)
	ship_preview = TextureRect.new()
	ship_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ship_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	well.add_child(ship_preview)
	var sd := Win95.field("", 14)
	sd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_desc = sd.get_child(0)
	row.add_child(sd)
	ship.item_selected.connect(func(_i): _refresh_ship())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(buttons)
	var cancel := Win95.button("Cancel", 52)
	cancel.custom_minimum_size.x = 130
	cancel.pressed.connect(_back)
	buttons.add_child(cancel)
	var go := Win95.button("Build Directory Map", 52)
	go.custom_minimum_size.x = 230
	go.pressed.connect(_build)
	buttons.add_child(go)
	_refresh_team()
	pilot.grab_focus()


func _field(col: VBoxContainer, label: String, ctrl: Control) -> void:
	col.add_child(Win95.label(label, 17))
	ctrl.custom_minimum_size.y = 46
	col.add_child(ctrl)


func _options(col: VBoxContainer, label: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.add_theme_font_size_override("font_size", 18)
	_field(col, label, o)
	return o


func _refresh_team() -> void:
	var t := team.get_item_text(team.selected)
	team_desc.text = DataStore.factions()[t]["desc"]
	_ships = Campaign.selectable_ships(t, SaveService.custom_ships())
	ship.clear()
	for s in _ships:
		ship.add_item(str(s.get("name", "Ship")))
	ship.select(0)
	_refresh_ship()


func _refresh_ship() -> void:
	var s: Dictionary = _ships[ship.selected]
	var p := ShipPerformance.compute(s)
	ship_desc.text = "%s\nSpeed %d · accel %.0f · hull %d · fuel %d · %s" % [s.get("desc", ""), roundi(p.maxSpeed), p.acceleration, roundi(p.maxHull), roundi(p.maxFuel),
		DataStore.modules()["primary"][p.mods.primary]["name"]]
	ship_preview.texture = Campaign.ship_texture(s)


func _build() -> void:
	var drives := ["SYSTEM", "GAMES", "ARCHIVE", "CUSTOM"]
	var names := []
	if drive.selected == 3:
		for n in custom_names.text.split(","):
			var t := n.strip_edges().to_upper().replace(" ", "_")
			if t != "":
				names.append(t + "/x")
		if names.is_empty():
			Win95.popup(self, "Custom drive", "Type at least one folder name, separated by commas.", [["OK", func(): pass]])
			return
	var opts := {
		"pilot": pilot.text, "team": team.get_item_text(team.selected), "ship": _ships[ship.selected],
		"mode": "strategy" if mode.selected == 1 else "action", "drive": drives[drive.selected], "custom_names": names,
		"difficulty": float(Campaign.data()["difficulties"][difficulty.selected]["value"]),
	}
	var proceed := func():
		SaveService.save_campaign(Campaign.create(opts))
		get_tree().change_scene_to_file("res://scenes/directory_map/directory_map.tscn")
	if SaveService.has_campaign():
		Win95.popup(self, "Replace saved operation?", "Starting a new operation replaces your current saved campaign.", [["Start new operation", proceed], ["Cancel", func(): pass]])
	else:
		proceed.call()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
