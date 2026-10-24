shader_type spatial;
// Models from the KayKit Medieval Hexagon pack (CC0). They all share one
// gradient atlas; the bottom-left swatch is the team colour, which is redrawn
// here in the owner's colour. Optional world map fog; trees drawn with
// MultiMesh can sway and take a per-instance tint (INSTANCE_CUSTOM.rgb).

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 team : source_color = vec3(0.23, 0.36, 0.65);
uniform bool map_fog_on = false;
uniform float roughness = 0.75;
uniform bool instance_tint = false;
uniform float sway = 0.0;

varying vec3 v_world;
varying vec3 v_tint;

void vertex() {
	if (sway > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		VERTEX.x += sin(TIME * 1.3 + origin.x * 0.05 + origin.z * 0.07) * sway * max(VERTEX.y - 0.25, 0.0) * 0.04;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_tint = instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
}

void fragment() {
	vec3 col = texture(atlas, UV).rgb;
	if (UV.x < 0.125 && UV.y > 0.75) {
		float t = clamp((UV.y - 0.75) * 4.0, 0.0, 1.0);
		col = mix(team * 1.3 + vec3(0.04), team * 0.5, t);
	}
	// Map trees: calm the kit's toy green a little and tint each tree's
	// leaves (not its trunk).
	if (instance_tint && col.g > col.r) {
		col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))), 0.3) * v_tint;
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
	// A soft rim keeps silhouettes readable against the ground.
	RIM = 0.25;
	RIM_TINT = 0.6;
	// FOG is always written: on Vulkan (Forward+) a FOG left unwritten on
	// some paths comes out as garbage and the model renders black.
	FOG = map_fog_on ? map_fog(v_world, CAMERA_POSITION_WORLD) : vec4(0.0);
}
