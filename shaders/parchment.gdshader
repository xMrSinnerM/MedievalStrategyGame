shader_type spatial;
// Strategic "parchment map" shown at maximum zoom-out: inked coastline,
// contour lines, rivers, faction territories as colour washes with borders.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float world_size = 2048.0;
uniform float heightmap_resolution = 1025.0;
uniform float max_height = 300.0;
uniform float sea_level = 40.0;
uniform float sheet_margin = 220.0;   // paper beyond the map on each side
uniform float opacity = 0.0;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D territory : filter_nearest, repeat_disable;  // r = faction index + 1, 0 = none
uniform sampler2D river_mask : filter_linear, repeat_disable;
uniform sampler2D faction_palette : source_color, filter_nearest, repeat_disable;
uniform sampler2D paper_noise : filter_linear_mipmap, repeat_enable;
uniform int faction_count = 5;

uniform vec3 paper_color : source_color = vec3(0.91, 0.84, 0.68);
uniform vec3 sea_tint : source_color = vec3(0.70, 0.78, 0.78);
uniform vec3 ink : source_color = vec3(0.30, 0.22, 0.15);
uniform vec3 river_ink : source_color = vec3(0.25, 0.40, 0.52);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float height_at(vec2 xz) {
	if (xz.x < 0.0 || xz.y < 0.0 || xz.x > world_size || xz.y > world_size) {
		return 0.0;
	}
	float n = heightmap_resolution;
	vec2 uv = (xz / world_size * (n - 1.0) + 0.5) / n;
	return textureLod(heightmap, uv, 0.0).r * max_height;
}

int faction_at(vec2 xz) {
	vec2 uv = xz / world_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return -1;
	}
	return int(round(texture(territory, uv).r * 255.0)) - 1;
}

vec3 faction_color(int idx) {
	return texelFetch(faction_palette, ivec2(idx, 0), 0).rgb;
}

float line(float value, float spacing, float width_px) {
	float f = abs(fract(value / spacing + 0.5) - 0.5) * spacing;
	float w = fwidth(value) * width_px;
	return 1.0 - smoothstep(w * 0.5, w, f);
}

void fragment() {
	vec2 xz = v_world.xz;
	float n_big = texture(paper_noise, xz * 0.0011).r;
	float n_mid = texture(paper_noise, xz * 0.006).r;
	float n_fine = texture(paper_noise, xz * 0.05).r;

	// Paper with stains, darker towards the ragged sheet edge.
	vec2 sheet = (xz + sheet_margin) / (world_size + 2.0 * sheet_margin);
	float edge = min(min(sheet.x, 1.0 - sheet.x), min(sheet.y, 1.0 - sheet.y));
	float ragged = edge - (n_mid - 0.5) * 0.02;
	vec3 col = paper_color * (0.9 + 0.12 * n_big + 0.05 * n_fine);
	col *= mix(0.72, 1.0, smoothstep(0.0, 0.07, ragged));

	float h = height_at(xz);
	float land = smoothstep(sea_level - 0.5, sea_level + 0.5, h);

	// Sea: tinted wash with ripple lines echoing the coast.
	float depth = max(sea_level - h, 0.0);
	vec3 sea = col * sea_tint;
	sea = mix(sea, sea * 0.82, line(depth, 9.0, 1.2) * (1.0 - smoothstep(10.0, 34.0, depth)) * 0.8);

	// Land: relief shading and contour lines.
	float e = 6.0;
	float dx = height_at(xz - vec2(e, 0.0)) - height_at(xz + vec2(e, 0.0));
	float dz = height_at(xz - vec2(0.0, e)) - height_at(xz + vec2(0.0, e));
	float relief = clamp(1.0 + (dx + dz) * 0.012, 0.78, 1.12);
	vec3 ground = col * relief;
	float contour = line(h, 30.0, 1.0) * smoothstep(sea_level + 6.0, sea_level + 20.0, h);
	ground = mix(ground, ink, contour * 0.22);

	int f = faction_at(xz);
	if (f >= 0 && f < faction_count) {
		vec3 fc = faction_color(f);
		ground = mix(ground, ground * mix(vec3(1.0), fc * 1.6, 0.55), 0.6);
		float o = max(fwidth(xz.x) * 1.6, 2.0);
		bool border = faction_at(xz + vec2(o, 0.0)) != f || faction_at(xz - vec2(o, 0.0)) != f
			|| faction_at(xz + vec2(0.0, o)) != f || faction_at(xz - vec2(0.0, o)) != f;
		if (border) {
			ground = mix(ground, fc * 0.55, 0.85);
		}
	}

	float river = smoothstep(0.25, 0.6, texture(river_mask, xz / world_size).r) * land;
	ground = mix(ground, river_ink, river * 0.85);

	col = mix(sea, ground, land);
	float coast = 1.0 - smoothstep(fwidth(h) * 0.6, fwidth(h) * 1.6, abs(h - sea_level));
	col = mix(col, ink, coast * 0.9);

	ALBEDO = col;
	ALPHA = opacity * smoothstep(0.0, 0.006, ragged);
}
