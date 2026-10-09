extends Node3D
## Strategic parchment map that fades in as the camera reaches its maximum
## zoom-out. Territories come from each faction's region_center for now; once
## settlements exist (next step) they will be drawn from settlement ownership.
##
## Press M to toggle the parchment at any zoom.

const PARCHMENT_SHADER := preload("res://shaders/parchment.gdshader")
const SHEET_MARGIN := 220.0
const FADE_START := 0.86     ## zoom_t where the parchment starts to appear
const FADE_END := 0.97
const TERRITORY_SIZE := 512
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
	material.set_shader_parameter("territory", ImageTexture.create_from_image(_territory_image()))
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
		var centre: Array = faction.get("region_center", [0, 0])
		var label := Label3D.new()
		label.text = String(faction.name).to_upper()
		label.font_size = 160
		label.pixel_size = 0.25
		label.outline_size = 0
		label.modulate = Color(0.25, 0.17, 0.1)
		label.no_depth_test = true
		label.render_priority = 11
		label.shaded = false
		label.double_sided = true
		label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		label.position = Vector3(centre[0], terrain.max_height + 27.0, centre[1])
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


func _territory_image() -> Image:
	## Nearest faction region centre (with a noisy boundary) for every land pixel.
	## Stored as faction index + 1; 0 means sea.
	var terrain: TerrainData = GameData.terrain
	var img := Image.create(TERRITORY_SIZE, TERRITORY_SIZE, false, Image.FORMAT_R8)
	var noise := FastNoiseLite.new()
	noise.seed = 91
	noise.frequency = 0.004
	noise.fractal_octaves = 3
	var centres: Array[Vector2] = []
	for faction in GameData.factions:
		var c: Array = faction.get("region_center", [0, 0])
		centres.append(Vector2(c[0], c[1]))
	var px := terrain.world_size / TERRITORY_SIZE
	for j in TERRITORY_SIZE:
		for i in TERRITORY_SIZE:
			var x := (i + 0.5) * px
			var z := (j + 0.5) * px
			if terrain.get_height(x, z) < terrain.sea_level:
				continue
			var p := Vector2(x + noise.get_noise_2d(x, z) * 160.0, z + noise.get_noise_2d(z + 500.0, x) * 160.0)
			var best := 0
			var best_d := INF
			for k in centres.size():
				var d := p.distance_squared_to(centres[k])
				if d < best_d:
					best_d = d
					best = k
			img.set_pixel(i, j, Color8(best + 1, 0, 0))
	return img


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
