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
var barons: Node3D
var players: Node3D
var outposts: Node3D
var villages: Node3D
var encounters: Node3D


func _ready() -> void:
	if not GameData.ensure_loaded():
		push_error("World data failed to load; see errors above.")
		return
	Economy.ensure_loaded()
	Economy.sync_castles(GameData.settlements, GameData.parties)
	var started := Time.get_ticks_msec()
	_build_environment()
	# Darker, warmer edges draw the eye to the middle of the map, like a
	# painted campaign map; it sits under the name plates and the HUD.
	var frame := CanvasLayer.new()
	frame.name = "Vignette"
	frame.layer = -1
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.material = ShaderMaterial.new()
	shade.material.shader = preload("res://shaders/map_vignette.gdshader")
	frame.add_child(shade)
	add_child(frame)
	var plates := Nameplates.new()
	plates.name = "Nameplates"
	add_child(plates)
	terrain.build()
	water.build()
	rivers.build()
	settlements.build()
	barons = preload("res://scripts/world/barons_layer.gd").new()
	barons.name = "Barons"
	barons.settlements = settlements
	add_child(barons)
	barons.build()
	vegetation.build()   # after the camps, which clear the trees around them
	if Economy.online:
		players = preload("res://scripts/world/players_layer.gd").new()
		players.name = "Players"
		add_child(players)
		players.build()
	outposts = preload("res://scripts/world/outposts_layer.gd").new()
	outposts.name = "Outposts"
	add_child(outposts)
	outposts.build()
	villages = preload("res://scripts/world/villages_layer.gd").new()
	villages.name = "Villages"
	add_child(villages)
	villages.build()
	encounters = preload("res://scripts/world/encounters_layer.gd").new()
	encounters.name = "Encounters"
	add_child(encounters)
	encounters.build()
	var weather := preload("res://scripts/world/weather_layer.gd").new()
	weather.name = "Weather"
	add_child(weather)
	weather.build()
	parties.barons = barons
	parties.encounters = encounters
	parties.villages = villages
	parties.players = players
	parties.outposts = outposts
	parties.camera_rig = camera_rig
	parties.build()
	parchment.build()
	camera_rig.setup()
	if Economy.online:
		var home := Economy.home_position()
		camera_rig.focus_on(Vector3(home.x, GameData.terrain.get_surface_height(home.x, home.y), home.y))
	Economy.castle_captured.connect(_on_castle_captured)
	EventBus.map_focus_requested.connect(func(p: Vector2) -> void:
		camera_rig.focus_on(Vector3(p.x, GameData.terrain.get_surface_height(p.x, p.y), p.y)))
	Economy.diplomacy_changed.connect(func(_news: Array) -> void: parties.on_diplomacy_changed())
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
	# A soft glow on the brightest spots: sun on water, snow and banners.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
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
