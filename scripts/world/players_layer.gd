extends Node3D
## Online: the other players' castles on the world map, each with its owner's
## name, alliance tag and castle level, allies' names in green. The list comes
## from the server (Economy.others) and
## is redrawn whenever it changes. Armies sent between players march here too:
## yours in gold, and in red the ones coming for your castle.

const LABEL_COLOR := Color(0.62, 0.84, 1.0)
const ALLY_COLOR := Color(0.55, 0.95, 0.55)
const LABEL_MAX_ZOOM := 0.9
const MINE := KitModels.PLAYER_COLOR
const ENEMY := Color(0.38, 0.4, 0.46)

var castles: Array[Settlement] = []
var _armies := {}          ## raid id -> {"node", "label"}
var _zoom_t := 0.0


func build() -> void:
	Economy.others_changed.connect(_rebuild)
	EventBus.camera_zoom_changed.connect(func(t: float) -> void:
		_zoom_t = t
		for s in castles:
			s.set_zoom(t))
	Economy.raids_changed.connect(_sync_armies)
	_rebuild()
	_sync_armies()


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
		"name": ("[%s] " % p.tag if String(p.get("tag", "")) != "" else "") + "%s  Lv %d" % [player_name, int(p.get("level", 1))],
		"type": "castle",
		"faction": faction.id,
		"position": [float(p.home_x), float(p.home_y)],
		"rotation_deg": float(absi(hash(player_name)) % 360),
		"label_color": ALLY_COLOR if p.get("ally", false) else LABEL_COLOR,
	}


static func _shown(r: Dictionary) -> bool:
	## Your own armies until they are home; others' only on their way to you.
	return r.get("mine", false) or r.get("state", "") == "out"


func _sync_armies() -> void:
	var live := {}
	for r: Dictionary in Economy.raids:
		if not _shown(r):
			continue
		var id := int(r.id)
		live[id] = true
		if not _armies.has(id):
			_armies[id] = _make_army(MINE if r.get("mine", false) else ENEMY)
	for id in _armies.keys():
		if not live.has(id):
			_armies[id].node.queue_free()
			_armies.erase(id)


func _make_army(color: Color) -> Dictionary:
	var root := Node3D.new()
	var frames := Soldiers.troop([
		Soldiers.figure("knight", Vector3(0, 0, -0.9), 0.85),
		Soldiers.figure("knight", Vector3(-0.9, 0, 0.5), 0.75),
		Soldiers.figure("knight", Vector3(0.9, 0, 0.5), 0.75),
		Soldiers.figure("crossbowman", Vector3(-0.9, 0, 1.8), 0.75),
		Soldiers.figure("crossbowman", Vector3(0.9, 0, 1.8), 0.75),
	], color)
	var model := MeshInstance3D.new()
	model.mesh = frames[0]
	root.add_child(model)
	var label := Label3D.new()
	label.font_size = 26
	label.outline_size = 8
	label.modulate = Color(1.0, 0.86, 0.5) if color == MINE else Color(0.9, 0.9, 0.92)
	label.outline_modulate = Color(0.12, 0.08, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.no_depth_test = true
	label.render_priority = 12
	label.outline_render_priority = 11
	label.shaded = false
	label.position = Vector3(0, 5.0, 0)
	root.add_child(label)
	add_child(root)
	return {"node": root, "label": label, "frames": frames}


func _process(_delta: float) -> void:
	var now := Economy.now()
	for r: Dictionary in Economy.raids:
		var army: Dictionary = _armies.get(int(r.get("id", -1)), {})
		if army.is_empty():
			continue
		var start := Vector2(float(r.from[0]), float(r.from[1]))
		var target := Vector2(float(r.to[0]), float(r.to[1]))
		var out: bool = r.state == "out" or r.state == "fighting"
		var t0 := float(r.depart) if out else float(r.arrive)
		var t1 := float(r.arrive) if out else float(r.back)
		var f := clampf((now - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0)
		var from := start if out else target
		var to := target if out else start
		var p := from.lerp(to, f)
		var node: Node3D = army.node
		node.position = Vector3(p.x, Party.ground_height(p.x, p.y), p.y)
		node.rotation.y = atan2(-(to - from).x, -(to - from).y)
		var model: MeshInstance3D = node.get_child(0)
		model.scale = Vector3.ONE * lerpf(1.0, 4.0, _zoom_t)
		model.mesh = army.frames[Time.get_ticks_msec() / 220 % 2]
		var label: Label3D = army.label
		if not r.get("mine", false):
			label.text = "%s's army %s" % [r.attacker_name, _clock(t1 - now)]
		elif out:
			label.text = "To %s %s" % [r.defender_name, _clock(t1 - now)]
		else:
			label.text = "Home %s" % _clock(t1 - now)
		label.visible = _zoom_t <= LABEL_MAX_ZOOM


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
