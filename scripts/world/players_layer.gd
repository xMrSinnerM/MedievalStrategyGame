extends Node3D
## Online: the other players' castles on the world map, each with its owner's
## name and castle level. The list comes from the server (Economy.others) and
## is redrawn whenever it changes.

const LABEL_COLOR := Color(0.62, 0.84, 1.0)

var castles: Array[Settlement] = []
var _zoom_t := 0.0


func build() -> void:
	Economy.others_changed.connect(_rebuild)
	EventBus.camera_zoom_changed.connect(func(t: float) -> void:
		_zoom_t = t
		for s in castles:
			s.set_zoom(t))
	_rebuild()


func _rebuild() -> void:
	for s in castles:
		s.queue_free()
	castles.clear()
	for p: Dictionary in Economy.others:
		var s := Settlement.new()
		add_child(s)
		s.setup(_settlement_data(p))
		s.set_zoom(_zoom_t)
		castles.append(s)


func player_at(map_pos: Vector2, radius := 18.0) -> Dictionary:
	## The other player whose castle is under this map position ({} if none).
	var best := {}
	var best_d := radius
	for p: Dictionary in Economy.others:
		var d := Vector2(float(p.home_x), float(p.home_y)).distance_to(map_pos)
		if d < best_d:
			best_d = d
			best = p
	return best


static func _settlement_data(p: Dictionary) -> Dictionary:
	# Each player flies the banner of one of the realm's factions, the same
	# one every time for the same name.
	var player_name := String(p.get("name", "?"))
	var faction: Dictionary = GameData.factions[absi(hash(player_name)) % GameData.factions.size()]
	return {
		"id": "player:" + player_name,
		"name": "%s  Lv %d" % [player_name, int(p.get("level", 1))],
		"type": "castle",
		"faction": faction.id,
		"position": [float(p.home_x), float(p.home_y)],
		"rotation_deg": float(absi(hash(player_name)) % 360),
		"label_color": LABEL_COLOR,
	}
