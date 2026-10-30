extends PanelContainer
## The skills screen (a tab of the Army window): pick a commander, then
## spend the skill points they earn by levelling up in three branches
## (Siegecraft, Warfare, Plunder). Each skill needs a commander level and
## the skill above it; retraining hands every point back for gold
## (GearRules skills).

const LEARNED := Color(0.55, 0.9, 0.45)
const READY := Color(1.0, 0.85, 0.45)
const LOCKED := Color(0.5, 0.45, 0.38)
const BRANCH_ICONS := {"siegecraft": "defence", "warfare": "battle", "plunder": "rewards"}

var _picker: HBoxContainer
var _who: Label
var _points: Label
var _retrain: Button
var _branches: HBoxContainer
var _status: Label
var _chosen := 1               ## the commander shown
var _signature := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1060, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Skills", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	set_meta("window_close", close)
	var help := MenuStyle.label("Commanders earn a skill point each time they rise a level. Spend it here: each skill needs "
			+ "the commander's level and the skill above it in its branch. Skills add to what a commander's gear does in "
			+ "every attack they lead. Changed your mind? Retraining hands every point back, for gold.", 14, MenuStyle.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(1000, 0)
	set_meta("window_help", help)
	box.add_child(help)
	_picker = HBoxContainer.new()
	_picker.add_theme_constant_override("separation", 6)
	box.add_child(_picker)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	box.add_child(line)
	var who_box := VBoxContainer.new()
	who_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(who_box)
	_who = MenuStyle.label("", 20, MenuStyle.GOLD)
	_who.add_theme_font_override("font", GameTheme.TITLE_FONT)
	who_box.add_child(_who)
	_points = MenuStyle.label("", 15, MenuStyle.TEXT)
	who_box.add_child(_points)
	_retrain = Button.new()
	_retrain.focus_mode = Control.FOCUS_NONE
	_retrain.add_theme_font_size_override("font_size", 14)
	_retrain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_retrain.pressed.connect(func() -> void:
		var c := Economy.gear_rules.commander(Economy.player_castle, _chosen)
		_tell(Economy.retrain_commander(_chosen), "%s has forgotten their skills. Spend the points again." % c.get("name", "")))
	line.add_child(_retrain)
	_branches = HBoxContainer.new()
	_branches.add_theme_constant_override("separation", 12)
	box.add_child(_branches)
	_status = MenuStyle.label("", 15, MenuStyle.GOLD)
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_refresh())


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	_status.text = ""
	_signature = ""
	visible = true
	_refresh()


func close_panel() -> void:
	visible = false


func show_commander(id: int) -> void:
	_chosen = id
	_signature = ""
	_refresh()


func _refresh() -> void:
	var castle := Economy.player_castle
	var g := Economy.gear_rules
	if castle == null or g == null:
		return
	var signature := JSON.stringify(castle.armoury.commanders) + str(_chosen) + str(int(castle.resources.get("gold", 0.0)) / 50)
	if signature == _signature:
		return
	_signature = signature
	for child in _picker.get_children():
		_picker.remove_child(child)
		child.queue_free()
	for child in _branches.get_children():
		_branches.remove_child(child)
		child.queue_free()
	var list: Array = castle.armoury.commanders
	if list.is_empty():
		_who.text = "No commanders yet"
		_points.text = "Your first commander joins when you build up your keep."
		_retrain.visible = false
		return
	if g.commander(castle, _chosen).is_empty():
		_chosen = int(list[0].id)
	for c: Dictionary in list:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = int(c.id) == _chosen
		var spare := GearRules.skill_points(c)
		b.text = "%s  (level %d%s)" % [c.name, int(c.level), ", %d to spend" % spare if spare > 0 else ""]
		b.add_theme_font_size_override("font_size", 14)
		if spare > 0:
			b.add_theme_color_override("font_color", READY)
		var id := int(c.id)
		b.pressed.connect(func() -> void: show_commander(id))
		_picker.add_child(b)
	var c := g.commander(castle, _chosen)
	var spare := GearRules.skill_points(c)
	_who.text = "%s, level %d" % [c.name, int(c.level)]
	var next := g.xp_to_next(c)
	_points.text = "%s.   %s" % [
		"%d skill point%s to spend" % [spare, "" if spare == 1 else "s"] if spare > 0 else "No skill points to spend",
		"Next point at level %d (%d xp to go)" % [int(c.level) + 1, next] if next > 0 else "Highest level reached"]
	_retrain.visible = not c.get("skills", {}).is_empty()
	_retrain.text = "Retrain for %d gold" % int(g.retrain_cost(c).gold)
	_retrain.disabled = g.check_retrain(castle, _chosen) != ""
	_retrain.tooltip_text = "Forget every skill and get the points back."
	for branch: Dictionary in g.branches:
		_branches.add_child(_branch(castle, g, c, branch))


func _branch(castle: CastleState, g: GearRules, c: Dictionary, branch: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(Icons.rect(String(BRANCH_ICONS.get(String(branch.id), "battle")), 30))
	var names := VBoxContainer.new()
	head.add_child(names)
	var title := MenuStyle.label(String(branch.name), 20, MenuStyle.GOLD)
	title.add_theme_font_override("font", GameTheme.TITLE_FONT)
	names.add_child(title)
	names.add_child(MenuStyle.label(String(branch.text), 13, MenuStyle.MUTED))
	var first := true
	for k: Dictionary in g.skills:
		if k.branch != branch.id:
			continue
		if not first:
			var arrow := MenuStyle.label("▼", 14, LOCKED)
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(arrow)
		first = false
		box.add_child(_skill(castle, g, c, k))
	return panel


func _skill(castle: CastleState, g: GearRules, c: Dictionary, k: Dictionary) -> Control:
	var rank := GearRules.skill_rank(c, k.id)
	var top := int(k.max)
	var why := g.check_learn(castle, int(c.id), k.id)
	var locked := rank == 0 and (int(c.level) < int(k.needs) or (String(k.after) != "" and GearRules.skill_rank(c, k.after) == 0))
	var card := PanelContainer.new()
	var style: StyleBoxFlat = MenuStyle.panel(0.35, 8)
	if rank > 0:
		style.border_color = LEARNED.darkened(0.2)
	elif why == "":
		style.border_color = READY
	style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := MenuStyle.label(String(k.name), 16, LOCKED if locked else (LEARNED if rank > 0 else MenuStyle.TEXT))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(MenuStyle.label("●".repeat(rank) + "○".repeat(top - rank), 15, LEARNED if rank > 0 else LOCKED))
	var text := MenuStyle.label(g.skill_text(k, maxi(rank, 1)), 13, MenuStyle.MUTED if locked else MenuStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(300, 0)
	box.add_child(text)
	var row := HBoxContainer.new()
	box.add_child(row)
	var need := MenuStyle.label("Needs level %d%s" % [int(k.needs), ", " + String(g.skill(k.after).name) if String(k.after) != "" else ""],
			12, LOCKED if locked else MenuStyle.MUTED)
	need.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	need.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(need)
	if rank < top:
		var learn := Button.new()
		learn.focus_mode = Control.FOCUS_NONE
		learn.text = "Learn" if rank == 0 else "Rank %d" % (rank + 1)
		learn.add_theme_font_size_override("font_size", 13)
		learn.disabled = why != ""
		learn.tooltip_text = why if why != "" else "Next rank: " + g.skill_text(k, rank + 1)
		if why == "":
			GameTheme.primary(learn)
		var id := String(k.id)
		learn.pressed.connect(func() -> void:
			_tell(Economy.learn_skill(int(c.id), id), "%s learned %s." % [c.name, k.name]))
		row.add_child(learn)
	else:
		row.add_child(MenuStyle.label("Mastered", 13, LEARNED))
	return card


func _tell(why: String, done: String) -> void:
	if why != "":
		Audio.play("denied")
	_status.text = why if why != "" else done
	_signature = ""
	_refresh()
