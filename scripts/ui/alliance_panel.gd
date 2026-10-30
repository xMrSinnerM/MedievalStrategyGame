extends PanelContainer
## The alliance screen (G on the world map, online). Without an alliance:
## invitations you got, alliances you asked to join, founding your own and the
## list of all alliances to join. In one: its members and their roles; the
## leader and officers also answer requests, invite players and remove
## members, and the leader changes roles and settings. Everything is decided
## by the server; the screen is redrawn from each answer it sends.

const ME := Color(1.0, 0.85, 0.45)
const GOOD := Color(0.6, 0.9, 0.5)
const BAD := Color(1.0, 0.55, 0.42)
const ROLE_NAMES := {"leader": "Leader", "officer": "Officer", "member": "Member"}

var _title: Label
var _tabs: HBoxContainer
var _mine_tab: Button
var _list_tab: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _note: Label
var _showing_list := false
var _armed := ""               ## a button that asks twice (leave, disband) waiting for its second press
var _fields := {}              ## text fields kept across redraws: name, tag, invite, description


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(760, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = MenuStyle.title("Alliance", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	head.add_child(close)
	set_meta("window_head", close)   ## in a GameWindow, its close button does this
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	box.add_child(_tabs)
	_mine_tab = _small("Your alliance", func() -> void: _show_list(false))
	_mine_tab.toggle_mode = true
	_tabs.add_child(_mine_tab)
	_list_tab = _small("All alliances", func() -> void: _show_list(true))
	_list_tab.toggle_mode = true
	_tabs.add_child(_list_tab)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 440)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	_note = MenuStyle.label("", 16, ME)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	for key in ["name", "tag", "invite", "description"]:
		var field := LineEdit.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_fields[key] = field
	_fields.name.placeholder_text = "Alliance name"
	_fields.name.max_length = 24
	_fields.tag.placeholder_text = "Tag"
	_fields.tag.max_length = 4
	_fields.tag.custom_minimum_size = Vector2(90, 0)
	_fields.tag.size_flags_horizontal = Control.SIZE_FILL
	_fields.invite.placeholder_text = "Player name"
	_fields.invite.max_length = 20
	_fields.description.placeholder_text = "A few words about your alliance"
	_fields.description.max_length = 300
	Economy.alliance_changed.connect(func(error: String) -> void:
		if visible:
			_note.text = error
			_note.add_theme_color_override("font_color", BAD if error != "" else ME)
			_fill())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.physical_keycode == KEY_G and not get_tree().paused and Economy.online:
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
	_note.text = "" if not Economy.alliance.is_empty() else "Asking the server..."
	_armed = ""
	_showing_list = false
	_fill()
	Economy.alliance_order({"action": "alliance"})
	visible = true


func close_panel() -> void:
	for field: LineEdit in _fields.values():
		field.release_focus()
	visible = false


func _show_list(on: bool) -> void:
	_showing_list = on
	_armed = ""
	_fill()


func _invites() -> Array:
	return Economy.alliance.get("invites", [])


# --- Drawing -------------------------------------------------------------------------

func _fill() -> void:
	_detach_fields()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var mine := Economy.my_alliance()
	_title.text = "Alliance" if mine.is_empty() else "[%s] %s" % [mine.tag, mine.name]
	_title.visible = not mine.is_empty() or not has_meta("in_window")   ## the window already says "Alliance"
	_mine_tab.text = "Your alliance" if not mine.is_empty() else "Join or found"
	_mine_tab.button_pressed = not _showing_list
	_list_tab.button_pressed = _showing_list
	if Economy.alliance.is_empty():
		return
	if _showing_list:
		_fill_list(mine)
	elif mine.is_empty():
		_fill_lonely()
	else:
		_fill_mine(mine)


func _detach_fields() -> void:
	## The text fields are reused so typing survives a redraw; take them out of
	## the rows about to be freed.
	for field: LineEdit in _fields.values():
		if field.get_parent() != null:
			field.get_parent().remove_child(field)


func _fill_lonely() -> void:
	var view := Economy.alliance
	var invites := _invites()
	if not invites.is_empty():
		_heading("Invitations")
		for inv: Dictionary in invites:
			var row := _row()
			row.add_child(_expand(MenuStyle.label("[%s] %s invites you to join." % [inv.tag, inv.name], 16)))
			row.add_child(_small("Join", func() -> void: _order({"action": "accept_invite", "id": inv.id})))
			row.add_child(_small("Decline", func() -> void: _order({"action": "decline_invite", "id": inv.id})))
	var asked: Array = view.get("asked", [])
	if not asked.is_empty():
		_heading("Waiting for an answer")
		for a: Dictionary in asked:
			var row := _row()
			row.add_child(_expand(MenuStyle.label("You asked to join [%s] %s." % [a.tag, a.name], 16, MenuStyle.MUTED)))
			row.add_child(_small("Withdraw", func() -> void: _order({"action": "cancel_request", "id": a.id})))
	_heading("Found an alliance")
	var rules: Dictionary = view.get("rules", {})
	_body.add_child(MenuStyle.label("Costs %s and needs keep level %d. Up to %d members; the founder leads it." % [
			_cost(rules.get("found_cost", {})), int(rules.get("found_keep", 1)), int(rules.get("max_members", 30))], 15, MenuStyle.MUTED))
	var row := _row()
	row.add_child(_fields.name)
	row.add_child(_fields.tag)
	var why := Economy.check_found_alliance()
	var found := _small("Found", func() -> void:
		var error := Economy.found_alliance(String(_fields.name.text).strip_edges(), String(_fields.tag.text).strip_edges())
		_say(error if error != "" else "Founding your alliance..."))
	found.disabled = why != ""
	found.tooltip_text = why
	row.add_child(found)
	if why != "":
		_body.add_child(MenuStyle.label(why, 15, BAD))
	_heading("Join an alliance")
	_body.add_child(MenuStyle.label("Open alliances take you at once; the others get your request.", 15, MenuStyle.MUTED))
	_alliance_rows({})


func _fill_list(mine: Dictionary) -> void:
	_heading("All alliances, mightiest first")
	_alliance_rows(mine)


func _alliance_rows(mine: Dictionary) -> void:
	var list: Array = Economy.alliance.get("alliances", [])
	if list.is_empty():
		_body.add_child(MenuStyle.label("No alliances yet. Found the first one!", 16, MenuStyle.MUTED))
		return
	var grid := _grid(6)
	for text in ["Tag", "Name", "Members", "Might", "", ""]:
		grid.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
	var asked := {}
	for a: Dictionary in Economy.alliance.get("asked", []):
		asked[int(a.id)] = true
	var full := int(Economy.alliance.get("rules", {}).get("max_members", 30))
	for a: Dictionary in list:
		var own := not mine.is_empty() and int(a.id) == int(mine.id)
		var color := ME if own else MenuStyle.TEXT
		grid.add_child(MenuStyle.label(String(a.tag), 16, color))
		grid.add_child(_expand(MenuStyle.label(String(a.name), 16, color)))
		grid.add_child(MenuStyle.label("%d / %d" % [int(a.members), full], 16, color))
		grid.add_child(MenuStyle.label(str(int(a.might)), 16, color))
		grid.add_child(MenuStyle.label("open" if a.get("open", false) else "by request", 14, MenuStyle.MUTED))
		if not mine.is_empty():
			grid.add_child(Control.new())
		elif asked.has(int(a.id)):
			grid.add_child(MenuStyle.label("asked", 14, MenuStyle.MUTED))
		else:
			var b := _small("Join" if a.get("open", false) else "Ask to join", func() -> void:
				_order({"action": "join_alliance", "id": a.id}))
			b.disabled = int(a.members) >= full
			grid.add_child(b)


func _fill_mine(mine: Dictionary) -> void:
	var view := Economy.alliance
	var role := String(mine.get("role", "member"))
	var leader := role == "leader"
	var officer := role != "member"
	var about := String(mine.get("description", ""))
	_body.add_child(MenuStyle.label(about if about != "" else "No description yet.", 16,
			MenuStyle.TEXT if about != "" else MenuStyle.MUTED))
	_body.add_child(MenuStyle.label("You are %s. %s" % [String(ROLE_NAMES.get(role, role)).to_lower(),
			"Anyone can join." if mine.get("open", false) else "Players ask to join and officers answer."], 15, MenuStyle.MUTED))
	var members: Array = view.get("members", [])
	_heading("Members (%d / %d)" % [members.size(), int(view.get("rules", {}).get("max_members", 30))])
	var grid := _grid(5)
	for text in ["Name", "Role", "Keep", "Might", ""]:
		grid.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
	var me_name := String(view.get("you", ""))
	for m: Dictionary in members:
		var me := String(m.name) == me_name
		var color := ME if me else MenuStyle.TEXT
		grid.add_child(_expand(MenuStyle.label(String(m.name), 16, color)))
		grid.add_child(MenuStyle.label(String(ROLE_NAMES.get(m.role, m.role)), 16, color))
		grid.add_child(MenuStyle.label(str(int(m.level)), 16, color))
		grid.add_child(MenuStyle.label(str(int(m.might)), 16, color))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 6)
		grid.add_child(actions)
		if me or not officer or m.role == "leader":
			continue
		if leader:
			if m.role == "member":
				actions.add_child(_small("Make officer", func() -> void: _order({"action": "set_role", "target": m.name, "role": "officer"})))
			else:
				actions.add_child(_small("Make member", func() -> void: _order({"action": "set_role", "target": m.name, "role": "member"})))
			actions.add_child(_twice("lead:" + String(m.name), "Make leader", "Hand over?", func() -> void:
				_order({"action": "set_role", "target": m.name, "role": "leader"})))
		if leader or m.role == "member":
			actions.add_child(_twice("kick:" + String(m.name), "Remove", "Sure?", func() -> void:
				_order({"action": "kick", "target": m.name})))
	if officer:
		var requests: Array = view.get("requests", [])
		if not requests.is_empty():
			_heading("Asking to join")
			for r: Dictionary in requests:
				var row := _row()
				row.add_child(_expand(MenuStyle.label(String(r.name), 16)))
				row.add_child(_small("Accept", func() -> void: _order({"action": "answer_request", "target": r.name, "accept": true})))
				row.add_child(_small("Decline", func() -> void: _order({"action": "answer_request", "target": r.name, "accept": false})))
		_heading("Invite a player")
		var row := _row()
		row.add_child(_fields.invite)
		row.add_child(_small("Invite", func() -> void:
			var who := String(_fields.invite.text).strip_edges()
			if who != "":
				_fields.invite.text = ""
				_order({"action": "invite", "target": who})))
		for inv: Dictionary in view.get("invited", []):
			var r2 := _row()
			r2.add_child(_expand(MenuStyle.label("Invited: %s" % inv.name, 15, MenuStyle.MUTED)))
			r2.add_child(_small("Withdraw", func() -> void: _order({"action": "cancel_invite", "target": inv.name})))
	if leader:
		_heading("Settings")
		var open := CheckBox.new()
		open.text = "Anyone can join without asking"
		open.focus_mode = Control.FOCUS_NONE
		open.button_pressed = mine.get("open", false)
		open.toggled.connect(func(on: bool) -> void: _order({"action": "alliance_settings", "open": on}))
		_body.add_child(open)
		var row := _row()
		if _fields.description.text == "" and not _fields.description.has_focus():
			_fields.description.text = about
		row.add_child(_fields.description)
		row.add_child(_small("Save", func() -> void:
			_fields.description.release_focus()
			_order({"action": "alliance_settings", "description": String(_fields.description.text)})))
	_body.add_child(HSeparator.new())
	var bottom := _row()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_twice("leave", "Leave alliance", "Really leave?", func() -> void: _order({"action": "leave_alliance"})))
	if leader:
		bottom.add_child(_twice("disband", "Disband alliance", "Really disband?", func() -> void:
			_order({"action": "disband_alliance"})))


# --- Helpers ---------------------------------------------------------------------------

func _order(body: Dictionary) -> void:
	_armed = ""
	_say("Asking the server...")
	Economy.alliance_order(body)


func _say(text: String) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", ME)


func _heading(text: String) -> void:
	var l := MenuStyle.label(text, 19, MenuStyle.GOLD)
	l.add_theme_font_override("font", GameTheme.TITLE_FONT)
	_body.add_child(l)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	return row


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	return grid


static func _expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _small(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(action)
	return b


func _twice(key: String, text: String, sure: String, action: Callable) -> Button:
	## A button that has to be pressed twice, for things that can't be undone.
	var b := _small(sure if _armed == key else text, func() -> void:
		if _armed == key:
			action.call()
		else:
			_armed = key
			_fill())
	if _armed == key:
		b.add_theme_color_override("font_color", BAD)
	return b


static func _cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in cost:
		parts.append("%d %s" % [int(cost[r]), r])
	return ", ".join(parts)
