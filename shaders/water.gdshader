shader_type spatial;
// Sea surface. Depth comes from the heightmap rather than the depth buffer, so
// the shallows, foam and colour work the same in every renderer.

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D wave_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 shallow_color : source_color = vec3(0.36, 0.62, 0.62);
uniform vec3 deep_color : source_color = vec3(0.13, 0.30, 0.42);
uniform vec3 foam_color : source_color = vec3(0.93, 0.91, 0.84);
uniform float wave_strength = 0.35;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float wave(vec2 p) {
	vec2 a = p * 0.012 + vec2(TIME * 0.006, TIME * 0.004);
	vec2 b = p * 0.027 - vec2(TIME * 0.005, -TIME * 0.007);
	return texture(wave_noise, a).r * 0.6 + texture(wave_noise, b).r * 0.4;
}

void fragment() {
	vec2 xz = v_world.xz;
	bool inside = xz.x >= 0.0 && xz.y >= 0.0 && xz.x <= world_size && xz.y <= world_size;
	float ground = inside ? textureLod(heightmap, map_uv(xz), 0.0).r * max_height : 0.0;
	float depth = sea_level - ground;

	float w = wave(xz);
	float e = 1.5;
	vec3 n_world = normalize(vec3(wave(xz - vec2(e, 0.0)) - wave(xz + vec2(e, 0.0)), 1.0 / wave_strength, wave(xz - vec2(0.0, e)) - wave(xz + vec2(0.0, e))));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 38.0, depth + (w - 0.5) * 6.0));
	float foam_band = 1.0 - smoothstep(0.2, 2.4, depth + (w - 0.5) * 2.5);
	float foam_pulse = 0.65 + 0.35 * sin(TIME * 0.9 - depth * 2.2 + w * 6.0);
	col = mix(col, foam_color, clamp(foam_band * foam_pulse, 0.0, 1.0) * 0.85);

	ALBEDO = col;
	ROUGHNESS = 0.22;
	SPECULAR = 0.45;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
