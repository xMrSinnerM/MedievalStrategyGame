shader_type spatial;
// Faction banner cloth. UV.x runs from the pole (0) to the free edge (1);
// the free side waves more. Transparent pixels (the swallowtail) are cut out.
render_mode cull_disabled;

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D banner : source_color, filter_linear_mipmap;
uniform float wave = 0.5;

varying vec3 v_world;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = TIME * 3.2 + origin.x * 0.1 + origin.z * 0.13;
	VERTEX.z += sin(phase - UV.x * 4.5) * wave * UV.x;
	VERTEX.x -= (1.0 - cos(sin(phase - UV.x * 4.5) * 0.5)) * UV.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(banner, UV);
	if (tex.a < 0.5) {
		discard;
	}
	float shade = 0.85 + 0.15 * sin(TIME * 3.2 - UV.x * 4.5);
	ALBEDO = tex.rgb * shade;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
