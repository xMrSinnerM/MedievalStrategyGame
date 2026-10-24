extends PanelContainer
## The academy's window: the three branches of the research tree side by
## side, each study a card under the one it needs, with what it does now
## and at its next level, its cost and time, and why it can't start yet.
## Above them, the study under way with its progress. Opened from the
## academy's panel or the construction list; read-only in someone else's
## castle. Studies run one at a time and can't be hurried with anything
## bought: only time and resources.

const DONE := Color(0.55, 0.9, 0.45)
const LOCKED := Color(1.0, 0.6, 0.45)
const BRANCH_ICONS := {"economy": "gold", "military": "battle", "defence": "defence"}
const CARD_WIDTH := 300.0

var hud: CanvasLayer     ## the castle HUD, for its view

var _level: Label
var _now_title: Label
var _now_bar: ProgressBar
var _now_time: Label
var _cancel: Button
var _columns: HBoxContainer
var _scroll: ScrollContainer
var _cards := {}          ## study -> {panel, name, pips, effect, cost, button, lock}
var _branch_counts := {}  ## branch -> Label
var _built_for: BuildingRules


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.96, 20))
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	head.add_child(Icons.rect("research", 38))
	var title := MenuStyle.title("Academy", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)
	_level = MenuStyle.label("", 15, MenuStyle.MUTED)
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_level)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)

	# The study under way.
	var now := PanelContainer.new()
	now.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	box.add_child(now)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	now.add_child(row)
	_now_title = MenuStyle.label("", 17, MenuStyle.TEXT)
	_now_title.custom_minimum_size = Vector2(330, 0)
	_now_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_now_title)
	_now_bar = ProgressBar.new()
	_now_bar.show_percentage = false
	_now_bar.custom_minimum_size = Vector2(260, 14)
	_now_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_now_bar)
	_now_time = MenuStyle.label("", 15, MenuStyle.GOLD)
	_now_time.custom_minimum_size = Vector2(90, 0)
	_now_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_now_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_now_time)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.tooltip_text = "Stops the study and refunds %d%% of its cost" % int(CastleState.CANCEL_REFUND * 100.0)
	_cancel.pressed.connect(func() -> void: hud.view.cancel_research())
	row.add_child(_cancel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 16)
	_scroll.add_child(_columns)
	Economy.changed.connect(func() -> void:
		if visible:
			refresh())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	visible = true
	refresh()
	_fit.call_deferred()


func close_panel() -> void:
	visible = false


func refresh() -> void:
	var castle: CastleState = hud.view.castle
	if castle == null:
		return
	var rules := castle.rules
	if _built_for != rules:
		_build(rules)
	var academy := castle.academy_level()
	var faster := 100.0 * (1.0 - pow(rules.time_per_academy_level, maxi(academy - 1, 0)))
	_level.text = "Level %d   ·   studies %d%% faster   ·   one study at a time" % [academy, roundi(faster)] if academy > 0 \
		else "Build an academy to start researching"
	for branch: String in rules.branches:
		var done := 0
		var total := 0
		for study: String in rules.studies:
			if String(rules.studies[study].get("branch", "")) == branch:
				done += castle.study_level(study)
				total += rules.study_max_level(study)
		_branch_counts[branch].text = "%d / %d" % [done, total]
	for study: String in _cards:
		_fill_card(castle, study)
	update_progress(Economy.now())


func update_progress(now: float) -> void:
	## Called every frame while open, for a smooth progress bar.
	var castle: CastleState = hud.view.castle
	if castle == null:
		return
	var busy := not castle.studying.is_empty()
	_now_bar.visible = busy
	_now_time.visible = busy
	_cancel.visible = busy and hud.view.editable
	if not busy:
		_now_title.text = "The scholars are idle. Choose a study below." if castle.academy_level() > 0 else "No academy yet."
		return
	var study := String(castle.studying.study)
	var target := int(castle.studying.target)
	_now_title.text = "Researching %s, level %d" % [castle.rules.study_name(study), target]
	var total := castle.rules.study_time(study, target, castle.academy_level())
	var left := castle.research_left(now)
	_now_bar.value = 100.0 * (1.0 - left / maxf(total, 1.0))
	_now_time.text = hud.view.format_time(left)


func _process(_delta: float) -> void:
	if visible:
		update_progress(Economy.now())


func _fit() -> void:
	## Lets the tree scroll when the screen is too short for it.
	var room := get_viewport().get_visible_rect().size.y - 230.0
	var want := _columns.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(want.x, minf(want.y, room))
	reset_size()
	position = (get_viewport().get_visible_rect().size - size) * 0.5


# --- The tree ------------------------------------------------------------------

func _build(rules: BuildingRules) -> void:
	_built_for = rules
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	_cards.clear()
	for branch: String in rules.branches:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		_columns.add_child(column)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		column.add_child(head)
		head.add_child(Icons.rect(BRANCH_ICONS.get(branch, "research"), 28))
		var heading := MenuStyle.title(String(rules.branches[branch]), 20)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(heading)
		var count := MenuStyle.label("", 14, MenuStyle.MUTED)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(count)
		_branch_counts[branch] = count
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		column.add_child(gap)
		var first := true
		for study: String in rules.studies:
			if String(rules.studies[study].get("branch", "")) != branch:
				continue
			if not first:
				column.add_child(_link())
			first = false
			column.add_child(_card(rules, study))


func _link() -> Control:
	## The gold line from a study down to the one that needs it.
	var holder := CenterContainer.new()
	var line := ColorRect.new()
	line.color = GameTheme.RIM_DIM
	line.custom_minimum_size = Vector2(3, 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)
	return holder


func _card(rules: BuildingRules, study: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := MenuStyle.label(rules.study_name(study), 17, MenuStyle.TEXT)
	title.add_theme_font_override("font", GameTheme.BOLD_FONT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pips)
	for k in rules.study_max_level(study):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(10, 10)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	var effect := MenuStyle.label("", 14, MenuStyle.TEXT)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.custom_minimum_size = Vector2(CARD_WIDTH - 20, 0)
	box.add_child(effect)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	box.add_child(bottom)
	var cost := RichTextLabel.new()
	cost.bbcode_enabled = true
	cost.fit_content = true
	cost.scroll_active = false
	cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_theme_font_size_override("normal_font_size", 13)
	cost.add_theme_color_override("default_color", MenuStyle.MUTED)
	bottom.add_child(cost)
	var button := GameTheme.primary(Button.new())
	button.text = "Research"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(func() -> void: hud.view.research(study))
	bottom.add_child(button)
	panel.tooltip_text = String(rules.studies[study].get("description", ""))
	_cards[study] = {"panel": panel, "name": title, "pips": pips, "effect": effect, "cost": cost, "button": button}
	return panel


func _fill_card(castle: CastleState, study: String) -> void:
	var rules := castle.rules
	var card: Dictionary = _cards[study]
	var level := castle.study_level(study)
	var top := rules.study_max_level(study)
	var busy: bool = not castle.studying.is_empty() and castle.studying.study == study
	var why := castle.check_research(study)
	var locked := why.begins_with("Needs") or why == "Build an academy first"
	var rim := GameTheme.RIM_BRIGHT if busy else (GameTheme.RIM if level > 0 else GameTheme.RIM_DIM)
	var bg := Color(0.12, 0.095, 0.06, 0.95) if busy else Color(0.075, 0.063, 0.05, 0.92)
	var style := GameTheme.card_box(bg, rim)
	style.set_content_margin_all(9)
	if busy:
		style.shadow_color = Color(1.0, 0.75, 0.3, 0.25)
		style.shadow_size = 6
		style.shadow_offset = Vector2.ZERO
	card.panel.add_theme_stylebox_override("panel", style)
	card.panel.modulate = Color(1, 1, 1, 0.62) if locked and level == 0 else Color.WHITE
	card.name.add_theme_color_override("font_color", MenuStyle.GOLD if level > 0 else MenuStyle.TEXT)
	var pips: Array = card.pips.get_children()
	for k in pips.size():
		var pip := StyleBoxFlat.new()
		pip.set_corner_radius_all(5)
		pip.border_color = GameTheme.RIM
		pip.set_border_width_all(1)
		pip.bg_color = GameTheme.GOLD if k < level else (Color(0.55, 0.42, 0.2) if busy and k == level else Color(0.1, 0.08, 0.06))
		pips[k].add_theme_stylebox_override("panel", pip)
	var now := effect_text(rules.study_effects(study), level)
	if level >= top:
		card.effect.text = now
	elif level == 0:
		card.effect.text = effect_text(rules.study_effects(study), 1)
	else:
		card.effect.text = "%s  →  %s" % [now, effect_text(rules.study_effects(study), level + 1)]
	var editable: bool = hud.view.editable
	if level >= top:
		card.cost.text = "[color=#9fd18a]Fully researched[/color]"
	elif busy:
		card.cost.text = "[color=#ffd98a]Researching level %d…[/color]" % (level + 1)
	elif locked:
		card.cost.text = "[color=#ff9a7a]%s[/color]" % why
	else:
		card.cost.text = "%s  ·  %s" % [_cost_text(castle, rules.study_cost(study, level + 1)), hud.view.format_time(castle.research_time(study))]
	card.button.visible = editable and level < top and not busy and not locked
	card.button.disabled = why != ""
	card.button.text = "Research" if level == 0 else "Level %d" % (level + 1)
	card.button.tooltip_text = why


func _cost_text(castle: CastleState, cost: Dictionary) -> String:
	## "60 wood, 30 stone", with what the castle lacks in red.
	var parts: PackedStringArray = []
	for r: String in cost:
		var part := "%d %s" % [int(cost[r]), r]
		if castle.resources.get(r, 0.0) + 0.0001 < cost[r]:
			part = "[color=#ff8a6a]%s[/color]" % part
		parts.append(part)
	return ", ".join(parts)


static func effect_text(effects: Dictionary, level: int) -> String:
	## What a study does at `level`, in words: "+8% wood".
	var parts: PackedStringArray = []
	for effect: String in effects:
		var n := float(effects[effect]) * level
		var pct := roundi(absf(n) * 100.0)
		match effect:
			"wood", "stone", "food", "gold":
				parts.append("+%d%% %s" % [pct, effect])
			"storage":
				parts.append("+%d%% storage" % pct)
			"recruit_time":
				parts.append("training %d%% faster" % pct)
			"upkeep":
				parts.append("soldiers eat %d%% less" % pct)
			"craft_time":
				parts.append("siege tools %d%% faster" % pct)
			"march_time":
				parts.append("marches %d%% faster" % pct)
			"wall_attack":
				parts.append("+%d%% attack at walls" % pct)
			"yard_attack":
				parts.append("+%d%% in courtyard" % pct)
			"wall_defence":
				parts.append("+%d%% defence on walls" % pct)
			"yard_defence":
				parts.append("+%d%% in courtyard" % pct)
			"wall_bonus":
				parts.append("+%d%% wall strength" % pct)
			"hidden":
				parts.append("%d%% of storage hidden" % pct)
			"heal":
				parts.append("%d%% of fallen defenders healed" % pct)
			"defence_slots":
				parts.append("+%d defence tool%s per wall" % [roundi(n), "" if roundi(n) == 1 else "s"])
			_:
				parts.append("%s %+d%%" % [effect, roundi(n * 100.0)])
	return ", ".join(parts)
