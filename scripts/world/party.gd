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

const SKIN := Color(0.86, 0.68, 0.52)
const STEEL := Color(0.62, 0.63, 0.66)
const HORSE := Color(0.42, 0.29, 0.19)
const WOOD := Color(0.4, 0.29, 0.18)

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

var _figures: Node3D
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
	var model := MeshInstance3D.new()
	model.mesh = _build_model(faction.get("color", Color.GRAY), faction.get("secondary_color", Color.WHITE))
	_figures.add_child(model)
	if not faction.is_empty():
		var banner := Banners.make(faction, 5.5, 2.2)
		banner.position = Vector3(0.9, 1.6, 0.0)
		_figures.add_child(banner)

	_label = Label3D.new()
	_label.name = "Label"
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
	# A little bob while marching.
	_walk_time += delta
	_figures.position.y = absf(sin(_walk_time * 7.0)) * 0.12 * _scale
	if path.is_empty():
		moving = false
		_figures.position.y = 0.0
		if not destination_settlement.is_empty():
			enter_settlement(destination_settlement)
		destination_settlement = ""
		arrived.emit(self)


func _leave_settlement() -> void:
	inside_settlement = ""
	_label.visible = true


func _build_model(tunic: Color, trim: Color) -> ArrayMesh:
	## A mounted leader with a few soldiers on foot; facing -z.
	var kit := MeshKit.new()
	# Horse and rider.
	kit.box(HORSE, Transform3D(Basis(), Vector3(0, 0.75, 0)), Vector3(0.7, 0.75, 1.9))
	for leg in [Vector3(-0.25, 0, -0.7), Vector3(0.25, 0, -0.7), Vector3(-0.25, 0, 0.7), Vector3(0.25, 0, 0.7)]:
		kit.box(HORSE, Transform3D(Basis(), leg), Vector3(0.18, 0.8, 0.18))
	kit.box(HORSE, Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 1.3, -0.95)), Vector3(0.35, 0.8, 0.4))
	kit.cylinder(tunic, Transform3D(Basis(), Vector3(0, 1.45, 0.05)), 0.26, 0.85, 6, 0.2)
	kit.dome(STEEL, Transform3D(Basis(), Vector3(0, 2.32, 0.05)), 0.2)
	kit.cylinder(SKIN, Transform3D(Basis(), Vector3(0, 2.15, 0.05)), 0.16, 0.2, 6)
	# Soldiers in two ranks behind the leader, spears up.
	for spot in [Vector3(-0.7, 0, 1.6), Vector3(0.7, 0, 1.6), Vector3(-0.7, 0, 2.7), Vector3(0.7, 0, 2.7), Vector3(0, 0, 2.15)]:
		var base := Transform3D(Basis(), spot)
		kit.cylinder(tunic.darkened(0.1), base, 0.24, 1.0, 6, 0.18)
		kit.box(trim, base.translated_local(Vector3(0, 0.55, 0)), Vector3(0.44, 0.08, 0.44))
		kit.cylinder(SKIN, base.translated_local(Vector3(0, 1.0, 0)), 0.14, 0.2, 6)
		kit.dome(STEEL, base.translated_local(Vector3(0, 1.18, 0)), 0.17)
		kit.cylinder(WOOD, base.translated_local(Vector3(0.3, 0, -0.05)), 0.04, 2.1, 4)
		kit.cone(STEEL, base.translated_local(Vector3(0.3, 2.1, -0.05)), 0.07, 0.25, 4)
	return kit.commit()
