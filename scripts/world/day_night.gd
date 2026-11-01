class_name DayNight
extends Node3D
## The time of day on the world map: the sun, sky and ambient light follow a
## day and night that take DAY_SECONDS (on the real clock, so every player
## sees the same). Only the light changes; it has no effect on the game.
## The light is updated a few times a second, not every frame.

const DAY_SECONDS := 7200.0
const UPDATE_EVERY := 0.5
const DAY_SKY := Color(0.56, 0.68, 0.80)
const NIGHT_SKY := Color(0.07, 0.10, 0.22)
const DAY_SUN := Color(1.0, 0.9, 0.76)
const NIGHT_SUN := Color(0.55, 0.65, 1.0)
const LOW_SUN := Color(1.0, 0.58, 0.32)

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun_energy := 1.25
var _timer := 0.0


static func day_phase(t: float) -> float:
	## 0 to 1 through a day: 0 is midnight, 0.25 dawn, 0.5 noon, 0.75 dusk.
	return fposmod(t, DAY_SECONDS) / DAY_SECONDS


static func daylight(t: float) -> float:
	## 0 at night, 1 by day, with dawn and dusk in between.
	var sun := sin((day_phase(t) - 0.25) * TAU)
	return smoothstep(-0.25, 0.25, sun)


static func time_name(t: float) -> String:
	var p := day_phase(t)
	if p < 0.2 or p >= 0.8:
		return "Night"
	if p < 0.3:
		return "Dawn"
	if p < 0.7:
		return "Day"
	return "Dusk"


func build() -> void:
	_sun = get_tree().get_first_node_in_group("sun")
	var world_env: WorldEnvironment = get_tree().get_first_node_in_group("environment")
	if world_env != null:
		_env = world_env.environment
		_sky = _env.sky.sky_material if _env.sky != null else null
	if _sun != null:
		_sun_energy = _sun.light_energy
	_light(Economy.now())


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_EVERY
	_light(Economy.now())


func _light(t: float) -> void:
	if _sun == null:
		return
	var d := daylight(t)
	var low := 4.0 * d * (1.0 - d)      # strongest at dawn and dusk
	_sun.light_color = NIGHT_SUN.lerp(DAY_SUN, d).lerp(LOW_SUN, low * 0.55)
	_sun.light_energy = lerpf(0.28, _sun_energy, d)
	# The sun swings across the sky over the day, staying high enough for shadows.
	_sun.rotation = Vector3(deg_to_rad(lerpf(-28.0, -48.0, d)), deg_to_rad(-140.0 + (day_phase(t) - 0.5) * 120.0), 0.0)
	if _env != null:
		_env.ambient_light_energy = lerpf(0.38, 0.75, d)
		_env.tonemap_exposure = lerpf(0.85, 0.95, d)
	if _sky != null:
		_sky.sky_top_color = NIGHT_SKY.lerp(DAY_SKY, d).lerp(LOW_SUN.darkened(0.3), low * 0.25)
