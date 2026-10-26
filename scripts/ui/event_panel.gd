extends PanelContainer
## The event screen (V on the world map, online): the week's timed events,
## then a tab for each event with camps. Baron Invasion: its reward tiers with
## your points, and the players with the most points in it. Ember Horde: the
## Trophy Market, its ranking and your ranked prize (scripts/ui/horde_section.gd).
## Rewards are earned only by playing: beat invader camps for points, then
## claim each tier in order until the next invasion.

const ME := Color(1.0, 0.85, 0.45)
const DONE := Color(0.55, 0.9, 0.45)

var _calendar: Label
var _status: Label
var _rewards: GridContainer
var _board: GridContainer
var _rank: Label
var _invasion: VBoxContainer
var _horde: VBoxContainer
var _tabs: Array[Button] = []
var _timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(720, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Events", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_calendar = MenuStyle.label("", 15, MenuStyle.TEXT)
	box.add_child(_calendar)
	box.add_child(HSeparator.new())
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	box.add_child(tab_row)
	for i in 2:
		var tab := Button.new()
		tab.text = ["Baron Invasion", "Ember Horde"][i]
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(180, 32)
		tab.add_theme_font_size_override("font_size", 16)
		tab.pressed.connect(show_tab.bind(i))
		tab_row.add_child(tab)
		_tabs.append(tab)
	_invasion = VBoxContainer.new()
	_invasion.add_theme_constant_override("separation", 10)
	box.add_child(_invasion)
	_horde = preload("res://scripts/ui/horde_section.gd").new()
	_horde.visible = false
	box.add_child(_horde)
	var inv := _invasion
	inv.add_child(MenuStyle.label("Baron Invasion rewards", 19, MenuStyle.GOLD))
	_status = MenuStyle.label("", 15, MenuStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv.add_child(_status)
	_rewards = GridContainer.new()
	_rewards.columns = 3
	_rewards.add_theme_constant_override("h_separation", 24)
	_rewards.add_theme_constant_override("v_separation", 4)
	inv.add_child(_rewards)
	inv.add_child(HSeparator.new())
	inv.add_child(MenuStyle.label("Most event points", 19, MenuStyle.GOLD))
	_board = GridContainer.new()
	_board.columns = 3
	_board.add_theme_constant_override("h_separation", 28)
	_board.add_theme_constant_override("v_separation", 4)
	inv.add_child(_board)
	_rank = MenuStyle.label("", 16, ME)
	_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv.add_child(_rank)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(MenuStyle.button("Refresh", _ask_boards, 180.0))
	buttons.add_child(MenuStyle.button("Close", close_panel, 180.0))
	box.add_child(buttons)
	Economy.event_board_changed.connect(_fill_board)
	Economy.changed.connect(func() -> void:
		if visible:
			_fill_rewards())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_V and not get_tree().paused and Economy.online:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_fill_calendar()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	_fill_calendar()
	_fill_rewards()
	_fill_board()
	if Economy.event_board.is_empty():
		_rank.text = "Asking the server..."
	_ask_boards()
	# The horde's tab while it rides, or while its prizes wait and no invasion is on.
	var horde := not Economy.horde_event().is_empty() or (Economy.invasion().is_empty() and Economy.my_horde_points() > 0
			and not Economy.horde_prize_taken())
	show_tab(1 if horde else 0)
	visible = true


func show_tab(i: int) -> void:
	## 0: the Baron Invasion, 1: the Ember Horde.
	for k in _tabs.size():
		_tabs[k].button_pressed = k == i
	_invasion.visible = i == 0
	_horde.visible = i == 1
	if i == 1:
		_horde.fill()
	_recenter.call_deferred()


func _recenter() -> void:
	## The tabs differ in size: shrink to fit and stay in the middle of the screen.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _ask_boards() -> void:
	Economy.ask_event_board()
	Economy.ask_horde_board()


func close_panel() -> void:
	visible = false


func _fill_calendar() -> void:
	var t := Economy.now()
	var lines: PackedStringArray = []
	var on := Economy.events_on()
	for e: Dictionary in on:
		lines.append("%s: on now, ends in %s. %s" % [e.name, _days(float(e.end) - t), e.description])
	for e: Dictionary in Economy.events.get("upcoming", []):
		if on.any(func(o: Dictionary) -> bool: return o.id == e.id):
			continue
		lines.append("%s: starts in %s. %s" % [e.name, _days(float(e.start) - t), e.description])
	_calendar.text = "\n".join(lines) if not lines.is_empty() else "No events on the calendar."


func _fill_rewards() -> void:
	for child in _rewards.get_children():
		_rewards.remove_child(child)
		child.queue_free()
	var last := Economy.last_invasion()
	var points := Economy.my_event_points()
	if last.is_empty():
		_status.text = "No Baron Invasion on the calendar."
		return
	var t := Economy.now()
	if t < float(last.end):
		_status.text = "On now, ends in %s. Beat the invader camps near your castle for points: each win gives 10 per level of the camp. Your points: %d" % [_days(float(last.end) - t), points]
	else:
		_status.text = "The last invasion is over. Claim what you earned before the next one starts. Your points: %d" % points
	_status.text += "\nResources go into your storage; what doesn't fit is lost, so claim them when there's room."
	var claimed := Economy.event_claimed if points > 0 else 0
	var tiers := Economy.reward_tiers()
	for i in tiers.size():
		var tier: Dictionary = tiers[i]
		var need := int(tier.points)
		var color := DONE if i < claimed else (MenuStyle.TEXT if points >= need else MenuStyle.MUTED)
		_rewards.add_child(MenuStyle.label("%d points" % need, 16, color))
		var what := MenuStyle.label(Economy.reward_text(tier), 16, color)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rewards.add_child(what)
		if i < claimed:
			_rewards.add_child(MenuStyle.label("Claimed", 15, DONE))
		elif i == claimed and points >= need:
			var claim := GameTheme.primary(Button.new())
			claim.text = "Claim"
			claim.focus_mode = Control.FOCUS_NONE
			claim.custom_minimum_size = Vector2(110, 30)
			claim.add_theme_font_size_override("font_size", 15)
			claim.pressed.connect(func() -> void:
				claim.disabled = true
				Audio.play("reward")
				Economy.claim_reward(i))
			_rewards.add_child(claim)
		else:
			_rewards.add_child(MenuStyle.label("%d to go" % maxi(0, need - points) if points < need else "", 15, MenuStyle.MUTED))


func _fill_board() -> void:
	for child in _board.get_children():
		_board.remove_child(child)
		child.queue_free()
	var board: Dictionary = Economy.event_board
	var me: Variant = board.get("me")
	var my_name := String(me.get("name", "")) if me is Dictionary else ""
	var rank := 0
	for p: Dictionary in board.get("players", []):
		rank += 1
		if rank > 10:
			break
		var color := ME if String(p.name) == my_name else MenuStyle.TEXT
		_board.add_child(_cell(str(rank), color, true))
		var tag := String(p.get("tag", ""))
		var who := _cell(("[%s] " % tag if tag != "" else "") + String(p.name), color, false)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.add_child(who)
		_board.add_child(_cell(str(int(p.get("points", 0))), color, true))
	if board.is_empty():
		return
	if me is Dictionary:
		_rank.text = "You are #%d of %d with %d points." % [int(board.get("rank", 0)), int(board.get("total", 0)), int(me.get("points", 0))]
	elif rank == 0:
		_rank.text = "Nobody has event points yet."
	else:
		_rank.text = "%d players have event points. Beat invader camps to join them." % int(board.get("total", 0))


static func _cell(text: String, color: Color, right: bool) -> Label:
	var l := MenuStyle.label(text, 16, color)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]
