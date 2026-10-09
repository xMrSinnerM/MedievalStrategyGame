extends Node3D
## Places every settlement from data/settlements.json and a bridge wherever a
## road crosses a river.

const BRIDGE_STONE := Color(0.6, 0.56, 0.5)
const BRIDGE_DECK := Color(0.45, 0.34, 0.24)

var settlements: Array[Settlement] = []
var bridge_count := 0


func build() -> void:
	for data in GameData.settlements:
		var s := Settlement.new()
		add_child(s)
		s.setup(data)
		settlements.append(s)
	_build_bridges()
	EventBus.camera_zoom_changed.connect(_on_zoom_changed)


func _on_zoom_changed(zoom_t: float) -> void:
	for s in settlements:
		s.set_zoom(zoom_t)


func _build_bridges() -> void:
	var terrain: TerrainData = GameData.terrain
	# Bucket river segments on a coarse grid so each road segment only checks its neighbours.
	const BUCKET := 64.0
	var buckets := {}
	for river in terrain.rivers:
		var pts: Array = river.points
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var key := Vector2i((a + b) / 2.0 / BUCKET)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append([a, b, pts[k], pts[k + 1]])

	var kit := MeshKit.new()
	var placed: Array[Vector2] = []
	for road in GameData.roads.roads:
		var pts: Array = road.points
		var width := RoadNetwork.MAIN_WIDTH if road.kind == "main" else RoadNetwork.TRACK_WIDTH
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var key := Vector2i((a + b) / 2.0 / BUCKET)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					for seg in buckets.get(key + Vector2i(ox, oy), []):
						var hit = Geometry2D.segment_intersects_segment(a, b, seg[0], seg[1])
						if hit == null:
							continue
						var p: Vector2 = hit
						var near := false
						for q in placed:
							if q.distance_to(p) < 12.0:
								near = true
								break
						if near:
							continue
						placed.append(p)
						var t: float = p.distance_to(seg[0]) / maxf(seg[0].distance_to(seg[1]), 0.001)
						var surface: float = lerpf(seg[2][2], seg[3][2], t)
						var river_width: float = lerpf(seg[2][3], seg[3][3], t)
						_bridge(kit, terrain, p, (b - a).normalized(), surface, river_width, width)
	var mesh := MeshInstance3D.new()
	mesh.name = "Bridges"
	mesh.mesh = kit.commit()
	add_child(mesh)


func _bridge(kit: MeshKit, terrain: TerrainData, at: Vector2, dir: Vector2, surface: float, river_width: float, road_width: float) -> void:
	var half_len := river_width * 0.5 + 5.0
	var end_a := at - dir * half_len
	var end_b := at + dir * half_len
	var deck_y := maxf(surface + 1.6, maxf(terrain.get_height(end_a.x, end_a.y), terrain.get_height(end_b.x, end_b.y)) + 0.3)
	var yaw := atan2(-dir.y, dir.x)
	var basis := Basis(Vector3.UP, yaw)
	var origin := Vector3(at.x, 0, at.y)
	var deck_w := road_width + 1.6
	# Stone piers down to the riverbed, then the deck and low parapets.
	for side in [-1.0, 1.0]:
		var pier := origin + basis * Vector3(side * river_width * 0.25, 0, 0)
		kit.box(BRIDGE_STONE, Transform3D(basis, pier + Vector3(0, surface - 6.0, 0)), Vector3(1.8, deck_y - surface + 6.0, deck_w))
	kit.box(BRIDGE_DECK, Transform3D(basis, origin + Vector3(0, deck_y - 0.6, 0)), Vector3(half_len * 2.0, 0.6, deck_w))
	for side in [-1.0, 1.0]:
		var rail := origin + basis * Vector3(0, 0, side * (deck_w * 0.5 - 0.3))
		kit.box(BRIDGE_STONE, Transform3D(basis, rail + Vector3(0, deck_y, 0)), Vector3(half_len * 2.0, 0.8, 0.5))
	bridge_count += 1
