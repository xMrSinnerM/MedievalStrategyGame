extends PanelContainer
## A small box with the story quest you're on, today's daily tasks, today's
## Royal Gift if it's waiting, and your achievement points. It glows when a
## reward is waiting; clicking it opens the Royal Gift while it waits, else
## the quest screen, or the achievements when only those have a reward.

var panel: Control   ## the quest panel to open; set by the HUD
var achievements: Control   ## the achievements panel; set by the HUD
var gift: Control           ## the Royal Gift panel; set by the HUD

var _label: Label
var _timer := 0.0
var _ready_glow := false


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.7, 10))
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Quests (J)"
	_label = MenuStyle.label("", 14, MenuStyle.TEXT)
	add_child(_label)
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and panel != null:
			if gift != null and Economy.login_waiting():
				gift.toggle()
			elif achievements != null and _achievement_waiting() and not Economy.quest_book.can_claim_anything(Economy.player_castle):
				achievements.toggle()
			else:
				panel.toggle()
			accept_event())


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_refresh()
	modulate = Color(1, 1, 1) if not _ready_glow else Color(1.0, 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.006), 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006))


func _refresh() -> void:
	var book := Economy.quest_book
	var castle := Economy.player_castle
	if book == null or castle == null:
		visible = false
		return
	visible = true
	var lines: PackedStringArray = []
	var quest := book.current_story(castle)
	if quest.is_empty():
		lines.append("Every quest is done")
	else:
		var p := book.progress(castle, quest.goal)
		lines.append("Quest: %s    %d / %d" % [quest.title, mini(p[0], p[1]), p[1]])
	var q := castle.quests
	if not q.picks.is_empty():
		var done := 0
		for i in q.picks.size():
			var p := book.daily_progress(castle, i)
			if q.claimed.has(i) or p[0] >= p[1]:
				done += 1
		lines.append("Daily tasks: %d / %d%s" % [done, q.picks.size(), "    coffer opened" if q.chest else ""])
	if Economy.achievements != null:
		lines.append("Achievements: %d points%s" % [Economy.achievements.score(castle),
			"    reward waiting (Y)" if _achievement_waiting() else ""])
	if Economy.season_rules != null:
		lines.append("Season renown: %d%s" % [Economy.season_rules.renown(castle),
			"    reward waiting" if Economy.season_waiting() else ""])
	if Economy.chest_rules != null and Economy.chest_rules.total(castle) > 0:
		lines.append("Treasure chests to open: %d" % Economy.chest_rules.total(castle))
	if Economy.login_waiting():
		lines.append("Today's Royal Gift is waiting")
	if Economy.weather_rules != null:
		lines.append(_weather_line())
	_ready_glow = book.can_claim_anything(castle) or _achievement_waiting() or Economy.login_waiting() or Economy.season_waiting()
	if book.can_claim_anything(castle):
		lines.append("A reward is waiting! Click or press J")
	_label.text = "\n".join(lines)
	_label.add_theme_color_override("font_color", MenuStyle.GOLD if _ready_glow else MenuStyle.TEXT)


func _weather_line() -> String:
	## "Dusk    2 storms, 1 rain on the map", or what's over your castle.
	var w := Economy.weather_rules
	var now := Economy.now()
	var counts := {"storm": 0, "rain": 0}
	var over := ""
	for cell: Dictionary in w.active(now):
		if counts.has(cell.kind):
			counts[cell.kind] += 1
			if w.centre(cell, now).distance_to(Economy.home_position()) <= float(cell.radius) and (over == "" or cell.kind == "storm"):
				over = String(cell.kind)
	var parts: PackedStringArray = []
	if counts.storm > 0:
		parts.append("%d storm%s" % [counts.storm, "" if counts.storm == 1 else "s"])
	if counts.rain > 0:
		parts.append("%d rain" % counts.rain)
	var sky := "clear skies" if parts.is_empty() else ", ".join(parts) + " on the map"
	if over != "":
		sky = "%s over your castle" % w.kind_name(over).to_lower()
	return "%s    %s" % [w.time_name(now), sky]


func _achievement_waiting() -> bool:
	return Economy.achievements != null and Economy.achievements.can_claim_anything(Economy.player_castle)
