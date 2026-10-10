extends PanelContainer
## Display settings, shared by the main menu and the pause menu. Changes apply
## at once and are saved by the Settings autoload.

signal closed

var _rows: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel())
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	box.add_child(MenuStyle.title("Settings", 28))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	box.add_child(_rows)
	_toggle("Fullscreen", "fullscreen")
	_toggle("Vertical sync", "vsync")
	_toggle("Shadows", "shadows")
	_toggle("Ambient occlusion", "ambient_occlusion")
	_slider("3D resolution", "render_scale", 0.5, 1.0, 0.05, "%d%%", 100.0)
	_slider("Interface size", "ui_scale", 0.75, 1.5, 0.05, "%d%%", 100.0)
	var back := MenuStyle.button("Back", func() -> void: closed.emit(), 200.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := MenuStyle.label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_rows.add_child(row)
	return row


func _toggle(text: String, key: String) -> void:
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.button_pressed = bool(Settings.get_value(key))
	check.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	_row(text).add_child(check)


func _slider(text: String, key: String, lo: float, hi: float, step: float, fmt: String, show_scale: float) -> void:
	var row := _row(text)
	var value_label := MenuStyle.label("", 16, MenuStyle.MUTED)
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(160, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(Settings.get_value(key))
	value_label.text = fmt % roundi(slider.value * show_scale)
	# While dragging, only the number follows; the value applies on release so
	# changing the interface size doesn't resize the slider under the mouse.
	var dragging := [false]
	slider.drag_started.connect(func() -> void: dragging[0] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging[0] = false
		Settings.set_value(key, slider.value))
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt % roundi(v * show_scale)
		if not dragging[0]:
			Settings.set_value(key, v))
	row.add_child(slider)
	row.add_child(value_label)
