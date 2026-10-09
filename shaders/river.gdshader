shader_type spatial;
// River ribbons: UV.x runs across the river (0..1), UV.y along it in map units.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D wave_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.28, 0.52, 0.58);
uniform vec3 bank_color : source_color = vec3(0.45, 0.62, 0.58);
uniform float flow_speed = 6.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	vec2 flow_uv = vec2(UV.x * 0.15, (UV.y - TIME * flow_speed) * 0.03);
	float ripple = texture(wave_noise, flow_uv).r;
	vec3 col = mix(water_color, bank_color, smoothstep(0.4, 1.0, across));
	col *= 0.92 + 0.16 * ripple;
	ALBEDO = col;
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
	ALPHA = (1.0 - smoothstep(0.7, 1.0, across)) * 0.92;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
