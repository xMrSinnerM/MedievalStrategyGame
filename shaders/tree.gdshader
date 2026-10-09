shader_type spatial;
// Low-poly trees drawn with MultiMesh. One material for trunks, one for
// foliage; INSTANCE_CUSTOM.rgb tints each tree's foliage, INSTANCE_CUSTOM.a
// picks between the broadleaf and conifer colour.

#include "res://shaders/includes/map_common.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.30, 0.42, 0.20);
uniform vec3 alt_color : source_color = vec3(0.20, 0.34, 0.20);
uniform float sway = 0.0;

varying vec3 v_world;
varying vec3 v_color;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	VERTEX.x += sin(TIME * 1.3 + origin.x * 0.05 + origin.z * 0.07) * sway * max(VERTEX.y - 2.0, 0.0) * 0.04;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = mix(base_color, alt_color, INSTANCE_CUSTOM.a) * INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
