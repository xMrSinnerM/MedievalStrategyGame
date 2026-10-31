extends PanelContainer
## One folder of the mail window (I on the world map, online): your reports
## (every battle, spy, cart and market report), the letters other players sent
## you, or the ones you sent. The list is on the left, newest first, unread
## ones in gold; the one you pick is shown on the right. The server sends a
## page at a time (Economy.mail); text is shown as plain text, never markup.

const UNREAD := Color(1.0, 0.85, 0.45)
const READ := Color(0.82, 0.77, 0.68)

## "reports", "inbox" or "sent".
var folder := "inbox"
## The page for writing letters, and the window holding both (set by the HUD).
var compose: Control
var window: GameWindow

var _info: Label
var _read_all: Button
var _list: VBoxContainer
var _empty: Label
var _subject: Label
var _meta: Label
var _text: RichTextLabel
var _battle: Button
var _reply: Button
var _delete: Button
var _newer: Button
var _older: Button
var _selected := -1
var _pages: Array[int] = []    ## the `before` of each page back to the newest
var _before := 0


func _init(p_folder := "inbox") -> void:
	folder = p_folder


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_info = MenuStyle.label("", 15, MenuStyle.MUTED)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_info)
	_read_all = _button("Mark all read", func() -> void: Economy.mark_all_mail_read(folder))
	_read_all.visible = folder != "sent"
	head.add_child(_read_all)
	head.add_child(_button("Refresh", func() -> void: Economy.ask_mail(folder, _before)))
	var write := _button("Write a letter", func() -> void: _write("", ""))
	write.icon = Icons.get_icon("mail", 18)
	head.add_child(write)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	split.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_empty = MenuStyle.label("", 15, MenuStyle.MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_empty)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 8)
	left.add_child(pager)
	_newer = _button("‹ Newer", _go_newer)
	_newer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_newer)
	_older = _button("Older ›", _go_older)
	_older.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_older)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GameTheme.panel_box(0.45, 16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(card)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	card.add_child(detail)
	_subject = MenuStyle.title("", 22)
	_subject.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_subject)
	_meta = MenuStyle.label("", 14, MenuStyle.MUTED)
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_meta)
	detail.add_child(HSeparator.new())
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.selection_enabled = true
	_text.focus_mode = Control.FOCUS_NONE
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 260)
	_text.add_theme_font_size_override("normal_font_size", 16)
	detail.add_child(_text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	detail.add_child(actions)
	_battle = GameTheme.primary(_button("See the battle", _show_battle))
	actions.add_child(_battle)
	_reply = GameTheme.primary(_button("Reply", _reply_to))
	actions.add_child(_reply)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(gap)
	_delete = _button("Delete", _delete_selected)
	actions.add_child(_delete)
	Economy.mail_changed.connect(func(_error: String) -> void: _fill())
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	_pages.clear()
	_before = 0
	_selected = -1
	visible = true
	_fill()
	Economy.ask_mail(folder, 0)


func close_panel() -> void:
	visible = false


func _items() -> Array:
	## The page on show, if it is this folder's.
	if String(Economy.mail.get("folder", "")) != folder:
		return []
	return Economy.mail.get("items", [])


func _item(id: int) -> Dictionary:
	for item: Dictionary in _items():
		if int(item.id) == id:
			return item
	return {}


func _fill() -> void:
	if not is_node_ready():
		return
	var unread: Dictionary = Economy.mail_unread
	match folder:
		"reports":
			_info.text = "%d unread. Every battle, spy, cart and market report, kept until you delete it." % int(unread.get("reports", 0))
		"inbox":
			_info.text = "%d unread. Letters from other players, kept for 30 days." % int(unread.get("inbox", 0))
		_:
			_info.text = "The letters you sent, kept for 30 days."
	for child in _list.get_children():
		if child != _empty:
			_list.remove_child(child)
			child.queue_free()
	var items := _items()
	var mine := String(Economy.mail.get("folder", "")) == folder
	_empty.visible = items.is_empty()
	_empty.text = "Asking the server..." if not mine else {"reports": "No reports yet.", "inbox": "No letters yet.",
			"sent": "You haven't sent any letters yet."}.get(folder, "")
	for item: Dictionary in items:
		_list.add_child(_row(item))
	_newer.disabled = _pages.is_empty()
	_older.disabled = not (mine and Economy.mail.get("more", false))
	if _item(_selected).is_empty():
		_selected = -1
	_show(_item(_selected))


func _row(item: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 54)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var unread: bool = not item.get("read", false) and folder != "sent"
	var title: String
	var who: String
	if folder == "reports":
		title = Economy.report_title(item.get("report", {}))
		who = ""
	else:
		title = String(item.get("subject", ""))
		who = ("To " + String(item.get("to_name", ""))) if folder == "sent" else String(item.get("from_name", ""))
	b.text = "%s%s\n%s%s" % ["● " if unread else "", title, (who + "  ·  ") if who != "" else "", _ago(float(item.get("at", 0.0)))]
	b.add_theme_color_override("font_color", UNREAD if unread else READ)
	b.add_theme_font_size_override("font_size", 15)
	if int(item.id) == _selected:
		b.add_theme_stylebox_override("normal", GameTheme.button_box(Color(0.2, 0.14, 0.07), GameTheme.RIM_BRIGHT))
	b.pressed.connect(func() -> void: _pick(int(item.id)))
	return b


func _pick(id: int) -> void:
	_selected = id
	var item := _item(id)
	if not item.is_empty() and not item.get("read", false) and folder != "sent":
		Economy.mark_mail_read(folder, [id])   # emits mail_changed, which refills
	else:
		_fill()


func _show(item: Dictionary) -> void:
	_battle.visible = false
	_reply.visible = false
	_delete.visible = not item.is_empty()
	if item.is_empty():
		_subject.text = ""
		_meta.text = ""
		_text.text = "Choose a report on the left." if folder == "reports" else "Choose a letter on the left."
		return
	if folder == "reports":
		var r: Dictionary = item.get("report", {})
		_subject.text = Economy.report_title(r)
		_meta.text = _when(float(item.get("at", 0.0)))
		_text.text = Economy.report_text(r)
		_battle.visible = Economy.is_battle_report(r)
		return
	_subject.text = String(item.get("subject", ""))
	if folder == "sent":
		_meta.text = "To %s  ·  %s" % [String(item.get("to_name", "")), _when(float(item.get("at", 0.0)))]
	else:
		_meta.text = "From %s  ·  %s" % [String(item.get("from_name", "")), _when(float(item.get("at", 0.0)))]
		_reply.visible = true
	_text.text = String(item.get("text", ""))


func _show_battle() -> void:
	var item := _item(_selected)
	if not item.is_empty():
		Economy.show_report(item.get("report", {}))


func _reply_to() -> void:
	var item := _item(_selected)
	if item.is_empty():
		return
	var subject := String(item.get("subject", ""))
	if subject == "(no subject)":
		subject = ""
	if subject != "" and not subject.begins_with("Re: "):
		subject = "Re: " + subject
	_write(String(item.get("from_name", "")), subject)


func _write(to: String, subject: String) -> void:
	if compose == null or window == null:
		return
	compose.call("prefill", to, subject)
	window.open(compose)


func _delete_selected() -> void:
	if _selected < 0:
		return
	Economy.delete_mail(folder, [_selected])
	_selected = -1


func _go_older() -> void:
	var items := _items()
	if items.is_empty():
		return
	_pages.append(_before)
	_before = int(items.back().id)
	_selected = -1
	Economy.ask_mail(folder, _before)


func _go_newer() -> void:
	if _pages.is_empty():
		return
	_before = _pages.pop_back()
	_selected = -1
	Economy.ask_mail(folder, _before)


static func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _ago(at: float) -> String:
	var s := maxf(0.0, Economy.now() - at)
	if s < 60.0:
		return "just now"
	if s < 3600.0:
		return "%d min ago" % floori(s / 60.0)
	if s < 86400.0:
		return "%d h ago" % floori(s / 3600.0)
	return "%d d ago" % floori(s / 86400.0)


static func _when(at: float) -> String:
	## A date and time in your own time zone.
	var bias := Time.get_time_zone_from_system().get("bias", 0) as int
	var d := Time.get_datetime_dict_from_unix_time(int(at) + bias * 60)
	return "%04d-%02d-%02d %02d:%02d  (%s)" % [d.year, d.month, d.day, d.hour, d.minute, _ago(at)]
