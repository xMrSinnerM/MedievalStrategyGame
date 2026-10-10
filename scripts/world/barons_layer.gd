extends Node3D
## Robber baron camps on the world map (a palisade, tents and a black banner,
## with a label showing the camp's level), and your armies marching to and
## from them. Camps are placed by BaronPlacer the first time a game sees them.

const PICK_RADIUS := 16.0
const LABEL_MAX_ZOOM := 0.9
const STAKE := Color(0.36, 0.26, 0.17)
const TENT := Color(0.62, 0.52, 0.38)
const TENT_DARK := Color(0.42, 0.2, 0.16)
const FIRE := Color(0.95, 0.5, 0.15)
const BARON_BANNER := {"id": "barons", "color": Color(0.1, 0.09, 0.09), "secondary_color": Color(0.7, 0.12, 0.1),
		"banner": {"pattern": "chevron", "charge": ""}}
const ARMY := Color(0.85, 0.7, 0.25)

var _camps := {}          ## camp id -> {"node", "label"}
var _armies := {}         ## march id -> {"node", "label"}
var _zoom_t := 0.0
var _label_timer := 0.0


func build() -> void:
	var home := Economy.home_position()
	var camps := BaronPlacer.place(Economy.baron_rules, GameData.nav.is_passable, GameData.settlements,
			home, GameData.terrain.world_size)
	Economy.sync_barons(camps)
	for camp in Economy.barons:
		_add_camp(camp)
	EventBus.camera_zoom_changed.connect(func(t: float) -> void:
		_zoom_t = t
		for id in _camps:
			_camps[id].label.visible = t <= LABEL_MAX_ZOOM)
	Economy.marches_changed.connect(_sync_armies)
	_sync_armies()
	_refresh_labels()


func camp_at(map_pos: Vector2) -> String:
	## The camp under this map position ("" if none).
	var best := ""
	var best_d := PICK_RADIUS
	for camp in Economy.barons:
		var d := camp.position.distance_to(map_pos)
		if d < best_d:
			best_d = d
			best = camp.id
	return best


func _add_camp(camp: BaronCamp) -> void:
	var root := Node3D.new()
	root.name = camp.id
	var x := camp.position.x
	var z := camp.position.y
	root.position = Vector3(x, GameData.terrain.get_height(x, z), z)
	root.rotation.y = float(hash(camp.id) % 628) / 100.0
	var kit := MeshKit.new()
	# A ring of sharpened stakes with a gap for the gate.
	for k in 22:
		var angle := k * TAU / 24.0
		var p := Vector3(cos(angle) * 8.0, -1.0, sin(angle) * 8.0)
		var h := 3.6 + float((hash(camp.id) + k * 31) % 7) * 0.15
		kit.cylinder(STAKE, Transform3D(Basis(), p), 0.45, h, 5)
		kit.cone(STAKE, Transform3D(Basis(), p + Vector3(0, h, 0)), 0.45, 0.9, 5)
	# Tents around a camp fire.
	var tents := [Vector3(-3.0, 0, -2.5), Vector3(3.2, 0, -1.5), Vector3(-0.5, 0, 3.5)]
	for i in tents.size():
		kit.cone(TENT_DARK if i == 0 else TENT, Transform3D(Basis(), tents[i] + Vector3(0, -0.5, 0)), 2.4, 3.6, 6)
	kit.cylinder(Color(0.3, 0.3, 0.3), Transform3D(Basis(), Vector3(0.2, -0.3, 0.3)), 0.9, 0.5, 6)
	kit.cone(FIRE, Transform3D(Basis(), Vector3(0.2, 0.2, 0.3)), 0.6, 1.2, 5)
	var model := MeshInstance3D.new()
	model.mesh = kit.commit()
	root.add_child(model)
	var banner := Banners.make(BARON_BANNER, 8.0, 4.0)
	banner.position = Vector3(-1.5, 0, -0.5)
	root.add_child(banner)
	var label := Label3D.new()
	label.font_size = 32
	label.outline_size = 10
	label.modulate = Color(1.0, 0.62, 0.5)
	label.outline_modulate = Color(0.16, 0.06, 0.04, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.no_depth_test = true
	label.render_priority = 12
	label.outline_render_priority = 11
	label.shaded = false
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = Vector3(0, 13.0, 0)
	root.add_child(label)
	add_child(root)
	_camps[camp.id] = {"node": root, "label": label}


func _refresh_labels() -> void:
	var now := Economy.now()
	for camp in Economy.barons:
		if not _camps.has(camp.id):
			continue
		var label: Label3D = _camps[camp.id].label
		var text := "%s  Lv %d" % [camp.camp_name, camp.level]
		if not camp.is_ready(now):
			text += "\nRebuilding %s" % _clock(camp.rebuilt_at - now)
		label.text = text
		label.modulate = Color(1.0, 0.62, 0.5) if camp.is_ready(now) else Color(0.7, 0.62, 0.58)


func _sync_armies() -> void:
	var live := {}
	for m: Dictionary in Economy.marches:
		live[int(m.id)] = true
		if not _armies.has(int(m.id)):
			_armies[int(m.id)] = _make_army()
	for id in _armies.keys():
		if not live.has(id):
			_armies[id].node.queue_free()
			_armies.erase(id)
	_refresh_labels()


func _make_army() -> Dictionary:
	var root := Node3D.new()
	var kit := MeshKit.new()
	for k in 5:
		var p := Vector3((k % 3 - 1) * 1.6, 0, (k / 3) * 1.6 - 0.8)
		kit.cylinder(ARMY.darkened(0.25), Transform3D(Basis(), p), 0.5, 1.6, 6)
		kit.dome(Color(0.85, 0.75, 0.6), Transform3D(Basis(), p + Vector3(0, 1.7, 0)), 0.4)
	var model := MeshInstance3D.new()
	model.mesh = kit.commit()
	root.add_child(model)
	var label := Label3D.new()
	label.font_size = 26
	label.outline_size = 8
	label.modulate = Color(1.0, 0.86, 0.5)
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


func _process(delta: float) -> void:
	var now := Economy.now()
	var home := Economy.home_position()
	for m: Dictionary in Economy.marches:
		var army: Dictionary = _armies.get(int(m.id), {})
		var camp := Economy.get_baron(m.camp)
		if army.is_empty() or camp == null:
			continue
		var out: bool = m.state == "out"
		var t0: float = m.depart if out else m.arrive
		var t1: float = m.arrive if out else m.back
		var f := clampf((now - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0)
		var from := home if out else camp.position
		var to := camp.position if out else home
		var p := from.lerp(to, f)
		var node: Node3D = army.node
		node.position = Vector3(p.x, Party.ground_height(p.x, p.y), p.y)
		node.rotation.y = atan2(-(to - from).x, -(to - from).y)
		var model: Node3D = node.get_child(0)
		model.scale = Vector3.ONE * lerpf(1.0, 4.0, _zoom_t)
		var label: Label3D = army.label
		label.text = "%s %s" % ["To " + camp.camp_name if out else "Home", _clock(t1 - now)]
		label.visible = _zoom_t <= LABEL_MAX_ZOOM
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 1.0
		_refresh_labels()


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
