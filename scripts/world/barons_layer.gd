extends Node3D
## Robber baron camps on the world map (a palisade, tents and a black banner,
## with a label showing the camp's level), and your armies marching to and
## from them (and, offline, to and from resource villages). Camps are placed
## by BaronPlacer the first time a game sees them.
## Online, the invader camps of a Baron Invasion come and go with the event;
## they fly a red banner. The Ember Horde's camps come and go the same way,
## under an ember-orange banner. Fortresses (the old kingdoms' castles, online) are
## camps too, without a model: the castle stands there, and its label shows
## the fortress's level.

const PICK_RADIUS := 16.0
const LABEL_MAX_ZOOM := 0.9
const TENT_DARK := Color(0.42, 0.2, 0.16)
const FIRE := Color(0.95, 0.5, 0.15)
const BARON_BANNER := {"id": "barons", "color": Color(0.1, 0.09, 0.09), "secondary_color": Color(0.7, 0.12, 0.1),
		"banner": {"pattern": "chevron", "charge": ""}}
const INVADER_BANNER := {"id": "invaders", "color": Color(0.62, 0.08, 0.06), "secondary_color": Color(0.1, 0.09, 0.09),
		"banner": {"pattern": "chevron", "charge": ""}}
const INVADER_LABEL := Color(1.0, 0.42, 0.32)
const HORDE_BANNER := {"id": "horde", "color": Color(0.93, 0.45, 0.1), "secondary_color": Color(0.12, 0.1, 0.09),
		"banner": {"pattern": "per_pale", "charge": ""}}
const HORDE_LABEL := Color(1.0, 0.68, 0.25)

var _camps := {}          ## camp id -> {"node", "label"}
var settlements: Node3D   ## the settlements layer, for the fortresses' labels
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
	Economy.barons_changed.connect(_sync_camps)
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


func _sync_camps() -> void:
	## Adds camps that are new and removes those that have gone.
	var live := {}
	for camp in Economy.barons:
		live[camp.id] = true
		if not _camps.has(camp.id):
			_add_camp(camp)
			# Fortresses have no model of their own (_add_camp() skips them).
			if _camps.has(camp.id):
				_camps[camp.id].label.visible = _zoom_t <= LABEL_MAX_ZOOM
	for id in _camps.keys():
		if not live.has(id):
			_camps[id].node.queue_free()
			_camps.erase(id)
	_refresh_labels()


func _add_camp(camp: BaronCamp) -> void:
	if camp.fortress:
		return
	var root := Node3D.new()
	root.name = camp.id
	var x := camp.position.x
	var z := camp.position.y
	GameData.roads.clear_trees(camp.position, 18.0)
	root.position = Vector3(x, GameData.terrain.get_height(x, z), z)
	root.rotation.y = float(hash(camp.id) % 628) / 100.0
	var model := MeshInstance3D.new()
	model.mesh = camp_mesh()
	root.add_child(model)
	var fire := MeshKit.new()
	fire.cylinder(Color(0.3, 0.3, 0.3), Transform3D(Basis(), Vector3(0.2, -0.3, 0.3)), 0.9, 0.5, 6)
	fire.cone(FIRE, Transform3D(Basis(), Vector3(0.2, 0.2, 0.3)), 0.6, 1.2, 5)
	var fire_model := MeshInstance3D.new()
	fire_model.mesh = fire.commit()
	root.add_child(fire_model)
	var banner := Banners.make(HORDE_BANNER if camp.is_horde() else INVADER_BANNER if camp.is_invader() else BARON_BANNER, 8.0, 4.0)
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


static func camp_mesh(map_fog := true) -> ArrayMesh:
	## The camp: a palisade around tents, stores and a weapon rack.
	var kit := KitModels.new()
	# A wooden palisade with a gap for the gate.
	for k in 13:
		var angle := (k + 0.5) * TAU / 14.0
		var p := Vector3(cos(angle) * 12.0, -0.6, sin(angle) * 12.0)
		kit.add("fence_wood_straight", Transform3D(Basis(Vector3.UP, -angle).scaled(Vector3(4.8, 6.0, 4.8)), p))
	# Tents, stores and a training target around the camp fire.
	var tents := [[Vector3(-5.0, -0.3, -3.5), 0.4], [Vector3(4.8, -0.3, -3.0), -0.5], [Vector3(-1.5, -0.3, 5.5), 2.8]]
	for t: Array in tents:
		kit.add("tent", Transform3D(Basis(Vector3.UP, t[1]).scaled(Vector3.ONE * 7.0), t[0]))
	kit.add("weaponrack", Transform3D(Basis(Vector3.UP, 1.2).scaled(Vector3.ONE * 3.5), Vector3(6.5, -0.3, 4.0)))
	kit.add("barrel", Transform3D(Basis().scaled(Vector3.ONE * 3.0), Vector3(-7.5, -0.3, 1.0)))
	kit.add("crate_A_big", Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3.ONE * 3.0), Vector3(-7.0, -0.3, -1.0)))
	return kit.commit(TENT_DARK, map_fog)


func _refresh_labels() -> void:
	var now := Economy.now()
	for camp in Economy.barons:
		if camp.fortress and settlements != null:
			settlements.show_fortress(camp.id, "Lv %d" % camp.level + ("" if camp.is_ready(now)
					else "\nRebuilding %s" % _clock(camp.rebuilt_at - now)), camp.is_ready(now))
		if not _camps.has(camp.id):
			continue
		var label: Label3D = _camps[camp.id].label
		var text := "%s  Lv %d" % [camp.camp_name, camp.level]
		if camp.is_invader():
			text = "Invaders: " + text
		elif camp.is_horde():
			text = "Horde: " + text
		if not camp.is_ready(now):
			text += "\nRebuilding %s" % _clock(camp.rebuilt_at - now)
		label.text = text
		var color := INVADER_LABEL if camp.is_invader() else HORDE_LABEL if camp.is_horde() else Color(1.0, 0.62, 0.5)
		label.modulate = color if camp.is_ready(now) else Color(0.7, 0.62, 0.58)


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
	var frames := Soldiers.troop([
		Soldiers.figure("knight", Vector3(0, 0, -0.9), 0.85),
		Soldiers.figure("knight", Vector3(-0.9, 0, 0.5), 0.75),
		Soldiers.figure("knight", Vector3(0.9, 0, 0.5), 0.75),
		Soldiers.figure("crossbowman", Vector3(-0.9, 0, 1.8), 0.75),
		Soldiers.figure("crossbowman", Vector3(0.9, 0, 1.8), 0.75),
	], KitModels.PLAYER_COLOR)
	var model := MeshInstance3D.new()
	model.mesh = frames[0]
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
	return {"node": root, "label": label, "frames": frames}


func _process(delta: float) -> void:
	var now := Economy.now()
	var home := Economy.home_position()
	for m: Dictionary in Economy.marches:
		var army: Dictionary = _armies.get(int(m.id), {})
		var target := Economy.march_target(m)
		if army.is_empty() or target.is_empty():
			continue
		var out: bool = m.state == "out"
		var t0: float = m.depart if out else m.arrive
		var t1: float = m.arrive if out else m.back
		var f := clampf((now - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0)
		var from: Vector2 = home if out else target.position
		var to: Vector2 = target.position if out else home
		var p := from.lerp(to, f)
		var node: Node3D = army.node
		node.position = Vector3(p.x, Party.ground_height(p.x, p.y), p.y)
		node.rotation.y = atan2(-(to - from).x, -(to - from).y)
		var model: MeshInstance3D = node.get_child(0)
		model.scale = Vector3.ONE * lerpf(1.0, 4.0, _zoom_t)
		model.mesh = army.frames[Time.get_ticks_msec() / 220 % 2]
		var label: Label3D = army.label
		label.text = "%s %s" % ["To " + String(target.name) if out else "Home", _clock(t1 - now)]
		label.visible = _zoom_t <= LABEL_MAX_ZOOM
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 1.0
		_refresh_labels()


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
