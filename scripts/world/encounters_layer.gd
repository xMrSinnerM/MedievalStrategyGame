extends Node3D
## Random encounters on the world map (EncounterRules): bandit camps (two
## ragged tents round a fire under a red banner), merchant caravans (a
## covered wagon that walks its road) and treasure sites (a half-dug chest by
## a spade). They come and go by themselves; ones you've already won fade.
## Click one to open its card.

const PICK_RADIUS := 18.0
const LABEL_MAX_ZOOM := 0.9
const CHECK_EVERY := 2.0
const BANDIT_BANNER := {"id": "bandits", "color": Color(0.55, 0.1, 0.08), "secondary_color": Color(0.15, 0.12, 0.1),
		"banner": {"pattern": "per_pale", "charge": ""}}
const LABEL_COLORS := {"bandits": Color(1.0, 0.58, 0.45), "caravan": Color(0.75, 0.92, 1.0), "treasure": Color(1.0, 0.86, 0.45)}

var _shown := {}          ## encounter id -> {"node", "model", "label", "e"}
var _zoom_t := 0.0
var _timer := 0.0


func build() -> void:
	EventBus.camera_zoom_changed.connect(func(t: float) -> void: _zoom_t = t)
	_sync()


func encounter_at(map_pos: Vector2) -> String:
	## The encounter under this map position ("" if none).
	var best := ""
	var best_d := PICK_RADIUS * lerpf(1.0, 2.5, _zoom_t)
	var now := Economy.now()
	for id: String in _shown:
		var d := Economy.encounter_rules.position(_shown[id].e, now).distance_to(map_pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func _sync() -> void:
	var rules := Economy.encounter_rules
	if rules == null:
		return
	var live := {}
	for e: Dictionary in rules.active(Economy.now()):
		live[e.id] = true
		if not _shown.has(e.id):
			_shown[e.id] = _make(e)
	for id: String in _shown.keys():
		if not live.has(id):
			_shown[id].node.queue_free()
			_shown.erase(id)


func _make(e: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = String(e.id)
	root.rotation.y = float(int(e.variant) % 628) / 100.0
	var model := Node3D.new()
	root.add_child(model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh(String(e.kind))
	model.add_child(mesh)
	if e.kind == "bandits":
		var banner := Banners.make(BANDIT_BANNER, 6.0, 3.0)
		banner.position = Vector3(-2.0, 0, -1.0)
		model.add_child(banner)
	var label := Label3D.new()
	label.set_meta("plate", "tag")
	label.font_size = 28
	label.outline_size = 9
	label.modulate = LABEL_COLORS.get(String(e.kind), Color.WHITE)
	label.outline_modulate = Color(0.12, 0.07, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.no_depth_test = true
	label.render_priority = 12
	label.outline_render_priority = 11
	label.shaded = false
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = Vector3(0, 12.0, 0)
	label.text = Economy.encounter_rules.display_name(e)
	root.add_child(label)
	add_child(root)
	return {"node": root, "model": model, "label": label, "e": e}


static func _mesh(kind: String) -> ArrayMesh:
	var kit := MeshKit.new()
	match kind:
		"bandits":
			for k in 2:
				var at := Vector3(k * 3.4 - 1.7, 0, 0.6 - k * 1.2)
				kit.cone(Color(0.5, 0.38, 0.26), Transform3D(Basis(), at + Vector3(0, 1.2, 0)), 1.7, 2.6, 6)
			kit.cylinder(Color(0.3, 0.3, 0.3), Transform3D(Basis(), Vector3(0.4, 0.15, 2.4)), 0.8, 0.3, 6)
			kit.cone(Color(0.95, 0.5, 0.15), Transform3D(Basis(), Vector3(0.4, 0.7, 2.4)), 0.5, 1.1, 5)
		"caravan":
			kit.box(Color(0.5, 0.33, 0.18), Transform3D(Basis(), Vector3(0, 1.1, 0)), Vector3(2.0, 0.8, 3.6))
			kit.box(Color(0.92, 0.86, 0.7), Transform3D(Basis(), Vector3(0, 2.1, 0)), Vector3(1.9, 1.3, 3.2))
			for k in 4:
				var at := Vector3(-1.05 if k < 2 else 1.05, 0.6, -1.1 if k % 2 == 0 else 1.1)
				kit.cylinder(Color(0.3, 0.2, 0.1), Transform3D(Basis(Vector3.FORWARD, PI / 2), at), 0.6, 0.2, 8)
			kit.box(Color(0.45, 0.3, 0.2), Transform3D(Basis(), Vector3(0, 1.1, -3.2)), Vector3(0.9, 1.3, 1.8))
		_:
			kit.cylinder(Color(0.42, 0.3, 0.18), Transform3D(Basis(), Vector3(0, 0.15, 0)), 2.2, 0.3, 8, 1.8)
			kit.box(Color(0.55, 0.36, 0.17), Transform3D(Basis(), Vector3(0, 0.7, 0)), Vector3(1.8, 1.1, 1.2))
			kit.box(Color(0.9, 0.72, 0.3), Transform3D(Basis(), Vector3(0, 1.3, 0)), Vector3(1.9, 0.2, 1.3))
			kit.box(Color(0.35, 0.25, 0.15), Transform3D(Basis(Vector3.FORWARD, 0.35), Vector3(1.9, 1.4, 0.4)), Vector3(0.18, 2.6, 0.18))
	return kit.commit()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_EVERY
		_sync()
	var rules := Economy.encounter_rules
	if rules == null:
		return
	var now := Economy.now()
	var size := lerpf(1.8, 5.0, _zoom_t)
	for id: String in _shown:
		var s: Dictionary = _shown[id]
		var p := rules.position(s.e, now)
		var node: Node3D = s.node
		node.position = Vector3(p.x, Party.ground_height(p.x, p.y), p.y)
		if s.e.kind == "caravan":
			var ahead := rules.position(s.e, now + 60.0)
			if ahead.distance_to(p) > 0.01:
				node.rotation.y = atan2(-(ahead - p).x, -(ahead - p).y)
		s.model.scale = Vector3.ONE * size
		var done := EncounterRules.done(Economy.player_castle, id)
		s.label.visible = _zoom_t <= LABEL_MAX_ZOOM
		s.label.modulate.a = 0.45 if done else 1.0
		s.model.visible = not done or _zoom_t < 0.5
