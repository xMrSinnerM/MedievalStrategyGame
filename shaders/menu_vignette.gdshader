shader_type canvas_item;
// Darkens the title screen's edges, and its left side behind the banner, so
// the menu reads well over the bright map picture.

uniform float strength = 0.75;

void fragment() {
	vec2 d = UV - vec2(0.62, 0.48);
	float edge = smoothstep(0.35, 0.95, length(d * vec2(1.25, 1.0)));
	float left = smoothstep(0.55, 0.0, UV.x) * 0.45;
	float a = clamp(edge * strength + left, 0.0, 0.9);
	COLOR = vec4(0.06, 0.035, 0.02, a);
}
