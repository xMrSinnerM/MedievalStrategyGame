extends Node3D
## Builds the terrain as a grid of flat chunk meshes that the terrain shader
## displaces with the heightmap. All chunks share one mesh and one material,
## so building is instant and off-screen chunks are culled.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")

var material: ShaderMaterial


func build() -> void:
	var terrain: TerrainData = GameData.terrain
	var config := GameData.terrain_config
	var look := GameData.config_section("terrain")

	material = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	MapStyle.apply_common(material)
	material.set_shader_parameter("heightmap", terrain.make_height_texture())
	material.set_shader_parameter("biome_mask", terrain.make_biome_texture())
	material.set_shader_parameter("detail_noise", MapStyle.noise_texture(11, 0.02))
	material.set_shader_parameter("road_mask", GameData.roads.make_road_texture())
	material.set_shader_parameter("snow_height", float(look.get("snow_height", 205.0)))
	material.set_shader_parameter("rock_slope", float(look.get("rock_slope", 0.38)))
	material.set_shader_parameter("beach_height", float(look.get("beach_height", 4.0)))

	var chunks := int(config.get("chunks_per_side", 16))
	var chunk_size := terrain.world_size / chunks
	var segments := (terrain.resolution - 1) / chunks   # one vertex per heightmap sample

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(chunk_size, chunk_size)
	mesh.subdivide_width = segments - 1
	mesh.subdivide_depth = segments - 1
	# The shader lifts vertices up to max_height, so widen the bounds for culling.
	mesh.custom_aabb = AABB(Vector3(-chunk_size * 0.5, -20.0, -chunk_size * 0.5), Vector3(chunk_size, terrain.max_height + 40.0, chunk_size))

	for cz in chunks:
		for cx in chunks:
			var chunk := MeshInstance3D.new()
			chunk.name = "Chunk_%d_%d" % [cx, cz]
			chunk.mesh = mesh
			chunk.material_override = material
			chunk.position = Vector3((cx + 0.5) * chunk_size, 0.0, (cz + 0.5) * chunk_size)
			add_child(chunk)
