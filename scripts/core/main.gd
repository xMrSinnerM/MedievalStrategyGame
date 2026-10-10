extends Node
## Switches between the world map and the castle screen. Both stay loaded:
## the one not on screen is taken out of the scene tree, so coming back is
## instant and the map keeps its camera, parties and routes.
##
## C toggles between the world map and your castle.

const CASTLE_SCENE := preload("res://scenes/castle/castle_view.tscn")

@onready var world_map: Node = $WorldMap
var castle_view: Node


func _ready() -> void:
	EventBus.castle_requested.connect(show_castle)
	EventBus.world_map_requested.connect(show_world_map)


func show_castle(castle_id: String) -> void:
	Economy.ensure_loaded()
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
	if castle_view != null and castle_view.is_inside_tree():
		remove_child(castle_view)
	if not world_map.is_inside_tree():
		add_child(world_map)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		if world_map.is_inside_tree():
			show_castle(Economy.player_castle.id)
		else:
			show_world_map()


func _exit_tree() -> void:
	# Free whichever scene is not in the tree, so quitting doesn't leak it.
	for node in [world_map, castle_view]:
		if node != null and not node.is_inside_tree():
			node.free()
