extends VBoxContainer
## Spies and sabotage on a camp's or a player's map card (SabotageRules):
## how many agents to hire, what they should do (steal, burn the stores,
## weaken the walls), the chance and the cost, and what came of it. Hidden
## behind a "Send agents" button on the card until opened.

const MUTED := Color(0.78, 0.72, 0.62)
const GOOD := Color(0.55, 0.9, 0.45)
const BAD := Color(1.0, 0.55, 0.4)

var camp_id := ""
var player_name := ""
var player_keep := 1

var _agents := 5
var _mission := "steal"
var _resource := "gold"
var _count: Label
var _missions: HBoxContainer
var _resources: HBoxContainer
var _info: Label
var _send: Button
var _result: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	visible = false
	add_child(HSeparator.new())
	var title := MenuStyle.label("Spies and sabotage", 16, MenuStyle.GOLD)
	add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	row.add_child(MenuStyle.label("Agents", 14, MUTED))
	var less := _small("−", func() -> void: _set_agents(_agents - 1))
	row.add_child(less)
	_count = MenuStyle.label("", 15, MenuStyle.TEXT)
	_count.custom_minimum_size = Vector2(30, 0)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_count)
	row.add_child(_small("+", func() -> void: _set_agents(_agents + 1)))
	row.add_child(_small("Max", func() -> void: _set_agents(Economy.sabotage_rules.max_agents)))
	_missions = HBoxContainer.new()
	_missions.add_theme_constant_override("separation", 6)
	add_child(_missions)
	_resources = HBoxContainer.new()
	_resources.add_theme_constant_override("separation", 6)
	add_child(_resources)
	_info = MenuStyle.label("", 14, MenuStyle.TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(400, 0)
	add_child(_info)
	_send = GameTheme.primary(Button.new())
	_send.focus_mode = Control.FOCUS_NONE
	_send.pressed.connect(_go)
	add_child(_send)
	_result = MenuStyle.label("", 14, GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(400, 0)
	add_child(_result)
	Economy.agents_returned.connect(_on_returned)
	Economy.changed.connect(func() -> void:
		if visible:
			refresh())


func set_camp(id: String) -> void:
	if id != camp_id:
		_result.text = ""
	camp_id = id
	player_name = ""
	if _mission == "burn_stores":
		_mission = "steal"
	refresh()


func set_player(who: String, keep: int) -> void:
	if who != player_name:
		_result.text = ""
	player_name = who
	player_keep = keep
	camp_id = ""
	refresh()


func refresh() -> void:
	var rules := Economy.sabotage_rules
	if rules == null or (camp_id == "" and player_name == ""):
		return
	_agents = clampi(_agents, 1, rules.max_agents)
	_count.text = str(_agents)
	for child in _missions.get_children():
		_missions.remove_child(child)
		child.queue_free()
	for m: String in SabotageRules.MISSIONS:
		if camp_id != "" and bool(rules.missions[m].get("players_only", false)):
			continue
		var b := _small(rules.mission_name(m), _pick.bind(m))
		b.toggle_mode = true
		b.button_pressed = m == _mission
		b.tooltip_text = String(rules.missions[m].text)
		_missions.add_child(b)
	for child in _resources.get_children():
		_resources.remove_child(child)
		child.queue_free()
	_resources.visible = player_name != "" and _mission == "steal"
	if _resources.visible:
		_resources.add_child(MenuStyle.label("Steal", 14, MUTED))
		for r: String in Economy.player_castle.resources:
			var b := _small(r.capitalize(), func() -> void:
				_resource = r
				refresh())
			b.toggle_mode = true
			b.button_pressed = r == _resource
			_resources.add_child(b)
	var castle := Economy.player_castle
	var keep := castle.keep_level()
	var chance := 0.0
	var key := ""
	var what := ""
	if camp_id != "":
		var camp := Economy.get_baron(camp_id)
		if camp == null:
			return
		chance = rules.camp_chance(_agents, camp.level)
		key = SabotageRules.camp_key(camp_id)
	else:
		chance = rules.player_chance(_agents, keep, player_keep)
		key = SabotageRules.player_key(player_name)
	match _mission:
		"steal":
			what = "They can carry up to %d%s." % [rules.carry(_agents, keep),
				" " + _resource if player_name != "" else " of the camp's loot"]
		"burn_stores":
			what = "%d%% of everything above their hidden cellars burns." % roundi(rules.burn_share * 100.0)
		"burn_walls":
			what = "The %s loses %d%% of its strength for %d hours: attack while it's down." % [
				"palisade" if camp_id != "" else "wall", roundi(rules.walls_cut * 100.0), roundi(rules.walls_time / 3600.0)]
	_info.text = "%s\nChance: %d%%    Cost: %d gold" % [what, roundi(chance * 100.0), int(rules.cost(_agents).gold)]
	var why := rules.check(castle, key, _mission, _agents, Economy.now(), player_name != "")
	_send.text = "Send %d agent%s" % [_agents, "" if _agents == 1 else "s"]
	_send.disabled = why != ""
	_send.tooltip_text = why
	if why != "" and _result.text == "":
		_info.text += "\n" + why


func _pick(mission: String) -> void:
	_mission = mission
	refresh()


func _set_agents(n: int) -> void:
	_agents = n
	refresh()


func _go() -> void:
	if camp_id != "":
		var out := Economy.sabotage_camp(camp_id, _mission, _agents)
		if out.error != "":
			_say(out.error, BAD)
		elif not out.success:
			Audio.play("defeat")
			_say("Your agents were caught. The gold is gone.", BAD)
		elif _mission == "steal":
			Audio.play("reward")
			_say("Your agents slipped out with %s." % Economy.reward_text({"resources": out.stolen}), GOOD)
		else:
			Audio.play("reward")
			_say("The palisade is burning! It's weaker for %d hours." % roundi(Economy.sabotage_rules.walls_time / 3600.0), GOOD)
	else:
		var why := Economy.sabotage_player(player_name, _mission, _resource, _agents)
		_say(why if why != "" else "Your agents are slipping into %s's castle..." % player_name, BAD if why != "" else MUTED)
	refresh()


func _on_returned(r: Dictionary) -> void:
	if String(r.get("target", "")) != player_name:
		return
	if not bool(r.get("success", false)):
		Audio.play("defeat")
		_say("Your agents were caught. %s knows you sent them." % player_name, BAD)
		return
	Audio.play("reward")
	match String(r.get("mission", "")):
		"steal":
			_say("Your agents came back with %s." % Economy.reward_text({"resources": r.get("stolen", {})}), GOOD)
		"burn_stores":
			_say("%s's stores are burning!" % player_name, GOOD)
		_:
			_say("%s's gate is on fire: their walls are weaker for %d hours." % [player_name,
				roundi(Economy.sabotage_rules.walls_time / 3600.0)], GOOD)


func _say(text: String, color: Color) -> void:
	_result.add_theme_color_override("font_color", color)
	_result.text = text


func _small(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(action)
	return b
