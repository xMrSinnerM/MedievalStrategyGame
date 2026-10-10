extends Node3D
## The castle screen: one castle's grounds seen up close. Shows its buildings
## on the castle grid and lets the owner place, move, upgrade and cancel them.
## NPC castles open read-only, so the same screen can inspect them later.
##
## Mouse: click a building to select it. While placing or moving, the building
## follows the mouse; click to put it down, right-click or Esc to stop.

signal selection_changed(building_id: int)   ## -1 when nothing is selected
signal mode_changed(mode: int)
signal message(text: String)                 ## feedback such as "Not enough resources"

enum Mode { SELECT, PLACE, MOVE }

const CELL := CastleModels.CELL
const CLICK_SLOP := 6.0

var castle: CastleState
var editable := false
var mode := Mode.SELECT
var selected := -1
var placing_type := ""

@onready var camera_rig: CastleCamera = $CastleCamera
@onready var hud: CanvasLayer = $CastleHUD

var _ground: MeshInstance3D
var _ground_material: ShaderMaterial
var _buildings_root: Node3D
var _nodes := {}               ## building id -> Node3D (mesh + label)
var _signature := ""
var _ghost: MeshInstance3D
var _ghost_ok_material: StandardMaterial3D
var _ghost_bad_material: StandardMaterial3D
var _ghost_cell := Vector2i(-999, -999)
var _selection_mesh: MeshInstance3D
var _press_pos := Vector2.ZERO
var _pressed := false


func _ready() -> void:
	Economy.ensure_loaded()
	_build_environment()
	_build_ground()
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	_ghost = MeshInstance3D.new()
	_ghost.visible = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_ghost_ok_material = _ghost_material(Color(0.35, 0.95, 0.4, 0.55))
	_ghost_bad_material = _ghost_material(Color(1.0, 0.3, 0.25, 0.55))
	_selection_mesh = MeshInstance3D.new()
	_selection_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_mesh.visible = false
	add_child(_selection_mesh)
	Economy.changed.connect(_on_economy_changed)
	hud.view = self


func open(p_castle: CastleState) -> void:
	## Shows `p_castle`. The player's own castle can be changed, others only looked at.
	castle = p_castle
	editable = not castle.is_npc()
	var size := castle.rules.grid_size * CELL
	camera_rig.bounds = Rect2(-12, -12, size + 24, size + 24)
	camera_rig.reset(Vector3(size * 0.5, 0, size * 0.5 + 4.0))
	_ground_material.set_shader_parameter("grid_cells", float(castle.rules.grid_size))
	_set_mode(Mode.SELECT)
	select(-1)
	_signature = ""
	_refresh_buildings()
	hud.show_castle()


func grid_centre() -> Vector3:
	var size := castle.rules.grid_size * CELL
	return Vector3(size * 0.5, 0, size * 0.5)


# --- Orders (called by the HUD) ---------------------------------------------------

func select(building_id: int) -> void:
	selected = building_id
	_update_selection_mesh()
	selection_changed.emit(selected)


func start_placing(type: String) -> void:
	if not editable:
		return
	var reason := castle.check_build(type)
	if reason != "":
		message.emit(reason)
		return
	placing_type = type
	select(-1)
	_set_mode(Mode.PLACE)


func start_moving() -> void:
	if not editable or selected < 0:
		return
	var b := castle.get_building(selected)
	if b.is_empty() or b.cell.x < 0:
		return
	placing_type = b.type
	_set_mode(Mode.MOVE)


func upgrade_selected() -> void:
	if not editable or selected < 0:
		return
	var reason := castle.check_upgrade(selected)
	if reason != "" or not castle.upgrade(selected, Economy.now()):
		message.emit(reason if reason != "" else "Can't upgrade that now")
		return
	_after_order()


func cancel_selected() -> void:
	if not editable or selected < 0:
		return
	var b := castle.get_building(selected)
	var was_new: bool = not b.is_empty() and b.level == 0
	if castle.cancel(selected, Economy.now()):
		message.emit("Construction cancelled, %d%% of the cost refunded" % int(CastleState.CANCEL_REFUND * 100.0))
		if was_new:
			select(-1)
		_after_order()


func recruit(unit: String, amount: int) -> void:
	if not editable:
		return
	var reason := castle.check_recruit(unit, amount)
	if reason != "" or not castle.recruit(unit, amount, Economy.now()):
		message.emit(reason if reason != "" else "Can't train them now")
		return
	Economy.changed.emit()


func cancel_training(index: int) -> void:
	if editable and castle.cancel_training(index, Economy.now()):
		message.emit("Training cancelled, %d%% of the cost refunded" % int(CastleState.CANCEL_REFUND * 100.0))
		Economy.changed.emit()


func move_troops(unit: String, amount: int, to_field: bool) -> void:
	## Moves soldiers between the garrison and your warband, which must be at the castle.
	if not editable:
		return
	if not Economy.warband_home:
		message.emit("Your warband is away. Bring it to your castle first.")
		return
	var moved := castle.send_to_field(unit, amount) if to_field else castle.return_from_field(unit, amount)
	if moved > 0:
		Economy.changed.emit()


func stop_mode() -> void:
	_set_mode(Mode.SELECT)


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if castle == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_press_pos = event.position
			elif _pressed:
				_pressed = false
				if event.position.distance_to(_press_pos) <= CLICK_SLOP:
					_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mode != Mode.SELECT:
			_set_mode(Mode.SELECT)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		# Esc backs out of placing or a selection; with nothing to undo it
		# falls through to the pause menu.
		if mode != Mode.SELECT:
			_set_mode(Mode.SELECT)
			get_viewport().set_input_as_handled()
		elif selected >= 0:
			select(-1)
			get_viewport().set_input_as_handled()


func _click(screen_pos: Vector2) -> void:
	var hit = camera_rig.ground_point(screen_pos)
	if hit == null:
		return
	var point: Vector3 = hit
	match mode:
		Mode.PLACE:
			var cell := _footprint_cell(placing_type, point)
			var reason := castle.check_place(placing_type, cell)
			if reason != "":
				message.emit(reason)
				return
			var id := castle.place(placing_type, cell, Economy.now())
			_set_mode(Mode.SELECT)
			_after_order()
			select(id)
		Mode.MOVE:
			var cell := _footprint_cell(placing_type, point)
			if not castle.move(selected, cell):
				message.emit("There's no room there")
				return
			_set_mode(Mode.SELECT)
			_after_order()
			select(selected)
		_:
			select(building_at(point))


func building_at(point: Vector3) -> int:
	## The building under a ground point, the wall if the point is on it, or -1.
	var cell := Vector2i(floori(point.x / CELL), floori(point.z / CELL))
	for b in castle.buildings:
		if b.cell.x >= 0 and Rect2i(b.cell, castle.rules.size(b.type)).has_point(cell):
			return b.id
	var outer := CastleModels.wall_bounds(castle.rules.grid_size)
	var inner := outer.grow(-2.6)
	var p := Vector2(point.x, point.z)
	if outer.has_point(p) and not inner.has_point(p):
		for b in castle.buildings:
			if castle.rules.is_perimeter(b.type):
				return b.id
	return -1


func _footprint_cell(type: String, point: Vector3) -> Vector2i:
	## The top-left cell that centres `type`'s footprint under the mouse.
	var s := castle.rules.size(type)
	return Vector2i(roundi(point.x / CELL - s.x * 0.5), roundi(point.z / CELL - s.y * 0.5))


func _process(_delta: float) -> void:
	if castle == null:
		return
	if mode != Mode.SELECT:
		_update_ghost()
	_update_timer_labels()


# --- Visuals --------------------------------------------------------------------

func _on_economy_changed() -> void:
	if castle != null and is_inside_tree():
		_refresh_buildings()


func _after_order() -> void:
	_refresh_buildings()
	Economy.changed.emit()


func _refresh_buildings() -> void:
	## Rebuilds models whose type, level, place or construction state changed.
	var parts: PackedStringArray = []
	for b in castle.buildings:
		parts.append("%d:%s:%d:%d:%d,%d" % [b.id, b.type, b.level, b.target, b.cell.x, b.cell.y])
	var signature := "|".join(parts)
	if signature == _signature:
		return
	_signature = signature
	for node in _nodes.values():
		node.queue_free()
	_nodes.clear()
	for b in castle.buildings:
		var node := Node3D.new()
		var mesh := MeshInstance3D.new()
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.font_size = 26
		label.outline_size = 8
		label.modulate = Color(1.0, 0.95, 0.8)
		label.name = "Timer"
		if castle.rules.is_perimeter(b.type):
			mesh.mesh = CastleModels.wall(maxi(b.level, 1), castle.rules.grid_size)
			var gate := Vector3(grid_centre().x, 0, castle.rules.grid_size * CELL + CastleModels.WALL_MARGIN)
			label.position = gate + Vector3(0, 7.0, 0)
		else:
			var s := castle.rules.size(b.type)
			mesh.mesh = CastleModels.build(b.type, b.level, s, b.target > 0)
			node.position = Vector3((b.cell.x + s.x * 0.5) * CELL, 0, (b.cell.y + s.y * 0.5) * CELL)
			label.position = Vector3(0, 4.0 + (6.0 if b.type == "keep" else 0.0), 0)
		node.add_child(mesh)
		node.add_child(label)
		_buildings_root.add_child(node)
		_nodes[b.id] = node
	_update_timer_labels()
	_update_selection_mesh()
	if selected >= 0 and castle.get_building(selected).is_empty():
		select(-1)


func _update_timer_labels() -> void:
	var t := Economy.now()
	for b in castle.buildings:
		var node: Node3D = _nodes.get(b.id)
		if node == null:
			continue
		var label: Label3D = node.get_node("Timer")
		label.visible = b.target > 0
		if b.target > 0:
			var what := "Building" if b.level == 0 else "Level %d" % b.target
			label.text = "%s  %s" % [what, format_time(castle.time_left(b.id, t))]


func _update_selection_mesh() -> void:
	if castle == null or selected < 0 or castle.get_building(selected).is_empty():
		_selection_mesh.visible = false
		return
	var b := castle.get_building(selected)
	var kit := MeshKit.new()
	var gold := Color(1.0, 0.82, 0.3)
	var rect: Rect2
	if b.cell.x < 0:
		rect = CastleModels.wall_bounds(castle.rules.grid_size).grow(-0.4)
	else:
		var s := castle.rules.size(b.type)
		rect = Rect2(Vector2(b.cell) * CELL, Vector2(s) * CELL).grow(0.1)
	var c := rect.get_center()
	var y := 0.03
	kit.box(gold, Transform3D(Basis(), Vector3(c.x, y, rect.position.y)), Vector3(rect.size.x, 0.05, 0.18))
	kit.box(gold, Transform3D(Basis(), Vector3(c.x, y, rect.end.y)), Vector3(rect.size.x, 0.05, 0.18))
	kit.box(gold, Transform3D(Basis(), Vector3(rect.position.x, y, c.y)), Vector3(0.18, 0.05, rect.size.y))
	kit.box(gold, Transform3D(Basis(), Vector3(rect.end.x, y, c.y)), Vector3(0.18, 0.05, rect.size.y))
	_selection_mesh.mesh = kit.commit(true)
	_selection_mesh.visible = true


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_ghost_cell = Vector2i(-999, -999)
	var placing := mode != Mode.SELECT
	_ghost.visible = false
	_ground_material.set_shader_parameter("grid_amount", 1.0 if placing else 0.0)
	_ground_material.set_shader_parameter("highlight_rect", Vector4.ZERO)
	if placing:
		_ghost.mesh = CastleModels.build(placing_type, maxi(castle.get_building(selected).get("level", 1), 1) if mode == Mode.MOVE else 1,
			castle.rules.size(placing_type), false)
	mode_changed.emit(mode)


func _update_ghost() -> void:
	var hit = camera_rig.ground_point(get_viewport().get_mouse_position())
	if hit == null:
		_ghost.visible = false
		return
	var cell := _footprint_cell(placing_type, hit)
	if cell == _ghost_cell and _ghost.visible:
		return
	_ghost_cell = cell
	var ok: bool
	if mode == Mode.PLACE:
		ok = castle.check_place(placing_type, cell) == ""
	else:
		ok = castle.fits(placing_type, cell, selected)
	var s := castle.rules.size(placing_type)
	_ghost.position = Vector3((cell.x + s.x * 0.5) * CELL, 0.02, (cell.y + s.y * 0.5) * CELL)
	_ghost.material_override = _ghost_ok_material if ok else _ghost_bad_material
	_ghost.visible = true
	_ground_material.set_shader_parameter("highlight_rect", Vector4(cell.x * CELL, cell.y * CELL, s.x * CELL, s.y * CELL))
	_ground_material.set_shader_parameter("highlight_color", Color(0.3, 0.9, 0.35) if ok else Color(0.95, 0.25, 0.2))


func _ghost_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = preload("res://shaders/castle_ground.gdshader")
	_ground_material.set_shader_parameter("cell", CELL)
	_ground_material.set_shader_parameter("wall_margin", CastleModels.WALL_MARGIN)
	_ground_material.set_shader_parameter("noise", MapStyle.noise_texture(71, 0.01, 256))
	_ground = MeshInstance3D.new()
	_ground.mesh = plane
	_ground.material_override = _ground_material
	_ground.position = Vector3(24, 0, 24)
	add_child(_ground)
	# A ring of trees outside the walls so the castle doesn't float in a void.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var kit := MeshKit.new()
	var trunk := Color(0.36, 0.26, 0.17)
	for i in 160:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(44.0, 110.0)
		var at := Vector3(24, 0, 24) + Vector3(cos(angle), 0, sin(angle)) * r
		if at.z > 54.0 and absf(at.x - 24.0) < 7.0:
			continue   # keep the road out of the gate clear
		var h := rng.randf_range(3.0, 6.0)
		var leaf := Color(0.2, 0.36, 0.17).lerp(Color(0.32, 0.45, 0.2), rng.randf())
		kit.cylinder(trunk, Transform3D(Basis(), at), 0.25, h * 0.4, 5)
		kit.cone(leaf, Transform3D(Basis(), at + Vector3(0, h * 0.3, 0)), h * 0.32, h * 0.8, 7)
	var trees := MeshInstance3D.new()
	trees.mesh = kit.commit(true)
	add_child(trees)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.5, 0.65, 0.82)
	sky_material.sky_horizon_color = Color(0.82, 0.8, 0.72)
	sky_material.ground_horizon_color = Color(0.82, 0.8, 0.72)
	sky_material.ground_bottom_color = Color(0.35, 0.38, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.8, 0.72)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world_env.add_to_group("environment")
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.add_to_group("sun")
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.2
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-140.0), 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)


static func format_time(seconds: float) -> String:
	var s := int(ceilf(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s
