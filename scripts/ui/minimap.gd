class_name Minimap
extends PanelContainer
## A small map of the whole world in the top right corner: land shaded from
## the heightmap, forests, sand and snow from the biome mask, rivers and roads,
## castles and towns in their owner's colour, your castle's crest and the
## patch of ground the camera sees. Click or drag on it to look there.

const SIZE := 210.0
const PIXELS := 256              ## resolution of the painted terrain picture
const WATER_DEEP := Color(0.16, 0.33, 0.5)
const WATER := Color(0.3, 0.52, 0.68)
const GRASS := Color(0.5, 0.65, 0.3)
const GRASS_HIGH := Color(0.38, 0.52, 0.25)
const FOREST := Color(0.2, 0.38, 0.16)
const SAND := Color(0.8, 0.72, 0.5)
const ROCK := Color(0.56, 0.53, 0.48)
const SNOW := Color(0.93, 0.94, 0.96)
const DIRT := Color(0.66, 0.53, 0.35)
const RIVER := Color(0.36, 0.6, 0.78)
const VIEW := Color(1.0, 0.95, 0.8)
const PLAYER := Color(0.85, 0.22, 0.16)

var _map: Control
var _texture: ImageTexture
var _rivers: Array[PackedVector2Array] = []
var _redraw_left := 0.0
var _dragging := false


func _ready() -> void:
	add_theme_stylebox_override("panel", GameTheme.panel_box(0.9, 6))
	_map = Control.new()
	_map.custom_minimum_size = Vector2(SIZE, SIZE)
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_map.tooltip_text = "Click to look there"
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_input)
	add_child(_map)
	if GameData.terrain != null:
		_texture = ImageTexture.create_from_image(_paint())
		var scale := SIZE / GameData.terrain.world_size
		for river: Dictionary in GameData.terrain.rivers:
			var line := PackedVector2Array()
			for p: Array in river.get("points", []):
				line.append(Vector2(p[0], p[1]) * scale)
			if line.size() > 1:
				_rivers.append(line)


func _process(delta: float) -> void:
	# The view box follows the camera; a few redraws a second are plenty.
	_redraw_left -= delta
	if visible and _redraw_left <= 0.0:
		_redraw_left = 0.1
		_map.queue_redraw()


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_look_at(event.position)
		_map.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_look_at(event.position)
		_map.accept_event()


func _look_at(at: Vector2) -> void:
	var world := GameData.terrain.world_size
	var p := (at / SIZE).clamp(Vector2.ZERO, Vector2.ONE) * world
	EventBus.map_focus_requested.emit(p)
	_map.queue_redraw()


func _draw_map() -> void:
	if _texture == null:
		return
	_map.draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)
	for line in _rivers:
		_map.draw_polyline(line, RIVER, 1.5, true)
	var scale := SIZE / GameData.terrain.world_size
	# Towns and castles, in their owner's colour.
	for s: Dictionary in GameData.settlements:
		if s.type == "village":
			continue
		var castle := Economy.get_castle(s.id)
		var owner: String = castle.owner if castle != null else s.get("faction", "")
		var colour: Color = PLAYER if owner == "player" else GameData.get_faction(owner).get("color", Color.GRAY)
		var at := Vector2(s.position[0], s.position[1]) * scale
		var r := 4.0 if s.type == "town" else 2.6
		var diamond := PackedVector2Array([at + Vector2(0, -r - 1), at + Vector2(r + 1, 0), at + Vector2(0, r + 1), at + Vector2(-r - 1, 0)])
		_map.draw_colored_polygon(diamond, Color(0.08, 0.06, 0.04))
		_map.draw_rect(Rect2(at - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), colour)
	# Your castle's crest.
	var home := Economy.home_position() * scale
	var crest := Icons.get_icon("crest", 18)
	_map.draw_texture(crest, home - Vector2(9, 11))
	_draw_view(scale)


func _draw_view(scale: float) -> void:
	## The ground the camera sees: where the corners of the screen meet the land.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var level := GameData.terrain.sea_level + 15.0
	var corners := PackedVector2Array()
	for c: Vector2 in [Vector2(0, 0), Vector2(screen.x, 0), screen, Vector2(0, screen.y)]:
		var origin := camera.project_ray_origin(c)
		var dir := camera.project_ray_normal(c)
		var t := 6000.0
		if dir.y < -0.02:
			t = minf((origin.y - level) / -dir.y, t)
		var hit := origin + dir * t
		corners.append((Vector2(hit.x, hit.z) * scale).clamp(Vector2(-4, -4), Vector2(SIZE + 4, SIZE + 4)))
	corners.append(corners[0])
	_map.draw_polyline(corners, Color(0, 0, 0, 0.45), 3.0, true)
	_map.draw_polyline(corners, VIEW, 1.4, true)


func _paint() -> Image:
	## The terrain picture: colour by height and biome, lit from the north-west.
	var terrain: TerrainData = GameData.terrain
	var img := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	var step := terrain.world_size / PIXELS
	var light := Vector3(-0.55, 0.75, -0.4).normalized()
	var roads: Image = GameData.roads.road_image if GameData.roads != null else null
	for j in PIXELS:
		for i in PIXELS:
			var x := (i + 0.5) * step
			var z := (j + 0.5) * step
			var h := terrain.get_height(x, z)
			var colour: Color
			if h < terrain.sea_level:
				colour = WATER.lerp(WATER_DEEP, clampf((terrain.sea_level - h) / 25.0, 0.0, 1.0))
			else:
				var t := clampf((h - terrain.sea_level) / (terrain.max_height - terrain.sea_level), 0.0, 1.0)
				colour = GRASS.lerp(GRASS_HIGH, smoothstep(0.0, 0.5, t))
				colour = colour.lerp(ROCK, smoothstep(0.45, 0.75, t))
				var biome := terrain.get_biome(x, z)
				colour = colour.lerp(SAND, biome.r * 0.85)
				colour = colour.lerp(FOREST, biome.g * 0.7 * (1.0 - smoothstep(0.5, 0.7, t)))
				colour = colour.lerp(SNOW, maxf(biome.b, smoothstep(0.8, 0.95, t)))
				if roads != null:
					var dirt := roads.get_pixel(clampi(int(x), 0, roads.get_width() - 1), clampi(int(z), 0, roads.get_height() - 1)).a
					colour = colour.lerp(DIRT, dirt * 0.8)
				var shade := clampf(terrain.get_normal(x, z).dot(light) * 1.3, 0.55, 1.15)
				colour = colour * shade
			img.set_pixel(i, j, colour)
	return img
