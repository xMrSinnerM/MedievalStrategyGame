extends PanelContainer
## Shown on the world map when you click a castle: who holds it, how far its
## lord has built it up, and buttons to go inside or travel there. Castles of
## other factions also show your chances of storming them and a Besiege button.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)

var settlement_id := ""

var _title: Label
var _owner: Label
var _details: Label
var _enter: Button
var _travel: Button
var _siege_info: Label
var _besiege: Button


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.85)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(290, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = _label(20, Color(1.0, 0.9, 0.65))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: show_settlement(""))
	head.add_child(close)
	_owner = _label(15, MUTED)
	box.add_child(_owner)
	_details = _label(14, TEXT)
	box.add_child(_details)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_enter = Button.new()
	_enter.focus_mode = Control.FOCUS_NONE
	_enter.pressed.connect(func() -> void: EventBus.castle_requested.emit(settlement_id))
	buttons.add_child(_enter)
	_travel = Button.new()
	_travel.text = "Travel here"
	_travel.focus_mode = Control.FOCUS_NONE
	_travel.pressed.connect(func() -> void:
		EventBus.travel_requested.emit(settlement_id)
		show_settlement(""))
	buttons.add_child(_travel)
	_siege_info = _label(14, TEXT)
	box.add_child(_siege_info)
	_besiege = Button.new()
	_besiege.text = "Besiege"
	_besiege.focus_mode = Control.FOCUS_NONE
	_besiege.pressed.connect(func() -> void:
		EventBus.siege_requested.emit(settlement_id)
		show_settlement(""))
	box.add_child(_besiege)
	EventBus.settlement_selected.connect(show_settlement)
	Economy.changed.connect(_refresh)


func show_settlement(id: String) -> void:
	## Shows the castle with this settlement id, or hides the panel for "".
	settlement_id = id
	visible = id != "" and Economy.get_castle(id) != null
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	var castle := Economy.get_castle(settlement_id)
	if castle == null:
		visible = false
		return
	_title.text = castle.castle_name
	if castle.is_npc():
		var faction := GameData.get_faction(castle.owner)
		_owner.text = "Held by the %s" % faction.get("name", castle.owner)
		_owner.add_theme_color_override("font_color", faction.get("color", MUTED).lerp(Color.WHITE, 0.35))
		_enter.text = "Look inside"
	else:
		_owner.text = "Your castle"
		_owner.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
		_enter.text = "Enter castle (C)" if castle == Economy.player_castle else "Enter castle"
	var lines: PackedStringArray = []
	lines.append("Keep level %d    Defence %d" % [castle.keep_level(), int(castle.defense())])
	lines.append("%d buildings, %d under construction" % [castle.buildings.size(), castle.constructions().size()])
	lines.append("Garrison %d soldiers, warband %d" % [castle.troop_count(), castle.field_count()])
	if castle == Economy.player_castle and Economy.newcomer_protected():
		lines.append("Safe from sieges until your keep reaches level %d" % Economy.PROTECTED_BELOW_KEEP)
	var rates := castle.net_per_hour()
	var income: PackedStringArray = []
	for r in castle.rules.resources:
		income.append("%s %+d" % [r.capitalize(), int(rates.get(r, 0.0))])
	lines.append("Per hour: " + "  ".join(income))
	_details.text = "\n".join(lines)
	var settlement := GameData.get_settlement(settlement_id)
	var hostile: bool = castle.is_npc() and settlement.get("faction", "") != Economy.player_faction
	_siege_info.visible = hostile
	_besiege.visible = hostile
	if hostile:
		var mine := Economy.player_castle
		var wall := Battle.wall_bonus(castle)
		var siege: PackedStringArray = ["Walls: defenders +%d%% defence" % roundi((wall - 1.0) * 100.0),
				"A siege takes %d s before the assault" % int(Battle.siege_time(castle))]
		if mine.field_count() > 0:
			var chance := Battle.odds(castle.rules, mine.field, castle.troops, 1, wall)
			siege.append("Your %d soldiers: %s (%d%%)" % [mine.field_count(), Battle.odds_text(chance), roundi(chance * 100.0)])
			_siege_info.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3).lerp(Color(0.55, 0.9, 0.45), chance))
		else:
			siege.append("Your warband has no soldiers.")
			_siege_info.add_theme_color_override("font_color", TEXT)
		_siege_info.text = "\n".join(siege)
		_besiege.disabled = mine.field_count() <= 0


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
