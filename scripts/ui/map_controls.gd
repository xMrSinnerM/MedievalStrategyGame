class_name MapControls
extends PanelContainer
## The world map's tools, top left: a slim column of icon buttons for zoom,
## centring on your castle, the parchment map and the minimap, and "?" for a
## card with the zoom, frame rate and the list of keys.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.72, 0.66, 0.56)
const BUTTON := 38

## The minimap it switches on and off.
var minimap: Control
## Keys shown under "?"; the HUD sets them (they differ online).
var keys := ""

var _parchment: Button
var _minimap_button: Button
var _info: PanelContainer
var _stats: Label
var _keys_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", GameTheme.panel_box(0.8, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	column.add_child(_tool("+", "", "Zoom in", func() -> void: get_tree().call_group("campaign_camera", "zoom_by", 1)))
	column.add_child(_tool("−", "", "Zoom out", func() -> void: get_tree().call_group("campaign_camera", "zoom_by", -1)))
	column.add_child(_tool("", "target", "Centre on your castle (Home)", func() -> void:
		EventBus.map_focus_requested.emit(Economy.home_position())))
	_parchment = _tool("", "parchment", "Parchment map (M)", func() -> void:
		get_tree().call_group("parchment", "set_forced", _parchment.button_pressed))
	_parchment.toggle_mode = true
	column.add_child(_parchment)
	_minimap_button = _tool("", "minimap", "Minimap (N)", func() -> void:
		if minimap != null:
			minimap.visible = _minimap_button.button_pressed)
	_minimap_button.toggle_mode = true
	_minimap_button.set_pressed_no_signal(true)
	column.add_child(_minimap_button)
	var info := _tool("?", "", "Zoom, frame rate and keys", func() -> void: _info.visible = not _info.visible)
	column.add_child(info)

	# The "?" card opens to the right of the column, over the map.
	_info = PanelContainer.new()
	_info.add_theme_stylebox_override("panel", GameTheme.panel_box(0.85, 12))
	_info.top_level = true
	_info.visible = false
	_info.custom_minimum_size = Vector2(420, 0)
	add_child(_info)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_info.add_child(box)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 14)
	_stats.add_theme_color_override("font_color", TEXT)
	box.add_child(_stats)
	_keys_label = Label.new()
	_keys_label.add_theme_font_size_override("font_size", 13)
	_keys_label.add_theme_color_override("font_color", MUTED)
	_keys_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_keys_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N \
			and not get_viewport().gui_get_focus_owner() is LineEdit:
		_minimap_button.button_pressed = not _minimap_button.button_pressed
		if minimap != null:
			minimap.visible = _minimap_button.button_pressed


func show_status(zoom_t: float) -> void:
	## Keeps the switches and the "?" card up to date.
	var sheet := get_tree().get_first_node_in_group("parchment")
	if sheet != null:
		_parchment.set_pressed_no_signal(sheet.call("is_forced"))
	if not _info.visible:
		return
	_info.global_position = global_position + Vector2(size.x + 8, 0)
	_stats.text = "Zoom %d%%   %d fps" % [int(zoom_t * 100.0), Engine.get_frames_per_second()]
	if _keys_label.text != keys:
		_keys_label.text = keys


func _tool(text: String, icon: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BUTTON, BUTTON)
	b.add_theme_font_size_override("font_size", 20)
	if icon != "":
		b.icon = Icons.get_icon(icon, 22)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = false
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var lit: bool = state != "normal"
		var s := GameTheme.button_box(Color(0.075, 0.063, 0.05, 0.9) if not lit else Color(0.16, 0.11, 0.06, 0.95),
				GameTheme.RIM_DIM if not lit else GameTheme.RIM_BRIGHT, String(state).contains("pressed"))
		s.content_margin_left = 4
		s.content_margin_right = 4
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(action)
	return b
