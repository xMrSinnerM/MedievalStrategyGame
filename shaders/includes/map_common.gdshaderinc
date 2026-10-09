// Shared by the world map shaders: map-space helpers and the edge/haze fog.

uniform float world_size = 2048.0;
uniform float heightmap_resolution = 1025.0;
uniform float max_height = 300.0;
uniform float sea_level = 40.0;

uniform vec3 fog_color : source_color = vec3(0.85, 0.80, 0.70);
uniform float fog_edge_start = 0.0;    // distance in from the map border where edge fog ends
uniform float fog_edge_end = 260.0;
uniform float fog_haze_start = 700.0;  // camera distance where haze begins
uniform float fog_haze_end = 4200.0;
uniform float fog_haze_max = 0.5;

// Heightmap UV for a world xz position (texel centres line up with samples).
vec2 map_uv(vec2 xz) {
	float n = heightmap_resolution;
	return (xz / world_size * (n - 1.0) + 0.5) / n;
}

// 0 inside the map, rising to 1 past its border.
float map_edge_fog(vec2 xz) {
	float inner = min(min(xz.x, xz.y), min(world_size - xz.x, world_size - xz.y));
	return 1.0 - smoothstep(fog_edge_start, fog_edge_end, inner);
}

vec4 map_fog(vec3 world_pos, vec3 camera_pos) {
	float haze = smoothstep(fog_haze_start, fog_haze_end, distance(world_pos, camera_pos)) * fog_haze_max;
	return vec4(fog_color, max(map_edge_fog(world_pos.xz), haze));
}
