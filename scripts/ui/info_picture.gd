class_name InfoPicture
extends PanelContainer
## The gold-framed picture on the left of a world map info card: a capital,
## castle, village, camp or warband standing in a meadow, baked by
## tools/bake_places.tscn into assets/ui/places.

const ROOT := "res://assets/ui/places/"

var _picture: TextureRect


func _init() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.03, 0.025, 0.02)
	frame.border_color = GameTheme.RIM
	frame.set_border_width_all(1)
	frame.set_content_margin_all(3)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 4
	add_theme_stylebox_override("panel", frame)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(104, 135)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)


func show_place(place: String) -> void:
	## Shows assets/ui/places/<place>.png; hides the frame if there is none.
	var path := ROOT + place + ".png"
	visible = ResourceLoader.exists(path)
	if visible:
		_picture.texture = load(path)


static func faction_place(type: String, faction: String) -> String:
	## "capital" or "castle" in a faction's colours, any faction if unknown.
	if GameData.get_faction(faction).is_empty() and not GameData.factions.is_empty():
		faction = GameData.factions[absi(hash(faction)) % GameData.factions.size()].id
	return "%s_%s" % [type, faction]


static func wrap(card: Control, box: Control) -> InfoPicture:
	## Puts the picture beside a card's content: call instead of card.add_child(box).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var picture := InfoPicture.new()
	row.add_child(picture)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	return picture
