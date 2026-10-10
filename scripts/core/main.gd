extends Node
## Opens on the title screen, then runs the game: it switches between the
## world map and the castle screen and shows the pause menu. Both screens stay
## loaded while playing: the one not on screen is taken out of the scene tree,
## so coming back is instant and the map keeps its camera, parties and routes.
##
## C toggles between the world map and your castle; Esc opens the pause menu.

const WORLD_SCENE := preload("res://scenes/world_map/world_map.tscn")
const CASTLE_SCENE := preload("res://scenes/castle/castle_view.tscn")

var world_map: Node
var castle_view: Node
var main_menu: CanvasLayer
var pause_menu: CanvasLayer


func _ready() -> void:
	EventBus.castle_requested.connect(show_castle)
	EventBus.world_map_requested.connect(show_world_map)
	main_menu = preload("res://scripts/ui/main_menu.gd").new()
	main_menu.continue_requested.connect(start_game.bind(false))
	main_menu.new_game_requested.connect(start_game.bind(true))
	add_child(main_menu)
	pause_menu = preload("res://scripts/ui/pause_menu.gd").new()
	pause_menu.main_menu_requested.connect(show_main_menu)
	add_child(pause_menu)


func in_game() -> bool:
	return world_map != null


func start_game(new_game: bool) -> void:
	## Builds the world map for a new game or the saved one.
	if new_game:
		Economy.begin_new()
	else:
		Economy.begin_load()
	GameData.ensure_loaded()
	GameData.reset_settlements()
	world_map = WORLD_SCENE.instantiate()
	add_child(world_map)
	main_menu.visible = false


func show_main_menu() -> void:
	## Saves and leaves the game for the title screen.
	Economy.save_game()
	_free_screens()
	main_menu.refresh()
	main_menu.visible = true


func show_castle(castle_id: String) -> void:
	if not in_game():
		return
	var castle := Economy.get_castle(castle_id)
	if castle == null:
		push_warning("No castle with id %s" % castle_id)
		return
	if castle_view == null:
		castle_view = CASTLE_SCENE.instantiate()
	if world_map.is_inside_tree():
		remove_child(world_map)
	if not castle_view.is_inside_tree():
		add_child(castle_view)
	castle_view.open(castle)


func show_world_map() -> void:
	if not in_game():
		return
	if castle_view != null and castle_view.is_inside_tree():
		remove_child(castle_view)
	if not world_map.is_inside_tree():
		add_child(world_map)


func _unhandled_input(event: InputEvent) -> void:
	if not in_game() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		pause_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_C and not get_tree().paused:
		if world_map.is_inside_tree():
			show_castle(Economy.player_castle.id)
		else:
			show_world_map()


func _free_screens() -> void:
	for node in [world_map, castle_view]:
		if node == null:
			continue
		if node.is_inside_tree():
			remove_child(node)
		node.free()
	world_map = null
	castle_view = null


func _exit_tree() -> void:
	_free_screens()
