extends Node3D
## Scatters clustered trees using the forest channel of the biome mask, and
## boulders on steep and high ground. Models are KayKit pieces (CC0, see
## KitModels). Trees are grouped into MultiMesh blocks so distant blocks are
## culled and fade out as the camera rises.

const BLOCKS := 8   # blocks per side
## Models by kind: 0 conifer, 1 broadleaf, then boulders.
const PIECES := ["tree_single_A", "tree_single_B", "rock_single_B", "rock_single_C", "rock_single_E"]
const ROCK := 2
const TREE_SCALE := 8.5
const ROCK_SCALE := 14.0

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

	var roads: RoadNetwork = GameData.roads
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
			if roads.is_cleared(x, z):
				continue
			var slope := terrain.get_slope(x, z)
			if slope > max_slope:
				# Too steep for trees: now and then a boulder instead.
				if slope < max_slope * 2.5 and rng.randf() < 0.25:
					_place(buckets, block_size, ROCK + rng.randi() % (PIECES.size() - ROCK), x, h - 0.4, z, rng)
				continue
			var cold := biome.b > 0.15 or h > 140.0
			var kind := 0 if (cold or rng.randf() < 0.3) else 1   # 0 conifer, 1 broadleaf
			_place(buckets, block_size, kind, x, h - 0.3, z, rng)

	var meshes: Array[ArrayMesh] = []
	for k in PIECES.size():
		var kit := KitModels.new()
		kit.add(PIECES[k], Transform3D())
		var mesh := kit.commit(Color.WHITE, true)
		var mat: ShaderMaterial = mesh.surface_get_material(0).duplicate()
		mat.set_shader_parameter("instance_tint", true)
		mat.set_shader_parameter("sway", 1.0 if k < ROCK else 0.0)
		mesh.surface_set_material(0, mat)
		meshes.append(mesh)

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
		if key.z < ROCK:
			tree_count += mm.instance_count


func _place(buckets: Dictionary, block_size: float, kind: int, x: float, y: float, z: float, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.35) * (TREE_SCALE if kind < ROCK else ROCK_SCALE)
	var basis := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
	var key := Vector3i(int(x / block_size), int(z / block_size), kind)
	if not buckets.has(key):
		buckets[key] = {"xforms": [], "tints": []}
	buckets[key].xforms.append(Transform3D(basis, Vector3(x, y, z)))
	# The kit's leaves are a bright toy green; deepen them a little, each tree its own shade.
	var v := rng.randf_range(0.74, 0.98)
	buckets[key].tints.append(Color(v * rng.randf_range(0.95, 1.1), v * 0.9, v * rng.randf_range(0.7, 0.82)))
