extends Control
## Directory map (legacy renderMap v6.4/v6.6): campaign summary, the drive's 12 directories
## with mission family, threat and environment, completion salvage preview, and the
## Upgrade Bay (tuning, components, rare technology) and faction relations.

var c: Dictionary
var _selected := -1
var _info: Label
var _summary: Label
var _enter: Button
var _list: VBoxContainer
var _progress: Control


func _ready() -> void:
	var loaded = SaveService.load_campaign()
	if loaded == null:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu/main_menu.tscn")
		return
	c = loaded
	var col := Win95.desktop(self, "SYSTEM FRONTIER — %s:\\" % c.get("drive", "SYSTEM"), [["close", _menu]], 760)
	col.add_child(Win95.heading("Directory Map"))
	var sf := Win95.field("", 14)
	_summary = sf.get_child(0)
	col.add_child(sf)
	_progress = Progress.new()
	col.add_child(_progress)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)
	var inf := Win95.field("Select a directory.", 14)
	_info = inf.get_child(0)
	col.add_child(inf)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	_enter = _btn(grid, "Enter Directory", _enter_dir)
	_enter.disabled = true
	_btn(grid, "Upgrade Bay", _upgrade_bay)
	_btn(grid, "Faction Relations", _relations)
	_btn(grid, "Ship Factory", func():
		SaveService.save_campaign(c)
		get_tree().change_scene_to_file("res://scenes/factory/factory.tscn"))
	_btn(grid, "Main Menu", _menu)
	_render()
	_focus_first.call_deferred()


func _btn(grid: GridContainer, text: String, cb: Callable) -> Button:
	var b := Win95.button(text, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	grid.add_child(b)
	return b


func _render() -> void:
	var up := 0
	for k in c["upgrades"]:
		up += int(c["upgrades"][k])
	var bp := 0
	for k in c["blueprints"]:
		if c["blueprints"][k]:
			bp += 1
	var s: Dictionary = c["salvage"]
	_summary.text = "Pilot: %s · Faction: %s · Difficulty: %s%s\nCredits: %d · Missiles: %d · Noble Programs: %d/4\nSalvage: %d alloy / %d circuitry / %d data · Blueprints: %d/%d · Upgrade levels: %d\nDirectories cleared: %d/%d%s" % [
		c["pilot"], c["team"], Campaign.difficulty_label(float(c["difficulty"])), " · STRATEGY MODE" if c.get("mode") == "strategy" else "",
		c["credits"], c["missiles"], c["noble"], s["alloy"], s["circuitry"], s["data"], bp, c["blueprints"].size(), up,
		c["wavesCleared"], c["dirs"].size(), "   WARRANT %d" % c["warrant"] if int(c["warrant"]) > 0 else ""]
	_progress.set_meta("frac", float(c["wavesCleared"]) / maxf(1, c["dirs"].size()))
	_progress.queue_redraw()
	for ch in _list.get_children():
		ch.queue_free()
	var cd := Campaign.data()
	for d in c["dirs"]:
		var b := DirButton.new()
		b.dir = d
		b.theme_cfg = cd["themes"].get(d.get("theme", "default"), cd["themes"]["default"])
		b.type_name = cd["typeNames"].get(d["type"], str(d["type"]).to_upper())
		b.locked = Campaign.is_locked(c, d)
		b.disabled = d.get("cleared", false) or b.locked
		b.toggle_mode = true
		b.button_pressed = int(d["id"]) == _selected
		var id := int(d["id"])
		b.pressed.connect(func(): _select(id))
		_list.add_child(b)


func _focus_first() -> void:
	for b in _list.get_children():
		if not b.disabled:
			b.grab_focus()
			break
	if _list.get_children().filter(func(b): return not b.disabled).is_empty():
		_enter.grab_focus()
	await get_tree().process_frame
	var sc := find_children("*", "ScrollContainer", true, false)
	if not sc.is_empty():
		(sc[0] as ScrollContainer).scroll_vertical = 0


func _select(id: int) -> void:
	_selected = id
	var d := Campaign.directory(c, id)
	var cd := Campaign.data()
	for b in _list.get_children():
		b.button_pressed = int(b.dir["id"]) == id
	var theme_cfg: Dictionary = cd["themes"].get(d.get("theme", "default"), cd["themes"]["default"])
	var reward: Dictionary = cd["rewards"].get(d["type"], cd["rewards"]["normal"])
	_info.text = "%s — %s\n%s\nEnvironment: %s · Completion salvage: %s" % [d["name"], cd["typeNames"].get(d["type"], d["type"]),
		cd["descriptions"].get(d["type"], ""), theme_cfg["name"], Campaign.reward_text(reward)]
	_enter.disabled = false


func _enter_dir() -> void:
	if _selected < 0:
		return
	SaveService.save_campaign(c)
	AppState.launch = {"mode": "campaign", "dir_id": _selected}
	get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")


func _relations() -> void:
	var lines := []
	for f in DataStore.factions():
		var v: float = c["relations"].get(f, 0.0)
		lines.append("%-10s %5d   %s" % [f, roundi(v), "Friendly" if v > 20 else ("Hostile" if v < -20 else "Neutral")])
	var l := Win95.field("\n".join(lines), 15)
	(l.get_child(0) as Label).add_theme_font_override("font", _mono())
	Win95.popup(self, "Faction Relations", "", [["Close", func(): pass]], l)


func _mono() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Courier New", "DejaVu Sans Mono"])
	return f


## Legacy openUpgradeBay (v6 + v6.6 salvage section).
func _upgrade_bay() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(500, get_viewport_rect().size.y - 200))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var credits := Win95.label("", 16, Win95.TEXT, true)
	var build := func(rebuild: Callable) -> void:
		for ch in box.get_children():
			ch.queue_free()
		credits.text = "Credits: %d" % c["credits"]
		var cd := Campaign.data()
		box.add_child(Win95.label("Tuning", 16, Win95.NAVY, true))
		for key in cd["upgrades"]:
			var def: Dictionary = cd["upgrades"][key]
			var level := int(c["upgrades"].get(key, 0))
			var cost := Campaign.upgrade_cost(key, level)
			_row(box, "%s — Level %d/5" % [def["name"], level], def["desc"], "MAX" if level >= 5 else "Upgrade %d" % cost,
				level < 5 and c["credits"] >= cost, func():
					c["credits"] -= cost
					c["upgrades"][key] = level + 1
					Sfx.beep(700, 0.08)
					_save_and(rebuild))
		box.add_child(Win95.label("Components", 16, Win95.NAVY, true))
		var eng := DataStore.engineering()
		for key in eng["components"]:
			var def: Dictionary = eng["components"][key]
			var owned: bool = c["components"].get(key, false)
			_row(box, def["name"], def["desc"], "INSTALLED" if owned else "Buy %d" % def["cost"], not owned and c["credits"] >= def["cost"], func():
				c["credits"] -= int(def["cost"])
				c["components"][key] = true
				Sfx.beep(760, 0.08)
				_save_and(rebuild))
		box.add_child(Win95.label("Rare Technology", 16, Win95.NAVY, true))
		for key in eng["rareTech"]:
			var def: Dictionary = eng["rareTech"][key]
			var owned: bool = c["rareTech"].get(key, false)
			var locked := int(c["noble"]) < int(def["noble"])
			_row(box, def["name"], "%s Requires %d Noble Program%s." % [def["desc"], def["noble"], "" if def["noble"] == 1 else "s"],
				"INSTALLED" if owned else ("LOCKED" if locked else "Buy %d" % def["cost"]), not owned and not locked and c["credits"] >= def["cost"], func():
					c["credits"] -= int(def["cost"])
					c["rareTech"][key] = true
					Sfx.beep(900, 0.1)
					_save_and(rebuild))
		var s: Dictionary = c["salvage"]
		box.add_child(Win95.label("Recovered Fabrication Salvage", 16, Win95.NAVY, true))
		box.add_child(Win95.field("%d alloy • %d circuitry • %d data cores\nSpent in the Ship Factory library to unlock palettes and hull stencils." % [s["alloy"], s["circuitry"], s["data"]], 13))
	var wrap := VBoxContainer.new()
	wrap.add_child(credits)
	wrap.add_child(scroll)
	build.call(build)
	Win95.popup(self, "Campaign Ship Upgrades", "", [["Close", func(): _render()]], wrap)


func _save_and(rebuild: Callable) -> void:
	SaveService.save_campaign(c)
	rebuild.call(rebuild)
	_render()


func _row(box: VBoxContainer, title: String, desc: String, btn_text: String, enabled: bool, cb: Callable) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Win95.BevelBox.new("sunken", Win95.FACE, 8, 6))
	var h := HBoxContainer.new()
	p.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.add_child(Win95.label(title, 14, Win95.TEXT, true))
	var dl := Win95.label(desc, 12)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(dl)
	h.add_child(v)
	var b := Win95.button(btn_text, 44)
	b.custom_minimum_size.x = 120
	b.disabled = not enabled
	b.pressed.connect(cb)
	h.add_child(b)
	box.add_child(p)


func _menu() -> void:
	if c:
		SaveService.save_campaign(c)
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_menu()


class Progress:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(0, 22)

	func _draw() -> void:
		Win95.progress(self, Rect2(Vector2.ZERO, size), float(get_meta("frac", 0.0)), Win95.NAVY)


## Directory card: bevelled button with mission family, threat and environment chip.
class DirButton:
	extends Button
	var dir: Dictionary
	var theme_cfg: Dictionary
	var type_name := ""
	var locked := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 54)
		text = ""

	func _draw() -> void:
		var off := Vector2(1, 1) if button_pressed else Vector2.ZERO
		var fs := 16
		var state := "✓ " if dir.get("cleared", false) else ("LOCKED · " if locked else "")
		var col := Win95.DISABLED if disabled else Win95.TEXT
		var accent := Color(str(theme_cfg.get("accent", "#63dfff")))
		draw_rect(Rect2(Vector2(8, 10) + off, Vector2(10, size.y - 20)), accent.darkened(0.35))
		Win95.text(self, Vector2(26, 22) + off, state + str(dir["name"]), fs, col, true, size.x - 40)
		Win95.text(self, Vector2(26, 42) + off, "%s · Threat %d · %s" % [type_name, int(dir["difficulty"]), theme_cfg.get("name", "")], 13, Win95.SHADOW if disabled else Color("#202020"), false, size.x - 40)


func _gamepad_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") and not _popup_open():
		get_viewport().set_input_as_handled()
		_menu()
		return true
	return false


func _popup_open() -> bool:
	for ch in get_children():
		if ch is Win95.PopupOverlay:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	_gamepad_back(event)
