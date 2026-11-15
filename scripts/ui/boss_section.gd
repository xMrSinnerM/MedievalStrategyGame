extends VBoxContainer
## The Warlord's Stronghold on the event screen (online, for alliances): the
## host your alliance shares and how far it is worn down, the chest for each
## time the stronghold falls, your own rewards for the defenders you slew, and
## who in your alliance slew how many. Everything here is earned by storming
## the stronghold; nothing is bought with money.

const ME := Color(1.0, 0.85, 0.45)
const DONE := Color(0.55, 0.9, 0.45)
const ROWS_SHOWN := 10

var _status: Label
var _host: Label
var _bar: ProgressBar
var _chests: GridContainer
var _rewards: GridContainer
var _board: GridContainer
var _note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_status = MenuStyle.label("", 15, MenuStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(900, 0)
	add_child(_status)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(MenuStyle.label("The warlord's host", 19, MenuStyle.GOLD))
	_host = MenuStyle.label("", 15, MenuStyle.TEXT)
	left.add_child(_host)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 18)
	_bar.show_percentage = false
	left.add_child(_bar)
	left.add_child(MenuStyle.label("A chest each time the stronghold falls", 17, MenuStyle.GOLD))
	_chests = GridContainer.new()
	_chests.columns = 3
	_chests.add_theme_constant_override("h_separation", 18)
	_chests.add_theme_constant_override("v_separation", 4)
	left.add_child(_chests)
	left.add_child(MenuStyle.label("Your own rewards", 17, MenuStyle.GOLD))
	_rewards = GridContainer.new()
	_rewards.columns = 3
	_rewards.add_theme_constant_override("h_separation", 18)
	_rewards.add_theme_constant_override("v_separation", 4)
	left.add_child(_rewards)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(280, 0)
	columns.add_child(right)
	right.add_child(MenuStyle.label("Your alliance's raiders", 19, MenuStyle.GOLD))
	_board = GridContainer.new()
	_board.columns = 3
	_board.add_theme_constant_override("h_separation", 20)
	_board.add_theme_constant_override("v_separation", 3)
	right.add_child(_board)
	_note = MenuStyle.label("", 15, ME)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(280, 0)
	right.add_child(_note)
	Economy.boss_board_changed.connect(fill)
	Economy.changed.connect(func() -> void:
		if is_visible_in_tree():
			fill())


func fill() -> void:
	_fill_status()
	_fill_host()
	_fill_chests()
	_fill_rewards()
	_fill_board()


func _fill_status() -> void:
	var last := Economy.last_boss()
	if last.is_empty():
		_status.text = "No stronghold on the calendar."
		return
	var t := Economy.now()
	var slain := Economy.my_boss_slain()
	if t < float(last.end):
		_status.text = "Standing now, abandoned in %s. Warlord Garrak's stronghold stands near the castle of everyone in your alliance. Every defender slain there, win or lose, wears down his host, which your whole alliance shares. It never grows stronger; after a win its garrison rallies for a few minutes. Slain by you: %d" % [
				_days(float(last.end) - t), slain]
	else:
		_status.text = "The stronghold is abandoned. Claim your chests and rewards before the warlord returns in %s. Slain by you: %d" % [
				_days(float(last.start) + 7 * 86400.0 - t), slain]


func _fill_host() -> void:
	var host := Economy.boss_host()
	if host.is_empty():
		_bar.value = 0.0
		_host.text = "Asking the server..." if Economy.boss_board.is_empty() else "Your alliance has no host to fight this time."
		return
	var falls := int(host.get("falls", 0))
	var most := int(host.get("max_falls", 0))
	if falls >= most:
		_bar.max_value = 1.0
		_bar.value = 1.0
		_host.text = "The warlord is beaten: the stronghold fell all %d times. Slain by your alliance: %d" % [most, int(host.get("slain", 0))]
		return
	_bar.max_value = maxf(1.0, float(host.get("size", 1)))
	_bar.value = float(host.get("down", 0))
	_host.text = "%d of %d slain    Fallen %d of %d times    %d members count" % [int(host.get("down", 0)), int(host.get("size", 0)),
			falls, most, int(host.get("members", 0))]


func _fill_chests() -> void:
	_clear(_chests)
	var rules_now := Economy.boss_rules()
	var taken := Economy.boss_chests_taken()
	var fallen := int(Economy.boss_host().get("falls", 0))
	var chests: Array = rules_now.get("falls", [])
	for i in chests.size():
		var color := DONE if i < taken else (MenuStyle.TEXT if i < fallen else MenuStyle.MUTED)
		_chests.add_child(MenuStyle.label("Fall %d" % (i + 1), 15, color))
		var what := IconLabel.make(HordeSection.item_text(chests[i]), 15, color)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_chests.add_child(what)
		if i < taken:
			_chests.add_child(MenuStyle.label("Claimed", 14, DONE))
		elif i == taken and i < fallen:
			var why := Economy.check_boss_chest()
			var claim := _button("Claim", why == "")
			claim.tooltip_text = why
			claim.pressed.connect(func() -> void:
				claim.disabled = true
				Audio.play("reward")
				Economy.claim_boss_chest())
			_chests.add_child(claim)
		else:
			_chests.add_child(MenuStyle.label("", 14, MenuStyle.MUTED))


func _fill_rewards() -> void:
	_clear(_rewards)
	var slain := Economy.my_boss_slain()
	var claimed := Economy.boss_claimed()
	var tiers: Array = Economy.boss_rules().get("rewards", [])
	for i in tiers.size():
		var tier: Dictionary = tiers[i]
		var need := int(tier.points)
		var color := DONE if i < claimed else (MenuStyle.TEXT if slain >= need else MenuStyle.MUTED)
		_rewards.add_child(MenuStyle.label("%d slain" % need, 15, color))
		var what := IconLabel.make(Economy.reward_text(tier), 15, color)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rewards.add_child(what)
		if i < claimed:
			_rewards.add_child(MenuStyle.label("Claimed", 14, DONE))
		elif i == claimed and slain >= need:
			var claim := _button("Claim", true)
			claim.pressed.connect(func() -> void:
				claim.disabled = true
				Audio.play("reward")
				Economy.claim_boss_reward(i))
			_rewards.add_child(claim)
		else:
			_rewards.add_child(MenuStyle.label("%d to go" % maxi(0, need - slain) if slain < need else "", 14, MenuStyle.MUTED))


func _fill_board() -> void:
	_clear(_board)
	var board: Dictionary = Economy.boss_board
	var me: Variant = board.get("me")
	var my_name := String(me.get("name", "")) if me is Dictionary else ""
	var rank := 0
	for p: Dictionary in board.get("players", []):
		rank += 1
		if rank > ROWS_SHOWN:
			break
		var color := ME if String(p.name) == my_name else MenuStyle.TEXT
		_board.add_child(_cell(str(rank), color, true))
		var who := _cell(String(p.name), color, false)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.add_child(who)
		_board.add_child(_cell(str(int(p.get("points", 0))), color, true))
	if board.is_empty():
		_note.text = "Asking the server..."
	elif not bool(board.get("in_alliance", false)):
		_note.text = "The stronghold is an alliance raid. Join or found an alliance (J) to storm the next one."
	elif not bool(board.get("takes_part", false)):
		_note.text = "You joined your alliance after this stronghold rose. You storm the next one with them."
	elif rank == 0:
		_note.text = "Nobody in your alliance has slain a defender yet. Lead the way."
	else:
		_note.text = "Slay %d defenders yourself to share in the chests." % int(Economy.boss_rules().get("min_damage", 0))


static func _button(text: String, ready: bool) -> Button:
	var b := GameTheme.primary(Button.new()) if ready else Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 28)
	b.add_theme_font_size_override("font_size", 14)
	b.disabled = not ready
	return b


static func _clear(grid: Control) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


static func _cell(text: String, color: Color, right: bool) -> Label:
	var l := MenuStyle.label(text, 15, color)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]
