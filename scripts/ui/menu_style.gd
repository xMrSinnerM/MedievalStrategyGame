class_name MenuStyle
extends RefCounted
## Shared look for the menus and panels: dark oak boards with bronze rims and
## gold Cinzel titles (see GameTheme for buttons and the rest).

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const GOLD := Color(0.95, 0.78, 0.47)


static func panel(alpha := 0.92, margin := 24) -> StyleBox:
	return GameTheme.panel_box(alpha, margin)


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size := 34) -> Label:
	var l := label(text, size, GOLD)
	l.add_theme_font_override("font", GameTheme.TITLE_FONT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.015))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func button(text: String, action: Callable, width := 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 44)
	b.add_theme_font_override("font", GameTheme.TITLE_FONT)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(action)
	return b


static func ornate_panel() -> StyleBox:
	## The title screen's dialogs: a window with a deeper shadow.
	var s: OrnateBox = GameTheme.panel_box(0.95, 28)
	s.shadow = 16.0
	return s


static func menu_button(text: String, action: Callable, width := 300.0, primary := false) -> Button:
	## A big title-screen button: near black with a gold rim (or polished gold
	## for the main choice), glowing and growing a little under the mouse.
	var b := button(text, action, width)
	b.custom_minimum_size.y = 52
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_stylebox_override("normal", _menu_box(Color(0.07, 0.055, 0.045, 0.95), Color(0.72, 0.55, 0.28)))
	b.add_theme_stylebox_override("hover", _menu_box(Color(0.14, 0.1, 0.07, 0.95), Color(1.0, 0.82, 0.45), true))
	b.add_theme_stylebox_override("pressed", _menu_box(Color(0.04, 0.03, 0.025, 0.95), Color(1.0, 0.82, 0.45)))
	b.add_theme_stylebox_override("disabled", _menu_box(Color(0.08, 0.07, 0.06, 0.8), Color(0.35, 0.28, 0.18)))
	b.add_theme_color_override("font_color", Color(0.96, 0.9, 0.76))
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.55, 0.47))
	b.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.02))
	b.add_theme_constant_override("outline_size", 6)
	if primary:
		GameTheme.primary(b)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _grow(b, 1.04))
	b.mouse_exited.connect(func() -> void: _grow(b, 1.0))
	return b


static func _grow(b: Button, to: float) -> void:
	if b.disabled or not b.is_inside_tree():
		return
	b.create_tween().tween_property(b, "scale", Vector2.ONE * to, 0.12).set_trans(Tween.TRANS_SINE)


static func _menu_box(bg: Color, rim: Color, glow := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = rim
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_color = Color(1.0, 0.75, 0.3, 0.35) if glow else Color(0, 0, 0, 0.45)
	s.shadow_size = 10 if glow else 4
	s.shadow_offset = Vector2.ZERO if glow else Vector2(0, 3)
	return s


static func war_button_text(button: Button, action: String, faction: String) -> void:
	## Attacking a faction you are at peace with means declaring war first,
	## which a truce forbids.
	var d := Economy.diplomacy
	if d == null or d.at_war(d.player_faction, faction):
		button.text = action
		return
	var truce := d.truce_left(d.player_faction, faction, Economy.now())
	if truce > 0.0:
		button.text = "Truce: %d min left" % ceili(truce / 60.0)
		button.disabled = true
	else:
		button.text = "%s (declares war)" % action
