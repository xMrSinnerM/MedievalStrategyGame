class_name WorldGenerator
extends RefCounted
## Generates the continent from a fixed seed: heightmap, biome mask and rivers.
##
## The output is written to world/ by scripts/tools/generate_world.gd. After that
## the files are the source of truth: edit them by hand, the game only loads them.
##
## Coordinates: x runs west to east, z runs north to south, both 0..world_size.
## Range and region shapes below are given in normalized map coordinates (0..1).

const MOUNTAIN_RANGES := [
	# The northern wall that seals off the snowy north. Passes come from noise.
	{"points": [Vector2(0.10, 0.25), Vector2(0.28, 0.215), Vector2(0.47, 0.24), Vector2(0.66, 0.205), Vector2(0.84, 0.25)], "width": 0.032, "strength": 1.0},
	# The eastern spine between the central plains and the eastern coast.
	{"points": [Vector2(0.73, 0.31), Vector2(0.695, 0.43), Vector2(0.715, 0.55), Vector2(0.68, 0.67)], "width": 0.028, "strength": 0.9},
	# The southern ridge at the edge of the desert.
	{"points": [Vector2(0.26, 0.715), Vector2(0.40, 0.69), Vector2(0.55, 0.735)], "width": 0.026, "strength": 0.7},
	# Rolling western highlands under the forests.
	{"points": [Vector2(0.17, 0.37), Vector2(0.14, 0.49), Vector2(0.18, 0.6)], "width": 0.05, "strength": 0.38},
]

const ISLANDS := [
	Vector3(0.935, 0.37, 0.026),
	Vector3(0.94, 0.60, 0.02),
	Vector3(0.925, 0.49, 0.012),
	Vector3(0.09, 0.84, 0.018),
]

var seed_value: int
var world_size: float
var resolution: int
var max_height: float
var sea_level: float

var heights := PackedFloat32Array()   ## normalized 0..1, resolution * resolution
var rivers: Array = []                ## Array of Array[[x, z, surface_y, width]]

var _warp := FastNoiseLite.new()
var _coast := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _passes := FastNoiseLite.new()
var _biome := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _dunes := FastNoiseLite.new()
var _last_radius := 0.0   ## radial distance from the continent centre, set by _continent()


func _init(config: Dictionary) -> void:
	seed_value = int(config.get("seed", 1))
	world_size = float(config.get("world_size", 2048))
	resolution = int(config.get("heightmap_resolution", 1025))
	max_height = float(config.get("max_height", 300.0))
	sea_level = float(config.get("sea_level", 40.0))
	_setup_noise()


func _setup_noise() -> void:
	var noises := [_warp, _coast, _hills, _detail, _ridges, _passes, _biome, _forest, _dunes]
	for i in noises.size():
		var n: FastNoiseLite = noises[i]
		n.seed = seed_value * 31 + i * 1013
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
	_warp.frequency = 1.0 / 900.0
	_warp.fractal_octaves = 3
	_coast.frequency = 1.0 / 260.0
	_coast.fractal_octaves = 4
	_hills.frequency = 1.0 / 380.0
	_hills.fractal_octaves = 5
	_detail.frequency = 1.0 / 60.0
	_detail.fractal_octaves = 3
	_ridges.frequency = 1.0 / 210.0
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_passes.frequency = 1.0 / 170.0
	_passes.fractal_octaves = 2
	_biome.frequency = 1.0 / 240.0
	_biome.fractal_octaves = 3
	_forest.frequency = 1.0 / 150.0
	_forest.fractal_octaves = 4
	_dunes.frequency = 1.0 / 90.0
	_dunes.fractal_octaves = 2


# --- Public -----------------------------------------------------------------

func generate_heights() -> void:
	var n := resolution
	heights.resize(n * n)
	var cell := world_size / float(n - 1)
	var s := sea_level / max_height
	for j in n:
		var z := j * cell
		for i in n:
			var x := i * cell
			heights[j * n + i] = _height_at(x, z, s)
		if j % 128 == 0:
			print("  heights: row %d / %d" % [j, n])


func generate_rivers(count: int) -> void:
	var tracer := _RiverTracer.new(self)
	rivers = tracer.trace(count)


func height_image() -> Image:
	return Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, heights.to_byte_array())


func preview_image() -> Image:
	var img := Image.create(resolution, resolution, false, Image.FORMAT_L8)
	for j in resolution:
		for i in resolution:
			var h := heights[j * resolution + i]
			img.set_pixel(i, j, Color(h, h, h))
	return img


func biome_image(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var px := world_size / float(size)
	for j in size:
		for i in size:
			var x := (i + 0.5) * px
			var z := (j + 0.5) * px
			img.set_pixel(i, j, _biome_at(x, z))
	return img


func sample_height(x: float, z: float) -> float:
	## Bilinear sample of the normalized heightmap at a world position.
	var n := resolution
	var fx := clampf(x / world_size * (n - 1), 0.0, n - 1.001)
	var fz := clampf(z / world_size * (n - 1), 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * n + i]
	var b := heights[j * n + i + 1]
	var c := heights[(j + 1) * n + i]
	var d := heights[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


# --- Shape functions -----------------------------------------------------------

func _continent(x: float, z: float) -> float:
	var u := x / world_size
	var v := z / world_size
	var wu := _warp.get_noise_2d(x, z) * 0.15
	var wv := _warp.get_noise_2d(x + 7919.0, z - 3571.0) * 0.15
	var dx := (u + wu - 0.49) / 0.425
	var dz := (v + wv - 0.5) / 0.45
	var r := sqrt(dx * dx + dz * dz) + _coast.get_noise_2d(x, z) * 0.13 + _detail.get_noise_2d(x, z) * 0.03
	_last_radius = r
	var c := 1.0 - smoothstep(0.80, 1.0, r)
	for isl: Vector3 in ISLANDS:
		var d := Vector2(u - isl.x, v - isl.y).length() / isl.z + _coast.get_noise_2d(x * 2.0, z * 2.0) * 0.35
		c = maxf(c, 1.0 - smoothstep(0.55, 1.2, d))
	return c


func _range_mask(u: float, v: float, width_scale: float) -> float:
	var p := Vector2(u, v)
	var m := 0.0
	for r: Dictionary in MOUNTAIN_RANGES:
		var pts: Array = r.points
		var best := 1e9
		for k in pts.size() - 1:
			best = minf(best, _segment_distance(p, pts[k], pts[k + 1]))
		var w: float = r.width * width_scale
		m = maxf(m, exp(-(best * best) / (w * w)) * r.strength)
	return m


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func desert_weight(x: float, z: float) -> float:
	var u := x / world_size
	var v := z / world_size + _biome.get_noise_2d(x, z) * 0.05
	var w := smoothstep(0.735, 0.79, v)
	w *= smoothstep(0.14, 0.26, u) * (1.0 - smoothstep(0.80, 0.9, u))
	return w


func snow_weight(x: float, z: float) -> float:
	var v := z / world_size + _biome.get_noise_2d(x + 999.0, z) * 0.035
	return 1.0 - smoothstep(0.15, 0.215, v)


func _height_at(x: float, z: float, s: float) -> float:
	var c := _continent(x, z)
	var hills := _hills.get_noise_2d(x, z) * 0.5 + 0.5
	var detail := _detail.get_noise_2d(x, z)
	# The land rises gently inland so water drains towards the coast.
	var inland := clampf(0.9 - _last_radius, 0.0, 0.9)
	var plains := s + 0.012 + 0.075 * inland + 0.07 * hills * hills + 0.012 * detail
	var h := lerpf(0.025, plains, c)
	if c < 0.35:
		return h

	var u := x / world_size
	var v := z / world_size
	var land := smoothstep(0.5, 0.9, c)

	# Rugged north.
	var north := 1.0 - smoothstep(0.17, 0.26, v)
	h += north * land * 0.07 * hills

	# Mountain ranges with ridged peaks and passes cut by noise.
	var m := _range_mask(u, v, 1.0)
	var foothills := _range_mask(u, v, 2.6)
	if foothills > 0.01:
		var pass_cut := smoothstep(-0.6, -0.2, _passes.get_noise_2d(x, z))
		var ridged := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
		h += land * (foothills * 0.07 * (0.5 + ridged) + m * pass_cut * (0.18 + 0.48 * ridged * ridged))

	# Flatter desert with dune ripples.
	var d := desert_weight(x, z)
	if d > 0.0:
		var dune := absf(sin(x * 0.045 + _dunes.get_noise_2d(x, z) * 6.0))
		var flat := s + 0.025 + 0.05 * hills + 0.01 * dune
		h = lerpf(h, minf(h, flat), d * 0.75 * (1.0 - m))
	return clampf(h, 0.0, 1.0)


func _biome_at(x: float, z: float) -> Color:
	var h := sample_height(x, z) * max_height
	var land := 1.0 if h > sea_level + 1.5 else 0.0
	var desert := desert_weight(x, z) * land
	var snow := snow_weight(x, z) * land
	var u := x / world_size
	var v := z / world_size
	var f := _forest.get_noise_2d(x, z) * 0.5 + 0.5
	var bias := 0.24 * (1.0 - smoothstep(0.24, 0.40, u))       # Thornwald woods
	bias += 0.10 * (1.0 - smoothstep(0.20, 0.30, v))            # northern taiga
	bias += 0.05 * smoothstep(0.74, 0.82, u)                     # eastern coast groves
	var forest := smoothstep(0.56 - bias, 0.66 - bias, f)
	forest *= land * (1.0 - desert) * (1.0 - smoothstep(150.0, 185.0, h))
	return Color(desert, forest, snow)


# --- Rivers ---------------------------------------------------------------------
#
# Drainage is solved on a half-resolution grid with a priority flood from the
# sea: every land cell gets a downstream neighbour, so water always reaches the
# coast. Counting how many cells drain through each cell (flow accumulation)
# then shows where rivers naturally form; those paths are carved into the
# full-resolution heightmap.

class _RiverTracer:
	var g: WorldGenerator
	var n: int                              ## half-resolution grid size
	var hs := PackedFloat32Array()          ## half-resolution heights (normalized)
	var receiver := PackedInt32Array()
	var accumulation := PackedInt32Array()

	func _init(generator: WorldGenerator) -> void:
		g = generator
		n = (g.resolution - 1) / 2 + 1

	func trace(max_rivers: int) -> Array:
		_sample_half_res()
		_priority_flood()
		var paths := _extract_network(max_rivers)
		var result: Array = []
		for path in paths:
			result.append(_carve(path))
		_apply_stamps()
		return result

	func _sample_half_res() -> void:
		hs.resize(n * n)
		var full := g.resolution
		var jitter := RandomNumberGenerator.new()
		jitter.seed = g.seed_value * 7 + 3
		for j in n:
			for i in n:
				# A whisper of noise breaks ties on flat ground so rivers meander.
				hs[j * n + i] = g.heights[(j * 2) * full + i * 2] + jitter.randf() * 0.0004

	func _priority_flood() -> void:
		var s := g.sea_level / g.max_height
		var total := n * n
		receiver.resize(total)
		receiver.fill(-1)
		var done := PackedByteArray()
		done.resize(total)
		var filled := hs.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.seed = g.seed_value * 13 + 5
		var heap := _Heap.new()
		for k in total:
			var i := k % n
			var j := k / n
			if hs[k] < s or i == 0 or j == 0 or i == n - 1 or j == n - 1:
				heap.push(hs[k], k)
				done[k] = 1
		var order := PackedInt32Array()
		var offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
		while not heap.is_empty():
			var k := heap.pop()
			order.append(k)
			var i := k % n
			var j := k / n
			for o: Vector2i in offsets:
				var ni := i + o.x
				var nj := j + o.y
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var nk := nj * n + ni
				if done[nk]:
					continue
				done[nk] = 1
				# Random steps across flat or filled ground keep rivers from running in straight lines.
				filled[nk] = maxf(hs[nk], filled[k] + 0.000001 + rng.randf() * 0.00003)
				receiver[nk] = k
				heap.push(filled[nk], nk)
		accumulation.resize(total)
		accumulation.fill(1)
		for idx in range(order.size() - 1, -1, -1):
			var k := order[idx]
			if receiver[k] >= 0:
				accumulation[receiver[k]] += accumulation[k]

	func _extract_network(max_rivers: int) -> Array:
		# Lower the threshold until enough river heads appear.
		var s := g.sea_level / g.max_height
		var threshold := 6000
		var heads: Array[int] = []
		while threshold > 150:
			heads = _find_heads(threshold, s)
			if heads.size() >= max_rivers:
				break
			threshold = int(threshold * 0.8)
		# Longest catchments first, so main rivers claim their path before tributaries.
		heads.sort_custom(func(a, b): return _path_length(a, s) > _path_length(b, s))
		var claimed := {}
		var paths: Array = []
		for head in heads:
			if paths.size() >= max_rivers:
				break
			var path := PackedInt32Array()
			var k := head
			while k >= 0:
				path.append(k)
				if hs[k] < s or claimed.has(k):
					break
				k = receiver[k]
			if path.size() < 28:
				continue
			for c in path:
				claimed[c] = true
			paths.append({"cells": path, "threshold": threshold})
		return paths

	func _find_heads(threshold: int, s: float) -> Array[int]:
		var is_river := PackedByteArray()
		is_river.resize(n * n)
		for k in n * n:
			if accumulation[k] >= threshold and hs[k] >= s:
				is_river[k] = 1
		var has_river_donor := PackedByteArray()
		has_river_donor.resize(n * n)
		for k in n * n:
			if is_river[k] and receiver[k] >= 0:
				has_river_donor[receiver[k]] = 1
		var heads: Array[int] = []
		for k in n * n:
			if is_river[k] and not has_river_donor[k]:
				heads.append(k)
		return heads

	func _path_length(head: int, s: float) -> int:
		var count := 0
		var k := head
		while k >= 0 and hs[k] >= s:
			count += 1
			k = receiver[k]
		return count

	func _carve(path: Dictionary) -> Array:
		## Profiles one river and queues its channel and valley for _apply_stamps().
		var cells: PackedInt32Array = path.cells
		var threshold: int = path.threshold
		var full := g.resolution
		var cell := g.world_size / (full - 1)
		var s := g.sea_level / g.max_height
		var count := cells.size()
		var pos: Array[Vector2] = []
		var widths := PackedFloat32Array()
		var ground := PackedFloat32Array()
		for idx in count:
			var k := cells[idx]
			var p := Vector2((k % n) * 2, (k / n) * 2)
			pos.append(p)
			var flow := float(accumulation[k]) / float(threshold)
			widths.append(clampf(3.5 + 2.6 * sqrt(flow), 4.0, 18.0))
			ground.append(g.sample_height(p.x * cell, p.y * cell))

		# Water can't flow uphill. A cut-only profile digs gorges through every
		# rise and a fill-only one buries hollows; averaging the two splits the
		# difference, so the land is reshaped about half as much either way.
		var cut := ground.duplicate()
		for idx in range(1, count):
			cut[idx] = minf(cut[idx - 1] - 0.00005, ground[idx])
		var fill := ground.duplicate()
		for idx in range(count - 2, -1, -1):
			fill[idx] = maxf(fill[idx + 1] + 0.00005, ground[idx])
		var surface := PackedFloat32Array()
		surface.resize(count)
		var keep_above := s + 0.6 / g.max_height
		for idx in count:
			var level := (cut[idx] + fill[idx]) * 0.5
			# Stay above the sea until the river actually reaches the coast.
			if ground[idx] > keep_above:
				level = maxf(level, keep_above)
			surface[idx] = level
		for idx in range(1, count):
			surface[idx] = minf(surface[idx], surface[idx - 1])

		var points: Array = []
		for idx in count:
			var p := pos[idx]
			var stamps: Array[Vector2] = [p]
			if idx < count - 1:
				stamps.append((p + pos[idx + 1]) * 0.5)
			for c in stamps:
				_stamps.append([c, surface[idx], widths[idx], absf(surface[idx] - ground[idx])])
			var water := surface[idx] * g.max_height - 0.35
			points.append([snappedf(p.x * cell, 0.01), snappedf(p.y * cell, 0.01), snappedf(water, 0.01), snappedf(widths[idx], 0.01)])
		return points

	var _stamps: Array = []   ## [centre (px), surface (normalized), width (units), reshape amount]

	func _apply_stamps() -> void:
		## Reshapes the terrain around every river: a channel below the water,
		## banks at water level, then a valley blending back into the land.
		## Each pixel follows the nearest stamp so overlapping stamps never fight.
		var full := g.resolution
		var cell := g.world_size / (full - 1)
		var depth := 1.8 / g.max_height
		var bank := 0.4 / g.max_height
		var nearest := PackedFloat32Array()
		nearest.resize(full * full)
		nearest.fill(INF)
		var target := PackedFloat32Array()
		target.resize(full * full)
		for st: Array in _stamps:
			var c: Vector2 = st[0]
			var surface: float = st[1]
			var radius: float = st[2] * 0.5 / cell
			var reshape: float = st[3] * g.max_height
			var valley := minf(radius + 3.0 + reshape * 3.0 / cell, 36.0)
			var ci := int(round(c.x))
			var cj := int(round(c.y))
			var r := int(ceil(valley))
			for oy in range(-r, r + 1):
				var qy := cj + oy
				if qy < 0 or qy >= full:
					continue
				for ox in range(-r, r + 1):
					var qx := ci + ox
					if qx < 0 or qx >= full:
						continue
					var dist := Vector2(qx, qy).distance_to(c)
					var q := qy * full + qx
					if dist > valley or dist >= nearest[q]:
						continue
					nearest[q] = dist
					var t: float
					if dist <= radius:
						var bowl := dist / maxf(radius, 0.001)
						t = lerpf(surface - depth, surface + bank, bowl * bowl)
					else:
						var f := smoothstep(radius, valley, dist)
						t = lerpf(surface + bank, g.heights[q], f)
					target[q] = t
		for q in full * full:
			if nearest[q] < INF:
				g.heights[q] = target[q]


class _Heap:
	## Binary min-heap of (priority, value) pairs.
	var keys := PackedFloat32Array()
	var values := PackedInt32Array()

	func is_empty() -> bool:
		return values.is_empty()

	func push(key: float, value: int) -> void:
		keys.append(key)
		values.append(value)
		var i := values.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if keys[parent] <= keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := values[0]
		var last := values.size() - 1
		_swap(0, last)
		keys.resize(last)
		values.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var smallest := i
			if l < last and keys[l] < keys[smallest]:
				smallest = l
			if r < last and keys[r] < keys[smallest]:
				smallest = r
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var tk := keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv := values[a]
		values[a] = values[b]
		values[b] = tv
