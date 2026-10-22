extends Node3D
## Resource villages on the world map: a hamlet with a heap of what it works
## (logs, stone, sheaves or a market stall) and a label with its name, level
## and holder. Yours are labelled in gold, your alliance's in green, other
## players' in blue and the militia's in pale stone. Clicking one opens the
## village panel (village_panel.gd).

const PICK_RADIUS := 16.0
const MILITIA_COLOR := Color(0.86, 0.82, 0.74)
const OTHERS_COLOR := Color(0.62, 0.84, 1.0)
const ALLY_COLOR := Color(0.55, 0.95, 0.55)
## The heap beside each village, by resource.
const HEAP := {
	"wood": Color(0.45, 0.3, 0.17),
	"stone": Color(0.6, 0.6, 0.58),
	"food": Color(0.88, 0.74, 0.32),
	"gold": Color(0.92, 0.76, 0.24),
}

var _nodes := {}          ## village id -> Settlement
var _zoom_t := 0.0


func build() -> void:
	for v: Dictionary in Economy.villages:
		var s := Settlement.new()
		add_child(s)
		s.setup(_settlement_data(v))
		s.add_child(_heap(String(v.resource)))
		_nodes[String(v.id)] = s
	EventBus.camera_zoom_changed.connect(func(t: float) -> void:
		_zoom_t = t
		for id in _nodes:
			_nodes[id].set_zoom(t))
	Economy.villages_changed.connect(_refresh)
	Economy.alliance_changed.connect(func(_e: String) -> void: _refresh())
	_refresh()


func village_at(map_pos: Vector2) -> String:
	## The village under this map position ("" if none).
	var best := ""
	var best_d := PICK_RADIUS
	for v: Dictionary in Economy.villages:
		var d := Vector2(float(v.position[0]), float(v.position[1])).distance_to(map_pos)
		if d < best_d:
			best_d = d
			best = String(v.id)
	return best


func _refresh() -> void:
	for v: Dictionary in Economy.villages:
		var id := String(v.id)
		var label: Label3D = _nodes[id].get_node("Label")
		var state := Economy.village_state(id)
		var owner := String(state.get("owner", ""))
		var tag := String(state.get("tag", ""))
		label.text = "%s  Lv %d %s" % [v.name, int(v.level), v.resource]
		if Economy.is_my_village(id):
			label.text += "\nyours"
			label.modulate = Color(1.0, 0.84, 0.4)
		elif owner != "":
			label.text += "\n" + ("[%s] " % tag if tag != "" else "") + owner
			label.modulate = ALLY_COLOR if state.get("ally", false) else OTHERS_COLOR
		else:
			label.modulate = MILITIA_COLOR


static func _settlement_data(v: Dictionary) -> Dictionary:
	return {
		"id": "rv:" + String(v.id), "name": String(v.name), "type": "village", "faction": "",
		"position": [float(v.position[0]), float(v.position[1])],
		"rotation_deg": float(absi(hash(String(v.id))) % 360), "label_color": MILITIA_COLOR,
	}


static func _heap(resource: String) -> MeshInstance3D:
	## A heap of the village's resource by its edge.
	var kit := MeshKit.new()
	var color: Color = HEAP.get(resource, Color.WHITE)
	var at := Vector3(10.0, 0.0, -6.0)
	match resource:
		"wood":
			for k in 5:
				var row := Vector3(0, 0.6 + (k / 3) * 1.1, (k % 3 - 1) * 1.15 + (k / 3) * 0.55)
				kit.cylinder(color, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), at + row), 0.55, 4.5, 6)
		"stone":
			for k in 4:
				kit.box(color.darkened(0.08 * k), Transform3D(Basis(Vector3.UP, k * 0.5), at + Vector3((k % 2) * 1.8 - 0.9, 0.7 + (k / 2) * 1.3, (k / 2) * 0.4)),
						Vector3(1.7, 1.3, 1.5))
		"food":
			for k in 4:
				var p := at + Vector3((k % 2) * 2.2 - 1.1, 0.0, (k / 2) * 2.2 - 1.1)
				kit.cone(color, Transform3D(Basis(), p), 0.9, 2.8, 6)
		_:
			kit.box(Color(0.55, 0.36, 0.2), Transform3D(Basis(), at + Vector3(0, 1.2, 0)), Vector3(3.6, 0.3, 2.4))
			kit.box(Color(0.75, 0.2, 0.18), Transform3D(Basis(), at + Vector3(0, 3.2, 0)), Vector3(4.0, 0.25, 2.8))
			for k in 4:
				kit.cylinder(Color(0.45, 0.3, 0.17), Transform3D(Basis(), at + Vector3((k % 2) * 3.4 - 1.7, 0, (k / 2) * 2.2 - 1.1)), 0.15, 3.2, 5)
			kit.dome(color, Transform3D(Basis(), at + Vector3(0, 1.35, 0)), 0.9)
	var heap := MeshInstance3D.new()
	heap.name = "Heap"
	heap.mesh = kit.commit()
	return heap
