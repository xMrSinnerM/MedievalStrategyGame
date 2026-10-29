class_name BuildingRules
extends RefCounted
## The castle economy's numbers, read from data/buildings.json: what each
## building costs, how long it takes, what it produces or stores, and the
## limits the keep's level sets, and the academy's studies ("research").
## Troop types come from data/units.json.
##
## Values for level N grow from the level-1 value: base * growth^(N - 1).

const PATH := "res://data/buildings.json"
const UNITS_PATH := "res://data/units.json"

var resources: Array[String] = []
var grid_size := 24
var start: Dictionary = {}
var types: Dictionary = {}       ## type id -> definition
var units: Dictionary = {}       ## unit id -> definition
var queue_size := 5              ## training batches a castle can queue
var max_batch := 50              ## soldiers per batch
var time_per_barracks_level := 0.92
var tools: Dictionary = {}       ## siege tool id -> definition (data/units.json "tools")
var tool_slot_table: Array = []  ## tools per wall by level
var studies: Dictionary = {}     ## study id -> definition (buildings.json "research")
var branches: Dictionary = {}    ## research branch id -> name
var study_cost_growth := 1.8
var study_time_growth := 2.0
var time_per_academy_level := 0.94
var order_per_point := 0.002    ## production change per point of public order
var order_max_bonus := 0.3
var order_max_penalty := 0.3


static func load_default() -> BuildingRules:
	var rules := BuildingRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	var unit_data = JSON.parse_string(FileAccess.get_file_as_string(UNITS_PATH))
	if not unit_data is Dictionary:
		push_error("Could not read %s" % UNITS_PATH)
		unit_data = {}
	rules.load_units(unit_data)
	return rules


func load_from(data: Dictionary) -> void:
	resources.clear()
	for r in data.get("resources", []):
		resources.append(String(r))
	grid_size = int(data.get("grid_size", 24))
	start = data.get("start", {})
	types = data.get("buildings", {})
	var research: Dictionary = data.get("research", {})
	studies = research.get("studies", {})
	branches = research.get("branches", {})
	study_cost_growth = float(research.get("cost_growth", 1.8))
	study_time_growth = float(research.get("time_growth", 2.0))
	time_per_academy_level = float(research.get("time_per_academy_level", 0.94))
	var order: Dictionary = data.get("public_order", {})
	order_per_point = float(order.get("per_point", 0.002))
	order_max_bonus = float(order.get("max_bonus", 0.3))
	order_max_penalty = float(order.get("max_penalty", 0.3))


func load_units(data: Dictionary) -> void:
	units = data.get("units", {})
	queue_size = int(data.get("queue_size", 5))
	max_batch = int(data.get("max_batch", 50))
	time_per_barracks_level = float(data.get("time_per_barracks_level", 0.92))
	tools = data.get("tools", {})
	tool_slot_table = data.get("tool_slots", [0])


func has_type(type: String) -> bool:
	return types.has(type)


func display_name(type: String) -> String:
	return types[type].get("name", type)


func size(type: String) -> Vector2i:
	## Footprint in grid cells; perimeter buildings (the wall) have none.
	var s: Array = types[type].get("size", [0, 0])
	return Vector2i(int(s[0]), int(s[1]))


func is_perimeter(type: String) -> bool:
	return types[type].get("placement", "") == "perimeter"


func is_unique(type: String) -> bool:
	return types[type].get("unique", false)


func cost(type: String, level: int) -> Dictionary:
	## Resources needed to build `level` (1 = constructing it).
	var def: Dictionary = types[type]
	var factor := pow(float(def.get("cost_growth", 1.5)), level - 1)
	var out := {}
	for r: String in def.get("cost", {}):
		out[r] = roundf(float(def.cost[r]) * factor)
	return out


func build_time(type: String, level: int) -> float:
	## Seconds to finish `level`.
	var def: Dictionary = types[type]
	return roundf(float(def.get("time", 30)) * pow(float(def.get("time_growth", 1.6)), level - 1))


func production(type: String, level: int) -> Dictionary:
	## Resources per hour at `level` (nothing at level 0, i.e. while first being built).
	var def: Dictionary = types[type]
	var out := {}
	if level <= 0:
		return out
	var factor := pow(float(def.get("production_growth", 1.35)), level - 1)
	for r: String in def.get("produces", {}):
		out[r] = float(def.produces[r]) * factor
	return out


func storage(type: String, level: int) -> float:
	## Capacity this building adds for every resource.
	var def: Dictionary = types[type]
	if level <= 0 or not def.has("storage"):
		return 0.0
	return float(def.storage) * pow(float(def.get("storage_growth", 1.5)), level - 1)


func defense(type: String, level: int) -> float:
	var def: Dictionary = types[type]
	if level <= 0 or not def.has("defense"):
		return 0.0
	return float(def.defense) * pow(float(def.get("defense_growth", 1.5)), level - 1)


func is_decoration(type: String) -> bool:
	return types[type].get("category", "") == "decoration"


func order(type: String, level: int) -> float:
	## Public order this building gives (decorations, the keep) or takes away
	## (everything else crowds the castle). Nothing while first being built.
	var def: Dictionary = types[type]
	if level <= 0 or not def.has("order"):
		return 0.0
	return roundf(float(def.order) * pow(float(def.get("order_growth", 1.0)), level - 1))


func order_bonus(public_order: float) -> float:
	## How much more (or less, below zero) every resource is produced at this public order.
	return clampf(public_order * order_per_point, -order_max_penalty, order_max_bonus)


func builders(keep_level: int) -> int:
	## How many constructions can run at once.
	var table: Array = types.get("keep", {}).get("builders", [1])
	return int(table[clampi(keep_level - 1, 0, table.size() - 1)])


func max_level(type: String, keep_level: int) -> int:
	## The keep goes up to its own maximum; everything else up to twice the keep's level.
	var cap := int(types[type].get("max_level", 10))
	if type == "keep":
		return cap
	return mini(cap, keep_level * 2)


func required_keep(type: String) -> int:
	## The keep level a first building of this type needs.
	return int(types[type].get("keep_level", 1))


func max_count(type: String, keep_level: int) -> int:
	if is_unique(type):
		return 1
	var table: Array = types[type].get("max_count", [1])
	return int(table[clampi(keep_level - 1, 0, table.size() - 1)])


# --- Troops -------------------------------------------------------------------

func has_unit(unit: String) -> bool:
	return units.has(unit)


func unit_name(unit: String) -> String:
	return units[unit].get("name", unit)


func unit_plural(unit: String) -> String:
	return units[unit].get("plural", unit_name(unit) + "s")


func unit_cost(unit: String, count := 1) -> Dictionary:
	var out := {}
	for r: String in units[unit].get("cost", {}):
		out[r] = float(units[unit].cost[r]) * count
	return out


func unit_time(unit: String, barracks_level: int) -> float:
	## Seconds to train one soldier; each barracks level above 1 trains faster.
	return roundf(float(units[unit].get("time", 30)) * pow(time_per_barracks_level, maxi(barracks_level - 1, 0)))


func unit_upkeep(unit: String) -> float:
	## Food each soldier eats per hour.
	return float(units[unit].get("upkeep", 1.0))


func unit_stat(unit: String, stat: String) -> float:
	return float(units[unit].get(stat, 0.0))


func unit_barracks_level(unit: String) -> int:
	## The barracks level that unlocks this unit.
	return int(units[unit].get("barracks_level", 1))


func unit_bonus(unit: String, against: String) -> float:
	## How much harder this unit hits soldiers of the other type (1 = normal).
	return float(units[unit].get("bonus", {}).get(against, 1.0))


# --- Siege tools --------------------------------------------------------------

func has_tool(tool: String) -> bool:
	return tools.has(tool)


func tool_name(tool: String) -> String:
	return tools[tool].get("name", tool)


func tool_plural(tool: String) -> String:
	return tools[tool].get("plural", tool_name(tool) + "s")


func tool_side(tool: String) -> String:
	## "attack" or "defence".
	return String(tools[tool].get("side", "attack"))


func tool_cost(tool: String, count := 1) -> Dictionary:
	var out := {}
	for r: String in tools[tool].get("cost", {}):
		out[r] = float(tools[tool].cost[r]) * count
	return out


func tool_time(tool: String, workshop_level: int) -> float:
	## Seconds to build one tool; each workshop level above 1 builds faster.
	return roundf(float(tools[tool].get("time", 30)) * pow(time_per_barracks_level, maxi(workshop_level - 1, 0)))


func tool_workshop_level(tool: String) -> int:
	return int(tools[tool].get("workshop_level", 1))


func tool_fits(tool: String, wall: String) -> bool:
	## Whether the tool can be used at this wall.
	var walls: Variant = tools[tool].get("walls")
	return walls == null or (walls as Array).has(wall)


func tool_effect(tool: String, effect: String) -> float:
	return float(tools[tool].get("effect", {}).get(effect, 0.0))


func tool_slots(level: int) -> int:
	## How many tools fit on one wall: attack tools by keep level, defence tools by wall level.
	if level < 1:
		return 0
	return int(tool_slot_table[clampi(level - 1, 0, tool_slot_table.size() - 1)])


# --- Research -----------------------------------------------------------------

func has_study(study: String) -> bool:
	return studies.has(study)


func study_name(study: String) -> String:
	return studies[study].get("name", study)


func study_max_level(study: String) -> int:
	return int(studies[study].get("max_level", 5))


func study_academy_level(study: String) -> int:
	## The academy level that unlocks this study.
	return int(studies[study].get("academy_level", 1))


func study_requires(study: String) -> Dictionary:
	## Other studies (id -> level) this one needs first.
	return studies[study].get("requires", {})


func study_effects(study: String) -> Dictionary:
	## What each level adds: effect -> amount (see "research" in buildings.json).
	return studies[study].get("effects", {})


func study_cost(study: String, level: int) -> Dictionary:
	## Resources to research `level`.
	var def: Dictionary = studies[study]
	var factor := pow(study_cost_growth, level - 1)
	var out := {}
	for r: String in def.get("cost", {}):
		out[r] = roundf(float(def.cost[r]) * factor)
	return out


func study_time(study: String, level: int, academy_level: int) -> float:
	## Seconds to research `level`; each academy level above 1 researches faster.
	return roundf(float(studies[study].get("time", 300)) * pow(study_time_growth, level - 1)
		* pow(time_per_academy_level, maxi(academy_level - 1, 0)))
