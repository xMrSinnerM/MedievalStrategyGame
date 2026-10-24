extends Node
## Renders a small picture of every castle building from its KayKit model
## (CastleModels) for the build bar and the building panel, saved as
## assets/ui/buildings/<type>.png with a transparent background.
## Run after changing the castle models:
##   godot --path . res://tools/bake_portraits.tscn
## (a scene rather than --script so the autoloads are there; not --headless,
## it needs a renderer, so run it with a window or xvfb-run).

const OUT := "res://assets/ui/buildings/"
const SIZE := 160
const LEVEL := 3
const YAW := 0.65
const PITCH := -0.6

var _viewport: SubViewport
var _camera: Camera3D
var _model: MeshInstance3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.3
	sun.rotation = Vector3(-0.9, 0.3, 0)
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 28.0
	_viewport.add_child(_camera)
	_model = MeshInstance3D.new()
	_viewport.add_child(_model)

	var rules := BuildingRules.load_default()
	for type: String in rules.types:
		var mesh: ArrayMesh
		if type == "wall":
			mesh = _wall()
		else:
			mesh = CastleModels.build(type, LEVEL, rules.size(type), false, KitModels.PLAYER_COLOR)
		await _shoot(mesh, type)
	get_tree().quit()


func _wall() -> ArrayMesh:
	## A stretch of wall between two towers.
	var kit := KitModels.new()
	for x in [-1.0, 1.0]:
		kit.add("wall_straight", Transform3D(Basis.from_scale(Vector3(1, 1.4, 1.4)), Vector3(x, 0, 0)))
	for x in [-2.2, 2.2]:
		kit.add("building_tower_A_blue", Transform3D(Basis.from_scale(Vector3.ONE * 1.2), Vector3(x, 0, 0)))
	return kit.commit(KitModels.PLAYER_COLOR)


func _shoot(mesh: ArrayMesh, type: String) -> void:
	_model.mesh = mesh
	var box := mesh.get_aabb()
	var centre := box.get_center()
	var radius := box.size.length() * 0.5
	var dir := Vector3(sin(YAW) * cos(PITCH), -sin(PITCH), cos(YAW) * cos(PITCH))
	var dist := radius / sin(deg_to_rad(_camera.fov * 0.5)) * 0.8
	_camera.look_at_from_position(centre + dir * dist, centre)
	for k in 3:
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + type + ".png"))
	print("saved ", type)
