shader_type spatial;
// Solid-colour placeholder props (settlements, bridges) that share the map fog.

#include "res://shaders/includes/map_common.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.7);
uniform float roughness = 0.9;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.15;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
