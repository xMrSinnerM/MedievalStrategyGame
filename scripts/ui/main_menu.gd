extends CanvasLayer
## The title screen: continue the last game, start a new one or load one
## from the save slots, change the settings or quit. main.gd starts the game
## when game_requested fires.

signal game_requested(slot: int, new_game: bool)

const BACKGROUND := "res://ui/menu_background.jpg"

var _buttons: VBoxContainer
var _continue: Button
var _load: Button
var _slots: PanelContainer
var _slots_title: Label
var _slot_rows: VBoxContainer
var _confirm: PanelContainer
var _confirm_title: Label
var _confirm_text: Label
var _confirm_action := Callable()
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
	_continue = MenuStyle.button("Continue", func() -> void: _start(Economy.last_played_slot(), false))
	_buttons.add_child(_continue)
	_buttons.add_child(MenuStyle.button("New game", _show_slots.bind(true)))
	_load = MenuStyle.button("Load game", _show_slots.bind(false))
	_buttons.add_child(_load)
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
	_confirm_title = MenuStyle.title("", 26)
	ask.add_child(_confirm_title)
	_confirm_text = MenuStyle.label("")
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(MenuStyle.button("Yes", func() -> void: _confirm_action.call(), 180.0))
	row.add_child(MenuStyle.button("Cancel", func() -> void: _show(_slots), 180.0))
	ask.add_child(row)
	_confirm.visible = false
	column.add_child(_confirm)

	_slots = PanelContainer.new()
	_slots.add_theme_stylebox_override("panel", MenuStyle.panel())
	_slots.custom_minimum_size = Vector2(620, 0)
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 14)
	_slots.add_child(slot_box)
	_slots_title = MenuStyle.title("", 28)
	slot_box.add_child(_slots_title)
	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 10)
	slot_box.add_child(_slot_rows)
	var back := MenuStyle.button("Back", func() -> void: _show(null), 200.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot_box.add_child(back)
	_slots.visible = false
	column.add_child(_slots)

	_settings = preload("res://scripts/ui/settings_panel.gd").new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _show(null))
	column.add_child(_settings)
	refresh()


func refresh() -> void:
	## Called whenever the menu is shown again.
	var last := Economy.last_played_slot()
	_continue.visible = last > 0
	_continue.text = "Continue (slot %d)" % last
	_load.visible = Economy.has_save()
	_loading.visible = false
	_show(null)


func _show(sub_panel: Control) -> void:
	## Shows one of the sub-panels in place of the main buttons, or the buttons.
	_buttons.get_parent().visible = sub_panel == null
	_confirm.visible = sub_panel == _confirm
	_slots.visible = sub_panel == _slots
	_settings.visible = sub_panel == _settings


func _show_slots(for_new_game: bool) -> void:
	_slots_title.text = "Choose a slot for your new game" if for_new_game else "Load a game"
	for child in _slot_rows.get_children():
		_slot_rows.remove_child(child)
		child.queue_free()
	for k in range(1, Economy.SLOTS + 1):
		var info := Economy.slot_info(k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(MenuStyle.label("Slot %d" % k, 19, MenuStyle.GOLD))
		text.add_child(MenuStyle.label(_describe(info), 15, MenuStyle.MUTED))
		row.add_child(text)
		if for_new_game:
			row.add_child(MenuStyle.button("Start here", func() -> void:
				if info.is_empty():
					_start(k, true)
				else:
					_ask("Replace slot %d?" % k, "The game saved there will be lost.", _start.bind(k, true)), 150.0))
		else:
			var play := MenuStyle.button("Load", _start.bind(k, false), 110.0)
			play.disabled = info.is_empty()
			row.add_child(play)
			var delete := MenuStyle.button("Delete", func() -> void:
				_ask("Delete slot %d?" % k, "This game can't be brought back.", func() -> void:
					Economy.delete_slot(k)
					refresh()
					_show_slots(false)), 110.0)
			delete.disabled = info.is_empty()
			row.add_child(delete)
		_slot_rows.add_child(row)
	_show(_slots)


func _describe(info: Dictionary) -> String:
	if info.is_empty():
		return "Empty"
	var when := Time.get_datetime_string_from_unix_time(int(info.saved_at + Time.get_time_zone_from_system().bias * 60), true)
	return "Keep level %d, %d castle%s, %d soldiers. Saved %s" % [info.keep, info.castles,
			"" if info.castles == 1 else "s", info.soldiers, when.substr(0, 16)]


func _ask(title: String, text: String, action: Callable) -> void:
	_confirm_title.text = title
	_confirm_text.text = text
	_confirm_action = action
	_show(_confirm)


func _start(slot: int, new_game: bool) -> void:
	_show(_loading)
	_buttons.get_parent().visible = false
	_loading.visible = true
	# Let the "Loading" line draw before the world map takes a moment to build.
	await get_tree().process_frame
	await get_tree().process_frame
	game_requested.emit(slot, new_game)
