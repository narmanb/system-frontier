class_name Hud
extends Control
## In-flight HUD (Win95 style, kept compact so the play area stays clear):
##  - status window, top-left: one row per stat (label · segmented bar · value), credits in
##    the caption; no taller than the radar window
##  - chip bar, top-centre: icons collected/total, missiles, warrant, and a small pause button
##  - tooltip-style messages near the bottom
## The radar is a separate draggable RadarWindow. Presentation only.

signal pause_pressed

const SHORT := {"rescue": "RESCUE", "repair": "REPAIR", "scan": "SCAN", "defrag": "DEFRAG", "courier": "COURIER",
	"race": "RACE", "duel": "DUEL", "boss": "DEMON", "blackhole": "BLACK HOLE", "endless": "BIN"}

var world: SimWorld
var radar: Control                ## RadarWindow, so the chip bar can avoid it
var _message := ""
var _message_time := 0.0
var _pause: PauseButton
var _status_rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause = PauseButton.new()
	_pause.pressed.connect(func(): pause_pressed.emit())
	add_child(_pause)


func show_message(text: String, duration: float) -> void:
	_message = text
	_message_time = duration


func _process(dt: float) -> void:
	_message_time -= dt
	queue_redraw()


func _font_size() -> int:
	return 12 if AppState.is_touch_ui() else 11


var draw_us := 0


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_hud()
	draw_us = Time.get_ticks_usec() - t0


func _draw_hud() -> void:
	if world == null or world.player == null:
		return
	var vs := get_viewport_rect().size
	var fs := _font_size()
	var ins := AppState.safe_insets()
	_status_rect = _draw_status_window(Vector2(6 + ins.left, 6 + ins.top), fs)
	_draw_chip_bar(vs, fs)
	_draw_message(vs)


func _row(x: float, y: float, w: float, label: String, value: String, frac: float, color: Color, fs: int, label_w: float, value_w: float) -> void:
	Win95.text(self, Vector2(x, y + fs - 1), label, fs, Win95.TEXT, true)
	Win95.progress(self, Rect2(x + label_w, y, w - label_w - value_w - 4, fs + 1), frac, color)
	var vw := Win95.text_width(value, fs)
	Win95.text(self, Vector2(x + w - vw, y + fs - 1), value, fs, Win95.TEXT)


func _draw_status_window(pos: Vector2, fs: int) -> Rect2:
	var p := world.player
	var row_h := fs + 5.0
	var cap_h := 22.0 if not AppState.is_touch_ui() else 26.0
	var rows := 5 if p.max_shield > 0 else 4
	var w := clampf(Win95.text_width("Shield", fs, true) + 128 + Win95.text_width("125/125", fs), 190, 236)
	var r := Rect2(pos, Vector2(w, 3 + cap_h + 6 + rows * row_h + 4))
	Win95.bevel(self, r, "window", Win95.FACE)
	var cap := Rect2(pos + Vector2(3, 3), Vector2(w - 6, cap_h))
	Win95.caption(self, cap, "", fs)
	var credits := "CR %d" % world.campaign["credits"]
	var cw := Win95.text_width(credits, fs, true)
	Win95.text(self, Vector2(cap.position.x + cap_h + 2, cap.position.y + cap_h / 2 + fs * 0.36), "%s · %s" % [p.name, p.team], fs, Win95.HILITE, true, cap.size.x - cap_h - cw - 12)
	Win95.text(self, Vector2(cap.end.x - cw - 6, cap.position.y + cap_h / 2 + fs * 0.36), credits, fs, Color("#ffe98a"), true)
	var x := pos.x + 8
	var iw := w - 16
	var y := pos.y + 3 + cap_h + 6
	var lw := Win95.text_width("Shield", fs, true) + 6
	var vw := Win95.text_width("000/000", fs)
	_row(x, y, iw, "Hull", "%d/%d" % [ceili(maxf(0, p.hull)), roundi(p.max_hull)], p.hull / p.max_hull,
		Color("#11a011") if p.hull > p.max_hull * 0.35 else Color("#d01010"), fs, lw, vw)
	y += row_h
	if p.max_shield > 0:
		_row(x, y, iw, "Shield", "%d/%d" % [roundi(p.shield_hp), roundi(p.max_shield)], p.shield_hp / p.max_shield, Color("#008080"), fs, lw, vw)
		y += row_h
	_row(x, y, iw, "Fuel", "%d/%d" % [roundi(p.fuel), roundi(p.max_fuel)], p.fuel / p.max_fuel,
		Color("#c09000") if p.fuel > p.max_fuel * 0.2 else Color("#e05000"), fs, lw, vw)
	y += row_h
	var sp := p.vel.length()
	_row(x, y, iw, "Speed", "%d" % roundi(sp), sp / p.max_speed, Win95.NAVY, fs, lw, vw)
	y += row_h
	var heat := clampf(p.weapon_heat, 0, 100)
	var heat_c := Color("#d01010") if heat > 80 else (Color("#c07000") if heat > 55 else Color("#0050c0"))
	_row(x, y, iw, "Heat", "%d%%" % roundi(heat), heat / 100.0, heat_c, fs, lw, vw)
	return r


## Small chips at top-centre: icons collected/total (or test telemetry), missiles, warrant, pause.
func _draw_chip_bar(vs: Vector2, fs: int) -> void:
	var h := 24.0 if not AppState.is_touch_ui() else 30.0
	var chips: Array = []   # [kind, text]
	var m := world.mission
	if world.mode == "test":
		var t := world.telemetry
		chips.append(["text", "Peak %d · 90%% %s" % [roundi(t.maxSpeed), ("%.2fs" % t.timeTo90) if t.timeTo90 >= 0 else "—"]])
	elif world.gate_open:
		chips.append(["gate", "EXIT"])
	elif m and m.objective_text() != "":
		chips.append(["text", "%s %s" % [SHORT.get(m.type, m.type.to_upper()), m.objective_text()]])
	else:
		chips.append(["icon", "%d/%d" % [world.icons_collected, world.icons_collected + world.icons.size()]])
	if m and m.type == "endless":
		chips.append(["text", "PTS %d" % m.score])
	chips.append(["missile", "INF" if world.mode == "test" else str(world.campaign["missiles"])])
	if world.campaign["warrant"] > 0:
		chips.append(["warrant", str(world.campaign["warrant"])])
	var widths := []
	var total := 0.0
	for c in chips:
		var cw := Win95.text_width(c[1], fs + 1, true) + (h if c[0] != "text" else 0.0) + 12
		widths.append(cw)
		total += cw + 3
	total += h  # pause button
	var left := _status_rect.end.x + 6
	var ins := AppState.safe_insets()
	var right: float = vs.x - 6 - ins.right
	if radar and radar.visible and radar.position.y < _status_rect.end.y:
		right = minf(right, radar.position.x - 6)
	var x := clampf(vs.x / 2 - total / 2, left, maxf(left, right - total))
	var y: float = 6.0 + ins.top
	if left + total > right:   # not enough room between the windows: tuck under the status window
		x = 6 + ins.left
		y = _status_rect.end.y + 6
	for i in chips.size():
		var c: Array = chips[i]
		var r := Rect2(x, y, widths[i], h)
		Win95.bevel(self, r, "raised", Win95.FACE)
		var tx := r.position.x + 6
		var gc := Vector2(r.position.x + 4 + (h - 8) / 2, r.get_center().y)
		var g := (h - 8) * 0.5
		match c[0]:
			"icon":
				var pts := PackedVector2Array([gc + Vector2(-g * 0.7, -g), gc + Vector2(g * 0.3, -g), gc + Vector2(g * 0.7, -g * 0.6), gc + Vector2(g * 0.7, g), gc + Vector2(-g * 0.7, g)])
				draw_colored_polygon(pts, Win95.FIELD)
				pts.append(pts[0])
				draw_polyline(pts, Color("#1060c0"), 1.5)
				draw_rect(Rect2(gc + Vector2(-g * 0.4, -g * 0.1), Vector2(g * 0.8, g * 0.15)), Color("#1060c0"))
				draw_rect(Rect2(gc + Vector2(-g * 0.4, g * 0.3), Vector2(g * 0.6, g * 0.15)), Color("#1060c0"))
				tx = gc.x + g + 6
			"gate":
				draw_arc(gc, g * 0.85, 0, TAU, 16, Color("#008080"), 2.5)
				draw_circle(gc, g * 0.4, Color("#30d0e0"))
				tx = gc.x + g + 6
			"missile":
				draw_colored_polygon(PackedVector2Array([gc + Vector2(g, 0), gc + Vector2(g * 0.3, -g * 0.35), gc + Vector2(-g, -g * 0.35), gc + Vector2(-g, g * 0.35), gc + Vector2(g * 0.3, g * 0.35)]), Color("#c05000"))
				draw_colored_polygon(PackedVector2Array([gc + Vector2(-g * 0.6, -g * 0.35), gc + Vector2(-g, -g * 0.8), gc + Vector2(-g, -g * 0.35)]), Color("#c05000"))
				draw_colored_polygon(PackedVector2Array([gc + Vector2(-g * 0.6, g * 0.35), gc + Vector2(-g, g * 0.8), gc + Vector2(-g, g * 0.35)]), Color("#c05000"))
				tx = gc.x + g + 6
			"warrant":
				draw_circle(gc, g * 0.8, Color("#c00000"))
				Win95.text(self, gc + Vector2(-g * 0.22, g * 0.45), "!", int(g * 1.4), Color.WHITE, true)
				tx = gc.x + g + 6
		Win95.text(self, Vector2(tx, r.get_center().y + (fs + 1) * 0.36), c[1], fs + 1, Win95.TEXT, true)
		x += widths[i] + 3
	_pause.position = Vector2(x, y)
	_pause.size = Vector2(h, h)


func _draw_message(vs: Vector2) -> void:
	if _message_time <= 0 or _message == "":
		return
	var touch := AppState.is_touch_ui()
	var fs := 14
	var full := Win95.text_width(_message, fs)
	var mw := minf(full, vs.x * (0.55 if touch else 0.8))
	var lines := ceili(full / maxf(1.0, mw))
	var h := lines * (fs + 4) + 8
	var y: float = vs.y - AppState.safe_insets().bottom - (vs.y * 0.27 if touch else 24.0) - h
	var r := Rect2(vs.x / 2 - mw / 2 - 8, y, mw + 16, h)
	draw_rect(r, Win95.TOOLTIP)
	draw_rect(r, Win95.DARK, false, 1)
	draw_multiline_string(ThemeDB.fallback_font, r.position + Vector2(8, fs + 2), _message, HORIZONTAL_ALIGNMENT_LEFT, mw, fs, -1, Win95.TEXT)


class PauseButton:
	extends TouchRegion
	signal pressed
	var _down := false

	func _on_press(_p: Vector2) -> void:
		_down = true
		queue_redraw()

	func _on_release(p: Vector2) -> void:
		var hit := _hit(p)
		_down = false
		queue_redraw()
		if hit:
			pressed.emit()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		Win95.bevel(self, r, "pressed" if _down else "raised", Win95.FACE)
		var c := r.get_center() + (Vector2(1, 1) if _down else Vector2.ZERO)
		var k := size.y * 0.22
		draw_rect(Rect2(c + Vector2(-k * 0.8, -k), Vector2(k * 0.55, k * 2)), Win95.TEXT)
		draw_rect(Rect2(c + Vector2(k * 0.25, -k), Vector2(k * 0.55, k * 2)), Win95.TEXT)
