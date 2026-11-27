class_name Win95
extends RefCounted
## Windows 95–style look shared by every screen: palette, bevels, title bars, theme.
## Drawn procedurally (no third-party skin or font assets). The legacy HTML build used the
## same visual language (grey bevelled controls, navy caption bars, teal desktop).

const FACE := Color("#c0c0c0")
const LIGHT := Color("#dfdfdf")
const HILITE := Color("#ffffff")
const SHADOW := Color("#808080")
const DARK := Color("#000000")
const NAVY := Color("#000080")
const NAVY_END := Color("#1084d0")
const DESKTOP := Color("#2f7f7c")
const FIELD := Color("#ffffff")
const TOOLTIP := Color("#ffffe1")
const TEXT := Color("#000000")
const DISABLED := Color("#808080")
const WELL := Color("#05070f")    ## dark "screen" well inside a sunken frame

static var _bold: Font


static func bold_font() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.9
		_bold = fv
	return _bold


# ------------------------------------------------------------------ bevels

## kind: "raised" (button/window), "sunken" (field/well), "pressed" (pushed button),
## "window" (outer window frame), "thin_sunken" (status bar field)
static func bevel_rid(ci: RID, r: Rect2, kind: String, fill = null) -> void:
	var rs := RenderingServer
	if fill != null:
		rs.canvas_item_add_rect(ci, r, fill)
	var tl1: Color; var br1: Color; var tl2: Color; var br2: Color
	match kind:
		"raised", "window":
			tl1 = HILITE if kind == "raised" else LIGHT
			br1 = DARK
			tl2 = LIGHT if kind == "raised" else HILITE
			br2 = SHADOW
		"sunken":
			tl1 = SHADOW; br1 = HILITE; tl2 = DARK; br2 = LIGHT
		"pressed":
			tl1 = DARK; br1 = HILITE; tl2 = SHADOW; br2 = LIGHT
		"thin_sunken":
			tl1 = SHADOW; br1 = HILITE; tl2 = Color(0, 0, 0, 0); br2 = Color(0, 0, 0, 0)
		_:
			return
	_edges(ci, r, tl1, br1)
	if tl2.a > 0 or br2.a > 0:
		_edges(ci, r.grow(-1), tl2, br2)


static func _edges(ci: RID, r: Rect2, tl: Color, br: Color) -> void:
	var rs := RenderingServer
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	rs.canvas_item_add_rect(ci, Rect2(x, y, w, 1), tl)
	rs.canvas_item_add_rect(ci, Rect2(x, y, 1, h), tl)
	rs.canvas_item_add_rect(ci, Rect2(x, y + h - 1, w, 1), br)
	rs.canvas_item_add_rect(ci, Rect2(x + w - 1, y, 1, h), br)


static func bevel(c: CanvasItem, r: Rect2, kind: String, fill = null) -> void:
	bevel_rid(c.get_canvas_item(), r, kind, fill)


## Window caption bar: navy → light-blue gradient, diamond icon, bold white title.
static func caption(c: CanvasItem, r: Rect2, title: String, font_size := 15, active := true) -> void:
	var a := NAVY if active else SHADOW
	var b := NAVY_END if active else Color("#b5b5b5")
	c.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([a, b, b, a]))
	var icon := r.size.y - 6
	var ip := r.position + Vector2(3, 3)
	bevel(c, Rect2(ip, Vector2(icon, icon)), "raised", DARK)
	var cc := ip + Vector2(icon, icon) / 2
	var k := icon * 0.28
	c.draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -k), cc + Vector2(k, 0), cc + Vector2(0, k), cc + Vector2(-k, 0)]), HILITE)
	var f := bold_font()
	var ty := r.position.y + r.size.y / 2 + font_size * 0.36
	c.draw_string(f, Vector2(ip.x + icon + 6, ty), title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - icon - 14, font_size, HILITE)


## Segmented progress bar in a sunken well (Win95 progress-bar style).
static func progress(c: CanvasItem, r: Rect2, frac: float, color: Color) -> void:
	bevel(c, r, "sunken", FIELD)
	var inner := r.grow(-3)
	var seg := maxf(4.0, inner.size.y * 0.62)
	var gap := 2.0
	var filled := inner.size.x * clampf(frac, 0, 1)
	var x := 0.0
	while x + 1 < filled:
		var w := minf(seg, filled - x)
		c.draw_rect(Rect2(inner.position.x + x, inner.position.y, w, inner.size.y), color)
		x += seg + gap


static func text(c: CanvasItem, pos: Vector2, s: String, size := 13, color := TEXT, bold := false, width := -1.0) -> void:
	c.draw_string(bold_font() if bold else ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)


static func text_width(s: String, size := 13, bold := false) -> float:
	return (bold_font() if bold else ThemeDB.fallback_font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# ------------------------------------------------------------------ theme

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var btn_normal := BevelBox.new("raised", FACE, 10, 6)
	var btn_pressed := BevelBox.new("pressed", FACE, 10, 6)
	t.set_stylebox("normal", "Button", btn_normal)
	t.set_stylebox("hover", "Button", btn_normal)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("hover_pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_normal)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0, 0, 0, 0.75)
	focus.set_border_width_all(1)
	focus.set_expand_margin_all(-4)
	t.set_stylebox("focus", "Button", focus)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DISABLED)
	t.set_font("font", "Button", bold_font())
	t.set_stylebox("panel", "PanelContainer", BevelBox.new("window", FACE, 6, 6))
	t.set_stylebox("panel", "Panel", BevelBox.new("window", FACE, 6, 6))
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t


static func button(label: String, min_h := 48.0) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, min_h)
	return b


static func label(s: String, size := 16, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", bold_font())
	return l


## A sunken white text field (read-only), as used for descriptions in the legacy menus.
static func field(s: String, size := 15) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BevelBox.new("sunken", FIELD, 10, 8))
	var l := label(s, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(l)
	return p


## Window = raised frame + caption bar + content VBox. Returns [window, content].
static func window(title: String, caption_buttons: Array = []) -> Array:
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", BevelBox.new("window", FACE, 3, 3))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	win.add_child(col)
	var bar := TitleBar.new()
	bar.title = title
	for cb in caption_buttons:
		bar.add_button(cb[0], cb[1])
	col.add_child(bar)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	col.add_child(pad)
	var content := VBoxContainer.new()
	pad.add_child(content)
	return [win, content]


class BevelBox:
	extends StyleBox
	var kind := "raised"
	var fill: Color = Win95.FACE

	func _init(p_kind := "raised", p_fill := Win95.FACE, mx := 8.0, my := 6.0) -> void:
		kind = p_kind
		fill = p_fill
		content_margin_left = mx
		content_margin_right = mx
		content_margin_top = my
		content_margin_bottom = my

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		Win95.bevel_rid(to_canvas_item, rect, kind, fill)
