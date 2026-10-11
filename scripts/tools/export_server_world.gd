extends SceneTree
## Writes server/world/world.json: where your castle stands and the robber
## baron camps around it, placed exactly as the game places them
## (BaronPlacer). The server can't read the terrain, so it uses this list.
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
	var camps := BaronPlacer.place(BaronRules.load_default(), game_data.nav.is_passable, game_data.settlements,
			home, game_data.terrain.world_size)
	var out := {"home": [home.x, home.y], "camps": camps}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t", false))
	file.close()
	print("wrote %s with %d camps" % [OUT, camps.size()])
	game_data.free()
	quit()
