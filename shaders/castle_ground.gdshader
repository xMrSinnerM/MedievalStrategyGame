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

	float n3 = texture(noise, p * 0.45 + 0.71).r;
	vec3 grass = mix(vec3(0.24, 0.38, 0.14), vec3(0.38, 0.5, 0.19), n);
	grass = mix(grass, vec3(0.5, 0.58, 0.26), smoothstep(0.62, 0.8, n2) * 0.5);
	vec3 yard = mix(vec3(0.34, 0.47, 0.19), vec3(0.41, 0.52, 0.22), n2);
	// Mown stripes on the yard lawn.
	yard *= 0.96 + 0.05 * step(0.5, fract(p.x / 4.0));

	// Cobbles: staggered rows of stones with darker joints.
	vec2 cp = p / vec2(0.9, 0.7);
	cp.x += 0.5 * floor(cp.y);
	vec2 cf = abs(fract(cp) - 0.5);
	float joint = smoothstep(0.36, 0.48, max(cf.x * 0.9, cf.y));
	float stone_id = fract(sin(dot(floor(cp), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 dirt = mix(vec3(0.5, 0.47, 0.42), vec3(0.6, 0.56, 0.49), stone_id);
	dirt = mix(dirt, vec3(0.36, 0.33, 0.28), joint);

	// Inside the wall.
	float inner = min(min(p.x, p.y), min(size - p.x, size - p.y)) + wall_margin;
	vec3 col = mix(grass, yard, smoothstep(-1.5, 1.0, inner));
	// Wild flowers in the meadow outside.
	float flower = step(0.83, n3) * step(0.55, n) * (1.0 - smoothstep(-1.5, 1.0, inner));
	col = mix(col, mix(vec3(0.95, 0.9, 0.55), vec3(0.95, 0.95, 0.92), step(0.5, n2)), flower * 0.8);

	// Path from the south gate to the middle.
	float path = 1.0 - smoothstep(1.9, 2.1, abs(p.x - size * 0.5));
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
