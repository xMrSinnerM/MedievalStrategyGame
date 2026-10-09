extends Node3D
## Spawns the parties from data/parties.json, moves the lords around their
## realms and lets the player send their own party anywhere with a click.
##
## Controls: left click on the ground or a settlement to travel there,
## F to centre the camera on your party.

const ROUTE_SHADER := preload("res://shaders/route.gdshader")
const CLICK_SLOP := 6.0          ## pixels the mouse may move and still count as a click
const ROUTE_STEP := 3.0          ## route ribbon resolution in map units
const ROUTE_REFRESH := 0.2       ## seconds between ribbon rebuilds while walking
const LORD_WAIT := Vector2(4.0, 10.0)      ## seconds a lord rests in a settlement
const LORD_RANGE := 750.0                   ## lords prefer settlements within this distance

var parties: Array[Party] = []
var player: Party
var camera_rig: CampaignCamera

var _rng := RandomNumberGenerator.new()
var _lord_timers := {}           ## Party -> seconds left resting
var _press_pos := Vector2.ZERO
var _pressed := false
var _route: MeshInstance3D
var _route_material: ShaderMaterial
var _marker: MeshInstance3D
var _ring: MeshInstance3D
var _route_timer := 0.0
var _zoom_t := 0.0
var _status := ""


func build() -> void:
	_rng.seed = 7
	for data in GameData.parties:
		var start := GameData.get_settlement(data.get("start", ""))
		if start.is_empty():
			push_warning("Party %s has no valid start settlement" % data.id)
			continue
		var party := Party.new()
		add_child(party)
		party.setup(data)
		var home := Vector2(start.position[0], start.position[1])
		if party.is_player:
			player = party
			party.place_at(_outside(start))
		else:
			party.place_at(home)
			party.enter_settlement(start.id)
			_lord_timers[party] = _rng.randf_range(0.5, LORD_WAIT.y)
		party.arrived.connect(_on_arrived)
		parties.append(party)

	_build_markers()
	EventBus.camera_zoom_changed.connect(_on_zoom_changed)
	_set_status("Camped outside %s" % _nearest_settlement_name(player.map_position()) if player else "")


func _build_markers() -> void:
	_route_material = ShaderMaterial.new()
	_route_material.shader = ROUTE_SHADER
	MapStyle.apply_common(_route_material)
	_route = MeshInstance3D.new()
	_route.name = "Route"
	_route.material_override = _route_material
	_route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_route)

	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color(1.0, 0.84, 0.4)
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.8
	torus.rings = 24
	torus.ring_segments = 6
	_marker = MeshInstance3D.new()
	_marker.name = "DestinationMarker"
	_marker.mesh = torus
	_marker.material_override = gold
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)

	# A ring under the player's party so it is easy to spot.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 3.4
	ring_mesh.outer_radius = 3.9
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "PlayerRing"
	_ring.mesh = ring_mesh
	_ring.material_override = gold
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_pos) <= CLICK_SLOP:
				_on_click(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		if player and camera_rig:
			camera_rig.focus_on(player.position)


func _on_click(screen_pos: Vector2) -> void:
	if player == null:
		return
	var cam := get_viewport().get_camera_3d()
	var hit = GameData.terrain.raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if hit == null:
		return
	var target := Vector2(hit.x, hit.z)
	var settlement := _settlement_at(target)
	if not settlement.is_empty():
		target = Vector2(settlement.position[0], settlement.position[1])
	if player.travel_to(target, settlement.get("id", "")):
		_set_status("Travelling to %s" % settlement.name if not settlement.is_empty() else "Travelling")
		_route_timer = 0.0
	else:
		_set_status("No way to get there")


func _on_arrived(party: Party) -> void:
	if party == player:
		if not party.inside_settlement.is_empty():
			_set_status("Staying in %s" % GameData.get_settlement(party.inside_settlement).name)
		else:
			_set_status("Camped")
		_route.mesh = null
		_marker.visible = false
	else:
		if party.inside_settlement.is_empty():
			# Stopped short (an unreachable target); pick somewhere else soon.
			_lord_timers[party] = 1.0
		else:
			_lord_timers[party] = _rng.randf_range(LORD_WAIT.x, LORD_WAIT.y)


func _on_zoom_changed(zoom_t: float) -> void:
	_zoom_t = zoom_t
	for p in parties:
		p.set_zoom(zoom_t)


func _process(delta: float) -> void:
	_update_lords(delta)
	if player == null:
		return
	var s := player.display_scale()
	_ring.visible = player.is_shown()
	_ring.position = player.position + Vector3(0, 0.3, 0)
	_ring.scale = Vector3(s, 0.4 * s, s)
	if player.moving:
		_route_timer -= delta
		if _route_timer <= 0.0:
			_route_timer = ROUTE_REFRESH
			_rebuild_route()
		var end := player.path[player.path.size() - 1]
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
		_marker.visible = true
		_marker.position = Vector3(end.x, Party.ground_height(end.x, end.y) + 0.4, end.y)
		_marker.scale = Vector3(s * pulse, 0.4 * s, s * pulse)
		_set_status(_status.get_slice(" (", 0) + " (%s)" % GameData.nav.kind_name(player.position.x, player.position.z).to_lower())


func _update_lords(delta: float) -> void:
	for party: Party in _lord_timers.keys():
		if party.moving:
			continue
		_lord_timers[party] -= delta
		if _lord_timers[party] > 0.0:
			continue
		var target := _pick_lord_destination(party)
		if target.is_empty() or not party.travel_to(Vector2(target.position[0], target.position[1]), target.id):
			_lord_timers[party] = _rng.randf_range(LORD_WAIT.x, LORD_WAIT.y)


func _pick_lord_destination(party: Party) -> Dictionary:
	## Another settlement of the lord's own faction, preferring nearby ones.
	var here := party.map_position()
	var near: Array[Dictionary] = []
	var all: Array[Dictionary] = []
	for s in GameData.settlements:
		if s.faction != party.faction_id or s.id == party.inside_settlement:
			continue
		all.append(s)
		if here.distance_to(Vector2(s.position[0], s.position[1])) < LORD_RANGE:
			near.append(s)
	var pool := near if not near.is_empty() else all
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else {}


func _rebuild_route() -> void:
	## Ribbon from the party along the rest of its path, hugging the ground.
	var pts := PackedVector2Array([player.map_position()])
	pts.append_array(player.path)
	if pts.size() < 2:
		_route.mesh = null
		return
	# Resample evenly so the ribbon follows the terrain between path points.
	var dense := PackedVector2Array([pts[0]])
	for k in range(1, pts.size()):
		var steps := maxi(1, int(pts[k].distance_to(pts[k - 1]) / ROUTE_STEP))
		for s in range(1, steps + 1):
			dense.append(pts[k - 1].lerp(pts[k], float(s) / steps))
	var width := 1.4 * player.display_scale()
	var lift := 0.5 + 0.15 * player.display_scale()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var along := 0.0
	for k in dense.size():
		var q := dense[k]
		if k > 0:
			along += q.distance_to(dense[k - 1])
		var dir := (dense[mini(k + 1, dense.size() - 1)] - dense[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x) * width * 0.5
		for edge in [-1.0, 1.0]:
			var e: Vector2 = q + side * edge
			st.set_uv(Vector2(along, (edge + 1.0) * 0.5))
			st.add_vertex(Vector3(e.x, Party.ground_height(e.x, e.y) + lift, e.y))
	_route.mesh = st.commit()


func _settlement_at(p: Vector2) -> Dictionary:
	for s in GameData.settlements:
		var r: float = SettlementModels.RADIUS.get(s.type, 20.0)
		if p.distance_to(Vector2(s.position[0], s.position[1])) <= r:
			return s
	return {}


func _outside(settlement: Dictionary) -> Vector2:
	## A passable spot just outside a settlement's walls.
	var centre := Vector2(settlement.position[0], settlement.position[1])
	var r: float = SettlementModels.RADIUS.get(settlement.type, 20.0) + 14.0
	for k in 16:
		var p := centre + Vector2.from_angle(PI * 0.5 + k * TAU / 16.0) * r
		if GameData.nav.is_passable(p.x, p.y):
			return p
	return centre


func _nearest_settlement_name(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for s in GameData.settlements:
		var d := p.distance_to(Vector2(s.position[0], s.position[1]))
		if d < best_d:
			best_d = d
			best = s.name
	return best


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	EventBus.party_status_changed.emit(text)
