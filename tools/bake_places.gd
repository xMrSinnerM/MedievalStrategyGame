extends Node
## Renders the pictures on the world map's info cards: every faction's capital
## and castle, your castle, a village, a robber baron camp and a warband, each
## on a patch of meadow with trees under a warm sky. Saved as
## assets/ui/places/<name>.png. Run after changing the map models:
##   godot --path . res://tools/bake_places.tscn
## (a scene so the autoloads are there; it needs a renderer, so run it with a
## window or xvfb-run).

const OUT := "res://assets/ui/places/"
const SIZE := Vector2i(216, 280)
const AT := Vector3(1024, 0, 1024)    ## mid-map, away from the edge fog
const YAW := 0.62
const PITCH := 0.2                    ## radians the camera looks down
const GRASS := Color(0.4, 0.55, 0.24)
const TREE_SCALE := 8.5             ## as on the map (vegetation.gd)
const TREES := ["tree_single_A", "tree_single_B"]
const BaronsLayer := preload("res://scripts/world/barons_layer.gd")

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D


func _ready() -> void:
	GameData.ensure_loaded()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.add_child(_environment())
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.3
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-150.0), 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.far = 5000.0
	_viewport.add_child(_camera)

	for faction: Dictionary in GameData.factions:
		await _shoot("capital_" + faction.id, _settlement("town", faction.id, false), 40.0)
		await _shoot("castle_" + faction.id, _settlement("castle", faction.id, false), 22.0)
	var home: String = GameData.factions[0].id
	await _shoot("castle_player", _settlement("castle", home, true), 22.0)
	await _shoot("village", _settlement("village", "", false), 20.0)
	await _shoot("camp", _camp(), 11.0)
	await _shoot("warband", _warband(), 11.0)
	get_tree().quit()


func _environment() -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.42, 0.58, 0.78)
	sky_material.sky_horizon_color = Color(0.95, 0.84, 0.66)
	sky_material.ground_horizon_color = Color(0.95, 0.84, 0.66)
	sky_material.ground_bottom_color = Color(0.5, 0.45, 0.35)
	sky_material.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.93, 0.84, 0.7)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	var node := WorldEnvironment.new()
	node.environment = env
	return node


func _settlement(type: String, faction: String, player: bool) -> Node3D:
	var s := Settlement.new()
	_stage_add(s)
	s.setup({"id": "picture_%s_%s" % [type, faction], "name": "", "type": type, "faction": faction,
			"player": player, "position": [AT.x, AT.z], "rotation_deg": 25.0})
	s.position.y = 0.0
	s.get_node("Label").visible = false
	return s


func _camp() -> Node3D:
	var root := Node3D.new()
	var model := MeshInstance3D.new()
	model.mesh = BaronsLayer.camp_mesh(false)
	root.add_child(model)
	var banner := Banners.make(BaronsLayer.BARON_BANNER, 8.0, 4.0)
	banner.position = Vector3(-1.5, 0, -0.5)
	root.add_child(banner)
	root.position = AT
	root.rotation.y = 0.4
	_stage_add(root)
	return root


func _warband() -> Node3D:
	var root := Node3D.new()
	var model := MeshInstance3D.new()
	model.mesh = Soldiers.troop([
		Soldiers.figure("knight", Vector3(0, 0, -0.6), 1.05),
		Soldiers.figure("knight", Vector3(-1.0, 0, 1.0), 0.85),
		Soldiers.figure("knight", Vector3(1.0, 0, 1.0), 0.85),
		Soldiers.figure("crossbowman", Vector3(-1.0, 0, 2.5), 0.85),
		Soldiers.figure("crossbowman", Vector3(1.0, 0, 2.5), 0.85),
	], KitModels.PLAYER_COLOR)[0]
	model.scale = Vector3.ONE * 4.0
	root.add_child(model)
	root.position = AT
	root.rotation.y = PI + 0.5
	_stage_add(root)
	return root


func _stage_add(subject: Node3D) -> void:
	## A fresh stage: a meadow, a ring of trees and the subject in the middle.
	if _stage != null:
		_stage.free()
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_stage.add_child(subject)


func _dress(radius: float) -> void:
	var ground := MeshKit.new()
	ground.cylinder(GRASS, Transform3D(Basis(), AT + Vector3(0, -0.5, 0)), 900.0, 0.4, 40)
	var meadow := MeshInstance3D.new()
	meadow.mesh = ground.commit()
	_stage.add_child(meadow)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(radius * 100.0)
	var kit := KitModels.new()
	var front := atan2(cos(YAW), sin(YAW))   # towards the camera: kept clear
	for k in 46:
		var angle := rng.randf() * TAU
		if absf(angle_difference(angle, front)) < 1.3:
			continue
		var d := radius * rng.randf_range(1.35, 3.2) + 6.0
		var s := TREE_SCALE * rng.randf_range(0.8, 1.3)
		kit.add(TREES[k % 2], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				AT + Vector3(cos(angle) * d, -0.3, sin(angle) * d)))
	var trees := MeshInstance3D.new()
	trees.mesh = kit.commit(Color.WHITE)
	_stage.add_child(trees)


func _shoot(file: String, subject: Node3D, radius: float) -> void:
	_dress(radius)
	var centre := AT + Vector3(0, radius * 0.62, 0)
	var dir := Vector3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH))
	var dist := radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.15
	_camera.look_at_from_position(centre + dir * dist, centre)
	for k in 4:
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + file + ".png"))
	print("saved ", file)
