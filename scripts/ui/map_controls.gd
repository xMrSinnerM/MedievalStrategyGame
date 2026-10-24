class_name MapControls
extends PanelContainer
## The world map's control box, top left: zoom buttons, centre on your castle,
## the parchment map and minimap switches, what your party is doing and, on
## request, the list of keys. The header folds it down to one line.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.72, 0.66, 0.56)

## The minimap it switches on and off.
var minimap: Control
## Keys shown under "Keys"; the HUD sets them (they differ online).
var keys := ""

var _body: VBoxContainer
var _fold: Button
var _parchment: CheckBox
var _minimap_box: CheckBox
var _status: Label
var _stats: Label
var _keys_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", GameTheme.panel_box(0.85, 10))
	custom_minimum_size = Vector2(270, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(Icons.rect("compass", 22))
	var title := Label.new()
	title.text = "Map controls"
	title.add_theme_font_override("font", GameTheme.TITLE_FONT)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", GameTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_fold = _small("▴", _toggle_fold)
	head.add_child(_fold)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	box.add_child(_body)
	_body.add_child(HSeparator.new())
	var zoom := _row("zoom", "Zoom")
	zoom.add_child(_small("+", func() -> void: get_tree().call_group("campaign_camera", "zoom_by", 1)))
	zoom.add_child(_small("−", func() -> void: get_tree().call_group("campaign_camera", "zoom_by", -1)))
	var centre := _row("target", "Centre on your castle")
	centre.add_child(_small("Go", func() -> void: EventBus.map_focus_requested.emit(Economy.home_position())))
	_parchment = _check(_row("parchment", "Parchment map (M)"), func(on: bool) -> void:
		get_tree().call_group("parchment", "set_forced", on))
	_minimap_box = _check(_row("minimap", "Minimap (N)"), func(on: bool) -> void:
		if minimap != null:
			minimap.visible = on)
	_minimap_box.set_pressed_no_signal(true)
	_body.add_child(HSeparator.new())
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)
	var foot := HBoxContainer.new()
	_body.add_child(foot)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.add_theme_color_override("font_color", MUTED)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_stats)
	foot.add_child(_small("Keys", func() -> void: _keys_label.visible = not _keys_label.visible))
	_keys_label = Label.new()
	_keys_label.add_theme_font_size_override("font_size", 13)
	_keys_label.add_theme_color_override("font_color", MUTED)
	_keys_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys_label.visible = false
	_body.add_child(_keys_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N \
			and not get_viewport().gui_get_focus_owner() is LineEdit:
		_minimap_box.button_pressed = not _minimap_box.button_pressed


func show_status(status: String, zoom_t: float) -> void:
	## The lines about you (party, login, protection) and the zoom / frame rate.
	if _status.text != status:
		_status.text = status
	_status.visible = status != ""
	_stats.text = "Zoom %d%%   %d fps" % [int(zoom_t * 100.0), Engine.get_frames_per_second()]
	var sheet := get_tree().get_first_node_in_group("parchment")
	if sheet != null:
		_parchment.set_pressed_no_signal(sheet.call("is_forced"))
	if _keys_label.text != keys:
		_keys_label.text = keys


func _toggle_fold() -> void:
	_body.visible = not _body.visible
	_fold.text = "▴" if _body.visible else "▾"


func _row(icon: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Icons.rect(icon, 20))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_body.add_child(row)
	return row


func _check(row: HBoxContainer, action: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(action)
	row.add_child(box)
	return box


func _small(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 26)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(action)
	return b
