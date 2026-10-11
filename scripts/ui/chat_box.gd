extends VBoxContainer
## The chat box in the bottom left corner of the world map, online: the world
## channel everyone can read and your alliance's. Closed, it is one button
## that counts new messages; Enter opens it and puts you in the text field,
## Enter again sends, Esc leaves the field. Messages come from the server
## (Economy.chat_messages); text is shown as plain text, never as markup.

const ME := Color(1.0, 0.85, 0.45)
const ALLY := Color(0.6, 0.9, 0.5)
const NAME := Color(0.95, 0.82, 0.62)
const TEXT := Color(0.93, 0.89, 0.8)
const TIME := Color(0.65, 0.6, 0.52)
const BAD := Color(1.0, 0.55, 0.42)
const WIDTH := 480.0

var _open_button: Button
var _panel: PanelContainer
var _world_tab: Button
var _alliance_tab: Button
var _log: RichTextLabel
var _field: LineEdit
var _note: Label
var _channel := "world"
var _seen := {"world": 0, "alliance": 0}   ## newest message id read in each channel
var _primed := false                       ## the messages from before you came are marked read


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", MenuStyle.panel(0.88, 14))
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_world_tab = _tab("World", "world")
	head.add_child(_world_tab)
	_alliance_tab = _tab("Alliance", "alliance")
	head.add_child(_alliance_tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "Hide"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(close_box)
	head.add_child(close)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.custom_minimum_size = Vector2(0, 230)
	_log.add_theme_font_size_override("normal_font_size", 15)
	box.add_child(_log)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_field = LineEdit.new()
	_field.max_length = 200
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.text_submitted.connect(func(_text: String) -> void: _send())
	_field.gui_input.connect(_on_field_input)
	row.add_child(_field)
	var send := Button.new()
	send.text = "Send"
	send.focus_mode = Control.FOCUS_NONE
	send.pressed.connect(_send)
	row.add_child(send)
	_note = MenuStyle.label("", 14, BAD)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	box.add_child(_note)
	_open_button = Button.new()
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_open_button.pressed.connect(func() -> void: open_box(false))
	add_child(_open_button)
	Economy.chat_changed.connect(_on_chat)
	_on_chat("")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or get_tree().paused:
		return
	if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and get_viewport().gui_get_focus_owner() == null:
		open_box(true)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel.visible


func open_box(typing: bool) -> void:
	_panel.visible = true
	Economy.chat_open = true
	_refresh()
	if typing:
		_field.grab_focus()


func close_box() -> void:
	_field.release_focus()
	_panel.visible = false
	Economy.chat_open = false
	_refresh()


func _on_field_input(event: InputEvent) -> void:
	# Esc leaves the text field (and the game keys work again) instead of opening the menu.
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_field.release_focus()
		_field.accept_event()


func _send() -> void:
	var why := Economy.send_chat(_channel, _field.text)
	_show_note(why)
	if why == "":
		_field.clear()


func _on_chat(error: String) -> void:
	if not _primed and Economy.chat_loaded:
		_primed = true
		_seen = {"world": Economy.last_chat_id(), "alliance": Economy.last_chat_id()}
	_show_note(error)
	if not Economy.chat_in_alliance and _channel == "alliance":
		_channel = "world"
	_refresh()


func _show_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""


func _pick(channel: String) -> void:
	_channel = channel
	_show_note("")
	_refresh()


func _refresh() -> void:
	## Redraws the messages of the channel shown and the counts of the others.
	var newest := {"world": 0, "alliance": 0}
	var unread := {"world": 0, "alliance": 0}
	for m: Dictionary in Economy.chat_messages:
		var ch := String(m.get("channel", "world"))
		newest[ch] = maxi(newest[ch], int(m.id))
		if int(m.id) > _seen[ch]:
			unread[ch] += 1
	if _panel.visible:
		_seen[_channel] = maxi(_seen[_channel], newest[_channel])
		unread[_channel] = 0
	_world_tab.button_pressed = _channel == "world"
	_world_tab.text = "World" + ("  %d" % unread.world if unread.world > 0 else "")
	_alliance_tab.button_pressed = _channel == "alliance"
	_alliance_tab.disabled = not Economy.chat_in_alliance
	_alliance_tab.text = "Alliance" + ("  %d" % unread.alliance if unread.alliance > 0 else "")
	_alliance_tab.tooltip_text = "" if Economy.chat_in_alliance else "Join an alliance to talk with its members."
	_field.placeholder_text = "Message to everyone" if _channel == "world" else "Message to your alliance"
	var waiting: int = unread.world + unread.alliance
	_open_button.visible = not _panel.visible
	_open_button.text = "Chat (Enter)" + ("  %d new" % waiting if waiting > 0 else "")
	if not _panel.visible:
		return
	_log.clear()
	var me := String(Economy.alliance.get("you", ""))
	var shown := 0
	for m: Dictionary in Economy.chat_messages:
		if String(m.get("channel", "world")) != _channel:
			continue
		if shown > 0:
			_log.newline()
		shown += 1
		_log.push_color(TIME)
		_log.add_text(_clock(float(m.get("at", 0.0))) + "  ")
		_log.pop()
		var tag := String(m.get("tag", ""))
		var who := String(m.get("name", "?"))
		_log.push_color(ME if who == me else (ALLY if tag != "" and tag == _my_tag() else NAME))
		_log.add_text(("[%s] " % tag if tag != "" else "") + who + ": ")
		_log.pop()
		_log.push_color(TEXT)
		_log.add_text(String(m.get("text", "")))
		_log.pop()
	if shown == 0:
		_log.push_color(TIME)
		_log.add_text("No messages yet. Say hello!" if _channel == "world" else "No alliance messages yet.")
		_log.pop()


func _my_tag() -> String:
	return String(Economy.my_alliance().get("tag", ""))


func _clock(unix: float) -> String:
	## The time a message was sent, on this computer's clock (hours:minutes).
	var local := int(unix) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_time_dict_from_unix_time(local)
	return "%02d:%02d" % [t.hour, t.minute]


func _tab(text: String, channel: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func() -> void: _pick(channel))
	return b
