shader_type spatial;
// Ground of the castle screen: grass outside the walls, a trodden yard inside,
// a dirt path from the gate to the keep, and the build grid when placing.

uniform float cell = 2.0;
uniform float grid_cells = 24.0;
uniform float wall_margin = 2.0;
uniform float grid_amount = 0.0;          // 0 hidden .. 1 fully shown
uniform vec4 highlight_rect = vec4(0.0);  // footprint under the mouse: x, z, width, depth (world)
uniform vec3 highlight_color : source_color = vec3(0.3, 0.9, 0.35);
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float size = cell * grid_cells;
	float n = texture(noise, p * 0.012).r;
	float n2 = texture(noise, p * 0.07 + 0.37).r;

	vec3 grass = mix(vec3(0.27, 0.4, 0.17), vec3(0.38, 0.48, 0.21), n);
	vec3 yard = mix(vec3(0.4, 0.44, 0.24), vec3(0.47, 0.47, 0.29), n2);
	vec3 dirt = mix(vec3(0.45, 0.37, 0.26), vec3(0.53, 0.44, 0.31), n2);

	// Inside the wall.
	float inner = min(min(p.x, p.y), min(size - p.x, size - p.y)) + wall_margin;
	vec3 col = mix(grass, yard, smoothstep(-1.5, 1.0, inner));

	// Path from the south gate to the middle.
	float path = 1.0 - smoothstep(1.6, 2.6 + n2, abs(p.x - size * 0.5));
	path *= step(size * 0.5, p.y) * (1.0 - smoothstep(size + wall_margin + 6.0, size + wall_margin + 14.0, p.y));
	col = mix(col, dirt, path);

	// Build grid lines.
	vec2 g = abs(fract(p / cell + 0.5) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.03, 0.09, min(g.x, g.y));
	float on_grid = step(0.0, p.x) * step(0.0, p.y) * step(p.x, size) * step(p.y, size);
	col = mix(col, vec3(0.95, 0.92, 0.8), line * on_grid * grid_amount * 0.45);

	// Footprint under the mouse while placing or moving.
	vec2 h0 = highlight_rect.xy;
	vec2 h1 = highlight_rect.xy + highlight_rect.zw;
	float in_h = step(h0.x, p.x) * step(h0.y, p.y) * step(p.x, h1.x) * step(p.y, h1.y);
	col = mix(col, highlight_color, in_h * 0.55);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
