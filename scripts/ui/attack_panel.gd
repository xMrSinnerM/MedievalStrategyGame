extends PanelContainer
## The attack screen, opened from a robber baron camp's panel, a resource
## village's or (online) another player's: plan the siege wave by wave, with how many of each
## soldier storm the left, front and right walls (Battle.siege()), and see
## your chances, the losses to expect, how much loot they can carry and how
## long the march takes. Your keep decides how many waves you can send
## (Battle.waves_for_keep()). "Auto" tries a set of plans and picks the one
## with the best odds. Siege tools from the workshop (ladders, mantlets,
## rams) can go to each wall for the whole attack; your keep decides how many
## fit. A commander can lead the army, adding their gear's bonuses and
## earning xp. Against a player the odds use what your spy last saw, their
## defence tools and castellan included.

const WIN := Color(0.55, 0.9, 0.45)
const LOSS := Color(0.95, 0.4, 0.3)
const SAMPLES := 12
## The ways Auto tries to spread each wave over the walls (percentages).
const AUTO_SPLITS := [
	{"left": 30, "front": 40, "right": 30},
	{"left": 33, "front": 34, "right": 33},
	{"left": 50, "front": 0, "right": 50},
	{"left": 50, "front": 50, "right": 0},
	{"left": 0, "front": 50, "right": 50},
	{"left": 100, "front": 0, "right": 0},
	{"left": 0, "front": 100, "right": 0},
	{"left": 0, "front": 0, "right": 100},
]

var camp_id := ""              ## a camp's id, "player:<name>" for another player's castle, or "village:<id>"
var _player := ""              ## the other player's name when attacking a player
var _village := ""             ## the village's id when attacking a resource village

var _title: Label
var _tabs: HBoxContainer
var _tab_buttons: Array[Button] = []
var _rows: GridContainer
var _spins := {}               ## wall -> unit -> SpinBox, for the wave on show
var _spare := {}               ## unit -> Label with the soldiers not yet placed
var _enemy_title: Label
var _enemy: Label
var _summary: Label
var _send: Button
var _note: Label
var _quiet := false            ## true while setting spin boxes from code
var _plan: Array = []          ## one {wall: {unit: soldiers}} per wave the keep allows
var _wave := 0                 ## the wave on show
var _tools := {}               ## wall -> {tool: n}, siege tools for the whole attack
var _tool_rows: GridContainer
var _tool_spins := {}          ## wall -> tool -> SpinBox
var _tool_head: Label
var _commander: OptionButton
var _commander_fx: Label
var _verdict: PanelContainer
var _verdict_label: Label
var _army_total: Label         ## "Your army" title; its Sub line counts the soldiers at home
var _enemy_picture: InfoPicture
var _my_losses: Label
var _their_losses: Label
var _ring: ChanceRing


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1000, 0)
	visible = false
	add_to_group("tutorial_window")
	# Battle music while the attack screen is open.
	visibility_changed.connect(func() -> void: Audio.set_battle(is_visible_in_tree()))
	tree_exiting.connect(func() -> void: Audio.set_battle(false))
	tree_entered.connect(func() -> void: Audio.set_battle(visible))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	_title = MenuStyle.title("", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_verdict = PanelContainer.new()
	_verdict.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pill := HBoxContainer.new()
	pill.add_theme_constant_override("separation", 6)
	pill.add_child(Icons.rect("battle", 18))
	_verdict_label = MenuStyle.label("", 15, MenuStyle.TEXT)
	pill.add_child(_verdict_label)
	_verdict.add_child(pill)
	head.add_child(_verdict)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_panel)
	head.add_child(close)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)

	# Left: your army, wave by wave, with siege tools and a commander.
	var mine := VBoxContainer.new()
	mine.add_theme_constant_override("separation", 8)
	var army_card := _card(mine)
	army_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(army_card)
	_army_total = _card_head(mine, "soldiers", "Your army")
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	mine.add_child(_tabs)
	_rows = GridContainer.new()
	_rows.columns = 5
	_rows.add_theme_constant_override("h_separation", 10)
	_rows.add_theme_constant_override("v_separation", 6)
	mine.add_child(_rows)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	quick.add_child(_small_button("Auto", func() -> void: _auto(1.0), 90))
	quick.add_child(_small_button("Auto with half", func() -> void: _auto(0.5), 150))
	quick.add_child(_small_button("Clear wave", _clear_wave, 120))
	quick.add_child(_small_button("Clear all", func() -> void:
		_new_plan()
		_show_wave(_wave), 100))
	mine.add_child(quick)
	mine.add_child(HSeparator.new())
	_tool_head = MenuStyle.label("", 16, MenuStyle.GOLD)
	_tool_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mine.add_child(_tool_head)
	_tool_rows = GridContainer.new()
	_tool_rows.columns = 5
	_tool_rows.add_theme_constant_override("h_separation", 10)
	_tool_rows.add_theme_constant_override("v_separation", 6)
	mine.add_child(_tool_rows)
	mine.add_child(HSeparator.new())
	var lead_row := HBoxContainer.new()
	lead_row.add_theme_constant_override("separation", 10)
	lead_row.add_child(Icons.rect("commanders", 26))
	lead_row.add_child(MenuStyle.label("Commander", 16, MenuStyle.GOLD))
	_commander = OptionButton.new()
	_commander.focus_mode = Control.FOCUS_NONE
	_commander.custom_minimum_size = Vector2(240, 32)
	_commander.item_selected.connect(func(_i: int) -> void: _update())
	lead_row.add_child(_commander)
	_commander_fx = MenuStyle.label("", 14, MenuStyle.MUTED)
	_commander_fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commander_fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead_row.add_child(_commander_fx)
	mine.add_child(lead_row)

	# Right: who defends it, and the battle forecast.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	var theirs := VBoxContainer.new()
	theirs.add_theme_constant_override("separation", 8)
	right.add_child(_card(theirs))
	_enemy_title = _card_head(theirs, "shield", "Enemy defences")
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 10)
	theirs.add_child(enemy_row)
	_enemy_picture = InfoPicture.new()
	enemy_row.add_child(_enemy_picture)
	_enemy = MenuStyle.label("", 14, MenuStyle.TEXT)
	_enemy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_row.add_child(_enemy)
	var forecast := VBoxContainer.new()
	forecast.add_theme_constant_override("separation", 8)
	right.add_child(_card(forecast))
	_card_head(forecast, "battle", "Battle forecast")
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 14)
	forecast.add_child(stats)
	_my_losses = _stat(stats, "Your losses")
	_their_losses = _stat(stats, "Enemy losses")
	var ring_box := VBoxContainer.new()
	ring_box.add_child(MenuStyle.label("Victory chance", 13, MenuStyle.MUTED))
	_ring = ChanceRing.new()
	_ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring_box.add_child(_ring)
	stats.add_child(ring_box)
	forecast.add_child(HSeparator.new())
	forecast.add_child(MenuStyle.label("Key factors", 15, MenuStyle.GOLD))
	_summary = MenuStyle.label("", 14, MenuStyle.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(300, 0)
	forecast.add_child(_summary)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	_send = GameTheme.primary(MenuStyle.button("Send army", _send_army, 360.0))
	_send.custom_minimum_size.y = 46
	_send.add_to_group("tutorial_send_army")
	_send.add_theme_font_size_override("font_size", 18)
	buttons.add_child(_send)
	var cancel := MenuStyle.button("Cancel", close_panel, 160.0)
	cancel.custom_minimum_size.y = 46
	buttons.add_child(cancel)
	box.add_child(buttons)
	_note = MenuStyle.label("", 15, MenuStyle.GOLD)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	EventBus.attack_screen_requested.connect(open_for)
	Economy.spy_returned.connect(func(who: String) -> void:
		if visible and who == _player:
			_describe_player()
			_update())


func _card(content: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GameTheme.panel_box(0.45, 14))
	card.add_child(content)
	return card


func _card_head(box: VBoxContainer, icon: String, text: String) -> Label:
	## An icon and a gold title, with a muted line under it; returns the title.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Icons.rect(icon, 30))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", -2)
	var title := MenuStyle.label(text, 18, MenuStyle.GOLD)
	lines.add_child(title)
	var sub := MenuStyle.label("", 14, MenuStyle.MUTED)
	sub.name = "Sub"
	lines.add_child(sub)
	row.add_child(lines)
	box.add_child(row)
	return title


func _sub(title: Label) -> Label:
	return title.get_parent().get_node("Sub") as Label


func _stat(row: HBoxContainer, text: String) -> Label:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(MenuStyle.label(text, 13, MenuStyle.MUTED))
	var value := MenuStyle.label("", 22, MenuStyle.TEXT)
	col.add_child(value)
	row.add_child(col)
	return value


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func open_for(id: String) -> void:
	_village = ""
	if id.begins_with("village:"):
		var info := Economy.village_info(id.trim_prefix("village:"))
		if info.is_empty():
			return
		_player = ""
		_village = String(info.id)
		_title.text = "Attack %s (level %d)" % [info.name, int(info.level)]
		_sub(_enemy_title).text = "The capital" if info.get("capital", false) else "The village"
		_enemy_picture.show_place(InfoPicture.faction_place("capital", String(info.get("faction", ""))) if info.get("capital", false) else "village")
	elif id.begins_with("player:"):
		var other := Economy.get_other(id.trim_prefix("player:"))
		if other.is_empty():
			return
		_player = String(other.name)
		_title.text = "Attack %s (level %d)" % [_player, int(other.get("level", 1))]
		_sub(_enemy_title).text = "Their castle"
		_enemy_picture.show_place(InfoPicture.faction_place("castle", _player))
	else:
		var camp := Economy.get_baron(id)
		if camp == null:
			return
		_player = ""
		_title.text = "Attack %s (level %d)" % [camp.camp_name, camp.level]
		_sub(_enemy_title).text = "The fortress" if camp.fortress else "The camp"
		_enemy_picture.show_place(InfoPicture.faction_place("castle", camp.id) if camp.fortress else "camp")
	camp_id = id
	_note.text = ""
	_note.visible = false
	_build_tabs()
	_tools = {}
	_build_tool_rows()
	_build_commanders()
	if _village != "":
		_describe_village()
	elif _player != "":
		_describe_player()
	else:
		_describe_camp(Economy.get_baron(id))
	_auto(1.0)
	visible = true


func close_panel() -> void:
	visible = false


# --- The plan ------------------------------------------------------------------------

func _new_plan() -> void:
	_plan = []
	for k in Economy.max_waves():
		_plan.append({"left": {}, "front": {}, "right": {}})


func _have(unit: String) -> int:
	return int(Economy.player_castle.troops.get(unit, 0))


func _placed(unit: String, skip_wave := -1, skip_wall := "") -> int:
	## Soldiers of `unit` already in the plan, leaving out one wave's wall.
	var n := 0
	for k in _plan.size():
		for w: String in Battle.WALLS:
			if k == skip_wave and w == skip_wall:
				continue
			n += int(_plan[k][w].get(unit, 0))
	return n


func plan_waves() -> Array:
	## The plan as Battle.siege() waves: empty walls, units and waves left out.
	var out: Array = []
	for wave: Dictionary in _plan:
		var clean := {}
		for w: String in Battle.WALLS:
			var troops := {}
			for unit: String in wave[w]:
				if int(wave[w][unit]) > 0:
					troops[unit] = int(wave[w][unit])
			if not troops.is_empty():
				clean[w] = troops
		if not clean.is_empty():
			out.append(clean)
	return out


func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	var allowed := Economy.max_waves()
	for k in Battle.WAVES_BY_KEEP.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(112, 48)
		b.add_theme_font_size_override("font_size", 15)
		var wave := k
		b.pressed.connect(func() -> void: _show_wave(wave))
		if k >= allowed:
			b.disabled = true
			b.text = "Wave %d\nkeep %d" % [k + 1, _keep_for_wave(k + 1)]
			b.tooltip_text = "Upgrade your keep to level %d to send a wave %d." % [_keep_for_wave(k + 1), k + 1]
		_tabs.add_child(b)
		_tab_buttons.append(b)


static func _keep_for_wave(n: int) -> int:
	for row: Array in Battle.WAVES_BY_KEEP:
		if int(row[1]) >= n:
			return int(row[0])
	return 99


func _show_wave(k: int) -> void:
	_wave = clampi(k, 0, _plan.size() - 1)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_spins.clear()
	_spare.clear()
	var units: Array = []
	for unit: String in Economy.rules.units:
		if _have(unit) > 0:
			units.append(unit)
	if units.is_empty():
		_rows.columns = 1
		_rows.add_child(MenuStyle.label("Your garrison is empty.", 15, MenuStyle.MUTED))
		_update()
		return
	_rows.columns = 5
	for text in ["", "Left wall", "Front wall", "Right wall", "Not sent"]:
		_rows.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
	for w: String in Battle.WALLS:
		_spins[w] = {}
	for unit: String in units:
		var name_cell := HBoxContainer.new()
		name_cell.add_theme_constant_override("separation", 8)
		name_cell.add_child(Icons.rect(unit, 26))
		name_cell.add_child(MenuStyle.label(Economy.rules.unit_plural(unit), 16, MenuStyle.TEXT))
		_rows.add_child(name_cell)
		for w: String in Battle.WALLS:
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.step = 1
			spin.custom_minimum_size = Vector2(104, 0)
			var wall := w
			var u := unit
			spin.value_changed.connect(func(v: float) -> void:
				if _quiet:
					return
				_plan[_wave][wall][u] = int(v)
				_refresh_spins()
				_update())
			_rows.add_child(spin)
			_spins[w][unit] = spin
		var spare := MenuStyle.label("", 15, MenuStyle.MUTED)
		_rows.add_child(spare)
		_spare[unit] = spare
	_refresh_spins()
	_update()


func _refresh_spins() -> void:
	## Sets every spin box on show to the plan, each allowed what isn't
	## placed elsewhere, and the tabs to how many soldiers each wave holds.
	_quiet = true
	for w: String in _spins:
		for unit: String in _spins[w]:
			var spin: SpinBox = _spins[w][unit]
			spin.max_value = maxi(0, _have(unit) - _placed(unit, _wave, w))
			spin.value = int(_plan[_wave][w].get(unit, 0))
	_quiet = false
	for unit: String in _spare:
		_spare[unit].text = "%d of %d" % [_have(unit) - _placed(unit), _have(unit)]
	for k in _tab_buttons.size():
		var b := _tab_buttons[k]
		b.button_pressed = k == _wave
		_tab_style(b, k == _wave)
		if k < _plan.size():
			var n := 0
			for w: String in Battle.WALLS:
				for unit: String in _plan[k][w]:
					n += int(_plan[k][w][unit])
			b.text = "Wave %d\n%d" % [k + 1, n]


func _clear_wave() -> void:
	_plan[_wave] = {"left": {}, "front": {}, "right": {}}
	_refresh_spins()
	_update()


func _auto(share: float) -> void:
	## Fills the plan with `share` of the garrison: of a set of plans (every
	## number of waves the keep allows, each spread over the walls by one of
	## AUTO_SPLITS), the one with the best odds, then the fewest losses.
	## Without a spy's report on a player, the army goes in one wave
	## (Battle.auto_waves()).
	var army := {}
	for unit: String in Economy.rules.units:
		var n := floori(_have(unit) * share)
		if n > 0:
			army[unit] = n
	_new_plan()
	if not army.is_empty():
		var best: Array = Battle.auto_waves(army)
		var foe := _defence()
		if not foe.is_empty():
			var best_score := -1.0
			for n in range(1, _plan.size() + 1):
				for shares: Dictionary in AUTO_SPLITS:
					var waves := spread(army, n, shares)
					var score := _score(waves, foe)
					if score > best_score + 0.0001:
						best_score = score
						best = waves
		for k in best.size():
			for w: String in best[k]:
				_plan[k][w] = best[k][w].duplicate()
	_auto_tools()
	_refresh_tool_spins()
	_show_wave(0)


static func spread(army: Dictionary, n: int, shares: Dictionary) -> Array:
	## The army in `n` waves of nearly equal size, each spread over the walls
	## by `shares` (Battle.split()).
	var waves: Array = []
	var left := army.duplicate()
	for k in n:
		var wave := {}
		for unit: String in army:
			var part := int(left[unit]) if k == n - 1 else int(army[unit]) / n
			left[unit] = int(left[unit]) - part
			if part > 0:
				wave[unit] = part
		waves.append(Battle.split(wave, shares, ["left", "right", "front"]))
	return waves


func _score(waves: Array, foe: Dictionary) -> float:
	## Wins out of SAMPLES, less a sliver for each soldier expected to fall.
	var r := _simulate(waves, foe)
	var army := Battle.waves_army(waves)
	var sent := 0
	for unit: String in army:
		sent += int(army[unit])
	return r.chance - 0.001 * r.lost / maxf(1.0, sent)


func _simulate(waves: Array, foe: Dictionary) -> Dictionary:
	var wins := 0
	var lost := 0
	var lost_b := 0
	var kit := {"a": plan_tools(), "b": foe.get("tools", {}), "lead_a": _lead_fx(), "lead_b": foe.get("castellan", {})}
	for k in SAMPLES:
		var result := Battle.siege(Economy.rules, waves, foe.troops, foe.layout, 1000 + k, foe.wall, kit)
		if result.winner == "a":
			wins += 1
		lost += Battle.lost_count(result.a)
		lost_b += Battle.lost_count(result.b)
	return {"chance": float(wins) / SAMPLES, "lost": float(lost) / SAMPLES, "lost_b": float(lost_b) / SAMPLES}


func _defence() -> Dictionary:
	## What defends the target: {"troops", "layout", "wall"}, or {} if unknown.
	if _village != "":
		var vr := Economy.village_rules_for(_village)
		var info := Economy.village_info(_village)
		var state := Economy.village_state(_village)
		return {"troops": vr.defenders(info, state, Economy.now()), "layout": Battle.DEFAULT_LAYOUT,
				"wall": Battle.wall_from_defense(vr.wall_defense(info, state, Economy.now()))}
	if _player != "":
		var seen: Dictionary = Economy.spy_reports.get(_player, {})
		if seen.is_empty():
			return {}
		var layout: Variant = seen.get("layout", Battle.DEFAULT_LAYOUT)
		var tools: Variant = seen.get("tools", {})
		return {"troops": seen.get("troops", {}), "wall": float(seen.get("wall", 1.0)),
				"layout": layout if Battle.check_layout(layout) == "" else Battle.DEFAULT_LAYOUT,
				"tools": Battle.clean_tools(tools) if tools is Dictionary else {},
				"castellan": seen.get("castellan", {}) if seen.get("castellan") is Dictionary else {}}
	var camp := Economy.get_baron(camp_id)
	if camp == null:
		return {}
	var br := Economy.baron_rules.for_camp(camp)
	return {"troops": camp.garrison(br), "layout": Battle.DEFAULT_LAYOUT,
			"wall": Battle.wall_from_defense(br.palisade(camp.level) * camp.walls_factor(Economy.now()))}


# --- Siege tools ------------------------------------------------------------------

func plan_tools() -> Dictionary:
	## The siege tools as planned, {wall: {tool: n}} with empty ones left out.
	return Battle.clean_tools(_tools)


func _tool_placed(tool: String, skip_wall := "") -> int:
	var n := 0
	for w: String in _tools:
		if w != skip_wall:
			n += int(_tools[w].get(tool, 0))
	return n


func _wall_tools(wall: String, skip_tool := "") -> int:
	var n := 0
	for tool: String in _tools.get(wall, {}):
		if tool != skip_tool:
			n += int(_tools[wall][tool])
	return n


func _build_tool_rows() -> void:
	## A row per attack tool in store, a number box per wall it fits.
	for child in _tool_rows.get_children():
		_tool_rows.remove_child(child)
		child.queue_free()
	_tool_spins.clear()
	var rules := Economy.rules
	var stock: Dictionary = Economy.player_castle.tools
	var slots := Economy.tool_slots()
	var have: Array = []
	for tool: String in rules.tools:
		if rules.tool_side(tool) == "attack" and int(stock.get(tool, 0)) > 0:
			have.append(tool)
	_tool_rows.visible = not have.is_empty()
	if have.is_empty():
		_tool_head.text = "Siege tools: none in store. Ladders, mantlets and rams are built in the siege workshop."
		_tool_head.add_theme_color_override("font_color", MenuStyle.MUTED)
		_tool_head.add_theme_font_size_override("font_size", 14)
		return
	_tool_head.text = "Siege tools: up to %d on each wall (keep level %d), used up in the attack" % [slots, Economy.player_castle.keep_level()]
	_tool_head.add_theme_color_override("font_color", MenuStyle.GOLD)
	_tool_head.add_theme_font_size_override("font_size", 16)
	for text in ["", "Left wall", "Front wall", "Right wall", "In store"]:
		_tool_rows.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
	for w: String in Battle.WALLS:
		_tool_spins[w] = {}
	for tool: String in have:
		var name_label := MenuStyle.label(rules.tool_plural(tool), 16, MenuStyle.TEXT)
		name_label.tooltip_text = String(rules.tools[tool].get("description", ""))
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		_tool_rows.add_child(name_label)
		for w: String in Battle.WALLS:
			if not rules.tool_fits(tool, w):
				_tool_rows.add_child(MenuStyle.label("  not here", 14, MenuStyle.MUTED))
				continue
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.step = 1
			spin.custom_minimum_size = Vector2(104, 0)
			var wall := w
			var t := tool
			spin.value_changed.connect(func(v: float) -> void:
				if _quiet:
					return
				if not _tools.has(wall):
					_tools[wall] = {}
				_tools[wall][t] = int(v)
				_refresh_tool_spins()
				_update())
			_tool_rows.add_child(spin)
			_tool_spins[w][tool] = spin
		_tool_rows.add_child(MenuStyle.label(str(int(stock[tool])), 15, MenuStyle.MUTED))
	_refresh_tool_spins()


func _refresh_tool_spins() -> void:
	## Each tool box allowed what's left in store and room on its wall.
	var stock: Dictionary = Economy.player_castle.tools
	var slots := Economy.tool_slots()
	_quiet = true
	for w: String in _tool_spins:
		for tool: String in _tool_spins[w]:
			var spin: SpinBox = _tool_spins[w][tool]
			spin.max_value = maxi(0, mini(int(stock.get(tool, 0)) - _tool_placed(tool, w), slots - _wall_tools(w, tool)))
			spin.value = int(_tools.get(w, {}).get(tool, 0))
	_quiet = false


func _auto_tools() -> void:
	## Hands out the tools in store: rams to the front, then ladders and
	## mantlets in turn to the walls the plan attacks, most soldiers first.
	_tools = {}
	var rules := Economy.rules
	var stock: Dictionary = Economy.player_castle.tools
	var slots := Economy.tool_slots()
	if slots < 1:
		return
	var men := {}
	for wave: Dictionary in plan_waves():
		for w: String in wave:
			for unit: String in wave[w]:
				men[w] = int(men.get(w, 0)) + int(wave[w][unit])
	var walls: Array = men.keys()
	walls.sort_custom(func(x: String, y: String) -> bool: return int(men[x]) > int(men[y]))
	var left := {}
	for tool: String in rules.tools:
		if rules.tool_side(tool) == "attack":
			left[tool] = int(stock.get(tool, 0))
	for tool: String in ["ram", "ladder", "mantlet"]:
		if not left.has(tool):
			continue
		var placed := true
		while int(left[tool]) > 0 and placed:
			placed = false
			for w: String in walls:
				if int(left[tool]) > 0 and rules.tool_fits(tool, w) and _wall_tools(w) < slots:
					if not _tools.has(w):
						_tools[w] = {}
					_tools[w][tool] = int(_tools[w].get(tool, 0)) + 1
					left[tool] = int(left[tool]) - 1
					placed = true


# --- Commander --------------------------------------------------------------------

func _build_commanders() -> void:
	## Every commander, those away greyed out; the first one at home is picked.
	_commander.clear()
	_commander.add_item("None", 0)
	var picked := 0
	var g := Economy.gear_rules
	for c: Dictionary in Economy.player_castle.armoury.commanders:
		var away := float(c.away_until) > Economy.now()
		_commander.add_item("%s (level %d)%s" % [c.name, int(c.level), "  away" if away else ""], int(c.id))
		var index := _commander.item_count - 1
		_commander.set_item_disabled(index, away)
		if not away and picked == 0:
			picked = index
	_commander.select(picked)
	if g == null:
		_commander.disabled = true


func commander_id() -> int:
	return _commander.get_selected_id() if _commander.selected >= 0 else 0


func _lead_fx() -> Dictionary:
	var g := Economy.gear_rules
	var c := g.commander(Economy.player_castle, commander_id()) if g != null else {}
	var fx := g.commander_effects(c) if not c.is_empty() else {}
	return GearRules.with_research(fx, Economy.player_castle.research_effects("attack"))


# --- The other side --------------------------------------------------------------

func _describe_camp(camp: BaronCamp) -> void:
	var br := Economy.baron_rules.for_camp(camp)
	var lines: PackedStringArray = []
	var garrison := camp.garrison(br)
	for unit: String in garrison:
		lines.append("%d %s" % [garrison[unit], Economy.rules.unit_plural(unit)])
	var wall := Battle.wall_from_defense(br.palisade(camp.level) * camp.walls_factor(Economy.now()))
	lines.append("%s: +%d%% defence" % ["Walls" if camp.fortress else "Palisade", roundi((wall - 1.0) * 100.0)])
	lines.append_array(_posts(garrison, Battle.DEFAULT_LAYOUT))
	var loot := Economy.baron_loot(camp.level, camp)
	var parts: PackedStringArray = []
	for r: String in loot:
		parts.append("%d %s" % [loot[r], r])
	lines.append("Loot: " + ", ".join(parts) + Economy.loot_bonus_note())
	_enemy.text = "\n".join(lines)


func _describe_village() -> void:
	var vr := Economy.village_rules_for(_village)
	var info := Economy.village_info(_village)
	var capital: bool = info.get("capital", false)
	var foe := _defence()
	var lines: PackedStringArray = []
	var owner := String(Economy.village_state(_village).get("owner", ""))
	lines.append("Held by %s" % (owner if owner != "" else "the town guard" if capital else "the militia"))
	for unit: String in foe.troops:
		lines.append("%d %s" % [int(foe.troops[unit]), Economy.rules.unit_plural(unit)])
	if foe.troops.is_empty():
		lines.append("Nobody guards it")
	lines.append("%s: +%d%% defence" % ["Walls" if capital else "Palisade", roundi((float(foe.wall) - 1.0) * 100.0)])
	if not foe.troops.is_empty():
		lines.append_array(_posts(foe.troops, Battle.DEFAULT_LAYOUT))
	if capital:
		lines.append("Win it and your castles produce +%d%% more" % roundi(Economy.capital_rules.bonus(int(info.level)) * 100.0))
	lines.append("Holds %d %s; win it and it sends you %d an hour" % [Economy.village_stock(_village), info.resource,
			vr.rate(info, Economy.village_state(_village), Economy.now())])
	_enemy.text = "\n".join(lines)


func _describe_player() -> void:
	var seen: Dictionary = Economy.spy_reports.get(_player, {})
	if seen.is_empty():
		_enemy.text = "You don't know what defends this castle.\nSend a spy first to see their soldiers, walls and how they man them."
		return
	var lines: PackedStringArray = []
	var troops: Dictionary = seen.get("troops", {})
	for unit: String in troops:
		lines.append("%d %s" % [int(troops[unit]), Economy.rules.unit_plural(unit)])
	if troops.is_empty():
		lines.append("No soldiers at home")
	lines.append("Walls: +%d%% defence" % roundi((float(seen.get("wall", 1.0)) - 1.0) * 100.0))
	if not troops.is_empty():
		lines.append_array(_posts(troops, _defence().layout))
	var tools: Dictionary = _defence().tools
	for w: String in Battle.WALLS:
		if tools.has(w):
			lines.append("%s wall: %s" % [w.capitalize(), tools_text(tools[w])])
	var castellan: Dictionary = _defence().castellan
	if not castellan.is_empty():
		lines.append("Castellan: " + Economy.gear_rules.effects_text(castellan))
	lines.append("Seen %s ago" % _clock(Economy.now() - float(seen.get("at", Economy.now()))))
	_enemy.text = "\n".join(lines)


static func tools_text(at: Dictionary) -> String:
	## "2 ladders, 1 battering ram".
	var parts: PackedStringArray = []
	for tool: String in at:
		var n := int(at[tool])
		if n > 0 and Economy.rules.has_tool(tool):
			parts.append("%d %s" % [n, (Economy.rules.tool_name(tool) if n == 1 else Economy.rules.tool_plural(tool)).to_lower()])
	return ", ".join(parts)


static func _posts(troops: Dictionary, layout: Dictionary) -> PackedStringArray:
	## How many defenders stand on each wall and in the courtyard.
	var posts := Battle.split(troops, layout, ["left", "right", "courtyard", "front"])
	var parts: PackedStringArray = []
	for key: String in ["left", "front", "right", "courtyard"]:
		var n := 0
		for unit: String in posts[key]:
			n += int(posts[key][unit])
		parts.append("%s %d" % [key.capitalize(), n])
	return PackedStringArray(["On the walls: " + ", ".join(parts.slice(0, 3)), parts[3] + " in reserve"])


# --- Summary ---------------------------------------------------------------------

func _update() -> void:
	var waves := plan_waves()
	var army := Battle.waves_army(waves) if not waves.is_empty() else {}
	var total := 0
	for unit: String in army:
		total += int(army[unit])
	var foe := _defence()
	var br := Economy.baron_rules
	var lines: PackedStringArray = []
	var home := 0
	for unit: String in Economy.rules.units:
		home += _have(unit)
	_sub(_army_total).text = "%d soldiers at home, %d sent in %s" % [home, total, _waves_text(waves.size())] if total > 0 \
			else "%d soldiers at home" % home
	var defenders := 0
	for unit: String in foe.get("troops", {}):
		defenders += int(foe.troops[unit])
	_send.text = "Send army  ·  %d soldiers" % total if total > 0 else "Send army"
	var chance := -1.0
	if total == 0:
		lines.append("Put some soldiers on the walls to attack.")
		_set_losses(_my_losses, -1, 0)
		_set_losses(_their_losses, -1, 0)
	elif foe.is_empty():
		lines.append("Without a spy's report the odds are unknown.")
		_set_losses(_my_losses, -1, 0)
		_set_losses(_their_losses, -1, 0)
	else:
		var r := _simulate(waves, foe)
		chance = r.chance
		lines.append("%s: %d%% of the battles we tried were won" % [Battle.odds_text(r.chance), roundi(r.chance * 100.0)])
		_set_losses(_my_losses, roundi(r.lost), total)
		_set_losses(_their_losses, roundi(r.lost_b), defenders)
	_ring.chance = chance
	_show_verdict(chance)
	if not foe.is_empty():
		lines.append("Defenders: %d on the walls and in the courtyard, walls +%d%%" % [defenders, roundi((float(foe.wall) - 1.0) * 100.0)])
	var fx := _lead_fx()
	_commander_fx.text = Economy.gear_rules.effects_text(fx) if commander_id() != 0 else ""
	var tools := plan_tools()
	if total > 0 and not tools.is_empty():
		var parts: PackedStringArray = []
		for w: String in Battle.WALLS:
			if tools.has(w):
				parts.append("%s %s" % [w, tools_text(tools[w])])
		lines.append("Siege tools: " + "; ".join(parts))
	var why := ""
	if _village != "":
		var info := Economy.village_info(_village)
		if total > 0:
			var stock := Economy.village_stock(_village)
			var carry := br.carry(army) * (1.0 + float(fx.get("loot", 0.0)))
			lines.append("They can carry %d of the %d %s it holds" % [mini(int(carry), stock), stock, info.resource])
		var march := Economy.village_march_time(_village)
		lines.append("March: %s there, %s back" % [_clock(march), _clock(march)])
		why = Economy.check_village_attack(_village, army, waves, plan_tools(), commander_id())
	elif _player != "":
		if total > 0:
			lines.append("A win carries off up to %d%% of each resource, as much as they can carry (%d)"
					% [roundi(float(Economy.pvp.get("loot_share", 0.25)) * 100.0), int(br.carry(army) * (1.0 + float(fx.get("loot", 0.0))))])
		var march := Economy.march_time_to_player(_player)
		lines.append("March: %s there, %s back" % [_clock(march), _clock(march)])
		why = Economy.check_raid(_player, army, waves, plan_tools(), commander_id())
	else:
		var camp := Economy.get_baron(camp_id)
		if camp == null:
			return
		if total > 0:
			var loot_total := 0
			var loot := Economy.baron_loot(camp.level, camp)
			for r: String in loot:
				loot_total += int(loot[r])
			var carry := br.carry(army) * (1.0 + float(fx.get("loot", 0.0)))
			lines.append("They can carry %d of the camp's %d loot" % [mini(int(carry), loot_total), loot_total]
					+ ("" if carry >= loot_total else " (send more to carry it all)"))
		var march := Economy.march_time_to(camp)
		lines.append("March: %s there, %s back" % [_clock(march), _clock(march)])
		if not camp.is_ready(Economy.now()):
			lines.append("The camp is rebuilding for %s." % _clock(camp.rebuilt_at - Economy.now()))
		why = Economy.check_attack(camp_id, army, waves, plan_tools(), commander_id())
	if why != "" and total > 0 and not lines[lines.size() - 1].begins_with("The camp is rebuilding"):
		lines.append(why)
	_summary.text = "\n".join(lines)
	_send.disabled = why != ""


func _set_losses(label: Label, n: int, of: int) -> void:
	if n < 0:
		label.text = "?"
		label.add_theme_color_override("font_color", MenuStyle.MUTED)
		return
	label.text = "~%d  (%d%%)" % [n, roundi(100.0 * n / maxf(1.0, of))]
	label.add_theme_color_override("font_color", LOSS if n > 0 else WIN)


func _show_verdict(chance: float) -> void:
	## The pill by the title: how the battle looks, in its colour.
	var text := "Odds unknown"
	var colour := MenuStyle.MUTED
	if chance >= 0.0:
		colour = ChanceRing.colour_for(chance)
		text = "Certain" if chance >= 0.85 else "Favourable" if chance >= 0.6 else "Even" if chance > 0.4 \
				else "Risky" if chance > 0.15 else "Hopeless"
	_verdict_label.text = text
	_verdict_label.add_theme_color_override("font_color", colour)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(colour.darkened(0.75), 0.85)
	pill.border_color = Color(colour, 0.7)
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(14)
	pill.content_margin_left = 14
	pill.content_margin_right = 16
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	_verdict.add_theme_stylebox_override("panel", pill)


func _tab_style(b: Button, on: bool) -> void:
	## The wave on show is a gold tab; the others dark.
	if on:
		GameTheme.primary(b)
		b.remove_theme_font_override("font")
		return
	for style in ["normal", "hover", "pressed", "hover_pressed"]:
		b.remove_theme_stylebox_override(style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.remove_theme_color_override(state)
	b.remove_theme_constant_override("outline_size")


static func _waves_text(n: int) -> String:
	return "one wave" if n == 1 else "%d waves" % n


func _send_army() -> void:
	var waves := plan_waves()
	var why := "Put some soldiers on the walls to attack."
	if not waves.is_empty():
		var tools := plan_tools()
		if _village != "":
			why = Economy.send_village_attack(_village, {}, waves, tools, commander_id())
		elif _player != "":
			why = Economy.send_raid(_player, {}, waves, tools, commander_id())
		else:
			why = Economy.send_attack(camp_id, {}, waves, tools, commander_id())
	if why != "":
		_note.text = why
		_note.visible = true
		return
	close_panel()
	Audio.play("march")
	if _village != "":
		EventBus.village_selected.emit("")
	elif _player != "":
		EventBus.player_selected.emit("")
	else:
		EventBus.baron_selected.emit("")


func _small_button(text: String, action: Callable, width := 80) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 32)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
