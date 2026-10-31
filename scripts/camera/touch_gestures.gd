class_name TouchGestures
extends RefCounted
## Two-finger gestures for the cameras on touch screens (phones and tablets in
## the browser): pinch to zoom, twist to rotate, and both fingers together to
## pan. One finger needs nothing here: Godot turns it into the left mouse
## button, so it drags the map and taps pick things like a click.
##
## While two fingers are down that pretend mouse would drag the map too, and
## lifting them could count as a tap; `busy()` tells the cameras to ignore it
## and `tapped_since()` tells click handlers a gesture happened.

## Seconds after the last two-finger touch during which mouse drags and taps are ignored.
const SETTLE_MS := 250

static var _last_multi_ms := -100000

var _points := {}              ## finger index -> position
var _span := 0.0
var _angle := 0.0
var _centre := Vector2.ZERO


static func gesture_since(ms: int) -> bool:
	## Whether two fingers touched the screen since Time.get_ticks_msec() was `ms`
	## (a tap that started then was part of a pinch, not a tap).
	return _last_multi_ms >= ms


static func busy() -> bool:
	return Time.get_ticks_msec() - _last_multi_ms < SETTLE_MS


func feed(event: InputEvent) -> Dictionary:
	## Takes a touch event; returns what the fingers did since the last one:
	## {"zoom": factor (>1 spreads them: zoom in), "twist": radians, "pan": pixels},
	## or {} if it wasn't a two-finger gesture.
	if event is InputEventScreenTouch:
		if event.pressed:
			_points[event.index] = event.position
		else:
			_points.erase(event.index)
		if _points.size() >= 2:
			_last_multi_ms = Time.get_ticks_msec()
			_measure()
		return {}
	if not event is InputEventScreenDrag or not _points.has(event.index):
		return {}
	_points[event.index] = event.position
	if _points.size() < 2:
		return {}
	_last_multi_ms = Time.get_ticks_msec()
	var before_span := _span
	var before_angle := _angle
	var before_centre := _centre
	_measure()
	return {
		"zoom": _span / maxf(before_span, 1.0),
		"twist": wrapf(_angle - before_angle, -PI, PI),
		"pan": _centre - before_centre,
	}


func _measure() -> void:
	var keys := _points.keys()
	keys.sort()
	var a: Vector2 = _points[keys[0]]
	var b: Vector2 = _points[keys[1]]
	_span = a.distance_to(b)
	_angle = (b - a).angle()
	_centre = (a + b) * 0.5
