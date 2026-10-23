extends Node3D
## Places every settlement from data/settlements.json and a bridge wherever a
## road crosses a river (found by RoadNetwork). Towns are capitals: their
## labels say who holds them. The villages are resource villages, drawn by
## villages_layer.gd.

const BRIDGE_STONE := Color(0.6, 0.56, 0.5)
const BRIDGE_DECK := Color(0.45, 0.34, 0.24)
const LABEL := Color(1.0, 0.96, 0.86)
const LABEL_MINE := Color(1.0, 0.84, 0.4)
const LABEL_ALLY := Color(0.6, 0.95, 0.6)
const LABEL_OTHER := Color(1.0, 0.62, 0.5)

var settlements: Array[Settlement] = []
var bridge_count := 0
var _zoom_t := 0.0


func build() -> void:
	for data in GameData.settlements:
		if data.type == "village":
			continue  # a resource village now: villages_layer.gd draws it
		var s := Settlement.new()
		add_child(s)
		s.setup(data)
		settlements.append(s)
	_build_bridges()
	EventBus.camera_zoom_changed.connect(_on_zoom_changed)
	Economy.villages_changed.connect(_show_holders)
	_show_holders()


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
		_show_holders()
		return


func show_fortress(id: String, text: String, ready: bool) -> void:
	## Online: a castle is a fortress; its label shows its level (and any rebuilding).
	for s in settlements:
		if s.id == id:
			s.set_holder(text, LABEL_OTHER if ready else Color(0.7, 0.62, 0.58))
			return


func _show_holders() -> void:
	## Writes who holds each capital under its town's name.
	for s in settlements:
		if s.type != "town" or not Economy.is_capital(s.id):
			continue
		var state := Economy.village_state(s.id)
		var owner := String(state.get("owner", ""))
		var tag := String(state.get("tag", ""))
		if Economy.is_my_village(s.id):
			s.set_holder("(yours)", LABEL_MINE)
		elif owner != "":
			s.set_holder(("[%s] " % tag if tag != "" else "") + owner, LABEL_ALLY if state.get("ally", false) else LABEL_OTHER)
		else:
			s.set_holder("", LABEL)


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
