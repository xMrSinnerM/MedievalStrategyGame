extends PanelContainer
## Writing a letter (the mail window's "Write" tab, online): to a player by
## name or, for alliance leaders and officers, to the whole alliance. The
## server checks it again and answers with Economy.letter_sent.

const BAD := Color(1.0, 0.55, 0.42)
const GOOD := Color(0.6, 0.9, 0.5)
const LENGTH := 1000

## The "Sent" folder and the window holding both (set by the HUD), to show the letter once it went.
var sent_page: Control
var window: GameWindow

var _to: LineEdit
var _whole: CheckBox
var _subject: LineEdit
var _text: TextEdit
var _count: Label
var _note: Label
var _send: Button
var _waiting := false


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var to_row := HBoxContainer.new()
	to_row.add_theme_constant_override("separation", 10)
	box.add_child(to_row)
	to_row.add_child(_caption("To"))
	_to = LineEdit.new()
	_to.placeholder_text = "A player's name"
	_to.max_length = 20
	_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_to.gui_input.connect(_on_field_input.bind(_to))
	to_row.add_child(_to)
	_whole = CheckBox.new()
	_whole.text = "My whole alliance"
	_whole.focus_mode = Control.FOCUS_NONE
	_whole.toggled.connect(func(on: bool) -> void: _to.editable = not on)
	to_row.add_child(_whole)
	var subject_row := HBoxContainer.new()
	subject_row.add_theme_constant_override("separation", 10)
	box.add_child(subject_row)
	subject_row.add_child(_caption("Subject"))
	_subject = LineEdit.new()
	_subject.max_length = 60
	_subject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subject.gui_input.connect(_on_field_input.bind(_subject))
	subject_row.add_child(_subject)
	_text = TextEdit.new()
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "Your letter..."
	_text.custom_minimum_size = Vector2(0, 340)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 16)
	_text.text_changed.connect(_count_letters)
	_text.gui_input.connect(_on_field_input.bind(_text))
	box.add_child(_text)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	box.add_child(bottom)
	_count = MenuStyle.label("", 14, MenuStyle.MUTED)
	bottom.add_child(_count)
	_note = MenuStyle.label("", 15, BAD)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_note)
	_send = GameTheme.primary(Button.new())
	_send.text = "Send"
	_send.icon = Icons.get_icon("mail", 20)
	_send.focus_mode = Control.FOCUS_NONE
	_send.custom_minimum_size = Vector2(160, 42)
	_send.pressed.connect(_on_send)
	bottom.add_child(_send)
	Economy.letter_sent.connect(_on_sent)
	Economy.alliance_changed.connect(func(_e: String) -> void: _update_whole())
	_count_letters()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	if visible:
		open_panel()


func open_panel() -> void:
	_update_whole()
	visible = true
	if _to.text == "" and not _whole.button_pressed:
		_to.grab_focus()
	else:
		_text.grab_focus()


func close_panel() -> void:
	for field: Control in [_to, _subject, _text]:
		field.release_focus()
	visible = false


func prefill(to: String, subject: String) -> void:
	## Starts a letter to `to` (a reply, or from a player's card).
	_whole.button_pressed = false
	_to.text = to
	_subject.text = subject
	_note.text = ""


func _update_whole() -> void:
	var role := String(Economy.my_alliance().get("role", ""))
	_whole.visible = role == "leader" or role == "officer"
	if not _whole.visible:
		_whole.button_pressed = false


func _count_letters() -> void:
	var n := _text.text.strip_edges().length()
	_count.text = "%d / %d" % [n, LENGTH]
	_count.add_theme_color_override("font_color", BAD if n > LENGTH else MenuStyle.MUTED)


func _on_send() -> void:
	if _waiting:
		return
	var why := Economy.send_letter(_to.text, _subject.text, _text.text, _whole.button_pressed)
	_note.add_theme_color_override("font_color", BAD)
	_note.text = why
	if why == "":
		_waiting = true
		_send.disabled = true
		_note.add_theme_color_override("font_color", MenuStyle.MUTED)
		_note.text = "Sending..."


func _on_sent(error: String) -> void:
	_waiting = false
	_send.disabled = false
	if error != "":
		_note.add_theme_color_override("font_color", BAD)
		_note.text = error
		return
	_to.text = ""
	_subject.text = ""
	_text.text = ""
	_whole.button_pressed = false
	_count_letters()
	_note.add_theme_color_override("font_color", GOOD)
	_note.text = "Sent."
	if visible and sent_page != null and window != null:
		window.open(sent_page)


func _on_field_input(event: InputEvent, field: Control) -> void:
	# Esc leaves the field (and the game keys work again) instead of closing the window.
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		field.release_focus()
		field.accept_event()


func _caption(text: String) -> Label:
	var l := MenuStyle.label(text, 16, MenuStyle.GOLD)
	l.custom_minimum_size = Vector2(80, 0)
	return l
