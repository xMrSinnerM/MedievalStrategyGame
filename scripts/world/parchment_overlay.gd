extends Node3D
## Strategic parchment map that fades in as the camera reaches its maximum
## zoom-out. Territories are drawn from settlement ownership in the shader;
## call refresh_settlements() after a settlement changes hands.
##
## Press M to toggle the parchment at any zoom.

const PARCHMENT_SHADER := preload("res://shaders/parchment.gdshader")
const SHEET_MARGIN := 220.0
const FADE_START := 0.86     ## zoom_t where the parchment starts to appear
const FADE_END := 0.97
const TYPE_CODE := {"town": 0.0, "castle": 1.0, "village": 2.0}
## How much each settlement type pulls its faction's name label towards it.
const LABEL_WEIGHT := {"town": 3.0, "castle": 2.0, "village": 1.0}
const RIVER_MASK_SIZE := 1024

var material: ShaderMaterial
var amount := 0.0

var _sheet: MeshInstance3D
var _labels: Array[Label3D] = []
var _zoom_t := 0.0
var _forced := false


func build() -> void:
	var terrain: TerrainData = GameData.terrain
	material = ShaderMaterial.new()
	material.shader = PARCHMENT_SHADER
	material.render_priority = 10
	material.set_shader_parameter("world_size", terrain.world_size)
	material.set_shader_parameter("heightmap_resolution", float(terrain.resolution))
	material.set_shader_parameter("max_height", terrain.max_height)
	material.set_shader_parameter("sea_level", terrain.sea_level)
	material.set_shader_parameter("sheet_margin", SHEET_MARGIN)
	material.set_shader_parameter("heightmap", terrain.make_height_texture())
	material.set_shader_parameter("road_mask", GameData.roads.make_road_texture())
	refresh_settlements()
	material.set_shader_parameter("river_mask", ImageTexture.create_from_image(_river_image()))
	material.set_shader_parameter("faction_palette", ImageTexture.create_from_image(_palette_image()))
	material.set_shader_parameter("faction_count", GameData.factions.size())
	material.set_shader_parameter("paper_noise", MapStyle.noise_texture(5, 0.01))

	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * (terrain.world_size + SHEET_MARGIN * 2.0)
	_sheet = MeshInstance3D.new()
	_sheet.name = "Sheet"
	_sheet.mesh = mesh
	_sheet.material_override = material
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.position = Vector3(terrain.world_size * 0.5, terrain.max_height + 25.0, terrain.world_size * 0.5)
	add_child(_sheet)

	for faction in GameData.factions:
		var centre := _label_centre(faction)
		var label := Label3D.new()
		label.text = String(faction.name).to_upper()
		label.font_size = 130
		label.pixel_size = 0.25
		label.outline_size = 0
		label.modulate = Color(0.25, 0.17, 0.1)
		label.no_depth_test = true
		label.render_priority = 11
		label.shaded = false
		label.double_sided = true
		label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		label.position = Vector3(centre.x, terrain.max_height + 27.0, centre.y)
		add_child(label)
		_labels.append(label)

	EventBus.camera_zoom_changed.connect(_on_zoom_changed)
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		_forced = not _forced
		_update()


func _on_zoom_changed(zoom_t: float) -> void:
	_zoom_t = zoom_t
	_update()


func _process(_delta: float) -> void:
	# Keep labels facing the camera's heading so they read upright on screen.
	var cam := get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	var yaw := cam.global_rotation.y
	for label in _labels:
		label.rotation = Vector3(-PI * 0.5, yaw, 0.0)


func _update() -> void:
	var target := 1.0 if _forced else smoothstep(FADE_START, FADE_END, _zoom_t)
	if is_equal_approx(target, amount) and _sheet.visible == (amount > 0.0):
		return
	amount = target
	material.set_shader_parameter("opacity", amount)
	_sheet.visible = amount > 0.001
	for label in _labels:
		label.visible = _sheet.visible
		label.modulate.a = amount
	EventBus.parchment_amount_changed.emit(amount)


func refresh_settlements() -> void:
	## Uploads every settlement's position, owner and type for the shader.
	var count := GameData.settlements.size()
	var img := Image.create(maxi(count, 1), 1, false, Image.FORMAT_RGBAF)
	for i in count:
		var s: Dictionary = GameData.settlements[i]
		var faction := GameData.get_faction(s.faction)
		img.set_pixel(i, 0, Color(s.position[0], s.position[1], faction.get("index", 0), TYPE_CODE.get(s.type, 2.0)))
	material.set_shader_parameter("settlement_data", ImageTexture.create_from_image(img))
	material.set_shader_parameter("settlement_count", count)


func _label_centre(faction: Dictionary) -> Vector2:
	## Weighted middle of the faction's settlements, or its region centre if it has none.
	var total := Vector2.ZERO
	var weight := 0.0
	for s in GameData.settlements:
		if s.faction == faction.id:
			var w: float = LABEL_WEIGHT.get(s.type, 1.0)
			total += Vector2(s.position[0], s.position[1]) * w
			weight += w
	var centre: Vector2
	if weight == 0.0:
		var c: Array = faction.get("region_center", [0, 0])
		centre = Vector2(c[0], c[1])
	else:
		centre = total / weight
	# Nudge the label off settlement marks and town names (the only settlement
	# labels left at this zoom): the nearest clear spot on land. Town names float
	# above the terrain, below the sheet, so from the steep camera they show a
	# little south of their mark.
	var terrain: TerrainData = GameData.terrain
	var best := centre
	var best_d := INF
	for oy in range(-12, 13):
		for ox in range(-12, 13):
			var p := centre + Vector2(ox * 20.0, oy * 15.0)
			var d := p.distance_squared_to(centre)
			if d >= best_d or terrain.get_height(p.x, p.y) < terrain.sea_level:
				continue
			var clear := true
			for s in GameData.settlements:
				var q := Vector2(s.position[0], s.position[1]) - p
				var town: bool = s.type == "town"
				if absf(q.x) < (170.0 if town else 110.0) and q.y > (-80.0 if town else -18.0) and q.y < 20.0:
					clear = false
					break
			if clear:
				best = p
				best_d = d
	return best


func _river_image() -> Image:
	var terrain: TerrainData = GameData.terrain
	var img := Image.create(RIVER_MASK_SIZE, RIVER_MASK_SIZE, false, Image.FORMAT_L8)
	var scale := RIVER_MASK_SIZE / terrain.world_size
	for river in terrain.rivers:
		var points: Array = river.get("points", [])
		for k in points.size() - 1:
			var a := Vector2(points[k][0], points[k][1]) * scale
			var b := Vector2(points[k + 1][0], points[k + 1][1]) * scale
			var r := clampf(points[k][3] * scale * 0.5, 0.8, 2.5)
			var steps := int(ceil(a.distance_to(b))) + 1
			for s in steps:
				var p := a.lerp(b, float(s) / steps)
				for oy in range(-3, 4):
					for ox in range(-3, 4):
						var q := Vector2i(int(p.x) + ox, int(p.y) + oy)
						if q.x < 0 or q.y < 0 or q.x >= RIVER_MASK_SIZE or q.y >= RIVER_MASK_SIZE:
							continue
						var v := clampf(r + 0.5 - Vector2(q).distance_to(p), 0.0, 1.0)
						if v > img.get_pixel(q.x, q.y).r:
							img.set_pixel(q.x, q.y, Color(v, v, v))
	return img


func _palette_image() -> Image:
	var img := Image.create(8, 1, false, Image.FORMAT_RGB8)
	for faction in GameData.factions:
		img.set_pixel(faction.index, 0, faction.color)
	return img
