class_name GameWindow
extends Control
## One frame for the map's windows, so they all look and sit the same: the
## map dims behind it, the frame stays in the middle at one size, with an
## icon and a title, "?" for the longer explanations, a close button and, when
## it holds more than one screen, tabs (Quests | Achievements).
##
## The screens inside (pages) are the old panels. They still open and close
## themselves as before, from their keys, buttons and Esc; the window follows
## them: it shows the page that opened, closes the others and hides itself
## when none is left open. A page can mark its own title row
## (meta "window_head"), its own close button (meta "window_close") and its
## explanation (meta "window_help", a Label) for the window to take over.

const SIZE := Vector2(1120, 720)
const TOP := 70.0             ## below the resource bar

var _icon: TextureRect
var _title: Label
var _tab_row: HBoxContainer
var _body: VBoxContainer
var _help_button: Button
var _help_box: PanelContainer
var _help_text: Label
var _frame: PanelContainer
var _pages: Array[Control] = []
var _scrolls: Array[ScrollContainer] = []
var _tabs: Array[Button] = []
var _names: PackedStringArray = []
var _current: Control
var _syncing := false


func _init(title: String, icon: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent) -> void:
		# A click beside the window closes it, like the close button.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.offset_top = TOP
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", MenuStyle.panel(0.96))
	_frame.custom_minimum_size = SIZE
	centre.add_child(_frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_frame.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_icon = Icons.rect(icon, 34)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_icon)
	_title = MenuStyle.title(title, 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_help_button = _square("?", func() -> void:
		_help_text.text = _help()
		_help_box.visible = not _help_box.visible)
	_help_button.tooltip_text = "What is this?"
	head.add_child(_help_button)
	head.add_child(_square("×", close))
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	_tab_row.visible = false
	box.add_child(_tab_row)
	_help_box = PanelContainer.new()
	_help_box.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 12))
	_help_box.visible = false
	box.add_child(_help_box)
	_help_text = MenuStyle.label("", 15, MenuStyle.MUTED)
	_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_box.add_child(_help_text)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func add_page(page: Control, tab := "") -> Control:
	## Puts a panel in the window, under a tab named `tab` when there are
	## several. Returns the page, so it can be kept by whoever opens it.
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	page.custom_minimum_size.x = 0.0
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	scroll.add_child(page)
	_body.add_child(scroll)
	_pages.append(page)
	_scrolls.append(scroll)
	_names.append(tab)
	var b := Button.new()
	b.text = tab
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(160, 38)
	b.add_theme_font_override("font", GameTheme.TITLE_FONT)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func() -> void: open(page))
	_tabs.append(b)
	_tab_row.add_child(b)
	_tab_row.visible = _pages.size() > 1
	page.visibility_changed.connect(_on_page_shown.bind(page))
	if page.is_node_ready():
		_take_over(page)
	else:
		page.ready.connect(func() -> void: _take_over(page), CONNECT_ONE_SHOT)
	return page


func open(page: Control) -> void:
	## Opens a page the way its own key would.
	if page.visible and visible:
		return
	if page.has_method("open_panel") and page.get_method_argument_count("open_panel") == 0:
		page.call("open_panel")
	elif page.has_method("toggle") and not page.visible:
		page.call("toggle")
	else:
		page.visible = true


func toggle() -> void:
	## Opens the first page, or closes the window.
	if visible:
		close()
	elif not _pages.is_empty():
		open(_pages[0])


func close() -> void:
	if _current != null:
		_close_page(_current)
	visible = false


func is_open() -> bool:
	return visible


func _help() -> String:
	## The open page's explanation, as it reads now.
	if _current == null:
		return ""
	var help: Label = _current.get_meta("window_help") if _current.has_meta("window_help") else null
	return help.text if is_instance_valid(help) else ""


func _take_over(page: Control) -> void:
	## The window shows the title and close button, so the page's own go.
	## Pages that rebuild their explanation check meta "in_window" to hide it.
	page.set_meta("in_window", true)
	# The window is the frame; the page's own board (set in its _ready) goes.
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var head: Control = page.get_meta("window_head") if page.has_meta("window_head") else null
	if head != null:
		head.visible = false
	var close_button: Control = page.get_meta("window_close") if page.has_meta("window_close") else null
	if close_button != null:
		close_button.visible = false
	var help: Label = page.get_meta("window_help") if page.has_meta("window_help") else null
	if is_instance_valid(help):
		help.visible = false
	# The page's own min width (made for a free-standing window) would push
	# the frame wider than the others.
	page.custom_minimum_size.x = 0.0
	# Lists inside the page grow to fill the frame instead of keeping the
	# height they had in a window of their own.
	for list in page.find_children("*", "ScrollContainer", true, false):
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _on_page_shown(page: Control) -> void:
	if _syncing:
		return
	var i := _pages.find(page)
	if page.visible:
		_syncing = true
		for other in _pages:
			if other != page and other.visible:
				_close_page(other)
		_syncing = false
		_current = page
		for j in _pages.size():
			_scrolls[j].visible = j == i
			_style_tab(_tabs[j], j == i)
		_scrolls[i].scroll_vertical = 0
		_help_button.visible = page.has_meta("window_help")
		_help_box.visible = false
		# One window at a time: opening this one closes any other.
		for other in get_parent().get_children():
			if other is GameWindow and other != self and other.visible:
				other.close()
		visible = true
	else:
		_scrolls[i].visible = false
		for other in _pages:
			if other.visible:
				return
		_current = null
		visible = false


func _close_page(page: Control) -> void:
	if page.has_method("close_panel"):
		page.call("close_panel")
	else:
		page.visible = false


func _fit() -> void:
	## The same size everywhere, but never bigger than the screen.
	var room := get_viewport_rect().size - Vector2(32, TOP + 16)
	_frame.custom_minimum_size = SIZE.min(room)


func _style_tab(b: Button, on: bool) -> void:
	## Tabs sit on the board like bookmarks: the open one is crimson with a
	## gold rim and a gold edge along its foot, the others dark.
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		b.remove_theme_stylebox_override(state)
	if on:
		var s := _tab_box(Color(0.4, 0.085, 0.06), GameTheme.RIM_BRIGHT)
		s.border_width_bottom = 3
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, s)
		b.add_theme_color_override("font_color", GameTheme.GOLD)
		b.add_theme_color_override("font_hover_color", GameTheme.GOLD)
	else:
		b.add_theme_stylebox_override("normal", _tab_box(Color(0.075, 0.06, 0.047, 0.95), Color(GameTheme.RIM_DIM, 0.7)))
		b.add_theme_stylebox_override("hover", _tab_box(Color(0.2, 0.06, 0.045, 0.95), GameTheme.RIM))
		b.add_theme_stylebox_override("pressed", _tab_box(Color(0.3, 0.07, 0.05), GameTheme.RIM_BRIGHT))
		b.add_theme_color_override("font_color", MenuStyle.MUTED)
		b.remove_theme_color_override("font_hover_color")


static func _tab_box(bg: Color, rim: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = rim
	s.set_border_width_all(1)
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 1)
	return s


func _square(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 36)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	return b
