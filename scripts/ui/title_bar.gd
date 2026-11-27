class_name TitleBar
extends Control
## Win95 caption bar: gradient, icon, bold title, and functional caption buttons on the
## right. Buttons are sized up for touchscreens so they remain usable on phones.

var title := "SYSTEM FRONTIER"
var font_size := 16
var _buttons: HBoxContainer
var _pending: Array = []
## Display-cutout / status-bar insets the bar reaches under (mobile): the gradient fills
## them edge to edge while the title and buttons stay inside the safe area.
var insets := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _base_h := 30.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var touch := AppState.is_touch_ui()
	_base_h = 40.0 if touch else 30.0
	custom_minimum_size.y = _base_h + float(insets.top)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 3)
	add_child(_buttons)
	for p in _pending:
		_add(p[0], p[1])
	_pending.clear()
	resized.connect(_layout)
	_layout()


## glyph: close | minimize | fullscreen | pause | zoom_in | zoom_out | map | sound
func add_button(glyph: String, callback: Callable) -> void:
	if _buttons == null:
		_pending.append([glyph, callback])
	else:
		_add(glyph, callback)


func _add(glyph: String, callback: Callable) -> void:
	var b := CaptionButton.new()
	b.glyph = glyph
	var h := _base_h - 6
	b.custom_minimum_size = Vector2(h * 1.15, h)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	_buttons.add_child(b)
	_layout.call_deferred()


func _layout() -> void:
	if _buttons == null:
		return
	_buttons.size = _buttons.get_combined_minimum_size()
	_buttons.position = Vector2(size.x - float(insets.right) - _buttons.size.x - 3, float(insets.top) + 3)
	queue_redraw()


func _draw() -> void:
	var top := float(insets.top)
	var h := size.y - top
	var x0 := float(insets.left)
	var w := size.x - x0 - float(insets.right) - (_buttons.size.x + 8 if _buttons else 0.0)
	if top > 0:   # gradient runs up under the status bar / cutout
		var a := Win95.NAVY
		var b := Win95.NAVY_END
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, top + 1), Vector2(0, top + 1)]), PackedColorArray([a, b, b, a]))
	Win95.caption(self, Rect2(Vector2(x0, top), Vector2(size.x - x0, h)), "", font_size)
	if x0 > 0:
		draw_rect(Rect2(Vector2(0, top), Vector2(x0, h)), Win95.NAVY)
	Win95.text(self, Vector2(x0 + h + 4, top + h / 2 + font_size * 0.36), title, font_size, Win95.HILITE, true, maxf(10, w - h - 8))


class CaptionButton:
	extends Button
	var glyph := "close"

	func _init() -> void:
		text = ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c := r.get_center() + (Vector2(1, 1) if button_pressed or is_pressed() else Vector2.ZERO)
		var k := minf(size.x, size.y) * 0.24
		var ink := Win95.TEXT
		var lw := maxf(2.0, size.y * 0.09)
		match glyph:
			"close":
				draw_line(c + Vector2(-k, -k), c + Vector2(k, k), ink, lw)
				draw_line(c + Vector2(k, -k), c + Vector2(-k, k), ink, lw)
			"minimize", "zoom_out":
				draw_rect(Rect2(c + Vector2(-k, k * 0.6 if glyph == "minimize" else -lw / 2), Vector2(k * 2, lw)), ink)
			"zoom_in":
				draw_rect(Rect2(c + Vector2(-k, -lw / 2), Vector2(k * 2, lw)), ink)
				draw_rect(Rect2(c + Vector2(-lw / 2, -k), Vector2(lw, k * 2)), ink)
			"pause":
				draw_rect(Rect2(c + Vector2(-k * 0.8, -k), Vector2(k * 0.55, k * 2)), ink)
				draw_rect(Rect2(c + Vector2(k * 0.25, -k), Vector2(k * 0.55, k * 2)), ink)
			"fullscreen":
				draw_rect(Rect2(c - Vector2(k, k), Vector2(k * 2, k * 2)), ink, false, lw * 0.6)
				draw_rect(Rect2(c - Vector2(k, k), Vector2(k * 2, lw)), ink)
			"map":
				draw_arc(c, k * 1.05, 0, TAU, 20, ink, lw * 0.7)
				draw_line(c + Vector2(-k, 0), c + Vector2(k, 0), ink, lw * 0.5)
				draw_line(c + Vector2(0, -k), c + Vector2(0, k), ink, lw * 0.5)
			"sound":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-k, -k * 0.4), c + Vector2(-k * 0.4, -k * 0.4), c + Vector2(k * 0.2, -k), c + Vector2(k * 0.2, k), c + Vector2(-k * 0.4, k * 0.4), c + Vector2(-k, k * 0.4)]), ink)
				if Sfx.enabled:
					draw_arc(c + Vector2(k * 0.2, 0), k * 0.7, -0.9, 0.9, 8, ink, lw * 0.6)
				else:
					draw_line(c + Vector2(k * 0.5, -k * 0.5), c + Vector2(k * 1.1, k * 0.5), ink, lw * 0.6)
