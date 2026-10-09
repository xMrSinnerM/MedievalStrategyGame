class_name TerrainData
extends RefCounted
## The loaded heightmap and biome mask, with height and ground queries for
## gameplay code (camera, settlements, pathfinding).
##
## World space: x runs west to east and z north to south, both 0..world_size.
## y is up, in map units.

var world_size := 2048.0
var resolution := 1025
var max_height := 300.0
var sea_level := 40.0
var cell := 2.0                         ## map units between two heightmap samples

var heights := PackedFloat32Array()     ## world units, resolution * resolution
var height_image: Image                 ## normalized 0..1, FORMAT_RF
var biome_image: Image                  ## R desert, G forest, B snow
var rivers: Array = []                  ## [{ "points": [[x, z, surface_y, width], ...] }]


func load_from_config(config: Dictionary) -> Error:
	world_size = float(config.world_size)
	max_height = float(config.max_height)
	sea_level = float(config.sea_level)
	var files: Dictionary = config.files

	height_image = Image.load_from_file(files.heightmap)
	if height_image == null or height_image.is_empty():
		push_error("Heightmap missing: %s. Run scripts/tools/generate_world.gd first." % files.heightmap)
		return ERR_FILE_NOT_FOUND
	if height_image.is_compressed():
		height_image.decompress()
	height_image.convert(Image.FORMAT_RF)
	if height_image.get_width() != height_image.get_height():
		push_error("Heightmap must be square.")
		return ERR_INVALID_DATA
	resolution = height_image.get_width()
	cell = world_size / float(resolution - 1)
	heights = height_image.get_data().to_float32_array()
	for k in heights.size():
		heights[k] *= max_height

	biome_image = Image.load_from_file(files.biome_mask)
	if biome_image == null or biome_image.is_empty():
		push_warning("Biome mask missing: %s" % files.biome_mask)
		biome_image = Image.create(8, 8, false, Image.FORMAT_RGB8)
	biome_image.convert(Image.FORMAT_RGB8)

	if FileAccess.file_exists(files.rivers):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(files.rivers))
		if parsed is Dictionary:
			rivers = parsed.get("rivers", [])
	return OK


func get_height(x: float, z: float) -> float:
	## Terrain height at a world position, bilinear between samples.
	var n := resolution
	var fx := clampf(x / cell, 0.0, n - 1.001)
	var fz := clampf(z / cell, 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * n + i
	return lerpf(lerpf(heights[k], heights[k + 1], tx), lerpf(heights[k + n], heights[k + n + 1], tx), tz)


func get_surface_height(x: float, z: float) -> float:
	## Height of whatever is on top: terrain, or the sea surface where it is deeper.
	return maxf(get_height(x, z), sea_level)


func get_normal(x: float, z: float) -> Vector3:
	var l := get_height(x - cell, z)
	var r := get_height(x + cell, z)
	var u := get_height(x, z - cell)
	var d := get_height(x, z + cell)
	return Vector3(l - r, 2.0 * cell, u - d).normalized()


func get_slope(x: float, z: float) -> float:
	## 0 on flat ground, approaching 1 on a cliff.
	return 1.0 - get_normal(x, z).y


func is_water(x: float, z: float) -> bool:
	return get_height(x, z) < sea_level


func get_biome(x: float, z: float) -> Color:
	## Biome weights at a world position: r desert, g forest, b snow (0..1 each).
	var w := biome_image.get_width()
	var px := clampi(int(x / world_size * w), 0, w - 1)
	var pz := clampi(int(z / world_size * w), 0, w - 1)
	return biome_image.get_pixel(px, pz)


func contains(x: float, z: float) -> bool:
	return x >= 0.0 and z >= 0.0 and x <= world_size and z <= world_size


func raycast(origin: Vector3, direction: Vector3, max_distance := 20000.0) -> Variant:
	## First hit of a ray with the terrain or sea surface, or null.
	## Used for mouse picking; marches in steps and refines by bisection.
	var dir := direction.normalized()
	var step := 4.0
	var t := 0.0
	var prev := origin
	while t < max_distance:
		t += step
		var p := origin + dir * t
		if p.y <= get_surface_height(p.x, p.z):
			var lo := prev
			var hi := p
			for i in 12:
				var mid := (lo + hi) * 0.5
				if mid.y <= get_surface_height(mid.x, mid.z):
					hi = mid
				else:
					lo = mid
			return hi
		prev = p
		step = clampf(step * 1.04, 4.0, 40.0)
	return null


func make_height_texture() -> ImageTexture:
	## Normalized heights for shaders (multiply by max_height there).
	return ImageTexture.create_from_image(height_image)


func make_biome_texture() -> ImageTexture:
	var img := biome_image.duplicate()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
