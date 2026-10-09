extends Node3D
## The sea: one large plane at sea level that reaches past the map edges,
## where the edge fog swallows it.

const WATER_SHADER := preload("res://shaders/water.gdshader")


func build() -> void:
	var terrain: TerrainData = GameData.terrain
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	MapStyle.apply_common(material)
	material.set_shader_parameter("heightmap", terrain.make_height_texture())
	material.set_shader_parameter("wave_noise", MapStyle.noise_texture(23, 0.015))

	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * terrain.world_size * 6.0
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = mesh
	sea.material_override = material
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Vector3(terrain.world_size * 0.5, terrain.sea_level, terrain.world_size * 0.5)
	add_child(sea)
