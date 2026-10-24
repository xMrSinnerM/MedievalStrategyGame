class_name GameTheme
extends RefCounted
## The game's look, built in code and laid over Godot's default theme at start
## (Settings calls GameTheme.apply()), so every button, panel, slider and
## tooltip gets it without each screen asking: near-black boards with thin
## gold rims and corner filigree (OrnateBox), dark buttons edged in gold with
## polished gold ones for the main action (primary), Alegreya Sans for text
## and Cinzel for titles.

const WOOD := Color(0.26, 0.17, 0.1)
const WOOD_LIGHT := Color(0.36, 0.24, 0.13)
const WOOD_DARK := Color(0.17, 0.11, 0.06)
const BRONZE := Color(0.78, 0.6, 0.32)
const BRONZE_DARK := Color(0.45, 0.32, 0.16)
const INK := Color(0.07, 0.045, 0.025)
const TEXT := Color(0.95, 0.9, 0.8)
const GOLD := Color(1.0, 0.86, 0.55)
const PARCHMENT := Color(0.93, 0.86, 0.69)
const DARK := Color(0.075, 0.063, 0.05)
const DARK_LIGHT := Color(0.13, 0.1, 0.07)
const DARK_PRESSED := Color(0.04, 0.033, 0.026)
const RIM := Color(0.72, 0.55, 0.28)
const RIM_DIM := Color(0.55, 0.42, 0.22)
const RIM_BRIGHT := Color(0.98, 0.8, 0.46)
const INK_BROWN := Color(0.18, 0.09, 0.03)

const TITLE_FONT := preload("res://assets/fonts/Cinzel-Bold.ttf")

## Alegreya Sans with even-height numbers (its own are old-style, dipping
## below the line), so counts and timers line up.
static var BODY_FONT := _lining(preload("res://assets/fonts/AlegreyaSans-Regular.ttf"))
static var BOLD_FONT := _lining(preload("res://assets/fonts/AlegreyaSans-Bold.ttf"))

static var _applied := false


static func apply() -> void:
	## Lays the game's theme over Godot's default one, once.
	if _applied:
		return
	_applied = true
	ThemeDB.get_default_theme().merge_with(build())
	ThemeDB.get_default_theme().default_font = BODY_FONT
	ThemeDB.fallback_font = BODY_FONT


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 16

	# Buttons: near black with a thin gold rim; under the mouse the rim
	# brightens and glows. Main actions are gold (see primary()).
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, button_box(DARK, RIM_DIM))
		t.set_stylebox("hover", type, button_box(DARK_LIGHT, RIM_BRIGHT, false, true))
		t.set_stylebox("pressed", type, button_box(DARK_PRESSED, RIM_BRIGHT, true))
		t.set_stylebox("hover_pressed", type, button_box(DARK_PRESSED, RIM_BRIGHT, true))
		t.set_stylebox("disabled", type, button_box(Color(0.07, 0.06, 0.05, 0.85), Color(0.3, 0.25, 0.17)))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, BOLD_FONT)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1.0, 0.95, 0.82))
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_hover_pressed_color", type, GOLD)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(0.56, 0.5, 0.43))
		t.set_color("font_outline_color", type, INK)
		t.set_constant("outline_size", type, 3)

	# Panels and windows.
	t.set_stylebox("panel", "PanelContainer", panel_box(0.9, 14))
	t.set_stylebox("panel", "Panel", panel_box(0.9, 14))
	t.set_stylebox("panel", "TooltipPanel", panel_box(0.97, 8, 4))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", BODY_FONT)
	t.set_font_size("font_size", "TooltipLabel", 15)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", INK)

	# Text fields and number boxes.
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.08, 0.055, 0.03, 0.9)
	field.border_color = BRONZE_DARK
	field.set_border_width_all(1)
	field.set_corner_radius_all(4)
	field.content_margin_left = 8
	field.content_margin_right = 8
	field.content_margin_top = 4
	field.content_margin_bottom = 4
	var field_focus := field.duplicate()
	field_focus.border_color = BRONZE
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(0.6, 0.42, 0.18, 0.6))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.54, 0.45))

	# Progress bars fill with gold.
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.06, 0.04, 0.02, 0.85)
	trough.border_color = BRONZE_DARK
	trough.set_border_width_all(1)
	trough.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.86, 0.66, 0.26)
	fill.border_color = Color(1.0, 0.85, 0.5)
	fill.border_width_top = 1
	fill.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", trough)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", TEXT)

	# Sliders and scroll bars.
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.06, 0.04, 0.02, 0.8)
	rail.set_corner_radius_all(3)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", rail)
	var lit := rail.duplicate()
	lit.bg_color = BRONZE
	t.set_stylebox("grabber_area", "HSlider", lit)
	t.set_stylebox("grabber_area_highlight", "HSlider", lit)
	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.06, 0.04, 0.02, 0.6)
		track.set_corner_radius_all(4)
		track.set_content_margin_all(4)
		var grab := StyleBoxFlat.new()
		grab.bg_color = BRONZE_DARK
		grab.set_corner_radius_all(4)
		grab.set_content_margin_all(4)
		var grab_hot := grab.duplicate()
		grab_hot.bg_color = BRONZE
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hot)
		t.set_stylebox("grabber_pressed", type, grab_hot)

	# Separators are a thin bronze line.
	var line := StyleBoxLine.new()
	line.color = Color(BRONZE, 0.55)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = Color(BRONZE, 0.55)
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", GOLD)
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(state, type, StyleBoxEmpty.new())
	t.set_icon("unchecked", "CheckBox", Icons.get_icon("box", 20))
	t.set_icon("checked", "CheckBox", Icons.get_icon("box_ticked", 20))
	t.set_icon("unchecked_disabled", "CheckBox", Icons.get_icon("box", 20))
	t.set_icon("checked_disabled", "CheckBox", Icons.get_icon("box_ticked", 20))
	t.set_constant("h_separation", "CheckBox", 8)
	return t


static func _lining(base: Font) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("lnum"): 1}
	return f


static func button_box(bg: Color, rim: Color, pressed := false, glow := false) -> StyleBoxFlat:
	## A dark plate with a thin rim; pressed sits a pixel lower. A glowing one
	## (under the mouse) casts a warm gold halo.
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = rim
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6 if not pressed else 7
	s.content_margin_bottom = 6 if not pressed else 5
	s.shadow_color = Color(1.0, 0.75, 0.3, 0.22) if glow else Color(0, 0, 0, 0.4)
	s.shadow_size = 6 if glow else (0 if pressed else 2)
	s.shadow_offset = Vector2.ZERO if glow else Vector2(0, 1)
	return s


static func primary(b: Button) -> Button:
	## Makes b a main action button: polished gold with dark serif lettering.
	var normal := GoldBox.new()
	var hover := GoldBox.new()
	hover.top = Color(1.0, 0.92, 0.66)
	hover.bottom = Color(0.74, 0.52, 0.2)
	hover.glow = 1.0
	var pressed := GoldBox.new()
	pressed.top = Color(0.82, 0.62, 0.3)
	pressed.bottom = Color(0.58, 0.38, 0.13)
	for box: StyleBox in [normal, hover, pressed]:
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 6
		box.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_font_override("font", TITLE_FONT)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK_BROWN)
	b.add_theme_constant_override("outline_size", 0)
	return b


static func card_box(bg: Color, rim: Color, pressed := false) -> StyleBoxFlat:
	## A picture card for the castle's build bar: a dark plate with a gold rim.
	var s := button_box(bg, rim, pressed, false)
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 10
	return s


static func panel_box(alpha := 0.92, margin := 24, radius := 8) -> StyleBox:
	## A window: a near-black board with a gold rim and corner filigree
	## (OrnateBox). Faint boards (alpha under 0.6) are cards inside a window,
	## with a plain thin rim.
	if alpha < 0.6:
		var card := StyleBoxFlat.new()
		card.bg_color = Color(0.11, 0.09, 0.07, 0.35 + alpha * 0.5)
		card.border_color = Color(RIM, 0.45)
		card.set_border_width_all(1)
		card.set_corner_radius_all(mini(radius, 3))
		card.set_content_margin_all(margin)
		return card
	var s := OrnateBox.new()
	s.bg = Color(0.05, 0.042, 0.034, alpha)
	s.set_content_margin_all(margin + 2)
	if alpha >= 0.9:
		s.header = margin + 44.0   # under the title row of a full window
	return s


static func bar_box(alpha := 0.88) -> StyleBoxFlat:
	## A board along the top of the screen with a bronze edge under it.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.045, 0.038, 0.03, alpha + 0.06)
	s.border_color = RIM
	s.border_width_bottom = 1
	s.content_margin_left = 14
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s
