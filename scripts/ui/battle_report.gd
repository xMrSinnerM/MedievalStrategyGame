extends PanelContainer
## The report shown after your warband fights or storms a castle: who won,
## each side's soldiers before the battle and how many fell, and the plunder.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const WIN := Color(0.6, 0.9, 0.45)
const LOSS := Color(0.95, 0.45, 0.35)

var _title: Label
var _place: Label
var _grid: GridContainer
var _walls: GridContainer      ## how each wall and the courtyard went, for sieges in waves
var _footer: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.94, 18))
	custom_minimum_size = Vector2(440, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = _label(26, WIN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_place = _label(15, MUTED)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_place)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid)
	_walls = GridContainer.new()
	_walls.columns = 4
	_walls.add_theme_constant_override("h_separation", 18)
	_walls.add_theme_constant_override("v_separation", 4)
	box.add_child(_walls)
	_footer = _label(15, TEXT)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_footer)
	var ok := Button.new()
	ok.text = "Continue"
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size = Vector2(140, 0)
	ok.pressed.connect(func() -> void: visible = false)
	box.add_child(ok)
	EventBus.battle_fought.connect(_on_battle)
	Economy.attack_resolved.connect(show_baron_report)


func _on_battle(report: Dictionary) -> void:
	if report.player == "":
		return
	show_report(report)


func show_report(report: Dictionary) -> void:
	var me: String = report.player
	var them := "b" if me == "a" else "a"
	var won: bool = report.winner == me
	var enemy: String = report.defender if me == "a" else report.attacker
	var siege: bool = report.get("siege", false)
	_title.text = "Victory!" if won else "Defeat"
	if siege:
		if me == "a":
			_title.text = {"captured": "Castle captured!", "sacked": "Castle sacked!"}.get(report.outcome, "The walls held")
		else:
			_title.text = {"captured": "Castle lost!", "sacked": "Castle sacked!"}.get(report.outcome, "The walls held!")
	_title.add_theme_color_override("font_color", WIN if won else LOSS)
	if siege and me == "a":
		_place.text = "You stormed the walls of %s" % enemy
	elif siege:
		_place.text = "%s stormed %s" % [enemy, report.defender]
	elif me == "a":
		_place.text = "You attacked %s near %s" % [enemy, report.place]
	else:
		_place.text = "%s attacked you near %s" % [enemy, report.place]
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var their_side := "Garrison" if siege and me == "a" else enemy
	for text in ["", "Garrison" if siege and me == "b" else "Yours", "Fell", their_side, "Fell"]:
		_grid.add_child(_label(14, MUTED, text))
	var units: Array = []
	for side in [report[me], report[them]]:
		for unit: String in side:
			if not units.has(unit):
				units.append(unit)
	var totals := [0, 0, 0, 0]
	for unit: String in units:
		var row := [_count(report[me], unit, "start"), _count(report[me], unit, "lost"),
				_count(report[them], unit, "start"), _count(report[them], unit, "lost")]
		_grid.add_child(_label(15, TEXT, Economy.rules.unit_plural(unit)))
		for k in 4:
			totals[k] += row[k]
			_grid.add_child(_cell(row[k], k % 2 == 1))
	_grid.add_child(_label(15, Color(1.0, 0.9, 0.65), "Total"))
	for k in 4:
		_grid.add_child(_cell(totals[k], k % 2 == 1))
	if siege and me == "a":
		if report.outcome == "captured":
			_footer.text = "%s is yours, with its buildings and stores." % enemy
		elif report.outcome == "sacked":
			_footer.text = "You carried off %s." % _spoils(report.spoils)
		else:
			_footer.text = "Your surviving soldiers fell back from the walls."
		if won and report.loot > 0:
			_footer.text += " Plunder: %d gold." % report.loot
	elif siege:
		if report.outcome == "captured":
			_footer.text = "%s now belongs to %s." % [report.defender, enemy]
		elif report.outcome == "sacked":
			_footer.text = "%s carried off %s. Train more soldiers to hold the walls." % [enemy, _spoils(report.spoils)]
		else:
			_footer.text = "Your garrison held. %s fell back." % enemy
	elif won:
		var fate := "%s fled home." % enemy if totals[3] < totals[2] else "None of %s's soldiers survived." % enemy
		_footer.text = "Your warband plundered %d gold. %s" % [report.loot, fate] if report.loot > 0 else fate
	else:
		_footer.text = "Your surviving soldiers fell back. %s took %d gold in plunder." % [enemy, report.loot]
	if report.get("lifted", "") != "":
		_footer.text += "\nThe siege of %s is lifted." % report.lifted
	_add_siege_line(report, me == "a")
	visible = true


func show_baron_report(report: Dictionary) -> void:
	## The report for an army you sent against a robber baron camp (or, online,
	## a battle between your castle and another player's, or for a village).
	if report.get("village", false):
		show_village_report(report)
		return
	if report.get("raid", false):
		show_raid_report(report)
		return
	if report.get("empty", false):
		_title.text = "Nothing to fight"
		_title.add_theme_color_override("font_color", MUTED)
		_place.text = "%s was still in ashes when your army arrived." % report.defender
		_clear_grid()
		_fill_walls({}, true)
		_footer.text = "Your army is marching home."
		visible = true
		return
	report = report.duplicate()
	report.attacker = "Your army"
	show_report(report)
	var won: bool = report.winner == "a"
	_place.text = "Your army attacked %s (level %d)" % [report.defender, report.level]
	var lines: PackedStringArray = []
	if won:
		lines.append("Your army is bringing home %s." % _spoils(report.spoils))
		if int(report.get("points", 0)) > 0:
			lines.append("Baron Invasion: +%d event points." % int(report.points))
		if report.leveled:
			lines.append("%s rises to level %d: more soldiers, more loot%s." % [report.defender, report.new_level,
					", better gear" if report.get("fortress", false) else ""])
		else:
			lines.append("Wins %d of %d before %s reaches level %d." % [report.defeats, report.needed, report.defender, report.new_level + 1])
	else:
		lines.append("The %s held. Your surviving soldiers are marching home." % ("fortress" if report.get("fortress", false) else "camp"))
	_footer.text = "\n".join(lines)
	_add_siege_line(report, true)


func show_raid_report(report: Dictionary) -> void:
	## A battle between players: your army against their castle, or theirs against yours.
	show_report(report)
	var attacking: bool = report.player == "a"
	var won: bool = report.winner == report.player
	var walls := "+%d%% from the walls" % roundi((float(report.get("wall", 1.0)) - 1.0) * 100.0)
	if attacking:
		_title.text = "Victory!" if won else "Defeat"
		_place.text = "Your army attacked %s's castle (%s)" % [report.name, walls]
		_footer.text = "Your army is bringing home %s." % _spoils(report.spoils) if won \
				else "%s's garrison held. Your surviving soldiers are marching home." % report.name
		if report.b.is_empty():
			_footer.text = "No soldiers were home to defend it.\n" + _footer.text
	else:
		_title.text = "Your walls held!" if won else "Your castle was raided!"
		_place.text = "%s attacked your castle (%s)" % [report.name, walls]
		_footer.text = "%s's army fell back with nothing." % report.name if won \
				else "%s carried off %s. Train more soldiers to hold the walls." % [report.name, _spoils(report.spoils)]
		var helped: Array = report.get("helped_by", [])
		if not helped.is_empty():
			_footer.text = "Defenders from %s fought beside your garrison.\n" % ", ".join(PackedStringArray(helped)) + _footer.text
	_add_siege_line(report, attacking)
	_title.add_theme_color_override("font_color", WIN if won else LOSS)


func show_village_report(report: Dictionary) -> void:
	## A battle for a resource village or a capital: your army against its
	## militia (a capital's town guard) or its holder's guards, or (online)
	## someone's army against your guards.
	report = report.duplicate()
	var attacking: bool = report.player == "a"
	var other := String(report.get("other", ""))
	var village := String(report.name)
	var capital: bool = report.get("capital", false)
	var what := "capital" if capital else "village"
	var militia := "the town guard" if capital else "the militia"
	report.attacker = "Your army" if attacking else other
	report.defender = ("%s's guards" % other if other != "" else militia.capitalize()) if attacking else "Your guards"
	show_report(report)
	var won: bool = report.winner == report.player
	var lines: PackedStringArray = []
	if attacking:
		_title.text = ("%s is yours!" % village) if report.get("captured", false) else ("Victory!" if won else "Defeat")
		_place.text = "Your army attacked %s (level %d, %s), held by %s" % [village, int(report.level),
				what if capital else report.resource, other if other != "" else militia]
		var vr: VillageRules = Economy.capital_rules if capital else Economy.village_rules
		if won:
			if report.get("captured", false):
				lines.append("It sends you %d %s an hour from now on%s." % [vr.yield_per_hour(report.resource, int(report.level)),
						report.resource, ", and your castles produce +%d%% more" % roundi(Economy.capital_rules.bonus(int(report.level)) * 100.0)
						if capital else ""] + (" Station soldiers there to keep it." if Economy.online else ""))
			elif report.get("no_room", false):
				lines.append("You can't hold another %s, so your army left it to %s." % [what, other if other != "" else militia])
			lines.append("Your army is bringing home %s." % _spoils(report.spoils))
		else:
			lines.append("%s held. Your surviving soldiers are marching home." % village)
	else:
		_title.text = "Your guards held %s!" % village if won else "%s was taken!" % village
		_place.text = "%s attacked your %s %s" % [other, what, village]
		if won:
			lines.append("%s's army fell back with nothing." % other)
		elif report.get("captured", false):
			lines.append("%s holds it now and carried off %s. Take it back, or another one." % [other, _spoils(report.spoils)])
		else:
			lines.append("%s carried off %s, but had no room to hold the %s: it is still yours." % [other, _spoils(report.spoils), what])
	_footer.text = "\n".join(lines)
	_add_siege_line(report, attacking)
	_title.add_theme_color_override("font_color", WIN if won else LOSS)


func _add_siege_line(report: Dictionary, attacking: bool) -> void:
	## Puts how the walls and the courtyard went (Battle.siege()) above the footer.
	var line := siege_line(report, attacking)
	var tools := tools_line(report, attacking)
	if tools != "":
		line = tools if line == "" else line + "\n" + tools
	var gear := gear_line(report) if attacking else ""
	if gear != "":
		line = gear if line == "" else line + "\n" + gear
	if line != "":
		_footer.text = line + "\n" + _footer.text
	_fill_walls(report, attacking)


func _fill_walls(report: Dictionary, attacking: bool) -> void:
	## One row per wall and the courtyard: what happened there and who fell.
	for child in _walls.get_children():
		_walls.remove_child(child)
		child.queue_free()
	var walls: Dictionary = report.get("walls", {})
	_walls.visible = not walls.is_empty()
	if walls.is_empty():
		return
	var me := "a" if attacking else "b"
	var them := "b" if attacking else "a"
	for text in ["", "", "Yours fell", "Theirs fell"]:
		_walls.add_child(_label(14, MUTED, text))
	for w: String in Battle.WALLS:
		var wall: Dictionary = walls.get(w, {})
		var lost := [0, 0]
		for f: Dictionary in wall.get("fights", []):
			if f.has("winner"):
				lost[0] += Battle.lost_count(f[me])
				lost[1] += Battle.lost_count(f[them])
		_wall_row("%s wall" % w.capitalize(), wall_result(wall), lost)
	var yard: Dictionary = report.get("courtyard", {})
	var lost := [0, 0]
	if yard.has("winner"):
		lost = [Battle.lost_count(yard[me]), Battle.lost_count(yard[them])]
	_wall_row("Courtyard", courtyard_result(yard, attacking), lost)


func _wall_row(place: String, result: String, lost: Array) -> void:
	_walls.add_child(_label(15, TEXT, place))
	_walls.add_child(_label(15, MUTED, result))
	for k in 2:
		_walls.add_child(_cell(int(lost[k]), true))


static func wall_result(wall: Dictionary) -> String:
	var fights: Array = wall.get("fights", [])
	if fights.is_empty():
		return "Not attacked"
	if not wall.get("broken", false):
		return "Held"
	for f: Dictionary in fights:
		if f.get("open", false):
			return "Undefended" if f == fights[0] else "Broken in wave %d" % (int(f.wave) + 1)
		if f.get("winner", "") == "a":
			return "Broken in wave %d" % (int(f.wave) + 1)
	return "Broken"


static func courtyard_result(yard: Dictionary, attacking: bool) -> String:
	if yard.is_empty():
		return "Not reached"
	if yard.get("open", false):
		return "Empty"
	if yard.get("winner", "") == "a":
		return "Won" if attacking else "Lost"
	return "Lost" if attacking else "Held"


static func siege_line(report: Dictionary, attacking: bool) -> String:
	var walls: Dictionary = report.get("walls", {})
	if walls.is_empty():
		return ""
	var broken: PackedStringArray = []
	for w: String in Battle.WALLS:
		if walls.get(w, {}).get("broken", false):
			broken.append(w)
	var who := "Your army" if attacking else "The enemy"
	if broken.is_empty():
		return "%s broke no wall." % who if attacking else "Every wall held."
	var which := " and ".join(broken) if broken.size() < 3 else "left, front and right"
	var line := "%s broke %s %s wall%s" % [who, "the" if attacking else "your", which, "s" if broken.size() > 1 else ""]
	var yard: Dictionary = report.get("courtyard", {})
	if yard.get("open", false):
		return line + " and found the courtyard empty."
	if yard.has("winner"):
		var won_yard: bool = yard.winner == "a"
		return line + (" and won in the courtyard." if won_yard else " but lost in the courtyard.")
	return line + "."


static func gear_line(report: Dictionary) -> String:
	## The commander who led the army and what they earned, and gear the camp dropped.
	var lines: PackedStringArray = []
	var lead: Variant = report.get("lead")
	if lead is Dictionary and not lead.is_empty():
		var xp := int(lead.get("xp", 0))
		if report.get("raid", false):
			lines.append("%s led the army and earns %d xp when they are home." % [lead.name, xp])
		elif lead.get("leveled", false):
			lines.append("%s led the army: +%d xp, and rises to level %d!" % [lead.name, xp, int(lead.level)])
		else:
			lines.append("%s led the army: +%d xp." % [lead.name, xp])
	var item: Variant = report.get("gear")
	if item is Dictionary and not item.is_empty():
		var g: GearRules = Economy.gear_rules
		var what := "%s (%s %s: %s)" % [item.name, String(g.rarities.get(item.rarity, {}).get("name", item.rarity)).to_lower(),
				String(g.slot_names.get(item.slot, item.slot)).to_lower(), g.item_text(item)]
		if report.get("bag_full", false):
			lines.append("The baron dropped %s, but your bag was full, so it was left behind." % what)
		else:
			lines.append("Spoils of war: %s. Find it under Commanders." % what)
	return "\n".join(lines)


static func tools_line(report: Dictionary, attacking: bool) -> String:
	## Which siege tools each side used, and the defence tools lost with their walls.
	var tools: Variant = report.get("tools")
	if not tools is Dictionary or tools.is_empty():
		return ""
	var parts: PackedStringArray = []
	var a := _tools_at(tools.get("a", {}))
	var b := _tools_at(tools.get("b", {}))
	var lost := _tools_at(tools.get("lost", {}))
	if a != "":
		parts.append(("Your siege tools: " if attacking else "Their siege tools: ") + a + ".")
	if b != "":
		parts.append(("Their defence tools: " if attacking else "Your defence tools: ") + b + ".")
	if lost != "":
		parts.append(("Destroyed with their walls: " if attacking else "Lost with your walls: ") + lost + ".")
	return " ".join(parts)


static func _tools_at(group: Variant) -> String:
	## "front 4 ladders; left 2 arrow slits".
	if not group is Dictionary:
		return ""
	var rules := Economy.rules
	var out: PackedStringArray = []
	for w: String in Battle.WALLS:
		var at: Variant = group.get(w, {})
		if not at is Dictionary:
			continue
		var items: PackedStringArray = []
		for tool: String in at:
			var n := int(at[tool])
			if n > 0 and rules.has_tool(tool):
				items.append("%d %s" % [n, (rules.tool_name(tool) if n == 1 else rules.tool_plural(tool)).to_lower()])
		if not items.is_empty():
			out.append("%s %s" % [w, ", ".join(items)])
	return "; ".join(out)


func _clear_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


func _spoils(spoils: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in spoils:
		if spoils[r] > 0:
			parts.append("%d %s" % [spoils[r], r])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _count(side: Dictionary, unit: String, key: String) -> int:
	return int(side[unit][key]) if side.has(unit) else 0


func _cell(n: int, is_loss: bool) -> Label:
	var l := _label(15, LOSS if is_loss and n > 0 else TEXT, ("-%d" if is_loss and n > 0 else "%d") % n)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _label(size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
