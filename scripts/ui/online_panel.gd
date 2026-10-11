extends PanelContainer
## The title screen's "Play online" panel: sign in or create an account
## (email and password), then name your castle the first time. Fires
## `started` with the server's answer once there is a castle to play.

signal started(answer: Dictionary)
signal closed

var _title: Label
var _form: VBoxContainer
var _email: LineEdit
var _password: LineEdit
var _naming: VBoxContainer
var _name: LineEdit
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel())
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_title = MenuStyle.title("Play online", 28)
	box.add_child(_title)

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 10)
	box.add_child(_form)
	_form.add_child(MenuStyle.label("Email", 16, MenuStyle.MUTED))
	_email = _field("you@example.com")
	_form.add_child(_email)
	_form.add_child(MenuStyle.label("Password", 16, MenuStyle.MUTED))
	_password = _field("At least 6 characters")
	_password.secret = true
	_password.text_submitted.connect(func(_t: String) -> void: _sign_in())
	_form.add_child(_password)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_button("Sign in", _sign_in, 200.0))
	row.add_child(_button("Create account", _sign_up, 200.0))
	_form.add_child(row)

	_naming = VBoxContainer.new()
	_naming.add_theme_constant_override("separation", 10)
	_naming.visible = false
	box.add_child(_naming)
	var ask := MenuStyle.label("Name yourself. Other players will see this name, and it can't be changed later.", 16)
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_naming.add_child(ask)
	_name = _field("3 to 20 letters or numbers")
	_name.max_length = 20
	_name.text_submitted.connect(func(_t: String) -> void: _join())
	_naming.add_child(_name)
	var found := _button("Found my castle", _join, 260.0)
	found.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_naming.add_child(found)

	_status = MenuStyle.label("", 16, MenuStyle.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var back := _button("Back", func() -> void: closed.emit(), 200.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)


func open() -> void:
	## Shows the panel; with a remembered session it signs straight back in.
	_form.visible = true
	_naming.visible = false
	_title.text = "Play online"
	_email.text = Online.email
	_password.text = ""
	_say("")
	if Online.has_saved_session():
		_say("Signing in as %s..." % Online.email)
		_lock(true)
		var ok: bool = await Online.resume()
		_lock(false)
		if ok:
			await _enter()
		else:
			_say("Please sign in again.")


func _sign_in() -> void:
	if not _check_form():
		return
	_say("Signing in...")
	_lock(true)
	var why: String = await Online.sign_in(_email.text, _password.text)
	_lock(false)
	if why != "":
		_say(why)
		return
	await _enter()


func _sign_up() -> void:
	if not _check_form():
		return
	_say("Creating your account...")
	_lock(true)
	var why: String = await Online.sign_up(_email.text, _password.text)
	_lock(false)
	if why != "":
		_say(why)
		return
	await _enter()


func _enter() -> void:
	## Signed in: load the castle, or ask for a name if there is none yet.
	_say("Loading your castle...")
	_lock(true)
	var answer: Dictionary = await Online.call_game({"action": "state"})
	_lock(false)
	if answer.get("needs_join", false):
		_form.visible = false
		_naming.visible = true
		_title.text = "Your castle"
		_say("")
		_name.grab_focus()
		return
	if not answer.get("ok", false):
		_say(String(answer.get("error", "Something went wrong.")))
		return
	_say("")
	started.emit(answer)


func _join() -> void:
	var name_text := _name.text.strip_edges()
	if name_text.length() < 3:
		_say("Names are 3 to 20 characters long.")
		return
	_say("Founding your castle...")
	_lock(true)
	var answer: Dictionary = await Online.call_game({"action": "join", "name": name_text})
	_lock(false)
	if not answer.get("ok", false):
		_say(String(answer.get("error", "Something went wrong.")))
		return
	_say("")
	started.emit(answer)


func _check_form() -> bool:
	if not "@" in _email.text or _email.text.strip_edges().length() < 5:
		_say("Enter your email address.")
		return false
	if _password.text.length() < 6:
		_say("Passwords are at least 6 characters long.")
		return false
	return true


func _say(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _lock(on: bool) -> void:
	for b in _buttons:
		b.disabled = on


func _field(hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.custom_minimum_size = Vector2(0, 40)
	e.add_theme_font_size_override("font_size", 18)
	return e


func _button(text: String, action: Callable, width: float) -> Button:
	var b := MenuStyle.button(text, action, width)
	_buttons.append(b)
	return b
