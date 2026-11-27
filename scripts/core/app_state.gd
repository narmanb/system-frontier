extends Node
## Global app state: input map, persisted settings, selected hull, focus handling.
## Gameplay simulation never reads this directly; scenes pass values in.

signal settings_changed
signal input_mode_changed(using_gamepad: bool)

## True after gamepad input, false after a screen touch. With show_touch = "auto" the
## on-screen pads hide while a gamepad (e.g. Retroid Pocket controls) is in use.
var using_gamepad := false

const SETTINGS_PATH := "user://settings.json"
const SETTINGS_VERSION := 1
const GAMEPLAY_ACTIONS := ["thrust", "turn_left", "turn_right", "fire", "missile"]

## Set by the menu before switching to the mission scene.
var launch := {"mode": "sandbox", "threat": 3}

var settings := {
	"version": SETTINGS_VERSION,
	"hull": "redFalcon",
	"zoom": 1.0,
	"sound": true,
	"show_touch": "auto",   # auto | on | off
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()
	_load_settings()
	get_tree().root.size_changed.connect(_update_content_scale)
	_update_content_scale()
	if "--smoke" in OS.get_cmdline_user_args():
		_run_smoke.call_deferred()


## CI smoke run: menu → sandbox mission (with input) → test range → quit. CI fails the job
## if the log contains any SCRIPT ERROR.
func _run_smoke() -> void:
	var tree := get_tree()
	await tree.create_timer(1.0).timeout
	for scene in ["res://scenes/setup/setup.tscn", "res://scenes/free_flight/free_flight.tscn"]:
		tree.change_scene_to_file(scene)
		await tree.create_timer(0.5).timeout
	var c := Campaign.create({"pilot": "Smoke"})
	c["noble"] = 4
	SaveService.save_campaign(c)
	tree.change_scene_to_file("res://scenes/directory_map/directory_map.tscn")
	await tree.create_timer(0.5).timeout
	tree.change_scene_to_file("res://scenes/factory/factory.tscn")
	await tree.create_timer(0.8).timeout
	var fe := FactoryEditor.new()
	fe.load_starter("blockadeRam")
	var runs := [{"mode": "sandbox", "threat": 5}, {"mode": "test", "threat": 1},
		{"mode": "test", "threat": 1, "ship": fe.ship_data(), "return": "factory", "test_options": {"infinite": false, "moving": true}}]
	for i in c["dirs"].size():
		runs.append({"mode": "campaign", "dir_id": i})
	for l in runs:
		launch = l
		tree.change_scene_to_file("res://scenes/mission/mission.tscn")
		Input.action_press("thrust")
		Input.action_press("fire")
		Input.action_press("turn_left")
		await tree.create_timer(1.5).timeout
		release_gameplay_inputs()
	SaveService.reset("campaign")
	print("SMOKE OK")
	tree.quit(0)


## Keeps the short side of the logical canvas at 540 units in both orientations (legacy used a
## 960×540 landscape / 540×960 portrait canvas), so UI and ships keep a consistent physical
## size when the device rotates. Orientation is never forced.
func _update_content_scale() -> void:
	var win := get_tree().root
	var sz := win.size
	var target := Vector2i(540, 960) if sz.y > sz.x * 1.08 else Vector2i(960, 540)
	if win.content_scale_size != target:
		win.content_scale_size = target


func _register_inputs() -> void:
	# Legacy keys preserved: arrows turn/thrust, Space fire, X secondary, Esc pause, M map.
	# Down arrow intentionally does nothing (Brake removed; counter-thrust instead).
	_action("thrust", [KEY_UP, KEY_W], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("turn_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("turn_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("fire", [KEY_SPACE], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("missile", [KEY_X], [JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_action("map", [KEY_M], [JOY_BUTTON_BACK], [])
	_action("zoom_in", [KEY_EQUAL, KEY_KP_ADD], [], [])
	_action("zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT], [], [])
	_action("fullscreen", [KEY_F11], [], [])
	_action("ambulance", [KEY_A], [JOY_BUTTON_RIGHT_STICK], [])
	# Gamepad menu navigation (Retroid Pocket 5 etc.): A = accept, B = back/cancel.
	_action("ui_accept", [], [JOY_BUTTON_A], [])
	_action("ui_cancel", [], [JOY_BUTTON_B], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(name, e)
	for ax in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = ax[0]
		e.axis_value = ax[1]
		InputMap.action_add_event(name, e)


## Releases every gameplay action (touch fingers lifted while paused/backgrounded, etc).
func release_gameplay_inputs() -> void:
	for a in GAMEPLAY_ACTIONS:
		Input.action_release(a)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_gameplay_inputs()


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if data is Dictionary:
		for k in settings:
			if data.has(k) and k != "version":
				settings[k] = data[k]
	if not DataStore.starter_hulls()["hulls"].has(settings["hull"]):
		settings["hull"] = "redFalcon"
	Sfx.enabled = bool(settings["sound"])


func save_settings() -> void:
	settings["version"] = SETTINGS_VERSION
	var tmp := SETTINGS_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(settings, " "))
	f.close()
	DirAccess.rename_absolute(tmp, SETTINGS_PATH)  # atomic replace
	settings_changed.emit()


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	if key == "sound":
		Sfx.enabled = bool(value)
	save_settings()


func is_touch_ui() -> bool:
	match str(settings["show_touch"]):
		"on": return true
		"off": return false
	return (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")) and not using_gamepad


func toggle_fullscreen() -> void:
	# Never forces an orientation; on mobile the window is already fullscreen/immersive.
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
	if pad and not using_gamepad:
		using_gamepad = true
		input_mode_changed.emit(true)
	elif event is InputEventScreenTouch and using_gamepad:
		using_gamepad = false
		input_mode_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
