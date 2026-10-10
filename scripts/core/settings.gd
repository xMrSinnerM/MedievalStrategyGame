extends Node
## Autoload holding the player's display settings, saved to user://settings.cfg
## and applied at start and whenever they change. Lights that cast shadows
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
	"ui_scale": 1.0,        ## size of menus and panels, 0.75 .. 1.5
}

var values := DEFAULTS.duplicate()


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in DEFAULTS:
			values[key] = cfg.get_value("display", key, DEFAULTS[key])
	apply()
	get_tree().node_added.connect(_on_node_added)


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
	root.content_scale_factor = clampf(float(values.ui_scale), 0.75, 1.5)
	for light in get_tree().get_nodes_in_group("sun"):
		_apply_light(light)
	for env in get_tree().get_nodes_in_group("environment"):
		_apply_environment(env)


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
