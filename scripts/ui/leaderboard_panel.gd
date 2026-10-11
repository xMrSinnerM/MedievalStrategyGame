extends PanelContainer
## The leaderboard (L on the world map, online): the mightiest castles with
## their keep level, might and the robber baron camps they have beaten, and
## where your own castle stands. The server sends it each time it opens.

const ME := Color(1.0, 0.85, 0.45)

var _grid: GridContainer
var _scroll: ScrollContainer
var _status: Label
var _rule: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(640, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Leaderboard", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_rule = MenuStyle.label("", 14, MenuStyle.MUTED)
	box.add_child(_rule)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 380)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 28)
	_grid.add_theme_constant_override("v_separation", 6)
	_scroll.add_child(_grid)
	box.add_child(HSeparator.new())
	_status = MenuStyle.label("", 17, ME)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(MenuStyle.button("Refresh", Economy.ask_leaderboard, 180.0))
	buttons.add_child(MenuStyle.button("Close", close_panel, 180.0))
	box.add_child(buttons)
	Economy.leaderboard_changed.connect(_fill)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_L and not get_tree().paused and Economy.online:
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
	_rule.text = "Might: %d for every building level, %d for every soldier at home." % [
			int(Economy.pvp.get("might_per_building_level", 10)), int(Economy.pvp.get("might_per_soldier", 1))]
	_fill()
	if Economy.leaderboard.is_empty():
		_status.text = "Asking the server..."
	Economy.ask_leaderboard()
	visible = true


func close_panel() -> void:
	visible = false


func _fill() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for text in ["#", "Player", "Keep", "Might", "Barons beaten"]:
		_grid.add_child(_cell(text, MenuStyle.MUTED, 14, text != "Player"))
	var board: Dictionary = Economy.leaderboard
	var me: Variant = board.get("me")
	var my_name := String(me.get("name", "")) if me is Dictionary else ""
	var rank := 0
	for p: Dictionary in board.get("players", []):
		rank += 1
		var color := ME if String(p.name) == my_name else MenuStyle.TEXT
		_grid.add_child(_cell(str(rank), color, 16, true))
		var tag := String(p.get("tag", ""))
		var who := _cell(("[%s] " % tag if tag != "" else "") + String(p.name), color, 16, false)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(who)
		_grid.add_child(_cell(str(int(p.get("level", 1))), color, 16, true))
		_grid.add_child(_cell(str(int(p.get("might", 0))), color, 16, true))
		_grid.add_child(_cell(str(int(p.get("barons_beaten", 0))), color, 16, true))
	if board.is_empty():
		return
	if me is Dictionary:
		var beaten := int(me.get("barons_beaten", 0))
		_status.text = "Your castle is #%d of %d: %d might, %d %s beaten." % [int(board.get("rank", 0)),
				int(board.get("total", 0)), int(me.get("might", 0)), beaten, "baron" if beaten == 1 else "barons"]
	else:
		_status.text = "%d castles in the world." % int(board.get("total", 0))


static func _cell(text: String, color: Color, size: int, right: bool) -> Label:
	var l := MenuStyle.label(text, size, color)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l
