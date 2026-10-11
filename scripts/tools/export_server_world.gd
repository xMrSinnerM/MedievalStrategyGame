extends SceneTree
## Writes server/world/world.json: the robber baron camps, placed exactly as
## the game places them (BaronPlacer), how their starting level grows with
## distance, and the spots where players' castles can stand (PlayerSpots).
## The server can't read the terrain, so it uses these lists.
##
## Run from the project folder after changing the terrain, settlements,
## player.json or the "camps" section of barons.json:
##   godot --headless --path . --script res://scripts/tools/export_server_world.gd

const OUT := "res://server/world/world.json"
const MAIN_CASTLE := "player_castle"


func _initialize() -> void:
	var game_data = load("res://scripts/core/game_data.gd").new()
	if not game_data.ensure_loaded():
		push_error("Could not load the world")
		quit(1)
		return
	var own: Dictionary = game_data.settlements_by_id.get(MAIN_CASTLE, {})
	var home := Vector2(own.position[0], own.position[1])
	var baron_rules := BaronRules.load_default()
	var camps := BaronPlacer.place(baron_rules, game_data.nav.is_passable, game_data.settlements,
			home, game_data.terrain.world_size)
	var spots := PlayerSpots.place(game_data.terrain, game_data.nav.is_passable, game_data.settlements, camps, home)
	var out := {
		"home": [home.x, home.y],
		"camp_levels": {"per_distance": float(baron_rules.camps.get("level_per_distance", 170.0)),
				"max": int(baron_rules.camps.get("start_level_max", 12))},
		"camps": camps,
		"spots": spots,
	}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t", false))
	file.close()
	print("wrote %s with %d camps and %d spots" % [OUT, camps.size(), spots.size()])
	game_data.free()
	quit()
