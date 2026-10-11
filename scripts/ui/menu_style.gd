class_name MenuStyle
extends RefCounted
## Shared look for the menus and panels: dark oak boards with bronze rims and
## gold Cinzel titles (see GameTheme for buttons and the rest).

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const GOLD := Color(1.0, 0.86, 0.55)


static func panel(alpha := 0.92, margin := 24) -> StyleBoxFlat:
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
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	l.add_theme_constant_override("outline_size", 8)
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
