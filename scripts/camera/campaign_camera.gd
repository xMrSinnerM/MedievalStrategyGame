class_name CampaignCamera
extends Node3D
## Tilted top-down campaign camera.
##
## Controls:
##   WASD / arrow keys ...... pan
##   left or middle drag .... pan
##   right drag / Q, E ...... rotate
##   mouse wheel ............ zoom (tilts towards top-down as it zooms out)
##   Home ................... recentre on the map

@export var min_distance := 35.0
@export var max_distance := 2300.0
@export var start_distance := 700.0
@export var close_pitch_deg := 32.0      ## tilt when fully zoomed in
@export var far_pitch_deg := 78.0        ## tilt at the strategic overview
@export var key_pan_speed := 1.1         ## screen heights per second
@export var key_rotate_speed := 1.8      ## radians per second
@export var drag_rotate_speed := 0.006   ## radians per pixel
@export var zoom_step := 1.18
@export var smoothing := 10.0
@export var ground_clearance := 12.0

var camera: Camera3D

var _focus := Vector3.ZERO        ## target point on the ground
var _yaw := 0.0
var _distance := 700.0
var _focus_now := Vector3.ZERO    ## smoothed values actually used
var _yaw_now := 0.0
var _distance_now := 700.0
var _pan_drag := false
var _rotate_drag := false
var _last_zoom_t := -1.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 1.0
	camera.far = 20000.0
	add_child(camera)
	camera.make_current()


func setup() -> void:
	var terrain: TerrainData = GameData.terrain
	_focus = Vector3(terrain.world_size * 0.5, 0.0, terrain.world_size * 0.48)
	_focus.y = terrain.get_surface_height(_focus.x, _focus.z)
	_distance = start_distance
	_focus_now = _focus
	_distance_now = _distance
	_apply()


## 0 when fully zoomed in, 1 at the strategic overview.
func get_zoom_t() -> float:
	return inverse_lerp(log(min_distance), log(max_distance), log(_distance_now))


func focus_on(point: Vector3, distance := -1.0) -> void:
	_focus = point
	if distance > 0.0:
		_distance = clampf(distance, min_distance, max_distance)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = maxf(_distance / zoom_step, min_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = minf(_distance * zoom_step, max_distance)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				_pan_drag = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_rotate_drag = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_drag:
			_pan_by_pixels(-mm.relative)
		if _rotate_drag:
			_yaw -= mm.relative.x * drag_rotate_speed
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_HOME:
		setup()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move != Vector2.ZERO:
		var pixels_per_second := get_viewport().get_visible_rect().size.y * key_pan_speed
		_pan_by_pixels(move.normalized() * pixels_per_second * delta)
	if Input.is_physical_key_pressed(KEY_Q):
		_yaw += key_rotate_speed * delta
	if Input.is_physical_key_pressed(KEY_E):
		_yaw -= key_rotate_speed * delta

	var terrain: TerrainData = GameData.terrain
	_focus.x = clampf(_focus.x, 0.0, terrain.world_size)
	_focus.z = clampf(_focus.z, 0.0, terrain.world_size)
	_focus.y = terrain.get_surface_height(_focus.x, _focus.z)

	var k := 1.0 - exp(-smoothing * delta)
	_focus_now = _focus_now.lerp(_focus, k)
	_yaw_now = lerp_angle(_yaw_now, _yaw, k)
	_distance_now = exp(lerpf(log(_distance_now), log(_distance), k))
	_apply()


func _pan_by_pixels(pixels: Vector2) -> void:
	# Move the focus so the ground under the cursor follows the drag.
	var view_h := get_viewport().get_visible_rect().size.y
	var world_per_pixel := 2.0 * _distance_now * tan(deg_to_rad(camera.fov * 0.5)) / view_h
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var pitch := deg_to_rad(_pitch_for(get_zoom_t()))
	# Screen-vertical motion covers more ground when the camera is tilted.
	_focus += right * pixels.x * world_per_pixel - forward * pixels.y * world_per_pixel / maxf(sin(pitch), 0.3)


func _pitch_for(zoom_t: float) -> float:
	return lerpf(close_pitch_deg, far_pitch_deg, smoothstep(0.0, 1.0, zoom_t))


func _apply() -> void:
	var zoom_t := get_zoom_t()
	var pitch := deg_to_rad(_pitch_for(zoom_t))
	var offset := Vector3(sin(_yaw_now) * cos(pitch), sin(pitch), cos(_yaw_now) * cos(pitch)) * _distance_now
	var pos := _focus_now + offset
	var terrain: TerrainData = GameData.terrain
	pos.y = maxf(pos.y, terrain.get_surface_height(pos.x, pos.z) + ground_clearance)
	camera.look_at_from_position(pos, _focus_now, Vector3.UP)
	if absf(zoom_t - _last_zoom_t) > 0.001:
		_last_zoom_t = zoom_t
		EventBus.camera_zoom_changed.emit(zoom_t)
