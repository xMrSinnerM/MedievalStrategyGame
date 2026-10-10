extends Node3D
## Places every settlement from data/settlements.json and a bridge wherever a
## road crosses a river (found by RoadNetwork).

const BRIDGE_STONE := Color(0.6, 0.56, 0.5)
const BRIDGE_DECK := Color(0.45, 0.34, 0.24)

var settlements: Array[Settlement] = []
var bridge_count := 0
var _zoom_t := 0.0


func build() -> void:
	for data in GameData.settlements:
		var s := Settlement.new()
		add_child(s)
		s.setup(data)
		settlements.append(s)
	_build_bridges()
	EventBus.camera_zoom_changed.connect(_on_zoom_changed)


func rebuild(settlement_id: String) -> void:
	## Redraws one settlement after it changed hands (banner, colours, label).
	for i in settlements.size():
		var old := settlements[i]
		if old.id != settlement_id:
			continue
		var s := Settlement.new()
		add_child(s)
		s.setup(GameData.get_settlement(settlement_id))
		s.set_zoom(_zoom_t)
		settlements[i] = s
		old.queue_free()
		return


func _on_zoom_changed(zoom_t: float) -> void:
	_zoom_t = zoom_t
	for s in settlements:
		s.set_zoom(zoom_t)


func _build_bridges() -> void:
	var kit := MeshKit.new()
	for b in GameData.roads.bridges:
		_bridge(kit, b)
	bridge_count = GameData.roads.bridges.size()
	var mesh := MeshInstance3D.new()
	mesh.name = "Bridges"
	mesh.mesh = kit.commit()
	add_child(mesh)


func _bridge(kit: MeshKit, b: Dictionary) -> void:
	var dir: Vector2 = b.dir
	var half_len: float = b.half_length
	var deck_y: float = b.deck_y
	var surface: float = b.river_surface
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x))
	var origin := Vector3(b.at.x, 0, b.at.y)
	var deck_w: float = b.half_width * 2.0
	# Stone piers down to the riverbed, then the deck and low parapets.
	for side in [-1.0, 1.0]:
		var pier := origin + basis * Vector3(side * b.river_width * 0.25, 0, 0)
		kit.box(BRIDGE_STONE, Transform3D(basis, pier + Vector3(0, surface - 6.0, 0)), Vector3(1.8, deck_y - surface + 6.0, deck_w))
	kit.box(BRIDGE_DECK, Transform3D(basis, origin + Vector3(0, deck_y - 0.6, 0)), Vector3(half_len * 2.0, 0.6, deck_w))
	for side in [-1.0, 1.0]:
		var rail := origin + basis * Vector3(0, 0, side * (deck_w * 0.5 - 0.3))
		kit.box(BRIDGE_STONE, Transform3D(basis, rail + Vector3(0, deck_y, 0)), Vector3(half_len * 2.0, 0.8, 0.5))
