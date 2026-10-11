extends PanelContainer
## The diplomacy screen (K on the world map): every other faction with its
## relation to you and the state of your war or peace, with buttons to declare
## war, make peace and send gifts, plus the realm's other wars and the news.

const GIFTS := [100, 500]
const WAR_RED := Color(0.95, 0.45, 0.35)
const PEACE_GREEN := Color(0.6, 0.9, 0.5)

var _gold: Label
var _rows: VBoxContainer
var _row_parts := {}           ## faction -> {"status", "relation", "main", "gifts"}
var _wars: Label
var _news: Label
var _confirm: VBoxContainer
var _confirm_text: Label
var _confirm_action := Callable()
var _close_after := false      ## the question came from elsewhere (an attack); close when answered
var _note: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(860, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Diplomacy", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_gold = MenuStyle.label("", 15, MenuStyle.MUTED)
	box.add_child(_gold)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)
	_confirm = VBoxContainer.new()
	_confirm.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm.add_theme_constant_override("separation", 12)
	_confirm.visible = false
	_confirm_text = MenuStyle.label("", 18, MenuStyle.GOLD)
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(_confirm_text)
	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 12)
	choices.add_child(MenuStyle.button("Declare war", func() -> void:
		_confirm_action.call()
		_answered(), 200.0))
	choices.add_child(MenuStyle.button("Cancel", _answered, 200.0))
	_confirm.add_child(choices)
	box.add_child(_confirm)
	_note = MenuStyle.label("", 15, MenuStyle.GOLD)
	box.add_child(_note)
	box.add_child(HSeparator.new())
	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 24)
	box.add_child(lower)
	var wars_box := VBoxContainer.new()
	wars_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wars_box.add_child(MenuStyle.label("Wars in the realm", 17, MenuStyle.GOLD))
	_wars = MenuStyle.label("", 14, MenuStyle.TEXT)
	wars_box.add_child(_wars)
	lower.add_child(wars_box)
	var news_box := VBoxContainer.new()
	news_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	news_box.add_child(MenuStyle.label("News", 17, MenuStyle.GOLD))
	_news = MenuStyle.label("", 14, MenuStyle.TEXT)
	_news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_news.custom_minimum_size = Vector2(380, 0)
	news_box.add_child(_news)
	lower.add_child(news_box)
	Economy.changed.connect(_refresh)
	Economy.diplomacy_changed.connect(func(_news_items: Array) -> void: _refresh())
	EventBus.war_declaration_requested.connect(func(faction: String, then: Callable) -> void:
		ask_war(faction, then, true))


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_K and not get_tree().paused and not Economy.online:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if Economy.diplomacy == null:
		return
	_build_rows()
	_note.text = ""
	_show_confirm(false)
	visible = true
	_refresh()


func close_panel() -> void:
	visible = false


func _build_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_parts.clear()
	var d := Economy.diplomacy
	for f: String in d.factions:
		if f == d.player_faction:
			continue
		var faction := GameData.get_faction(f)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = faction.get("color", Color.GRAY)
		swatch.custom_minimum_size = Vector2(8, 0)
		row.add_child(swatch)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		text.add_child(MenuStyle.label(faction.get("name", f), 18, MenuStyle.GOLD))
		var status := MenuStyle.label("", 14, MenuStyle.TEXT)
		text.add_child(status)
		var relation := MenuStyle.label("", 14, MenuStyle.MUTED)
		text.add_child(relation)
		row.add_child(text)
		var main := _small_button("", _main_action.bind(f), 210.0)
		main.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(main)
		var gifts: Array[Button] = []
		for gold: int in GIFTS:
			var gift := _small_button("", _gift.bind(f, gold), 130.0)
			gift.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(gift)
			gifts.append(gift)
		_rows.add_child(row)
		_row_parts[f] = {"status": status, "relation": relation, "main": main, "gifts": gifts}


func _refresh() -> void:
	if not visible or Economy.diplomacy == null:
		return
	_note.visible = _note.text != ""
	var d := Economy.diplomacy
	var now := Economy.now()
	var gold := int(Economy.player_castle.resources.get("gold", 0.0))
	_gold.text = "You rule the %s. Gold in your castle: %d" % [GameData.get_faction(d.player_faction).get("name", d.player_faction), gold]
	for f: String in _row_parts:
		var parts: Dictionary = _row_parts[f]
		var status: Label = parts.status
		var relation: Label = parts.relation
		var main: Button = parts.main
		var value := d.relation(d.player_faction, f)
		relation.text = "Relation %+d (%s)" % [roundi(value), Diplomacy.relation_word(value)]
		relation.add_theme_color_override("font_color", WAR_RED.lerp(PEACE_GREEN, (value + 100.0) / 200.0))
		main.disabled = false
		if d.at_war(d.player_faction, f):
			var score := d.war_score(d.player_faction, f)
			status.text = "At war for %d min. %s" % [int(d.war_length(d.player_faction, f, now) / 60.0), _standing(score)]
			status.add_theme_color_override("font_color", WAR_RED)
			var terms := d.peace_terms(d.player_faction, f, now)
			if d.offers.has(f):
				main.text = "Accept their peace"
			elif not terms.possible:
				main.text = "They refuse peace"
				main.disabled = true
			elif int(terms.price) == 0:
				main.text = "Make peace"
			else:
				main.text = "Peace for %d gold" % terms.price
				main.disabled = int(terms.price) > gold
			main.tooltip_text = terms.reason
		else:
			var truce := d.truce_left(d.player_faction, f, now)
			status.text = "Truce for %d more min" % ceili(truce / 60.0) if truce > 0.0 else "At peace"
			status.add_theme_color_override("font_color", MenuStyle.TEXT)
			main.text = "Declare war"
			main.disabled = truce > 0.0
			main.tooltip_text = "No war while the truce holds." if truce > 0.0 else ""
		var gifts: Array = parts.gifts
		for i in GIFTS.size():
			var button: Button = gifts[i]
			var points := d.gift_value(d.player_faction, f, GIFTS[i], now)
			button.text = "Gift %d (+%d)" % [GIFTS[i], roundi(points)]
			button.disabled = gold < GIFTS[i] or points < 0.5
			button.tooltip_text = "They have had enough gifts for now." if points < 0.5 else "Send %d gold." % GIFTS[i]
	var wars: PackedStringArray = []
	for k: String in d.wars:
		var pair := k.split("|")
		if pair.has(d.player_faction):
			continue
		wars.append("%s against %s (%d min)" % [_short(pair[0]), _short(pair[1]), int(d.war_length(pair[0], pair[1], now) / 60.0)])
	_wars.text = "\n".join(wars) if not wars.is_empty() else "The other factions are at peace."
	var news: PackedStringArray = []
	for i in range(d.news.size() - 1, maxi(-1, d.news.size() - 6), -1):
		var item: Dictionary = d.news[i]
		news.append("%s  %s" % [_ago(now - float(item.time)), item.text])
	_news.text = "\n".join(news) if not news.is_empty() else "Nothing yet."


func _standing(score: float) -> String:
	if score >= 20.0:
		return "You are winning."
	if score <= -20.0:
		return "You are losing."
	return "Neither side has the upper hand."


func _short(id: String) -> String:
	## "Varnholt" for the Varnholt Jarldom, to keep the list readable.
	var full: String = GameData.get_faction(id).get("name", id)
	for word in full.split(" "):
		if word.to_lower() == id:
			return word
	return full


func _ago(seconds: float) -> String:
	if seconds < 60.0:
		return "now"
	if seconds < 3600.0:
		return "%dm" % int(seconds / 60.0)
	return "%dh" % int(seconds / 3600.0)


func _main_action(faction: String) -> void:
	var d := Economy.diplomacy
	if d.at_war(d.player_faction, faction):
		var terms := d.peace_terms(d.player_faction, faction, Economy.now())
		if Economy.propose_peace(faction, int(terms.price)):
			_note.text = "Peace with the %s." % GameData.get_faction(faction).get("name", faction)
		else:
			_note.text = terms.reason
	else:
		ask_war(faction, Callable())
	_refresh()


func ask_war(faction: String, then: Callable, close_after := false) -> void:
	## Asks before declaring war on faction, then declares it and calls then.
	open_panel()
	_close_after = close_after
	_confirm_text.text = "Declare war on the %s?" % GameData.get_faction(faction).get("name", faction)
	_confirm_action = func() -> void:
		var why := Economy.declare_war(faction)
		_note.text = why if why != "" else "You are at war with the %s." % GameData.get_faction(faction).get("name", faction)
		if why == "" and then.is_valid():
			then.call()
	_show_confirm(true)


func _gift(faction: String, gold: int) -> void:
	var points := Economy.send_gift(faction, gold)
	if points > 0.0:
		_note.text = "The %s welcome your gift (+%d)." % [GameData.get_faction(faction).get("name", faction), roundi(points)]
	_refresh()


func _answered() -> void:
	_show_confirm(false)
	if _close_after:
		close_panel()
	_refresh()


func _show_confirm(on: bool) -> void:
	_confirm.visible = on
	_rows.visible = not on


func _small_button(text: String, action: Callable, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b
