extends PanelContainer
## The achievements screen (Y): every achievement with its three tiers, how
## far you are towards the next one, the rewards waiting to be claimed, and
## the titles you've earned, one of which can stand with your name on the
## map, on the leaderboard and in your castle (Achievements).

const DONE := Color(0.55, 0.9, 0.45)
const READY := Color(1.0, 0.85, 0.45)
const TIER_COLORS := [Color(0.86, 0.58, 0.34), Color(0.84, 0.86, 0.9), Color(1.0, 0.82, 0.3)]
const LOCKED := Color(0.42, 0.38, 0.33)

var _points: Label
var _title_pick: OptionButton
var _rows: GridContainer
var _status: Label
var _signature := ""
var _title_keys: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(900, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Achievements", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_points = MenuStyle.label("", 17, MenuStyle.GOLD)
	_points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_points)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	box.add_child(title_row)
	title_row.add_child(MenuStyle.label("Your title:", 16, MenuStyle.TEXT))
	_title_pick = OptionButton.new()
	_title_pick.focus_mode = Control.FOCUS_NONE
	_title_pick.custom_minimum_size = Vector2(280, 30)
	_title_pick.add_theme_font_size_override("font_size", 15)
	_title_pick.item_selected.connect(_pick_title)
	title_row.add_child(_title_pick)
	var hint := MenuStyle.label("Shown with your name on the map, the leaderboard and in your castle.", 14, MenuStyle.MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(hint)

	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = GridContainer.new()
	_rows.columns = 5
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("h_separation", 16)
	_rows.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_rows)
	_status = MenuStyle.label("", 15, DONE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_fill())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_Y and not get_tree().paused:
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


func _fill() -> void:
	var book := Economy.achievements
	var castle := Economy.player_castle
	if book == null or castle == null:
		return
	# Rebuild only when something shown has changed, so buttons don't flicker every tick.
	var values: Array = []
	for def: Dictionary in book.shown(Economy.online):
		values.append(Achievements.measure(castle, def))
	var sig := str([castle.achievements, values])
	if sig == _signature:
		return
	_signature = sig
	_points.text = "%d points" % book.score(castle)
	_fill_titles()
	_fill_rows()


func _fill_titles() -> void:
	var book := Economy.achievements
	var castle := Economy.player_castle
	_title_pick.clear()
	_title_keys = [""]
	_title_pick.add_item("No title")
	for def: Dictionary in book.shown(Economy.online):
		for t in book.earned(castle, String(def.id)):
			var key := Achievements.title_key(String(def.id), t + 1)
			_title_keys.append(key)
			_title_pick.add_item("%s  (%s)" % [book.title_text(key), def.name])
	_title_pick.select(maxi(0, _title_keys.find(String(castle.achievements.title))))
	_title_pick.disabled = _title_keys.size() <= 1


func _fill_rows() -> void:
	var book := Economy.achievements
	var castle := Economy.player_castle
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for def: Dictionary in book.shown(Economy.online):
		var id := String(def.id)
		var have := book.earned(castle, id)
		var got := book.claimed(castle, id)
		var needs: Array = def.needs
		var value := Achievements.measure(castle, def)
		var about := VBoxContainer.new()
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about.add_theme_constant_override("separation", 0)
		about.add_child(MenuStyle.label(String(def.name), 17, TIER_COLORS[have - 1] if have > 0 else MenuStyle.TEXT))
		about.add_child(MenuStyle.label(String(def.text), 13, MenuStyle.MUTED))
		_rows.add_child(about)
		_rows.add_child(_medals(have, needs))
		var progress := VBoxContainer.new()
		progress.add_theme_constant_override("separation", 2)
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 12)
		var count := MenuStyle.label("", 13, MenuStyle.MUTED)
		if have >= needs.size():
			bar.max_value = 1.0
			bar.value = 1.0
			count.text = "All done"
			count.add_theme_color_override("font_color", DONE)
		else:
			var from := int(needs[have - 1]) if have > 0 else 0
			bar.max_value = maxf(1.0, float(int(needs[have]) - from))
			bar.value = clampf(float(value - from), 0.0, bar.max_value)
			count.text = "%s / %s" % [_number(value), _number(int(needs[have]))]
		progress.add_child(bar)
		progress.add_child(count)
		_rows.add_child(progress)
		var next_title := String(def.titles[mini(have, needs.size() - 1)])
		var title_text := ("Title: " if have < needs.size() else "Titles earned: ") + (next_title if have < needs.size()
				else ", ".join(def.titles))
		var title_label := MenuStyle.label(title_text, 14, MenuStyle.TEXT if have < needs.size() else DONE)
		title_label.custom_minimum_size = Vector2(230, 0)
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_rows.add_child(title_label)
		if got < have:
			var claim := Button.new()
			claim.text = "Claim %s" % book.tier_names[got]
			claim.tooltip_text = Economy.reward_text(book.reward(got + 1))
			claim.focus_mode = Control.FOCUS_NONE
			claim.custom_minimum_size = Vector2(130, 30)
			claim.add_theme_font_size_override("font_size", 15)
			claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			claim.pressed.connect(func() -> void: _claim(id))
			_rows.add_child(GameTheme.primary(claim))
		else:
			var reward := MenuStyle.label("" if have >= needs.size() else "Reward: %s" % _short(book.reward(have + 1)), 13, MenuStyle.MUTED)
			reward.custom_minimum_size = Vector2(130, 0)
			reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_rows.add_child(reward)


func _medals(have: int, needs: Array) -> Control:
	## Three medals: bright for tiers earned, dim for the rest.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t in needs.size():
		var medal := MenuStyle.label("●", 22, TIER_COLORS[t] if t < have else LOCKED)
		medal.tooltip_text = "%s: %s" % [Economy.achievements.tier_names[t], _number(int(needs[t]))]
		medal.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(medal)
	return row


func _claim(id: String) -> void:
	var book := Economy.achievements
	var reward := book.reward(book.claimed(Economy.player_castle, id) + 1)
	var why := Economy.claim_achievement(id)
	_status.add_theme_color_override("font_color", DONE if why == "" else Color(1.0, 0.55, 0.4))
	_status.text = "Received: %s" % Economy.reward_text(reward) if why == "" else why
	_signature = ""
	_fill()


func _pick_title(index: int) -> void:
	var key: String = _title_keys[index] if index >= 0 and index < _title_keys.size() else ""
	var why := Economy.set_title(key)
	_status.add_theme_color_override("font_color", DONE if why == "" else Color(1.0, 0.55, 0.4))
	if why != "":
		_status.text = why
	else:
		var shown := Economy.my_title()
		_status.text = "Your title is now \"%s\"." % shown if shown != "" else "You show no title now."
	_signature = ""
	_fill()


static func _short(reward: Dictionary) -> String:
	## "300 wood, 300 stone, 200 food".
	var parts: PackedStringArray = []
	var res: Dictionary = reward.get("resources", {})
	for r: String in res:
		parts.append("%s %s" % [_number(int(res[r])), r])
	return ", ".join(parts)


static func _number(n: int) -> String:
	## 12500 as "12,500".
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
