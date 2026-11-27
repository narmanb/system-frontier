class_name Hud
extends Control
## In-flight HUD in the Win95 style: a "status" window (hull, shield, fuel, speed, heat as
## segmented progress bars), a radar window, a bottom status bar with the objective, and
## tooltip-style messages. Presentation only; reads the SimWorld each frame.

const STATUS_BAR_H := 26.0

var world: SimWorld
var top_inset := 30.0           ## height of the window title bar above the HUD
var _message := ""
var _message_time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_message(text: String, duration: float) -> void:
	_message = text
	_message_time = duration


func _process(dt: float) -> void:
	_message_time -= dt
	queue_redraw()


func _draw() -> void:
	if world == null or world.player == null:
		return
	var vs := get_viewport_rect().size
	var touch := AppState.is_touch_ui()
	var fs := 13 if touch else 12
	_draw_status_window(Vector2(6, top_inset + 6), clampf(vs.x * 0.28, 196, 250), fs)
	_draw_radar_window(vs, fs)
	_draw_status_bar(vs, fs)
	_draw_message(vs, touch)


func _mini_caption(r: Rect2, title: String, fs: int) -> void:
	Win95.caption(self, r, "", fs)
	Win95.text(self, Vector2(r.position.x + r.size.y + 2, r.position.y + r.size.y / 2 + fs * 0.36), title, fs, Win95.HILITE, true, r.size.x - r.size.y - 6)


func _row(x: float, y: float, w: float, label: String, value: String, frac: float, color: Color, fs: int) -> float:
	Win95.text(self, Vector2(x, y + fs), label, fs, Win95.TEXT, true)
	var vw := Win95.text_width(value, fs)
	Win95.text(self, Vector2(x + w - vw, y + fs), value, fs, Win95.TEXT)
	Win95.progress(self, Rect2(x, y + fs + 4, w, 13), frac, color)
	return y + fs + 4 + 13 + 5


func _draw_status_window(pos: Vector2, w: float, fs: int) -> void:
	var p := world.player
	var rows := 5 if p.max_shield > 0 else 4
	var row_h := fs + 4 + 13 + 5
	var cap_h := fs + 9.0
	var h := 6 + cap_h + 6 + rows * row_h + fs + 10 + (fs + 4 if world.campaign["warrant"] > 0 else 0)
	var r := Rect2(pos, Vector2(w, h))
	Win95.bevel(self, r, "window", Win95.FACE)
	_mini_caption(Rect2(pos + Vector2(3, 3), Vector2(w - 6, cap_h)), "%s · %s" % [p.name, p.team], fs)
	var x := pos.x + 9
	var iw := w - 18
	var y := pos.y + 3 + cap_h + 6
	y = _row(x, y, iw, "Hull", "%d/%d" % [ceili(maxf(0, p.hull)), roundi(p.max_hull)], p.hull / p.max_hull,
		Color("#11a011") if p.hull > p.max_hull * 0.35 else Color("#d01010"), fs)
	if p.max_shield > 0:
		y = _row(x, y, iw, "Shield", "%d/%d" % [roundi(p.shield_hp), roundi(p.max_shield)], p.shield_hp / p.max_shield, Color("#008080"), fs)
	y = _row(x, y, iw, "Fuel", "%d/%d" % [roundi(p.fuel), roundi(p.max_fuel)], p.fuel / p.max_fuel,
		Color("#c09000") if p.fuel > p.max_fuel * 0.2 else Color("#e05000"), fs)
	var sp := p.vel.length()
	y = _row(x, y, iw, "Speed", "%d/%d" % [roundi(sp), roundi(p.max_speed)], sp / p.max_speed, Win95.NAVY, fs)
	var heat := clampf(p.weapon_heat, 0, 100)
	var heat_c := Color("#d01010") if heat > 80 else (Color("#c07000") if heat > 55 else Color("#0050c0"))
	var prim: String = DataStore.modules()["primary"][p.modules.get("primary", "pulse")]["name"]
	y = _row(x, y, iw, "Heat · " + prim, "%d%%" % roundi(heat), heat / 100.0, heat_c, fs)
	var missiles := "INF" if world.mode == "test" else str(world.campaign["missiles"])
	Win95.text(self, Vector2(x, y + fs), "Missiles: %s     Credits: %d" % [missiles, world.campaign["credits"]], fs, Win95.TEXT)
	if world.campaign["warrant"] > 0:
		Win95.text(self, Vector2(x, y + fs * 2 + 4), "WARRANT LEVEL %d" % world.campaign["warrant"], fs, Color("#b00000"), true)


func _draw_radar_window(vs: Vector2, fs: int) -> void:
	var w := clampf(vs.x * 0.2, 130, 190)
	var cap_h := fs + 9.0
	var well_h := w * 0.66
	var r := Rect2(Vector2(vs.x - w - 6, top_inset + 6), Vector2(w, cap_h + well_h + 18))
	Win95.bevel(self, r, "window", Win95.FACE)
	_mini_caption(Rect2(r.position + Vector2(3, 3), Vector2(w - 6, cap_h)), "Radar", fs)
	var well := Rect2(r.position + Vector2(8, cap_h + 9), Vector2(w - 16, well_h))
	Win95.bevel(self, well, "sunken", Color("#001010"))
	var inner := well.grow(-2)
	var c := inner.get_center()
	draw_line(Vector2(inner.position.x, c.y), Vector2(inner.end.x, c.y), Color(0.2, 0.8, 0.7, 0.18))
	draw_line(Vector2(c.x, inner.position.y), Vector2(c.x, inner.end.y), Color(0.2, 0.8, 0.7, 0.18))
	var scale := Vector2(inner.size.x / SimWorld.W, inner.size.y / SimWorld.H)
	var dot := func(world_pos: Vector2, col: Color, s := 3.0) -> void:
		var d := SimWorld.wrapped_delta(world.player.pos, world_pos) * scale
		draw_rect(Rect2(c + d - Vector2(s, s) / 2, Vector2(s, s)), col)
	for o in world.icons:
		dot.call(o.pos, Color("#f4f") if o.infected else Color("#5ff"))
	for s in world.ships:
		dot.call(s.pos, Color("#ff4040") if NpcAI.aggressive_to_player(world, s) else s.color)
	if world.gate_open:
		dot.call(world.gate_pos, Color("#9ff"), 6.0)
	draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)


func _draw_status_bar(vs: Vector2, fs: int) -> void:
	var r := Rect2(0, vs.y - STATUS_BAR_H, vs.x, STATUS_BAR_H)
	draw_rect(r, Win95.FACE)
	draw_rect(Rect2(0, r.position.y, vs.x, 1), Win95.HILITE)
	var obj := ""
	if world.mode == "test":
		var t := world.telemetry
		obj = "TEST RANGE · peak %d · 90%% speed %s · shots %d" % [roundi(t.maxSpeed), ("%.2f s" % t.timeTo90) if t.timeTo90 >= 0 else "—", t.shots]
	else:
		obj = "EXIT GATE OPEN — fly into it" if world.gate_open else "ICON RECOVERY · %d remain" % world.icons.size()
	var right := "Threat %d" % world.threat if world.mode != "test" else "Factory test"
	var rw := Win95.text_width(right, fs) + 20
	var f1 := Rect2(3, r.position.y + 3, vs.x - rw - 9, STATUS_BAR_H - 6)
	var f2 := Rect2(vs.x - rw - 3, r.position.y + 3, rw, STATUS_BAR_H - 6)
	Win95.bevel(self, f1, "thin_sunken")
	Win95.bevel(self, f2, "thin_sunken")
	Win95.text(self, f1.position + Vector2(6, f1.size.y / 2 + fs * 0.36), obj, fs, Win95.TEXT, false, f1.size.x - 10)
	Win95.text(self, f2.position + Vector2(10, f2.size.y / 2 + fs * 0.36), right, fs, Win95.TEXT)


func _draw_message(vs: Vector2, touch: bool) -> void:
	if _message_time <= 0 or _message == "":
		return
	var fs := 15
	var mw := minf(Win95.text_width(_message, fs), vs.x * (0.5 if touch else 0.8))
	var lines := ceili(Win95.text_width(_message, fs) / maxf(1.0, mw))
	var h := lines * (fs + 4) + 10
	var y := vs.y - STATUS_BAR_H - (vs.y * 0.24 if touch else 16.0) - h
	var r := Rect2(vs.x / 2 - mw / 2 - 8, y, mw + 16, h)
	draw_rect(r, Win95.TOOLTIP)
	draw_rect(r, Win95.DARK, false, 1)
	draw_multiline_string(ThemeDB.fallback_font, r.position + Vector2(8, fs + 3), _message, HORIZONTAL_ALIGNMENT_LEFT, mw, fs, -1, Win95.TEXT)
