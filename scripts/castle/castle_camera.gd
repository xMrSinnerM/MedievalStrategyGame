class_name CastleCamera
extends Node3D
## Orbiting camera for the castle screen.
##
## Controls:
##   WASD / arrow keys ...... pan
##   left or middle drag .... pan
##   right drag / Q, E ...... rotate
##   mouse wheel ............ zoom

@export var min_distance := 22.0
@export var max_distance := 120.0
@export var start_distance := 66.0
@export var close_pitch_deg := 38.0
@export var far_pitch_deg := 62.0
@export var key_pan_speed := 0.9         ## screen heights per second
@export var key_rotate_speed := 1.8      ## radians per second
@export var drag_rotate_speed := 0.006   ## radians per pixel
@export var zoom_step := 1.15
@export var smoothing := 10.0

var camera: Camera3D
## The area the focus point may move in (world xz).
var bounds := Rect2(-10, -10, 68, 68)

var _focus := Vector3.ZERO
var _yaw := 0.0
var _distance := 78.0
var _focus_now := Vector3.ZERO
var _yaw_now := 0.0
var _distance_now := 78.0
var _pan_drag := false
var _rotate_drag := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()


func reset(centre: Vector3) -> void:
	## Looks at `centre` from the south, as when you walk in through the gate.
	_focus = centre
	_yaw = 0.0
	_distance = start_distance
	_focus_now = _focus
	_yaw_now = _yaw
	_distance_now = _distance
	_apply()


func ground_point(screen_pos: Vector2) -> Variant:
	## Where the mouse ray meets the ground plane, or null if it misses.
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distance = maxf(_distance / zoom_step, min_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distance = minf(_distance * zoom_step, max_distance)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				_pan_drag = event.pressed
			MOUSE_BUTTON_RIGHT:
				_rotate_drag = event.pressed
	elif event is InputEventMouseMotion:
		if _rotate_drag:
			_yaw -= event.relative.x * drag_rotate_speed
		elif _pan_drag:
			_pan_by_pixels(event.relative)


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
		_pan_by_pixels(-move.normalized() * pixels_per_second * delta)
	if Input.is_physical_key_pressed(KEY_Q):
		_yaw += key_rotate_speed * delta
	if Input.is_physical_key_pressed(KEY_E):
		_yaw -= key_rotate_speed * delta

	var k := 1.0 - exp(-smoothing * delta)
	_focus_now = _focus_now.lerp(_focus, k)
	_yaw_now = lerpf(_yaw_now, _yaw, k)
	_distance_now = lerpf(_distance_now, _distance, k)
	_apply()


func _pan_by_pixels(pixels: Vector2) -> void:
	## Drags the ground so the point under the mouse roughly stays under it.
	var world_per_pixel := 2.0 * _distance_now * tan(deg_to_rad(camera.fov * 0.5)) / get_viewport().get_visible_rect().size.y
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_focus += (-right * pixels.x + forward * pixels.y) * world_per_pixel
	_focus.x = clampf(_focus.x, bounds.position.x, bounds.end.x)
	_focus.z = clampf(_focus.z, bounds.position.y, bounds.end.y)


func _apply() -> void:
	var t := inverse_lerp(min_distance, max_distance, _distance_now)
	var pitch := deg_to_rad(lerpf(close_pitch_deg, far_pitch_deg, t))
	var offset := Vector3(sin(_yaw_now) * cos(pitch), sin(pitch), cos(_yaw_now) * cos(pitch)) * _distance_now
	camera.global_position = _focus_now + offset
	camera.look_at(_focus_now, Vector3.UP)
