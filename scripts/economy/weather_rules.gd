class_name WeatherRules
extends RefCounted
## Weather on the world map: rain and storm cells that drift across it, and
## the time of day. Which cells are out, where and how big is worked out
## from the time alone (each of `count` slots picks a new one every
## `window_hours`, staggered), so the game and the server agree without
## keeping a list. An army marching out through rain or a storm takes longer
## (march_slow). The numbers are in data/weather.json;
## server/rules/weather.ts is the same rules.

const PATH := "res://data/weather.json"
const KINDS := ["clear", "rain", "storm"]

var window := 10800.0         ## seconds a cell lasts
var count := 0
var area: Array = [0, 2048]
var radius: Array = [100, 200]
var drift := 0
var kinds := {}               ## kind -> {weight, name, slow}
var day := 7200.0             ## seconds a whole day and night take


static func load_default() -> WeatherRules:
	var rules := WeatherRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


func load_from(data: Dictionary) -> void:
	window = float(data.get("window_hours", 3)) * 3600.0
	count = int(data.get("count", 0))
	area = data.get("area", [0, 2048])
	radius = data.get("radius", [100, 200])
	drift = int(data.get("drift", 0))
	kinds = data.get("kinds", {})
	day = float(data.get("day_hours", 2)) * 3600.0


# --- The cells -------------------------------------------------------------------

func make(slot: int, w: int) -> Dictionary:
	## The cell slot `slot` holds in its window `w`: {id, slot, kind, x, z,
	## dx, dz (its drift over the window), radius, start, end}.
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 6211 + slot * 92821 + 777
	var sum := 0
	for k: String in KINDS:
		sum += int(kinds.get(k, {}).get("weight", 0))
	var roll := int(rng.randi() % maxi(sum, 1))
	var kind: String = KINDS[0]
	for k: String in KINDS:
		roll -= int(kinds.get(k, {}).get("weight", 0))
		if roll < 0:
			kind = k
			break
	var lo := int(area[0])
	var hi := int(area[1])
	var x := lo + int(rng.randi() % maxi(1, hi - lo + 1))
	var z := lo + int(rng.randi() % maxi(1, hi - lo + 1))
	var dx := int(rng.randi() % (2 * drift + 1)) - drift
	var dz := int(rng.randi() % (2 * drift + 1)) - drift
	var r := int(radius[0]) + int(rng.randi() % maxi(1, int(radius[1]) - int(radius[0]) + 1))
	var start := w * window - window * slot / maxi(count, 1)
	return {"id": "w%d-%d" % [slot, w], "slot": slot, "kind": kind, "x": x, "z": z, "dx": dx, "dz": dz, "radius": r,
		"start": start, "end": start + window}


func active(t: float) -> Array:
	## The cells on the map at time t, clear ones too.
	var out: Array = []
	for slot in count:
		out.append(make(slot, int(floor((t + window * slot / count) / window))))
	return out


func centre(cell: Dictionary, t: float) -> Vector2:
	## Where the cell is at time t: it drifts evenly over its window.
	var f := clampf((t - float(cell.start)) / window, 0.0, 1.0)
	return Vector2(float(cell.x) + float(cell.dx) * f, float(cell.z) + float(cell.dz) * f)


func strength(cell: Dictionary, t: float) -> float:
	## 0 to 1: cells gather over their first tenth and break up over their last.
	var f := clampf((t - float(cell.start)) / window, 0.0, 1.0)
	return clampf(minf(f, 1.0 - f) * 10.0, 0.0, 1.0)


static func _near(cx: float, cz: float, a: Vector2, b: Vector2) -> float:
	## How far (cx, cz) is from the line from a to b (in doubles, as on the server).
	var ax := float(a.x)
	var az := float(a.y)
	var abx := float(b.x) - ax
	var abz := float(b.y) - az
	var len2 := abx * abx + abz * abz
	var f := 0.0 if len2 <= 0.0 else clampf(((cx - ax) * abx + (cz - az) * abz) / len2, 0.0, 1.0)
	return sqrt(pow(cx - (ax + abx * f), 2.0) + pow(cz - (az + abz * f), 2.0))


func march_cell(from: Vector2, to: Vector2, t: float) -> Dictionary:
	## The worst cell an army setting off at t from `from` to `to` marches
	## through ({} for none).
	var worst := {}
	var worst_slow := 0.0
	for cell: Dictionary in active(t):
		var slow := float(kinds.get(String(cell.kind), {}).get("slow", 0.0))
		var f := clampf((t - float(cell.start)) / window, 0.0, 1.0)
		var cx := float(cell.x) + float(cell.dx) * f
		var cz := float(cell.z) + float(cell.dz) * f
		if slow > worst_slow and _near(cx, cz, from, to) <= float(cell.radius):
			worst = cell
			worst_slow = slow
	return worst


func march_slow(from: Vector2, to: Vector2, t: float) -> float:
	## Multiplier on a march's time for the weather on its way (1 = none).
	var cell := march_cell(from, to, t)
	return 1.0 + (float(kinds[String(cell.kind)].get("slow", 0.0)) if not cell.is_empty() else 0.0)


func kind_name(kind: String) -> String:
	return String(kinds.get(kind, {}).get("name", kind))


# --- The time of day (the game only) --------------------------------------------

func day_phase(t: float) -> float:
	## 0 to 1 through a day: 0 is midnight, 0.25 dawn, 0.5 noon, 0.75 dusk.
	return fposmod(t, day) / day


func daylight(t: float) -> float:
	## 0 at night, 1 by day, with dawn and dusk in between.
	var sun := sin((day_phase(t) - 0.25) * TAU)
	return smoothstep(-0.25, 0.25, sun)


func time_name(t: float) -> String:
	var p := day_phase(t)
	if p < 0.2 or p >= 0.8:
		return "Night"
	if p < 0.3:
		return "Dawn"
	if p < 0.7:
		return "Day"
	return "Dusk"
