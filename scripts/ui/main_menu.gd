extends CanvasLayer
## The title screen: continue the saved game, start a new one, change the
## settings or quit. main.gd listens for the two start signals.

signal continue_requested
signal new_game_requested

const BACKGROUND := "res://ui/menu_background.jpg"

var _buttons: VBoxContainer
var _continue: Button
var _confirm: PanelContainer
var _settings: PanelContainer
var _loading: Label


func _ready() -> void:
	layer = 40
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(BACKGROUND):
		bg.texture = load(BACKGROUND)
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.03, 0.02, 0.45)
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	centre.add_child(column)
	column.add_child(MenuStyle.title("Medieval Strategy", 64))
	var sub := MenuStyle.label("Build your castle, raise your warband, win the realm", 20, MenuStyle.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(0.85))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	panel.add_child(_buttons)
	_continue = MenuStyle.button("Continue", _start.bind(false))
	_buttons.add_child(_continue)
	_buttons.add_child(MenuStyle.button("New game", _ask_new_game))
	_buttons.add_child(MenuStyle.button("Settings", func() -> void: _show(_settings)))
	_buttons.add_child(MenuStyle.button("Quit", func() -> void: get_tree().quit()))
	_loading = MenuStyle.label("Loading the realm...", 20, MenuStyle.GOLD)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.visible = false
	column.add_child(_loading)

	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", MenuStyle.panel())
	var ask := VBoxContainer.new()
	ask.add_theme_constant_override("separation", 14)
	_confirm.add_child(ask)
	ask.add_child(MenuStyle.title("Start a new game?", 26))
	ask.add_child(MenuStyle.label("Your current castle and everything in it will be replaced."))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(MenuStyle.button("Start again", _start.bind(true), 180.0))
	row.add_child(MenuStyle.button("Cancel", func() -> void: _show(null), 180.0))
	ask.add_child(row)
	_confirm.visible = false
	column.add_child(_confirm)

	_settings = preload("res://scripts/ui/settings_panel.gd").new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _show(null))
	column.add_child(_settings)
	refresh()


func refresh() -> void:
	## Called whenever the menu is shown again.
	_continue.visible = Economy.has_save()
	_loading.visible = false
	_show(null)


func _show(sub_panel: Control) -> void:
	## Shows one of the sub-panels in place of the main buttons, or the buttons.
	_buttons.get_parent().visible = sub_panel == null
	_confirm.visible = sub_panel == _confirm
	_settings.visible = sub_panel == _settings


func _ask_new_game() -> void:
	if Economy.has_save():
		_show(_confirm)
	else:
		_start(true)


func _start(new_game: bool) -> void:
	_show(_loading)
	_buttons.get_parent().visible = false
	_loading.visible = true
	# Let the "Loading" line draw before the world map takes a moment to build.
	await get_tree().process_frame
	await get_tree().process_frame
	if new_game:
		new_game_requested.emit()
	else:
		continue_requested.emit()
