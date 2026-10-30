extends CanvasLayer
## Esc during the game: pauses the map and offers saving, settings, going back
## to the title screen or quitting. Castles keep growing on the clock while
## paused, like when the game is closed.

signal main_menu_requested
signal tutorial_requested

var _panel: MenuBanner
var _settings: PanelContainer
var _note: Label


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.01, 0.55)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	centre.add_child(column)
	_panel = MenuBanner.new()
	_panel.custom_minimum_size = Vector2(380, 0)
	column.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	box.add_child(MenuStyle.title("Paused", 34))
	box.add_child(MenuStyle.menu_button("Resume", close, 280.0, true))
	box.add_child(MenuStyle.menu_button("Save game", _save, 280.0))
	box.add_child(MenuStyle.menu_button("Settings", func() -> void:
		_panel.visible = false
		_settings.visible = true, 280.0))
	box.add_child(MenuStyle.menu_button("Replay tutorial", func() -> void:
		close()
		tutorial_requested.emit(), 280.0))
	box.add_child(MenuStyle.menu_button("Main menu", func() -> void:
		close()
		main_menu_requested.emit(), 280.0))
	# A browser tab can't quit itself; players just close the tab.
	if not OS.has_feature("web"):
		box.add_child(MenuStyle.menu_button("Quit to desktop", func() -> void:
			Economy.save_game()
			get_tree().quit(), 280.0))
	_note = MenuStyle.label("", 15, MenuStyle.MUTED)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	_settings = preload("res://scripts/ui/settings_panel.gd").new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_panel.visible = true)
	column.add_child(_settings)
	_settings.add_theme_stylebox_override("panel", MenuStyle.ornate_panel())


func open() -> void:
	visible = true
	_panel.visible = true
	_settings.visible = false
	_note.text = "Playing slot %d. Esc to resume." % Economy.slot
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func toggle() -> void:
	if visible:
		if _settings.visible:
			_settings.visible = false
			_panel.visible = true
		else:
			close()
	else:
		open()


func _save() -> void:
	Economy.save_game()
	_note.text = "Saved to slot %d at %s" % [Economy.slot, Time.get_time_string_from_system().substr(0, 5)]
