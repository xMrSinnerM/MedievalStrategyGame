extends Node3D
## Root of the campaign map. Loads the data, sets up lighting and builds every
## layer in order.

@onready var terrain: Node3D = $Terrain
@onready var water: Node3D = $Water
@onready var rivers: Node3D = $Rivers
@onready var settlements: Node3D = $Settlements
@onready var vegetation: Node3D = $Vegetation
@onready var parties: Node3D = $Parties
@onready var parchment: Node3D = $ParchmentOverlay
@onready var camera_rig: CampaignCamera = $CampaignCamera


func _ready() -> void:
	if not GameData.ensure_loaded():
		push_error("World data failed to load; see errors above.")
		return
	Economy.ensure_loaded()
	Economy.sync_castles(GameData.settlements, GameData.parties)
	var started := Time.get_ticks_msec()
	_build_environment()
	terrain.build()
	water.build()
	rivers.build()
	settlements.build()
	vegetation.build()
	parties.camera_rig = camera_rig
	parties.build()
	parchment.build()
	camera_rig.setup()
	Economy.castle_captured.connect(_on_castle_captured)
	print("World map built in %d ms (%d settlements, %d bridges, %d trees, %d parties)" % [Time.get_ticks_msec() - started,
		settlements.settlements.size(), settlements.bridge_count, vegetation.tree_count, parties.parties.size()])


func _on_castle_captured(castle_id: String, _old_owner: String, _new_owner: String) -> void:
	settlements.rebuild(castle_id)
	parchment.refresh_settlements()
	parties.on_castle_captured(castle_id)


func _build_environment() -> void:
	var fog := MapStyle.fog_color()

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.56, 0.68, 0.80)
	sky_material.sky_horizon_color = fog
	sky_material.ground_horizon_color = fog
	sky_material.ground_bottom_color = fog.darkened(0.2)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 4.0
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var world_env := WorldEnvironment.new()
	world_env.add_to_group("environment")
	world_env.environment = env
	add_child(world_env)

	# Warm late-afternoon sun from the south-west.
	var sun := DirectionalLight3D.new()
	sun.add_to_group("sun")
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.25
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-140.0), 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1600.0
	sun.shadow_blur = 1.5
	add_child(sun)
