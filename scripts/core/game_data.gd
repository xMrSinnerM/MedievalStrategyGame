extends Node
## Loads the world's data files once and serves them to the rest of the game.

const TERRAIN_CONFIG_PATH := "res://data/terrain_config.json"
const FACTIONS_PATH := "res://data/factions.json"
const SETTLEMENTS_PATH := "res://data/settlements.json"
const ROADS_PATH := "res://data/roads.json"

var terrain_config: Dictionary = {}
var factions: Array[Dictionary] = []
var factions_by_id: Dictionary = {}
var settlements: Array[Dictionary] = []
var settlements_by_id: Dictionary = {}
var terrain: TerrainData
var roads: RoadNetwork

var _loaded := false


func ensure_loaded() -> bool:
	if _loaded:
		return true
	terrain_config = load_json(TERRAIN_CONFIG_PATH)
	if terrain_config.is_empty():
		return false

	terrain = TerrainData.new()
	if terrain.load_from_config(terrain_config) != OK:
		return false

	var faction_data := load_json(FACTIONS_PATH)
	for f in faction_data.get("factions", []):
		var faction: Dictionary = f
		faction.color = Color.html(faction.color)
		faction.secondary_color = Color.html(faction.get("secondary_color", "#ffffff"))
		faction.index = factions.size()
		factions.append(faction)
		factions_by_id[faction.id] = faction

	for s in load_json(SETTLEMENTS_PATH).get("settlements", []):
		var settlement: Dictionary = s
		settlements.append(settlement)
		settlements_by_id[settlement.id] = settlement

	roads = RoadNetwork.new()
	roads.build(load_json(ROADS_PATH).get("roads", []), settlements, terrain.world_size)

	_loaded = true
	return true


func get_faction(id: String) -> Dictionary:
	return factions_by_id.get(id, {})


func get_settlement(id: String) -> Dictionary:
	return settlements_by_id.get(id, {})


func config_section(name: String) -> Dictionary:
	return terrain_config.get(name, {})


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not parse %s" % path)
		return {}
	return parsed
