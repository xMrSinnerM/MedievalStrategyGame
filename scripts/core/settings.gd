extends Node
## Autoload holding the player's display and sound settings, saved to
## user://settings.cfg and applied at start and whenever they change (the
## volumes by the Audio autoload). Lights that cast shadows
## join the "sun" group so the shadow setting reaches them; environments join
## "environment" for ambient occlusion.

signal changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"fullscreen": false,
	"vsync": true,
	"shadows": true,
	"ambient_occlusion": true,
	"render_scale": 1.0,    ## 3D resolution relative to the window, 0.5 .. 1
	"ui_scale": 1.0,        ## size of menus and panels, 0.75 .. 1.5 (on phones and tablets, on top of touch_scale())
	"master_volume": 0.8,   ## volumes 0 .. 1
	"music_volume": 0.6,
	"effects_volume": 0.8,
	"ambience_volume": 0.6,
	"notices": true,        ## cards for attacks and finished work (Notices)
	"desktop_notices": true,   ## the same on the desktop while the game is in the background
}

var values := DEFAULTS.duplicate()
## On phones and tablets the interface is sized so the screen's short side holds about this many of its pixels.
const TOUCH_HEIGHT := 600.0


func _ready() -> void:
	GameTheme.apply()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in DEFAULTS:
			values[key] = cfg.get_value("display", key, DEFAULTS[key])
	apply()
	get_tree().node_added.connect(_on_node_added)
	# Phones turn: the interface size follows the screen.
	get_tree().root.size_changed.connect(func() -> void:
		get_tree().root.content_scale_factor = ui_factor()
		_update_turn_hint())
	if is_touch():
		_add_turn_hint()


var _turn_hint: CanvasLayer
var _turn_hint_closed := false


func _add_turn_hint() -> void:
	## On a phone held upright, a note to turn it sideways (the game is made for a wide screen). A tap closes it.
	_turn_hint = CanvasLayer.new()
	_turn_hint.layer = 100
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", MenuStyle.panel(0.92, 12))
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.offset_top = 8
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_turn_hint_closed = true
			_update_turn_hint())
	var text := MenuStyle.label("Turn your phone sideways for the best view.  (Tap to close)", 16, MenuStyle.GOLD)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(text)
	_turn_hint.add_child(bar)
	add_child(_turn_hint)
	_update_turn_hint()


func _update_turn_hint() -> void:
	if _turn_hint == null:
		return
	var size := get_tree().root.size
	_turn_hint.visible = not _turn_hint_closed and size.y > size.x


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	apply()
	save()
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in values:
		cfg.set_value("display", key, values[key])
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	var root := get_tree().root
	root.scaling_3d_scale = clampf(float(values.render_scale), 0.5, 1.0)
	root.content_scale_factor = ui_factor()
	for light in get_tree().get_nodes_in_group("sun"):
		_apply_light(light)
	for env in get_tree().get_nodes_in_group("environment"):
		_apply_environment(env)


func ui_factor() -> float:
	## How much bigger than its pixels the interface is drawn: your interface size, times touch_scale().
	return clampf(float(values.ui_scale), 0.75, 1.5) * touch_scale()


static func is_touch() -> bool:
	## A phone or tablet (in the browser or not), rather than a computer with a mouse.
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile") \
			or OS.get_cmdline_user_args().has("--touch")


func touch_scale() -> float:
	## On phones and tablets the screen has many small pixels: the menus are made
	## for a 1600x900 window, so they are drawn at the size where the screen's short
	## side holds about 600 of their pixels (bigger on sharp phone screens, smaller
	## on coarse ones), but never bigger than the screen's own pixel ratio (so a
	## tablet isn't blown up). 1 on computers.
	if not is_touch() or DisplayServer.get_name() == "headless":
		return 1.0
	var size := get_tree().root.size
	var short_side := float(mini(size.x, size.y))
	var ratio := maxf(1.0, DisplayServer.screen_get_scale())
	return clampf(short_side / TOUCH_HEIGHT, 0.6, ratio)


func _on_node_added(node: Node) -> void:
	if node.is_in_group("sun"):
		_apply_light(node)
	elif node.is_in_group("environment"):
		_apply_environment(node)


func _apply_light(light: Node) -> void:
	if light is Light3D:
		light.shadow_enabled = bool(values.shadows)


func _apply_environment(node: Node) -> void:
	if node is WorldEnvironment and node.environment != null:
		node.environment.ssao_enabled = bool(values.ambient_occlusion)
