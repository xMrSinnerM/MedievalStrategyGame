class_name Party
extends Node3D
## A party travelling the campaign map: a lord's warband or the player's.
## It walks a path from NavGrid at a speed set by the ground underneath, and
## is hidden while inside a settlement.

signal arrived(party: Party)

## Map units per second on open plains; the ground's travel cost divides it.
const BASE_SPEED := 22.0
## How much bigger parties get when zoomed out, so they stay visible.
const FAR_SCALE := 6.0
const LABEL_MAX_ZOOM := 0.8

## Seconds per walk frame while marching.
const STEP_TIME := 0.22

var id := ""
var party_name := ""
var faction_id := ""
var troops := 0
var is_player := false
var home := ""                       ## castle id whose warband this party is

var path := PackedVector2Array()     ## remaining route, map units
var destination_settlement := ""     ## settlement id the party is heading for, if any
var inside_settlement := ""          ## settlement id the party is waiting in, if any
var moving := false
var chasing: Party = null            ## party this one is marching on, if any
var truce_until := 0.0               ## no fighting before this time (seconds since start)

var _figures: Node3D
var _model: MeshInstance3D
var _frames: Array[ArrayMesh] = []
var _label: Label3D
var _scale := 1.0
var _walk_time := 0.0


func setup(data: Dictionary) -> void:
	id = data.id
	party_name = data.name
	faction_id = data.faction
	troops = int(data.get("troops", 20))
	is_player = data.get("player", false)
	home = data.get("home", "")
	name = id
	var faction := GameData.get_faction(faction_id)

	_figures = Node3D.new()
	_figures.name = "Figures"
	add_child(_figures)
	_model = MeshInstance3D.new()
	_frames = _build_model(faction.get("color", Color.GRAY))
	_model.mesh = _frames[0]
	_figures.add_child(_model)
	if not faction.is_empty():
		var banner := Banners.make(faction, 5.5, 2.2)
		banner.position = Vector3(0.9, 1.6, 0.0)
		_figures.add_child(banner)

	_label = Label3D.new()
	_label.name = "Label"
	_label.set_meta("plate", "party")
	_label.text = "%s (%d)" % [party_name, troops]
	_label.font_size = 30
	_label.outline_size = 9
	_label.modulate = Color(1.0, 0.92, 0.6) if is_player else Color(0.95, 0.93, 0.88)
	_label.outline_modulate = Color(0.12, 0.08, 0.05, 0.9)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0005
	_label.no_depth_test = true
	_label.render_priority = 13
	_label.outline_render_priority = 12
	_label.shaded = false
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.position = Vector3(0, 8.5, 0)
	add_child(_label)


func set_troops(count: int) -> void:
	if count == troops:
		return
	troops = count
	_label.text = "%s (%d)" % [party_name, troops]


func place_at(p: Vector2) -> void:
	position = Vector3(p.x, ground_height(p.x, p.y), p.y)
	# Out of sight among the houses while passing through a settlement.
	_figures.visible = inside_settlement.is_empty() and not _within_settlement(p)


func is_shown() -> bool:
	return _figures.visible


func _within_settlement(p: Vector2) -> bool:
	for s in GameData.settlements:
		var r: float = SettlementModels.RADIUS.get(s.type, 20.0) * 0.8
		if p.distance_squared_to(Vector2(s.position[0], s.position[1])) < r * r:
			return true
	return false


func can_fight() -> bool:
	## Out in the open, with soldiers, and not just out of a battle.
	return inside_settlement.is_empty() and _figures.visible and troops > 0 \
			and Time.get_ticks_msec() * 0.001 >= truce_until


func map_position() -> Vector2:
	return Vector2(position.x, position.z)


func travel_to(target: Vector2, settlement_id := "") -> bool:
	## Plans a route and starts walking. Returns false if there is no way there.
	var route := GameData.nav.find_path(map_position(), target)
	if route.size() < 2:
		return false
	path = route
	path.remove_at(0)
	destination_settlement = settlement_id
	_leave_settlement()
	moving = true
	return true


func stop() -> void:
	chasing = null
	path.clear()
	moving = false
	destination_settlement = ""


func enter_settlement(settlement_id: String) -> void:
	inside_settlement = settlement_id
	_figures.visible = false
	_label.visible = false


func current_speed() -> float:
	var cost := GameData.nav.cost_at(position.x, position.z)
	return BASE_SPEED / maxf(cost, NavGrid.ROAD) if cost > 0.0 else BASE_SPEED / NavGrid.FORD


func set_zoom(zoom_t: float) -> void:
	_scale = lerpf(1.0, FAR_SCALE, smoothstep(0.15, 0.9, zoom_t))
	_figures.scale = Vector3.ONE * _scale
	_label.position.y = 8.5 * _scale
	if inside_settlement.is_empty():
		_label.visible = is_player or zoom_t <= LABEL_MAX_ZOOM


func display_scale() -> float:
	return _scale


static func ground_height(x: float, z: float) -> float:
	## The ground a party stands on: terrain, the sea surface, or a bridge deck.
	return maxf(GameData.terrain.get_surface_height(x, z), GameData.roads.bridge_deck_at(x, z))


func _process(delta: float) -> void:
	if not moving:
		return
	var step := current_speed() * delta
	var pos := map_position()
	var heading := Vector2.ZERO
	while step > 0.0 and not path.is_empty():
		var next := path[0]
		var to_next := next - pos
		var d := to_next.length()
		if d > 0.001:
			heading = to_next / d
		if d <= step:
			pos = next
			step -= d
			path.remove_at(0)
		else:
			pos += heading * step
			step = 0.0
	place_at(pos)
	if heading != Vector2.ZERO:
		var yaw := atan2(-heading.x, -heading.y)
		_figures.rotation.y = lerp_angle(_figures.rotation.y, yaw, minf(delta * 8.0, 1.0))
	# Step through the walk frames while marching.
	_walk_time += delta
	_model.mesh = _frames[int(_walk_time / STEP_TIME) % 2]
	if path.is_empty():
		moving = false
		_model.mesh = _frames[0]
		if not destination_settlement.is_empty():
			enter_settlement(destination_settlement)
		destination_settlement = ""
		arrived.emit(self)


func _leave_settlement() -> void:
	inside_settlement = ""
	_label.visible = true


func _build_model(team: Color) -> Array[ArrayMesh]:
	## A knight leading two knights and two crossbowmen; facing -z.
	return Soldiers.troop([
		Soldiers.figure("knight", Vector3(0, 0, -0.6), 1.05),
		Soldiers.figure("knight", Vector3(-1.0, 0, 1.0), 0.85),
		Soldiers.figure("knight", Vector3(1.0, 0, 1.0), 0.85),
		Soldiers.figure("crossbowman", Vector3(-1.0, 0, 2.5), 0.85),
		Soldiers.figure("crossbowman", Vector3(1.0, 0, 2.5), 0.85),
	], team)
