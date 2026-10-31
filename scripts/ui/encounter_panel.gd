extends PanelContainer
## Shown on the world map when you click a random encounter (EncounterRules):
## what it is, how long it stays, and what it asks: bandits to fight with a
## share of your garrison (with the odds), a caravan's trade, or a treasure
## site to dig. What happened shows here afterwards.

const MUTED := Color(0.78, 0.72, 0.62)
const GOOD := Color(0.55, 0.9, 0.45)
const BAD := Color(1.0, 0.55, 0.4)
const ICONS := {"bandits": "battle", "caravan": "market", "treasure": "rewards"}

var encounter_id := ""
var _icon: TextureRect
var _title: Label
var _left: Label
var _text: Label
var _buttons: HBoxContainer
var _result: Label
var _signature := ""
var _timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.85, 12))
	custom_minimum_size = Vector2(440, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_icon = Icons.rect("battle", 30)
	head.add_child(_icon)
	_title = MenuStyle.label("", 20, MenuStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: show_encounter(""))
	head.add_child(close)
	_left = MenuStyle.label("", 14, MUTED)
	box.add_child(_left)
	_text = MenuStyle.label("", 15, MenuStyle.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(410, 0)
	box.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	box.add_child(_buttons)
	_result = MenuStyle.label("", 15, GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(410, 0)
	box.add_child(_result)
	EventBus.encounter_selected.connect(show_encounter)
	for sig: Signal in [EventBus.party_selected, EventBus.settlement_selected, EventBus.player_selected,
			EventBus.baron_selected, EventBus.village_selected]:
		sig.connect(func(id: String) -> void:
			if id != "":
				show_encounter(""))
	Economy.changed.connect(func() -> void:
		if visible:
			_fill())


func show_encounter(id: String) -> void:
	if id != encounter_id:
		_result.text = ""
	encounter_id = id
	_signature = ""
	visible = id != ""
	_fill()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_fill()


func _fill() -> void:
	var rules := Economy.encounter_rules
	if rules == null or encounter_id == "":
		return
	var now := Economy.now()
	var e := rules.find(now, encounter_id)
	if e.is_empty():
		_title.text = "Gone"
		_left.text = ""
		_text.text = "It has moved on from the map. Others will turn up along the roads."
		_clear_buttons()
		return
	_title.text = rules.display_name(e)
	_icon.texture = Icons.get_icon(ICONS.get(String(e.kind), "battle"), 30)
	_left.text = "Leaves in %s" % _hours(float(e.end) - now)
	var castle := Economy.player_castle
	var keep := castle.keep_level()
	var done := EncounterRules.done(castle, encounter_id)
	var sig := str([encounter_id, done, castle.troops, castle.resources.values().map(func(v: float) -> int: return int(v / 50.0)), keep])
	if sig == _signature:
		return
	_signature = sig
	_clear_buttons()
	match String(e.kind):
		"bandits":
			var army := rules.bandit_army(keep)
			_text.text = "Outlaws have made camp by the road: %s. Beat them for %s, and maybe a %s.\nSend part of your garrison; the survivors come straight home." % [
				_army_text(army), Economy.reward_text(rules.bandit_loot(keep)), String(Economy.chest_rules.kinds[rules.bandits.chest].name).to_lower()]
			if not done:
				for share: String in ["quarter", "half", "all"]:
					var sent := EncounterRules.sent_army(castle, share)
					var odds := Battle.odds(Economy.rules, sent, army) if not sent.is_empty() else 0.0
					var b := _button("%s: %s" % [{"quarter": "A quarter", "half": "Half", "all": "All"}[share], Battle.odds_text(odds)],
							_take.bind(share), share == "half")
					b.disabled = sent.is_empty()
					b.tooltip_text = _army_text(sent) if not sent.is_empty() else "No soldiers at home."
		"caravan":
			var offer := rules.trade(e, keep)
			_text.text = "A merchant caravan on its way through. The merchant offers:\n%s for %s." % [
				Economy.reward_text({"resources": offer.get}), Economy.reward_text({"resources": offer.give})]
			if not done:
				var b := _button("Trade", _take.bind(""), true)
				b.disabled = not castle.can_afford(offer.give)
		"treasure":
			_text.text = "Old stones and a marked tree: something is buried here. Digging needs %d soldiers at home and %s for them. You'll find %s and a treasure chest (wooden, iron or, if you're lucky, golden)." % [
				int(rules.treasure.diggers), Economy.reward_text({"resources": rules.dig_cost(keep)}),
				Economy.reward_text({"resources": {"gold": roundi(float(rules.treasure.gold) * rules._mult(keep))}})]
			if not done:
				var b := _button("Dig", _take.bind(""), true)
				b.disabled = rules.check(castle, e) != ""
	if done and _result.text == "":
		_result.add_theme_color_override("font_color", MUTED)
		_result.text = "You've already been here."


func _take(choice: String) -> void:
	var out := Economy.take_encounter(encounter_id, choice)
	_signature = ""
	if out.error != "":
		Audio.play("denied")
		_result.add_theme_color_override("font_color", BAD)
		_result.text = out.error
		return
	match String(out.kind):
		"bandits":
			var lost := 0
			for unit: String in out.fight.a:
				lost += int(out.fight.a[unit].lost)
			if out.won:
				Audio.play("victory")
				_result.add_theme_color_override("font_color", GOOD)
				_result.text = "Victory! The bandits are scattered. You lost %d soldiers and took %s." % [lost, Economy.reward_text(out.reward)]
			else:
				Audio.play("defeat")
				_result.add_theme_color_override("font_color", BAD)
				_result.text = "Defeat. Your men fled after losing %d soldiers. The bandits are still there." % lost
		"caravan":
			Audio.play("reward")
			_result.add_theme_color_override("font_color", GOOD)
			_result.text = "Done. You got %s." % Economy.reward_text(out.reward)
		_:
			Audio.play("reward")
			_result.add_theme_color_override("font_color", GOOD)
			_result.text = "Your diggers found %s. Open chests in the quest window's Treasure tab." % Economy.reward_text(out.reward)
	_fill()


func _button(text: String, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	if primary:
		GameTheme.primary(b)
	_buttons.add_child(b)
	return b


func _clear_buttons() -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()


static func _army_text(army: Dictionary) -> String:
	var parts: PackedStringArray = []
	for unit: String in army:
		parts.append("%d %s" % [int(army[unit]), Economy.rules.unit_plural(unit).to_lower() if Economy.rules.has_unit(unit) else unit])
	return ", ".join(parts)


static func _hours(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]
