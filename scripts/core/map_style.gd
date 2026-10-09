class_name MapStyle
extends RefCounted
## Shared look settings for the world map shaders.

static var _noise_cache := {}


static func apply_common(material: ShaderMaterial) -> void:
	## Sets the map dimensions and fog uniforms from map_common.gdshaderinc.
	var terrain: TerrainData = GameData.terrain
	material.set_shader_parameter("world_size", terrain.world_size)
	material.set_shader_parameter("heightmap_resolution", float(terrain.resolution))
	material.set_shader_parameter("max_height", terrain.max_height)
	material.set_shader_parameter("sea_level", terrain.sea_level)
	var fog := GameData.config_section("fog")
	material.set_shader_parameter("fog_color", fog_color())
	material.set_shader_parameter("fog_edge_start", float(fog.get("edge_start", 0.0)))
	material.set_shader_parameter("fog_edge_end", float(fog.get("edge_end", 260.0)))
	material.set_shader_parameter("fog_haze_start", float(fog.get("haze_start", 700.0)))
	material.set_shader_parameter("fog_haze_end", float(fog.get("haze_end", 4200.0)))
	material.set_shader_parameter("fog_haze_max", float(fog.get("haze_max", 0.5)))


static func fog_color() -> Color:
	return Color.html(GameData.config_section("fog").get("color", "#d9cdb4"))


static func noise_texture(seed_value: int, frequency: float, size := 512) -> ImageTexture:
	## Tileable grayscale noise, generated once per (seed, frequency, size).
	var key := "%d_%f_%d" % [seed_value, frequency, size]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = frequency
	var img := noise.get_seamless_image(size, size)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_noise_cache[key] = tex
	return tex
