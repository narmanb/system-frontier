class_name UiTheme
extends RefCounted
## Retro "directory OS" theme built in code (no third-party font or skin assets).

const BG := Color("#050a18")
const PANEL := Color("#0b1630")
const EDGE := Color("#4fc3ff")
const TEXT := Color("#e8f7ff")
const DIM := Color("#8fb0c8")
const ACCENT := Color("#ffcf4a")


static func _box(bg: Color, edge: Color, width := 2, radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("normal", "Button", _box(Color("#12244a"), Color("#3a7fb0")))
	t.set_stylebox("hover", "Button", _box(Color("#1a3466"), EDGE))
	t.set_stylebox("pressed", "Button", _box(Color("#2b5a9a"), Color("#bdf0ff")))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_stylebox("disabled", "Button", _box(Color("#0d1426"), Color("#2a3a50")))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#5a6a80"))
	t.set_stylebox("panel", "PanelContainer", _box(Color(PANEL, 0.94), EDGE, 2, 4))
	t.set_stylebox("panel", "Panel", _box(Color(PANEL, 0.94), EDGE, 2, 4))
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	return t


static func label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_height := 52.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	return b
