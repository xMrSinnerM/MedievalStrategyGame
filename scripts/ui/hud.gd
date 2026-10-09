extends CanvasLayer
## Minimal debug HUD: controls, zoom level and frame rate. F1 hides it.

var _info: Label
var _zoom_t := 0.0


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
	EventBus.camera_zoom_changed.connect(func(t: float) -> void: _zoom_t = t)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_info.text = "WASD / drag: pan    Q E / right-drag: rotate    wheel: zoom\nM: parchment map    Home: recentre    F1: hide\nzoom %d%%    %d fps" % [int(_zoom_t * 100.0), Engine.get_frames_per_second()]
