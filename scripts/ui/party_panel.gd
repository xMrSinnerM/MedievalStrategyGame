extends PanelContainer
## Shown on the world map when you click a lord's party: whose warband it is,
## what soldiers it has, your chances against it and a button to attack.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)

var party_id := ""

var _title: Label
var _owner: Label
var _details: Label
var _odds: Label
var _attack: Button


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
	close.pressed.connect(func() -> void: show_party(""))
	head.add_child(close)
	_owner = _label(15, MUTED)
	box.add_child(_owner)
	_details = _label(14, TEXT)
	box.add_child(_details)
	_odds = _label(15, TEXT)
	box.add_child(_odds)
	_attack = Button.new()
	_attack.text = "Attack"
	_attack.focus_mode = Control.FOCUS_NONE
	_attack.pressed.connect(func() -> void:
		EventBus.attack_requested.emit(party_id)
		show_party(""))
	box.add_child(_attack)
	EventBus.party_selected.connect(show_party)
	EventBus.settlement_selected.connect(func(id: String) -> void:
		if id != "":
			show_party(""))
	EventBus.battle_fought.connect(func(report: Dictionary) -> void:
		if report.player != "":
			show_party(""))
	Economy.changed.connect(_refresh)


func show_party(id: String) -> void:
	## Shows the party with this id, or hides the panel for "".
	party_id = id
	visible = not _data().is_empty()
	_refresh()


func _data() -> Dictionary:
	for p in GameData.parties:
		if p.id == party_id and not p.get("player", false):
			return p
	return {}


func _refresh() -> void:
	if not visible:
		return
	var data := _data()
	var castle := Economy.get_castle(data.get("home", ""))
	var mine := Economy.player_castle
	if castle == null or mine == null:
		visible = false
		return
	var faction := GameData.get_faction(data.faction)
	var player_faction := _player_faction()
	_title.text = data.name
	var relation := ""
	if data.faction == player_faction:
		relation = ", your ally"
	elif GameData.at_war(data.faction, player_faction):
		relation = ", at war with you"
	_owner.text = "%s%s" % [faction.get("name", data.faction), relation]
	_owner.add_theme_color_override("font_color", faction.get("color", MUTED).lerp(Color.WHITE, 0.35))
	var lines: PackedStringArray = ["Warband of %s: %d soldiers" % [castle.castle_name, castle.field_count()]]
	for unit: String in castle.field:
		if castle.field[unit] > 0:
			lines.append("    %d %s" % [castle.field[unit], castle.rules.unit_plural(unit) if castle.field[unit] != 1 else castle.rules.unit_name(unit)])
	_details.text = "\n".join(lines)
	var hostile: bool = data.faction != player_faction
	_odds.visible = hostile
	_attack.visible = hostile
	if not hostile:
		return
	if mine.field_count() <= 0:
		_odds.text = "Your warband has no soldiers."
		_attack.disabled = true
		return
	var chance := Battle.odds(Economy.rules, mine.field, castle.field)
	_odds.text = "Your %d soldiers: %s (%d%%)" % [mine.field_count(), Battle.odds_text(chance), roundi(chance * 100.0)]
	_odds.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3).lerp(Color(0.55, 0.9, 0.45), chance))
	_attack.disabled = castle.field_count() <= 0


func _player_faction() -> String:
	for p in GameData.parties:
		if p.get("player", false):
			return p.faction
	return ""


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
