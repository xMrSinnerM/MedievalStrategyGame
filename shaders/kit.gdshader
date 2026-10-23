shader_type spatial;
// Models from the KayKit Medieval Hexagon pack (CC0). They all share one
// gradient atlas; the bottom-left swatch is the team colour, which is redrawn
// here in the owner's colour. Optional world map fog.

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 team : source_color = vec3(0.23, 0.36, 0.65);
uniform bool map_fog_on = false;
uniform float roughness = 0.75;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = texture(atlas, UV).rgb;
	if (UV.x < 0.125 && UV.y > 0.75) {
		float t = clamp((UV.y - 0.75) * 4.0, 0.0, 1.0);
		col = mix(team * 1.3 + vec3(0.04), team * 0.5, t);
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
	// A soft rim keeps silhouettes readable against the ground.
	RIM = 0.25;
	RIM_TINT = 0.6;
	if (map_fog_on) {
		FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
	}
}
