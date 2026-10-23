shader_type spatial;
// Soldiers from the KayKit Adventurers pack (CC0). Each character has a small
// gradient atlas of 8 x 4 swatches; the swatches listed in team_cells (row * 8
// + column, -1 for none) are its tabard, cape or shield, redrawn here in the
// owner's colour. Uses the world map fog.

#include "res://shaders/includes/map_common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 team : source_color = vec3(0.66, 0.2, 0.16);
uniform ivec4 team_cells = ivec4(-1);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = texture(atlas, UV).rgb;
	ivec2 cell = ivec2(floor(UV * vec2(8.0, 4.0)));
	int index = cell.y * 8 + cell.x;
	if (index == team_cells.x || index == team_cells.y || index == team_cells.z || index == team_cells.w) {
		float t = clamp(fract(UV.y * 4.0), 0.0, 1.0);
		col = mix(team * 1.3 + vec3(0.04), team * 0.45, t);
	}
	ALBEDO = col;
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	RIM = 0.3;
	RIM_TINT = 0.6;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
