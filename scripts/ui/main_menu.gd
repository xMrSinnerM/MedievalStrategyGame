extends CanvasLayer
## The title screen: continue the last game, start a new one or load one
## from the save slots, change the settings or quit. main.gd starts the game
## when game_requested fires.

signal game_requested(slot: int, new_game: bool)
## You signed in to the multiplayer server; answer is its "state" or "join" reply.
signal online_requested(answer: Dictionary)

const BACKGROUND := "res://ui/menu_background.jpg"
const VIGNETTE := preload("res://shaders/menu_vignette.gdshader")
const CREDITS := [
	"Castles, buildings, trees and props: KayKit Medieval Hexagon Pack by Kay Lousberg (CC0), kaylousberg.com",
	"Soldiers: KayKit Adventurers Character Pack by Kay Lousberg (CC0)",
	"Fonts: Cinzel by Natanael Gama and Alegreya Sans by Huerta Tipográfica (SIL Open Font License)",
	"Made with the Godot Engine (MIT licence), godotengine.org",
]

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
var _online: PanelContainer
var _credits: PanelContainer
var _loading: Label


func _ready() -> void:
	layer = 40
	_build_background()

	# The menu hangs on a banner on the left; dialogs open beside it.
	var banner := MenuBanner.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	banner.offset_left = 90
	banner.offset_top = 18
	banner.offset_right = 490
	banner.offset_bottom = -36
	add_child(banner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	banner.add_child(column)
	column.add_child(MenuStyle.title("Medieval", 30))
	column.add_child(MenuStyle.title("Strategy", 46))
	column.add_child(_divider())
	var sub := MenuStyle.label("Build your castle, raise your warband,\nwin the realm", 16, Color(0.95, 0.86, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(sub)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.custom_minimum_size = Vector2(0, 14)
	column.add_child(gap)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_buttons)
	_continue = MenuStyle.menu_button("Continue", func() -> void: _start(Economy.last_played_slot(), false), 300.0, true)
	_buttons.add_child(_continue)
	_buttons.add_child(MenuStyle.menu_button("New game", _show_slots.bind(true)))
	_load = MenuStyle.menu_button("Load game", _show_slots.bind(false))
	_buttons.add_child(_load)
	_buttons.add_child(MenuStyle.menu_button("Play online", func() -> void:
		_show(_online)
		_online.open()))
	_buttons.add_child(MenuStyle.menu_button("Settings", func() -> void: _show(_settings)))
	_buttons.add_child(MenuStyle.menu_button("Credits", func() -> void: _show(_credits)))
	_buttons.add_child(MenuStyle.menu_button("Quit", func() -> void: get_tree().quit()))
	_loading = MenuStyle.title("Loading the realm...", 22)
	_loading.visible = false
	column.add_child(_loading)
	var gap2 := Control.new()
	gap2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(gap2)

	var area := CenterContainer.new()
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.offset_left = 520
	area.offset_right = -40
	add_child(area)
	column = VBoxContainer.new()
	area.add_child(column)

	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", MenuStyle.ornate_panel())
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
	_slots.add_theme_stylebox_override("panel", MenuStyle.ornate_panel())
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
	_settings.add_theme_stylebox_override("panel", MenuStyle.ornate_panel())

	_online = preload("res://scripts/ui/online_panel.gd").new()
	_online.visible = false
	_online.closed.connect(func() -> void: _show(null))
	_online.started.connect(_start_online)
	column.add_child(_online)
	_online.add_theme_stylebox_override("panel", MenuStyle.ornate_panel())

	_credits = _build_credits()
	_credits.visible = false
	column.add_child(_credits)
	refresh()


func refresh() -> void:
	## Called whenever the menu is shown again.
	var last := Economy.last_played_slot()
	_continue.visible = last > 0
	_continue.text = "Continue (slot %d)" % last
	_load.visible = Economy.has_save()
	_buttons.visible = true
	_loading.visible = false
	_show(null)


func _show(sub_panel: Control) -> void:
	## Opens one of the dialogs beside the banner, or none.
	_confirm.visible = sub_panel == _confirm
	_slots.visible = sub_panel == _slots
	_settings.visible = sub_panel == _settings
	_online.visible = sub_panel == _online
	_credits.visible = sub_panel == _credits


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
	_show(null)
	_buttons.visible = false
	_loading.visible = true
	# Let the "Loading" line draw before the world map takes a moment to build.
	await get_tree().process_frame
	await get_tree().process_frame
	game_requested.emit(slot, new_game)


func _start_online(answer: Dictionary) -> void:
	_show(null)
	_buttons.visible = false
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	online_requested.emit(answer)


func _build_credits() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.ornate_panel())
	panel.custom_minimum_size = Vector2(620, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(MenuStyle.title("Credits", 28))
	for line in CREDITS:
		var label := MenuStyle.label(line, 18, MenuStyle.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	var back := MenuStyle.button("Back", func() -> void: _show(null), 200.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	return panel


func _build_background() -> void:
	## The map picture drifts slowly, under a vignette and a few motes of
	## dust catching the light.
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(BACKGROUND):
		bg.texture = load(BACKGROUND)
	add_child(bg)
	bg.resized.connect(func() -> void: bg.pivot_offset = bg.size * Vector2(0.7, 0.5))
	var drift := bg.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(bg, "scale", Vector2.ONE * 1.08, 28.0)
	drift.tween_property(bg, "scale", Vector2.ONE, 28.0)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette := ShaderMaterial.new()
	vignette.shader = VIGNETTE
	shade.material = vignette
	add_child(shade)
	var motes := CPUParticles2D.new()
	motes.position = Vector2(1100, 950)
	motes.amount = 40
	motes.lifetime = 14.0
	motes.preprocess = 14.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(700, 20)
	motes.direction = Vector2(0.2, -1)
	motes.spread = 20.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 25.0
	motes.initial_velocity_max = 60.0
	motes.scale_amount_min = 1.5
	motes.scale_amount_max = 3.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.85, 0.5, 0.0))
	fade.set_color(1, Color(1.0, 0.85, 0.5, 0.0))
	fade.add_point(0.3, Color(1.0, 0.85, 0.5, 0.55))
	motes.color_ramp = fade
	add_child(motes)


func _divider() -> Control:
	## A thin gold rule with a diamond in the middle.
	var d := Control.new()
	d.custom_minimum_size = Vector2(0, 18)
	d.draw.connect(func() -> void:
		var y := d.size.y * 0.5
		var mid := d.size.x * 0.5
		var gold := Color(0.9, 0.7, 0.34)
		d.draw_line(Vector2(mid - 120, y), Vector2(mid - 12, y), gold, 2.0)
		d.draw_line(Vector2(mid + 12, y), Vector2(mid + 120, y), gold, 2.0)
		d.draw_colored_polygon(PackedVector2Array([Vector2(mid, y - 7), Vector2(mid + 7, y), Vector2(mid, y + 7), Vector2(mid - 7, y)]), gold))
	return d
