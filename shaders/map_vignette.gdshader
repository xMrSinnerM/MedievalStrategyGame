shader_type canvas_item;
// The world map's frame: its edges darken softly into a warm brown, like
// an old painted map, so the middle of the screen stands out.

uniform float strength = 0.38;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.0, 0.85);
	float edge = smoothstep(0.42, 0.85, length(d) * 1.25);
	COLOR = vec4(0.09, 0.05, 0.02, edge * strength);
}
