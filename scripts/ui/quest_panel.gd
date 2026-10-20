extends PanelContainer
## The quest screen (J, or the quest tracker): the steward's story quest with
## its chapter, today's daily tasks and the coffer for finishing them all.
## Rewards are given in full when claimed, even past the storage cap
## (QuestBook).

const DONE := Color(0.55, 0.9, 0.45)
const READY := Color(1.0, 0.85, 0.45)

var _chapter: Label
var _intro: Label
var _quest_title: Label
var _quest_text: Label
var _quest_bar: ProgressBar
var _quest_progress: Label
var _quest_reward: Label
var _quest_claim: Button
var _new_tasks: Label
var _tasks: GridContainer
var _coffer: Label
var _coffer_claim: Button
var _status: Label
var _signature := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(760, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Quests", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)

	_chapter = MenuStyle.label("", 19, MenuStyle.GOLD)
	box.add_child(_chapter)
	_intro = _wrapped("", 14, MenuStyle.MUTED)
	box.add_child(_intro)
	var quest := PanelContainer.new()
	quest.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 12))
	box.add_child(quest)
	var qbox := VBoxContainer.new()
	qbox.add_theme_constant_override("separation", 6)
	quest.add_child(qbox)
	_quest_title = MenuStyle.label("", 18, MenuStyle.TEXT)
	qbox.add_child(_quest_title)
	_quest_text = _wrapped("", 15, MenuStyle.TEXT)
	qbox.add_child(_quest_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	qbox.add_child(row)
	_quest_bar = ProgressBar.new()
	_quest_bar.show_percentage = false
	_quest_bar.custom_minimum_size = Vector2(220, 16)
	_quest_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_quest_bar)
	_quest_progress = MenuStyle.label("", 15, MenuStyle.MUTED)
	_quest_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_quest_progress)
	_quest_claim = _claim_button("Claim", func() -> void: _claim("story", 0))
	row.add_child(_quest_claim)
	_quest_reward = _wrapped("", 15, MenuStyle.GOLD)
	qbox.add_child(_quest_reward)

	box.add_child(HSeparator.new())
	var daily_head := HBoxContainer.new()
	box.add_child(daily_head)
	var daily_title := MenuStyle.label("Daily tasks", 19, MenuStyle.GOLD)
	daily_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daily_head.add_child(daily_title)
	_new_tasks = MenuStyle.label("", 14, MenuStyle.MUTED)
	daily_head.add_child(_new_tasks)
	_tasks = GridContainer.new()
	_tasks.columns = 4
	_tasks.add_theme_constant_override("h_separation", 18)
	_tasks.add_theme_constant_override("v_separation", 6)
	box.add_child(_tasks)
	var coffer_row := HBoxContainer.new()
	coffer_row.add_theme_constant_override("separation", 12)
	box.add_child(coffer_row)
	_coffer = _wrapped("", 15, MenuStyle.TEXT)
	_coffer.custom_minimum_size = Vector2(560, 0)
	_coffer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coffer_row.add_child(_coffer)
	_coffer_claim = _claim_button("Open", func() -> void: _claim("chest", 0))
	_coffer_claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coffer_row.add_child(_coffer_claim)
	_status = MenuStyle.label("", 15, DONE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_fill())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_J and not get_tree().paused:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


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


func _claim(kind: String, index: int) -> void:
	var book := Economy.quest_book
	var castle := Economy.player_castle
	var reward := {}
	match kind:
		"story":
			reward = book.current_story(castle).get("reward", {})
		"daily":
			reward = book.daily_reward(String(castle.quests.picks[index]), int(castle.quests.keep))
		"chest":
			reward = book.coffer_reward(int(castle.quests.keep), book.coffer_streak(castle))
	var why := Economy.claim_quest(kind, index)
	_status.add_theme_color_override("font_color", DONE if why == "" else Color(1.0, 0.55, 0.4))
	_status.text = "Received: %s" % Economy.reward_text(reward) if why == "" else why
	_signature = ""
	_fill()


func _fill() -> void:
	var book := Economy.quest_book
	var castle := Economy.player_castle
	if book == null or castle == null:
		return
	book.roll_day(castle, Economy.now())
	var left := float((QuestBook.day_of(Economy.now()) + 1) * QuestBook.DAY) - Economy.now()
	_new_tasks.text = "New tasks in %s" % _hours(left)
	# Rebuild only when something shown has changed, so buttons don't flicker every tick.
	var q := castle.quests
	var sig := str([q, book.can_claim_anything(castle), _story_progress(), _daily_progress()])
	if sig == _signature:
		return
	_signature = sig
	_fill_story()
	_fill_tasks()


func _story_progress() -> Array:
	var quest := Economy.quest_book.current_story(Economy.player_castle)
	return [] if quest.is_empty() else Economy.quest_book.progress(Economy.player_castle, quest.goal)


func _daily_progress() -> Array:
	var out: Array = []
	for i in Economy.player_castle.quests.picks.size():
		out.append(Economy.quest_book.daily_progress(Economy.player_castle, i))
	return out


func _fill_story() -> void:
	var book := Economy.quest_book
	var castle := Economy.player_castle
	var quest := book.current_story(castle)
	if quest.is_empty():
		_chapter.text = "The valley is yours"
		_intro.text = "%s: \"The Black Baron is gone, my lord. Every quest is done, and every song in the valley has your name in it.\"" % book.narrator
		_quest_title.text = "All %d quests done" % book.story.size()
		_quest_text.text = "Daily tasks and the coffer still come every day."
		_quest_bar.visible = false
		_quest_progress.text = ""
		_quest_reward.text = ""
		_quest_claim.visible = false
		return
	var chapter: Dictionary = book.chapters[int(quest.chapter)]
	_chapter.text = "Chapter %d: %s" % [int(quest.chapter) + 1, chapter.title]
	_intro.text = chapter.intro
	_quest_title.text = "%s    (quest %d of %d)" % [quest.title, int(castle.quests.story) + 1, book.story.size()]
	_quest_text.text = "%s: \"%s\"" % [book.narrator, quest.text]
	var p := book.progress(castle, quest.goal)
	_quest_bar.visible = true
	_quest_bar.max_value = maxf(1.0, float(p[1]))
	_quest_bar.value = minf(float(p[0]), float(p[1]))
	_quest_progress.text = "%s: %d / %d" % [goal_text(quest.goal), mini(p[0], p[1]), p[1]]
	_quest_reward.text = "Reward: %s" % Economy.reward_text(quest.reward)
	_quest_claim.visible = true
	_quest_claim.disabled = p[0] < p[1]
	_quest_progress.add_theme_color_override("font_color", READY if p[0] >= p[1] else MenuStyle.MUTED)


func _fill_tasks() -> void:
	var book := Economy.quest_book
	var castle := Economy.player_castle
	var q := castle.quests
	for child in _tasks.get_children():
		_tasks.remove_child(child)
		child.queue_free()
	for i in q.picks.size():
		var kind := String(q.picks[i])
		var p := book.daily_progress(castle, i)
		var claimed: bool = q.claimed.has(i)
		var color := DONE if claimed else (READY if p[0] >= p[1] else MenuStyle.TEXT)
		var what := MenuStyle.label(book.daily_text(kind, int(q.keep)), 15, color)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tasks.add_child(what)
		_tasks.add_child(MenuStyle.label("%d / %d" % [mini(p[0], p[1]), p[1]], 15, color))
		_tasks.add_child(MenuStyle.label(Economy.reward_text(book.daily_reward(kind, int(q.keep))), 15, MenuStyle.GOLD))
		if claimed:
			_tasks.add_child(MenuStyle.label("Claimed", 15, DONE))
		else:
			var index: int = i
			var claim := _claim_button("Claim", func() -> void: _claim("daily", index))
			claim.disabled = p[0] < p[1]
			_tasks.add_child(claim)
	var coffer_name: String = book.daily.coffer.name
	var streak := book.coffer_streak(castle)
	var best := int(book.daily.coffer.max_streak)
	if q.chest:
		_coffer.text = "%s opened. Days in a row: %d. Come back tomorrow to keep the streak." % [coffer_name, QuestBook.current_streak(castle)]
		_coffer_claim.visible = false
		return
	var reward := book.coffer_reward(int(q.keep), streak)
	var line := "%s: finish all %d tasks to open it. Day %d in a row" % [coffer_name, q.picks.size(), streak]
	if streak < best:
		line += " (at %d days in a row it also gives soldiers)" % best
	_coffer.text = line + ".\nInside: %s" % Economy.reward_text(reward)
	_coffer_claim.visible = true
	_coffer_claim.disabled = book.check_claim(castle, "chest") != ""


static func goal_text(goal: Dictionary) -> String:
	## "Woodcutter at level 2", "Soldiers in the garrison" and so on.
	match String(goal.get("kind", "")):
		"building":
			var type := String(goal.type)
			var n := Economy.rules.display_name(type) if Economy.rules.has_type(type) else type
			var count := int(goal.get("count", 1))
			return ("%d x %s" % [count, n] if count > 1 else n) + (" at level %d" % int(goal.level) if int(goal.level) > 1 else " built")
		"soldiers":
			return "Soldiers at home"
		"stat":
			return {"trained": "Soldiers trained", "spent": "Resources spent", "barons": "Robber barons beaten",
				"looted": "Loot brought home"}.get(String(goal.stat), String(goal.stat))
		"production":
			return "%s per hour" % String(goal.resource).capitalize()
		"storage":
			return "Storage"
		"levels":
			return "Building levels"
	return ""


func _claim_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 30)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := MenuStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700, 0)
	return l


static func _hours(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]
