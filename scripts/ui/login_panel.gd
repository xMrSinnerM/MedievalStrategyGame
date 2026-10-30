extends PanelContainer
## The Royal Gift screen (a tab of the quest window, opened by itself when
## today's gift is waiting): the week of gifts, which are taken, which is
## today's and what comes next, the streak and the button to take it
## (LoginRewards).

const DONE := Color(0.55, 0.9, 0.45)
const READY := Color(1.0, 0.85, 0.45)
const CARD := Vector2(136, 196)

var _line: Label
var _days: HBoxContainer
var _streak: Label
var _claim: Button
var _next: Label
var _status: Label
var _signature := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1000, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Royal Gift", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)

	var help := MenuStyle.label("", 14, MenuStyle.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	set_meta("window_help", help)
	box.add_child(help)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	box.add_child(top)
	var gift := Icons.rect("gift", 56)
	gift.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(gift)
	_line = MenuStyle.label("", 17, MenuStyle.TEXT)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_line)
	_days = HBoxContainer.new()
	_days.add_theme_constant_override("separation", 8)
	_days.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_days)
	_streak = MenuStyle.label("", 16, MenuStyle.GOLD)
	_streak.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_streak)
	_claim = Button.new()
	_claim.text = "Take today's gift"
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.custom_minimum_size = Vector2(260, 44)
	_claim.add_theme_font_size_override("font_size", 18)
	_claim.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_claim.pressed.connect(_on_claim)
	GameTheme.primary(_claim)
	box.add_child(_claim)
	_next = MenuStyle.label("", 15, MenuStyle.MUTED)
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_next)
	_status = MenuStyle.label("", 15, DONE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_fill())


func _process(_delta: float) -> void:
	if visible:
		_fill()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	_status.text = ""
	_signature = ""
	_fill()
	visible = true


func close_panel() -> void:
	visible = false


func _on_claim() -> void:
	var gifts := Economy.login_rewards
	var reward := gifts.today_reward(Economy.player_castle, Economy.now())
	var why := Economy.claim_login()
	Audio.play("reward" if why == "" else "denied")
	_status.add_theme_color_override("font_color", DONE if why == "" else Color(1.0, 0.55, 0.4))
	_status.text = "Received: %s" % Economy.reward_text(reward) if why == "" else why
	_signature = ""
	_fill()


func _fill() -> void:
	var gifts := Economy.login_rewards
	var castle := Economy.player_castle
	if gifts == null or castle == null:
		return
	var now := Economy.now()
	var left := float((LoginRewards.day_of(now) + 1) * LoginRewards.DAY) - now
	var taken := LoginRewards.taken_today(castle, now)
	_next.text = ("Next gift in %s. Come back then to keep your streak." if taken else "Today's gift waits until midnight (UTC), %s from now.") % _hours(left)
	# Rebuild only when something shown has changed, so the cards don't flicker every tick.
	var sig := str([castle.login, taken, castle.keep_level(), LoginRewards.day_of(now)])
	if sig == _signature:
		return
	_signature = sig
	var help: Label = get_meta("window_help")
	help.text = "A gift every day you come back, once a day (the day turns at midnight UTC). The gifts grow over a week, day 7 brings soldiers too, and then the week starts again. Every full week in a row adds %d%% to the gifts, up to %d%%. Miss a day and you start again at day 1. Bigger keeps get bigger gifts. Gifts are given in full, even past your storage." % [roundi(gifts.week_bonus * 100), roundi(gifts.week_bonus * gifts.max_weeks * 100)]
	help.visible = not has_meta("in_window")
	_line.text = "%s: \"%s\"" % [gifts.giver, gifts.line]
	var streak := LoginRewards.next_streak(castle, now)
	var today := gifts.week_day(streak)
	var weeks := gifts.weeks_kept(streak)
	for child in _days.get_children():
		_days.remove_child(child)
		child.queue_free()
	for d in gifts.days.size():
		var state := "taken" if d < today or (d == today and taken) else ("today" if d == today else "later")
		_days.add_child(_day_card(d, gifts.reward(d, castle.keep_level(), weeks), state))
	var shown_streak := LoginRewards.current_streak(castle, now)
	var parts: PackedStringArray = ["Days in a row: %d" % shown_streak]
	if weeks > 0:
		parts.append("full weeks kept: %d (+%d%% to every gift)" % [weeks, roundi(gifts.week_bonus * weeks * 100)])
	parts.append("days in all: %d" % int(castle.login.total))
	_streak.text = ",  ".join(parts)
	_claim.visible = not taken
	_claim.disabled = gifts.check_claim(castle, now) != ""


func _day_card(day: int, reward: Dictionary, state: String) -> Control:
	## One day of the week: its number, what it gives, and whether it's taken,
	## today's or still to come.
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD
	var style := GameTheme.card_box(Color(0.09, 0.075, 0.055, 0.95), GameTheme.RIM_DIM)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if state == "today":
		style.border_color = GameTheme.RIM_BRIGHT
		style.set_border_width_all(3)
		style.bg_color = Color(0.2, 0.14, 0.06, 0.95)
		style.shadow_color = Color(1.0, 0.75, 0.3, 0.3)
		style.shadow_size = 8
	elif state == "taken":
		style.bg_color = Color(0.06, 0.08, 0.05, 0.9)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var big := day == Economy.login_rewards.days.size() - 1
	var name := MenuStyle.label("Day %d" % (day + 1), 17, READY if state == "today" else (MenuStyle.GOLD if big else MenuStyle.TEXT))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override("font", GameTheme.TITLE_FONT)
	box.add_child(name)
	var picture := Icons.rect("box_ticked" if state == "taken" else ("rewards" if big else "gift"), 40)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(picture)
	for r: String in reward.get("resources", {}):
		box.add_child(_amount(r, "%d" % int(reward.resources[r])))
	var troops: Dictionary = reward.get("troops", {})
	for unit: String in troops:
		var plural := Economy.rules.unit_plural(unit) if Economy.rules.has_unit(unit) else unit
		box.add_child(_amount(unit, "%d %s" % [int(troops[unit]), plural.to_lower()]))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(gap)
	var tag := MenuStyle.label({"taken": "Taken", "today": "Today", "later": ""}[state], 14,
			DONE if state == "taken" else READY)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	if state == "taken":
		card.modulate = Color(1, 1, 1, 0.75)
	return card


static func _amount(icon: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(Icons.rect(icon, 18))
	row.add_child(MenuStyle.label(text, 14, MenuStyle.TEXT))
	return row


static func _hours(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]
