extends CanvasLayer
## Minimal HUD: controls, what your party is doing, zoom level and frame rate.
## F1 hides it.

var _info: Label
var _zoom_t := 0.0
var _party_status := ""


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.65)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_info.add_theme_font_size_override("font_size", 14)
	panel.add_child(_info)
	add_child(panel)
	var castle_button := Button.new()
	castle_button.text = "Your castle (C)"
	castle_button.focus_mode = Control.FOCUS_NONE
	castle_button.add_theme_font_size_override("font_size", 15)
	castle_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	castle_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	castle_button.offset_top = 12
	castle_button.offset_right = -12
	castle_button.pressed.connect(func() -> void: EventBus.castle_requested.emit(Economy.player_castle.id))
	add_child(castle_button)
	var info := preload("res://scripts/ui/castle_info_panel.gd").new()
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.offset_top = 56
	info.offset_right = -12
	add_child(info)
	EventBus.camera_zoom_changed.connect(func(t: float) -> void: _zoom_t = t)
	EventBus.party_status_changed.connect(func(text: String) -> void: _party_status = text)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var castle: CastleState = Economy.player_castle
	var stock := ""
	if castle:
		var cap := castle.storage_capacity()
		var rates := castle.net_per_hour()
		for r in Economy.rules.resources:
			stock += "%s %d/%d (%+d/h)   " % [r.capitalize(), int(castle.resources[r]), int(cap), int(rates[r])]
		stock += "Garrison %d   " % castle.troop_count()
	_info.text = stock + "\n" + "Click: travel there, or pick a castle    F: find your party    C: your castle\nWASD / drag: pan    Q E / right-drag: rotate    wheel: zoom\nM: parchment map    Home: recentre    F1: hide\nYour party: %s\nzoom %d%%    %d fps" % [_party_status, int(_zoom_t * 100.0), Engine.get_frames_per_second()]
