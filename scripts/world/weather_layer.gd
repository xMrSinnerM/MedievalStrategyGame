extends Node3D
## Weather and the time of day on the world map (WeatherRules). The sun,
## sky and ambient light follow a day that takes `day_hours`; rain and storm
## cells drift across the map as banks of cloud with rain falling under them,
## and storms flash with lightning. Armies marching out through them are
## slower (Economy's march times include it).

const CLOUD_HEIGHT := 150.0
const CHECK_EVERY := 2.0
const DAY_SKY := Color(0.56, 0.68, 0.80)
const NIGHT_SKY := Color(0.07, 0.10, 0.22)
const DAY_SUN := Color(1.0, 0.9, 0.76)
const NIGHT_SUN := Color(0.55, 0.65, 1.0)
const LOW_SUN := Color(1.0, 0.58, 0.32)
const CLOUD := {"rain": Color(0.62, 0.64, 0.68), "storm": Color(0.32, 0.33, 0.38)}
const LABEL := {"rain": Color(0.75, 0.88, 1.0), "storm": Color(0.85, 0.8, 1.0)}

var _shown := {}             ## cell id -> {"node", "clouds", "rain", "flash", "label", "cell", "materials"}
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun_energy := 1.25
var _zoom_t := 0.0
var _timer := 0.0
var _flash_timer := 0.0


func build() -> void:
	_sun = get_tree().get_first_node_in_group("sun")
	var world_env: WorldEnvironment = get_tree().get_first_node_in_group("environment")
	if world_env != null:
		_env = world_env.environment
		_sky = _env.sky.sky_material if _env.sky != null else null
	if _sun != null:
		_sun_energy = _sun.light_energy
	EventBus.camera_zoom_changed.connect(func(t: float) -> void: _zoom_t = t)
	_sync()
	_light(Economy.now())


func _sync() -> void:
	var rules := Economy.weather_rules
	if rules == null:
		return
	var live := {}
	for cell: Dictionary in rules.active(Economy.now()):
		if cell.kind == "clear":
			continue
		live[cell.id] = true
		if not _shown.has(cell.id):
			_shown[cell.id] = _make(cell)
	for id: String in _shown.keys():
		if not live.has(id):
			_shown[id].node.queue_free()
			_shown.erase(id)


func _make(cell: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = String(cell.id)
	add_child(root)
	var r := float(cell.radius)
	var storm: bool = cell.kind == "storm"
	var rng := RandomNumberGenerator.new()
	rng.seed = String(cell.id).hash()
	# A bank of soft puffs seen from above, layered so it looks billowy.
	var clouds := Node3D.new()
	root.add_child(clouds)
	var materials: Array = []
	for k in (22 if storm else 15):
		var puff := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var size := rng.randf_range(0.5, 0.95) * r
		quad.size = Vector2(size, size)
		quad.orientation = PlaneMesh.FACE_Y
		puff.mesh = quad
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		var shade := rng.randf_range(0.85, 1.1)
		var base: Color = CLOUD[String(cell.kind)]
		m.albedo_color = Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
		m.albedo_texture = _puff_texture()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		m.render_priority = k
		puff.material_override = m
		materials.append(m)
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.55
		puff.position = Vector3(cos(a) * d, k * 1.5, sin(a) * d)
		puff.rotation.y = rng.randf() * TAU
		clouds.add_child(puff)
	# Rain falling under it.
	var rain := CPUParticles3D.new()
	rain.amount = 900 if storm else 500
	rain.lifetime = 1.6
	rain.preprocess = 1.6
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(r * 0.7, 4.0, r * 0.7)
	rain.direction = Vector3(0.15 if storm else 0.05, -1, 0)
	rain.spread = 3.0
	rain.gravity = Vector3.ZERO
	rain.initial_velocity_min = 90.0
	rain.initial_velocity_max = 110.0
	rain.local_coords = true
	var drop := QuadMesh.new()
	drop.size = Vector2(0.35, 7.0)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.albedo_color = Color(0.78, 0.85, 0.95, 0.45)
	drop.material = dm
	rain.mesh = drop
	rain.position = Vector3(0, -10.0, 0)
	root.add_child(rain)
	var flash: OmniLight3D = null
	if storm:
		flash = OmniLight3D.new()
		flash.light_color = Color(0.85, 0.9, 1.0)
		flash.omni_range = r * 2.2
		flash.omni_attenuation = 0.6
		flash.light_energy = 0.0
		flash.shadow_enabled = false
		flash.position = Vector3(0, -40.0, 0)
		root.add_child(flash)
	var label := Label3D.new()
	label.set_meta("plate", "tag")
	label.font_size = 30
	label.outline_size = 9
	label.modulate = LABEL[String(cell.kind)]
	label.outline_modulate = Color(0.08, 0.08, 0.12, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.no_depth_test = true
	label.render_priority = 12
	label.outline_render_priority = 11
	label.shaded = false
	label.text = "%s: armies %d%% slower" % [Economy.weather_rules.kind_name(String(cell.kind)),
		roundi(float(Economy.weather_rules.kinds[String(cell.kind)].slow) * 100.0)]
	label.position = Vector3(0, 30.0, r * 0.6)
	root.add_child(label)
	return {"node": root, "clouds": clouds, "rain": rain, "flash": flash, "label": label, "cell": cell, "materials": materials}


static var _puff: Texture2D


static func _puff_texture() -> Texture2D:
	## A soft round puff: opaque in the middle, fading out to the edge.
	if _puff == null:
		var tex := GradientTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.add_point(0.45, Color(1, 1, 1, 0.6))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
		tex.gradient = g
		_puff = tex
	return _puff


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_EVERY
		_sync()
	var rules := Economy.weather_rules
	if rules == null:
		return
	var now := Economy.now()
	_light(now)
	# Clouds fade as the camera comes down to them, and before the parchment
	# overview takes over (the label stays on it).
	var cloud_seen := smoothstep(0.2, 0.42, _zoom_t) * (1.0 - smoothstep(0.78, 0.86, _zoom_t))
	_flash_timer -= delta
	var flash_now := _flash_timer <= 0.0
	if flash_now:
		_flash_timer = randf_range(0.8, 3.0)
	for id: String in _shown:
		var s: Dictionary = _shown[id]
		var c := rules.centre(s.cell, now)
		var ground := GameData.terrain.get_surface_height(c.x, c.y)
		var node: Node3D = s.node
		node.position = Vector3(c.x, maxf(ground, 60.0) + CLOUD_HEIGHT, c.y)
		var strength := rules.strength(s.cell, now)
		for m: StandardMaterial3D in s.materials:
			m.albedo_color.a = 0.85 * strength * cloud_seen
		s.clouds.visible = cloud_seen > 0.01 and strength > 0.01
		s.rain.emitting = strength > 0.2
		s.rain.visible = _zoom_t < 0.86
		s.label.visible = strength > 0.2
		var flash: OmniLight3D = s.flash
		if flash != null:
			if flash_now and strength > 0.5 and randf() < 0.35:
				flash.light_energy = 6.0
			flash.light_energy = move_toward(flash.light_energy, 0.0, delta * 30.0)


func _light(t: float) -> void:
	var rules := Economy.weather_rules
	if rules == null or _sun == null:
		return
	var d := rules.daylight(t)
	var low := 4.0 * d * (1.0 - d)      # strongest at dawn and dusk
	var color := NIGHT_SUN.lerp(DAY_SUN, d).lerp(LOW_SUN, low * 0.55)
	_sun.light_color = color
	_sun.light_energy = lerpf(0.28, _sun_energy, d)
	# The sun swings across the sky over the day, staying high enough for shadows.
	_sun.rotation = Vector3(deg_to_rad(lerpf(-28.0, -48.0, d)), deg_to_rad(-140.0 + (rules.day_phase(t) - 0.5) * 120.0), 0.0)
	if _env != null:
		_env.ambient_light_energy = lerpf(0.38, 0.75, d)
		_env.tonemap_exposure = lerpf(0.85, 0.95, d)
	if _sky != null:
		_sky.sky_top_color = NIGHT_SKY.lerp(DAY_SKY, d).lerp(LOW_SUN.darkened(0.3), low * 0.25)
