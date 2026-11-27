class_name Hud
extends Control
## In-flight HUD: hull/shield/fuel/heat bars, missiles, credits, message line, radar,
## test-range telemetry. Presentation only; reads the SimWorld each frame.

signal pause_pressed
signal zoom_pressed(delta: float)

var world: SimWorld
var _message := ""
var _message_time := 0.0
var _font: Font
var _buttons: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buttons)
	for spec in [["-", -0.15], ["+", 0.15]]:
		var zb := UiTheme.button(spec[0], 48)
		zb.custom_minimum_size.x = 52
		zb.focus_mode = Control.FOCUS_NONE
		var d: float = spec[1]
		zb.pressed.connect(func(): zoom_pressed.emit(d))
		_buttons.add_child(zb)
	var pb := UiTheme.button("II", 48)
	pb.custom_minimum_size.x = 60
	pb.focus_mode = Control.FOCUS_NONE
	pb.pressed.connect(func(): pause_pressed.emit())
	_buttons.add_child(pb)


func show_message(text: String, duration: float) -> void:
	_message = text
	_message_time = duration


func _process(dt: float) -> void:
	_message_time -= dt
	_buttons.size = _buttons.get_combined_minimum_size()
	_buttons.position = Vector2(get_viewport_rect().size.x - _buttons.size.x - 10, 10)
	queue_redraw()


func _bar(pos: Vector2, w: float, label: String, frac: float, color: Color, value: String) -> void:
	draw_rect(Rect2(pos, Vector2(w, 14)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(pos, Vector2(w * clampf(frac, 0, 1), 14)), color)
	draw_rect(Rect2(pos, Vector2(w, 14)), Color(1, 1, 1, 0.35), false, 1)
	draw_string(_font, pos + Vector2(4, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	var vw := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(_font, pos + Vector2(w - 4 - vw, 12), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _draw() -> void:
	if world == null or world.player == null:
		return
	var p := world.player
	var vs := get_viewport_rect().size
	var x := 12.0
	var y := 12.0
	var w := clampf(vs.x * 0.24, 170, 260)
	draw_rect(Rect2(x - 6, y - 6, w + 12, 106), Color(0.02, 0.05, 0.1, 0.5))
	_bar(Vector2(x, y), w, "HULL", p.hull / p.max_hull, Color("#52ff79") if p.hull > p.max_hull * 0.35 else Color("#ff5050"), "%d" % ceili(maxf(0, p.hull)))
	y += 18
	if p.max_shield > 0:
		_bar(Vector2(x, y), w, "SHIELD", p.shield_hp / p.max_shield, Color("#5affdc"), "%d" % roundi(p.shield_hp))
		y += 18
	_bar(Vector2(x, y), w, "FUEL", p.fuel / p.max_fuel, Color("#ffd24a") if p.fuel > p.max_fuel * 0.2 else Color("#ff8a3a"), "%d" % roundi(p.fuel))
	y += 18
	var heat := clampf(p.weapon_heat, 0, 100)
	var heat_c := Color("#ff4545") if heat > 80 else (Color("#ffcf3f") if heat > 55 else Color("#4fc3ff"))
	var prim: String = DataStore.modules()["primary"][p.modules.get("primary", "pulse")]["name"]
	_bar(Vector2(x, y), w, prim.to_upper(), heat / 100.0, heat_c, "%d%%" % roundi(heat))
	y += 22
	var missiles := "INF" if world.mode == "test" else str(world.campaign["missiles"])
	draw_string(_font, Vector2(x, y + 8), "MSL %s   CR %d   SPD %d" % [missiles, world.campaign["credits"], roundi(p.vel.length())], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
	if world.campaign["warrant"] > 0:
		draw_string(_font, Vector2(x, y + 24), "WARRANT %d" % world.campaign["warrant"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff6a6a"))
	# objective / telemetry line
	var obj := ""
	if world.mode == "test":
		var t := world.telemetry
		obj = "SPEED %d/%d  PEAK %d  90%% %s  HEAT %d%%" % [roundi(p.vel.length()), roundi(p.max_speed), roundi(t.maxSpeed), ("%.2fs" % t.timeTo90) if t.timeTo90 >= 0 else "—", roundi(heat)]
	else:
		obj = "EXIT GATE OPEN" if world.gate_open else "RECOVER ICONS  %d REMAIN" % world.icons.size()
	var ow := _font.get_string_size(obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var oy := 24.0 if vs.x > 760 else 140.0
	draw_rect(Rect2(vs.x / 2 - ow / 2 - 10, oy - 16, ow + 20, 24), Color(0.02, 0.05, 0.1, 0.55))
	draw_string(_font, Vector2(vs.x / 2 - ow / 2, oy), obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.ACCENT)
	if _message_time > 0 and _message != "":
		var a := clampf(_message_time / 0.3, 0, 1)
		# Bottom-centre, above the touch pads, so it never covers the status panel.
		var mw := minf(_font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, vs.x - 40)
		var my := vs.y - (0.30 * vs.y if AppState.is_touch_ui() else 48.0)
		draw_rect(Rect2(vs.x / 2 - mw / 2 - 10, my - 19, mw + 20, 26), Color(0.02, 0.05, 0.1, 0.6 * a))
		draw_string(_font, Vector2(vs.x / 2 - mw / 2, my), _message, HORIZONTAL_ALIGNMENT_LEFT, mw, 15, Color(1, 1, 1, a))
	_draw_radar(vs)


func _draw_radar(vs: Vector2) -> void:
	var touch := AppState.is_touch_ui()
	var rw := 124.0
	var rh := 82.0
	var c := Vector2(vs.x - rw / 2 - 12, 72 + rh / 2) if touch else Vector2(82, vs.y - 70)
	var r := Rect2(c - Vector2(rw, rh) / 2, Vector2(rw, rh))
	draw_rect(r, Color(0.01, 0.04, 0.07, 0.42))
	draw_rect(r, Color(0.35, 0.86, 0.94, 0.42), false, 1)
	draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), Color(0.35, 0.86, 0.94, 0.14))
	draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), Color(0.35, 0.86, 0.94, 0.14))
	draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
	var scale := Vector2(rw / SimWorld.W, rh / SimWorld.H)
	for o in world.icons:
		var d := SimWorld.wrapped_delta(world.player.pos, o.pos) * scale
		draw_rect(Rect2(c + d, Vector2(3, 3)), Color("#f4f") if o.infected else Color("#5ff"))
	for s in world.ships:
		var d := SimWorld.wrapped_delta(world.player.pos, s.pos) * scale
		var hostile := NpcAI.aggressive_to_player(world, s)
		draw_rect(Rect2(c + d, Vector2(3, 3)), Color("#f55") if hostile else s.color)
	if world.gate_open:
		var d := SimWorld.wrapped_delta(world.player.pos, world.gate_pos) * scale
		draw_rect(Rect2(c + d - Vector2(3, 3), Vector2(6, 6)), Color("#5ff"), false, 1)
