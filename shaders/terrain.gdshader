shader_type spatial;
// Continuous terrain: flat chunk meshes displaced by the heightmap, coloured by
// height, slope and the painted biome mask. No textures needed yet; colours are
// broken up with noise for a soft, painterly look.

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D biome_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D road_mask : filter_linear_mipmap, repeat_disable;  // alpha = road or settlement ground

uniform float snow_height = 205.0;
uniform float rock_slope = 0.38;
uniform float beach_height = 4.0;

uniform vec3 grass_a : source_color = vec3(0.38, 0.46, 0.23);
uniform vec3 grass_b : source_color = vec3(0.50, 0.50, 0.30);
uniform vec3 forest_floor : source_color = vec3(0.26, 0.37, 0.17);
uniform vec3 highland : source_color = vec3(0.50, 0.47, 0.31);
uniform vec3 dirt : source_color = vec3(0.53, 0.42, 0.28);
uniform vec3 sand : source_color = vec3(0.80, 0.72, 0.54);
uniform vec3 desert_a : source_color = vec3(0.76, 0.60, 0.39);
uniform vec3 desert_b : source_color = vec3(0.72, 0.53, 0.34);
uniform vec3 rock_a : source_color = vec3(0.52, 0.48, 0.43);
uniform vec3 rock_b : source_color = vec3(0.40, 0.37, 0.35);
uniform vec3 snow : source_color = vec3(0.93, 0.94, 0.96);
uniform vec3 road : source_color = vec3(0.60, 0.49, 0.34);
uniform vec3 seabed : source_color = vec3(0.45, 0.47, 0.38);

varying vec3 v_world;
varying vec3 v_normal;

float height_at(vec2 uv) {
	return textureLod(heightmap, uv, 0.0).r * max_height;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = map_uv(wp.xz);
	float t = 1.0 / heightmap_resolution;
	float cell = world_size / (heightmap_resolution - 1.0);
	float h = height_at(uv);
	float hl = height_at(uv - vec2(t, 0.0));
	float hr = height_at(uv + vec2(t, 0.0));
	float hn = height_at(uv - vec2(0.0, t));
	float hs = height_at(uv + vec2(0.0, t));
	vec3 n = normalize(vec3(hl - hr, 2.0 * cell, hn - hs));
	VERTEX.y = h;
	NORMAL = n;
	v_world = vec3(wp.x, h, wp.z);
	v_normal = n;
}

void fragment() {
	vec2 uv = map_uv(v_world.xz);
	vec3 biome = texture(biome_mask, v_world.xz / world_size).rgb;
	float h = v_world.y;
	float slope = 1.0 - normalize(v_normal).y;
	float n1 = texture(detail_noise, v_world.xz * 0.0035).r;
	float n2 = texture(detail_noise, v_world.xz * 0.021).r;
	float n3 = texture(detail_noise, v_world.xz * 0.09).r;

	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.75, n1));
	col = mix(col, dirt, smoothstep(0.6, 0.85, n2 * 0.7 + n1 * 0.3) * 0.55);
	col = mix(col, forest_floor, biome.g * 0.85);
	float alt = clamp((h - sea_level) / (snow_height - sea_level), 0.0, 1.0);
	col = mix(col, highland, smoothstep(0.45, 0.85, alt + (n2 - 0.5) * 0.15) * 0.75);

	vec3 desert = mix(desert_a, desert_b, smoothstep(0.35, 0.7, n2));
	col = mix(col, desert, smoothstep(0.2, 0.7, biome.r));

	float beach = 1.0 - smoothstep(beach_height * 0.3, beach_height, h - sea_level + (n3 - 0.5) * 2.5);
	col = mix(col, sand, beach);

	float rock = smoothstep(rock_slope - 0.07, rock_slope + 0.07, slope + (n2 - 0.5) * 0.14);
	col = mix(col, mix(rock_a, rock_b, n3), rock);

	float snow_alt = smoothstep(snow_height - 25.0, snow_height + 15.0, h + (n2 - 0.5) * 40.0);
	float snow_amount = max(snow_alt, smoothstep(0.2, 0.8, biome.b)) * (1.0 - smoothstep(0.5, 0.75, slope));
	col = mix(col, snow, snow_amount);

	// Roads and settlement grounds: packed dirt with ruts, dusted by snow up north.
	float road_amount = texture(road_mask, v_world.xz / world_size).a;
	road_amount = smoothstep(0.15, 0.6, road_amount + (n3 - 0.5) * 0.25);
	vec3 road_col = road * (0.9 + 0.18 * n2) * mix(vec3(1.0), vec3(1.1, 1.1, 1.06), biome.r);
	col = mix(col, mix(road_col, snow * 0.92, snow_amount * 0.6), road_amount * 0.9);

	col = mix(col, seabed, smoothstep(0.0, 10.0, sea_level - h));
	col *= 0.9 + 0.2 * n3;

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
