extends Node3D
## Resource villages on the world map: a hamlet around the building for what
## it works (lumber mill, mine, windmill and fields, or market) and a label with its name, level
## and holder. Yours are labelled in gold, your alliance's in green, other
## players' in blue and the militia's in pale stone. Clicking one opens the
## village panel (village_panel.gd).

const PICK_RADIUS := 16.0
const MILITIA_COLOR := Color(0.86, 0.82, 0.74)
const OTHERS_COLOR := Color(0.62, 0.84, 1.0)
const ALLY_COLOR := Color(0.55, 0.95, 0.55)
## KayKit pieces in the middle of each village, by resource: [piece, position, scale, yaw].
const WORKS := {
	"wood": [["building_lumbermill_blue", Vector3(0, 0, 0), 5.5, 0.0], ["resource_lumber", Vector3(5, 0, 4), 4.0, 0.6], ["tree_single_A_cut", Vector3(-5, 0, 4), 4.0, 0.0]],
	"stone": [["building_mine_blue", Vector3(0, 0, -1), 5.0, 0.0], ["resource_stone", Vector3(5, 0, 4), 4.0, 0.0], ["rock_single_B", Vector3(-5, 0, 4), 4.0, 1.0]],
	"food": [["building_windmill_blue", Vector3(-2, 0, -2), 5.5, 0.0], ["building_grain", Vector3(4, 0, 3), 4.0, 0.0], ["sack", Vector3(-4, 0, 4), 4.0, 0.0]],
	"gold": [["building_market_blue", Vector3(0, 0, -1), 5.0, 0.0], ["building_well_blue", Vector3(5, 0, 5), 3.5, 0.0], ["crate_A_big", Vector3(-5, 0, 4), 3.5, 0.3]],
}

var _nodes := {}          ## village id -> Settlement
var _zoom_t := 0.0


func build() -> void:
	for v: Dictionary in Economy.villages:
		var s := Settlement.new()
		add_child(s)
		s.setup(_settlement_data(v))
		s.add_child(_works(String(v.resource)))
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


static func _works(resource: String) -> MeshInstance3D:
	## The building for the village's resource, in the middle of the hamlet.
	var kit := KitModels.new()
	for part: Array in WORKS.get(resource, WORKS.gold):
		var at: Vector3 = part[1]
		kit.add(part[0], Transform3D(Basis(Vector3.UP, part[3]).scaled(Vector3.ONE * float(part[2])), at))
	var works := MeshInstance3D.new()
	works.name = "Works"
	works.mesh = kit.commit(KitModels.VILLAGE_COLOR, true)
	return works
