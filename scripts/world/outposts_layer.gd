extends Node3D
## Outposts on the world map: yours (click it to look inside) and, online,
## the other players' (from Economy.others), plus your carts on the road
## between your castle and your outpost.

const LABEL_MAX_ZOOM := 0.9
const OTHERS_COLOR := Color(0.62, 0.84, 1.0)
const CART_COLOR := Color(0.55, 0.38, 0.2)

var castles: Array[Settlement] = []
var _carts := {}           ## cart id -> {"node", "label"}
var _zoom_t := 0.0


func build() -> void:
	Economy.outpost_changed.connect(_rebuild)
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
	if not Economy.outpost.is_empty():
		var home: Dictionary = GameData.get_settlement(Economy.MAIN_CASTLE)
		_add({
			"id": OutpostRules.OUTPOST_ID, "name": "%s (outpost)" % Economy.outpost.name, "type": "castle", "player": true,
			"faction": home.get("faction", Economy.player_faction),
			"position": [float(Economy.outpost.x), float(Economy.outpost.y)], "rotation_deg": 35.0,
		})
	for p: Dictionary in Economy.others:
		var post: Variant = p.get("outpost")
		if not post is Dictionary:
			continue
		var player_name := String(p.get("name", "?"))
		_add({
			"id": "outpost:" + player_name, "name": "%s's outpost" % player_name, "type": "castle",
			"faction": GameData.factions[absi(hash(player_name)) % GameData.factions.size()].id,
			"position": [float(post.x), float(post.y)], "rotation_deg": float(absi(hash(player_name + "o")) % 360),
			"label_color": OTHERS_COLOR,
		})
	_sync_carts()


func _add(data: Dictionary) -> void:
	var s := Settlement.new()
	add_child(s)
	s.setup(data)
	s.set_zoom(_zoom_t)
	castles.append(s)


func outpost_at(map_pos: Vector2, radius := 18.0) -> bool:
	## Whether your outpost is under this map position.
	return not Economy.outpost.is_empty() and Economy.outpost_position().distance_to(map_pos) < radius


# --- Carts -------------------------------------------------------------------------

func _sync_carts() -> void:
	var live := {}
	for c: Dictionary in Economy.outpost.get("carts", []):
		var id := int(c.id)
		live[id] = true
		if not _carts.has(id):
			_carts[id] = _make_cart()
	for id in _carts.keys():
		if not live.has(id):
			_carts[id].node.queue_free()
			_carts.erase(id)


func _make_cart() -> Dictionary:
	var root := Node3D.new()
	var kit := MeshKit.new()
	for k in 2:
		var p := Vector3(0, 0, k * 3.2 - 1.6)
		kit.box(CART_COLOR, Transform3D(Basis(), p + Vector3(0, 1.1, 0)), Vector3(1.8, 0.9, 2.6))
		kit.box(Color(0.85, 0.78, 0.6), Transform3D(Basis(), p + Vector3(0, 1.8, 0)), Vector3(1.5, 0.6, 2.2))
	var model := MeshInstance3D.new()
	model.mesh = kit.commit()
	root.add_child(model)
	var label := Label3D.new()
	label.font_size = 26
	label.outline_size = 8
	label.modulate = Color(1.0, 0.9, 0.6)
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
	return {"node": root, "label": label}


func _process(_delta: float) -> void:
	if _carts.is_empty():
		return
	var now := Economy.now()
	var home := Economy.home_position()
	var post := Economy.outpost_position()
	for c: Dictionary in Economy.outpost.get("carts", []):
		var cart: Dictionary = _carts.get(int(c.id), {})
		if cart.is_empty():
			continue
		var from := home if c.to == "outpost" else post
		var to := post if c.to == "outpost" else home
		var f := clampf((now - float(c.depart)) / maxf(float(c.arrive) - float(c.depart), 0.01), 0.0, 1.0)
		var p := from.lerp(to, f)
		var node: Node3D = cart.node
		node.position = Vector3(p.x, Party.ground_height(p.x, p.y), p.y)
		node.rotation.y = atan2(-(to - from).x, -(to - from).y)
		var model: Node3D = node.get_child(0)
		model.scale = Vector3.ONE * lerpf(1.0, 4.0, _zoom_t)
		var label: Label3D = cart.label
		label.text = "Carts to %s %s" % ["your outpost" if c.to == "outpost" else "your castle", _clock(float(c.arrive) - now)]
		label.visible = _zoom_t <= LABEL_MAX_ZOOM


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
