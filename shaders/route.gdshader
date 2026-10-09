shader_type spatial;
// The player's planned route: a ribbon of dashes that drift towards the
// destination. UV.x counts map units along the route from the party.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/includes/map_common.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.86, 0.45, 0.9);
uniform float dash_length = 6.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dash = step(0.45, fract(UV.x / dash_length - TIME * 0.8));
	float edge = 1.0 - smoothstep(0.7, 1.0, abs(UV.y * 2.0 - 1.0));
	ALBEDO = color.rgb;
	ALPHA = color.a * dash * edge;
	FOG = map_fog(v_world, CAMERA_POSITION_WORLD);
}
