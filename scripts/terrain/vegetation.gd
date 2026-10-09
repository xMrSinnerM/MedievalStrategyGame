extends Node3D
## Scatters clustered low-poly trees using the forest channel of the biome mask.
## Trees are grouped into MultiMesh blocks so distant blocks are culled and fade
## out as the camera rises.

const TREE_SHADER := preload("res://shaders/tree.gdshader")
const BLOCKS := 8   # blocks per side

var tree_count := 0


func build() -> void:
	var terrain: TerrainData = GameData.terrain
	var cfg := GameData.config_section("vegetation")
	var cell_size := float(cfg.get("cell_size", 6.0))
	var max_slope := float(cfg.get("max_slope", 0.32))
	var density := float(cfg.get("density", 0.85))
	var cluster_scale := float(cfg.get("cluster_scale", 0.012))
	var visibility := float(cfg.get("visibility_range", 1100.0))
	var snow_height := float(GameData.config_section("terrain").get("snow_height", 205.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameData.terrain_config.get("seed", 1)) + 77
	var clusters := FastNoiseLite.new()
	clusters.seed = rng.seed
	clusters.frequency = cluster_scale
	clusters.fractal_octaves = 2

	var block_size := terrain.world_size / BLOCKS
	# Per block, per kind (0 conifer, 1 broadleaf): transforms and tints.
	var buckets := {}
	var steps := int(terrain.world_size / cell_size)
	for j in steps:
		for i in steps:
			var x := (i + rng.randf()) * cell_size
			var z := (j + rng.randf()) * cell_size
			var biome := terrain.get_biome(x, z)
			var cluster := clusters.get_noise_2d(x, z) * 0.5 + 0.5
			# Forests from the mask, plus sparse copses on open land.
			var chance := biome.g * density + smoothstep(0.72, 0.9, cluster) * 0.18
			chance *= 1.0 - biome.r
			if rng.randf() > chance:
				continue
			var h := terrain.get_height(x, z)
			if h < terrain.sea_level + 2.5 or h > snow_height - 10.0:
				continue
			if terrain.get_slope(x, z) > max_slope:
				continue
			var cold := biome.b > 0.15 or h > 140.0
			var kind := 0 if (cold or rng.randf() < 0.3) else 1   # 0 conifer, 1 broadleaf
			var s := rng.randf_range(0.8, 1.35)
			var basis := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
			var key := Vector3i(int(x / block_size), int(z / block_size), kind)
			if not buckets.has(key):
				buckets[key] = {"xforms": [], "tints": []}
			buckets[key].xforms.append(Transform3D(basis, Vector3(x, h - 0.3, z)))
			var v := rng.randf_range(0.82, 1.15)
			buckets[key].tints.append(Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.9, 1.0), float(kind == 0)))

	var trunk := ShaderMaterial.new()
	trunk.shader = TREE_SHADER
	MapStyle.apply_common(trunk)
	trunk.set_shader_parameter("base_color", Color(0.36, 0.26, 0.17))
	trunk.set_shader_parameter("alt_color", Color(0.32, 0.23, 0.15))
	var foliage := ShaderMaterial.new()
	foliage.shader = TREE_SHADER
	MapStyle.apply_common(foliage)
	foliage.set_shader_parameter("sway", 1.0)
	var meshes: Array[ArrayMesh] = [TreeMeshes.conifer(), TreeMeshes.broadleaf()]
	for mesh in meshes:
		mesh.surface_set_material(TreeMeshes.Part.TRUNK, trunk)
		mesh.surface_set_material(TreeMeshes.Part.FOLIAGE, foliage)

	for key: Vector3i in buckets:
		var bucket: Dictionary = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[key.z]
		mm.instance_count = bucket.xforms.size()
		for k in mm.instance_count:
			mm.set_instance_transform(k, bucket.xforms[k])
			mm.set_instance_custom_data(k, bucket.tints[k])
		var node := MultiMeshInstance3D.new()
		node.name = "Trees_%d_%d_%d" % [key.x, key.y, key.z]
		node.multimesh = mm
		node.visibility_range_end = visibility
		node.visibility_range_end_margin = visibility * 0.15
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(node)
		tree_count += mm.instance_count
