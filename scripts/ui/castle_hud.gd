extends CanvasLayer
## The castle screen's interface: resource bar, build menu, the selected
## building's panel and the list of constructions under way.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const RESOURCE_COLORS := {
	"wood": Color(0.85, 0.65, 0.4), "stone": Color(0.78, 0.78, 0.8),
	"food": Color(0.6, 0.85, 0.45), "gold": Color(1.0, 0.84, 0.35),
}

var view: Node3D   ## the castle view this HUD belongs to; set by the view

var _title: Label
var _resource_labels := {}
var _builders_label: Label
var _defense_label: Label
var _troops_label: Label
var _warband_button: Button
var _warband: PanelContainer
var _recruit: VBoxContainer
var _build_menu: PanelContainer
var _build_buttons := {}       ## type -> Button
var _side_panel: PanelContainer
var _side_scroll: ScrollContainer
var _side_box: VBoxContainer
var _side_title: Label
var _side_level: Label
var _side_text: RichTextLabel
var _upgrade_button: Button
var _move_button: Button
var _cancel_button: Button
var _progress: ProgressBar
var _queue_panel: PanelContainer
var _queue_list: VBoxContainer
var _queue_rows := {}          ## building id -> ProgressBar
var _queue_signature := "?"   ## "?" forces the first rebuild
var _hint: Label
var _toast: Label
var _toast_time := 0.0


func _ready() -> void:
	_build_top_bar()
	_build_build_menu()
	_build_side_panel()
	_build_queue_panel()
	_hint = _label("", 15, TEXT)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -150
	_hint.offset_bottom = -126
	_hint.offset_left = -400
	_hint.offset_right = 400
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_hint)
	_toast = _label("", 17, Color(1.0, 0.85, 0.6))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 120
	_toast.add_theme_constant_override("outline_size", 7)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_toast)
	var controls := _label("WASD / drag: pan    Q E / right-drag: rotate    wheel: zoom    Esc: deselect    C: world map", 13, MUTED)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 12
	controls.offset_top = -26
	controls.add_theme_constant_override("outline_size", 5)
	controls.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(controls)
	_warband = preload("res://scripts/ui/warband_panel.gd").new()
	_warband.hud = self
	_warband.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_warband.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warband.offset_top = 70
	add_child(_warband)
	Economy.changed.connect(_refresh)


func show_castle() -> void:
	## Called by the view when it opens a castle.
	view.selection_changed.connect(_on_selection_changed, CONNECT_REFERENCE_COUNTED)
	view.mode_changed.connect(_on_mode_changed, CONNECT_REFERENCE_COUNTED)
	view.message.connect(_show_toast, CONNECT_REFERENCE_COUNTED)
	_build_menu.visible = view.editable
	_warband_button.visible = view.editable
	_warband.visible = false
	_queue_signature = "?"
	_on_mode_changed(view.mode)
	_refresh()


# --- Layout -------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _panel_style(0.8, 0))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_title = _label("", 18, Color(1.0, 0.9, 0.65))
	row.add_child(_title)
	for r in ["wood", "stone", "food", "gold"]:
		var l := _label("", 15, RESOURCE_COLORS.get(r, TEXT))
		row.add_child(l)
		_resource_labels[r] = l
	_builders_label = _label("", 15, TEXT)
	row.add_child(_builders_label)
	_defense_label = _label("", 15, TEXT)
	row.add_child(_defense_label)
	_troops_label = _label("", 15, TEXT)
	row.add_child(_troops_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_warband_button = _button("Warband")
	_warband_button.pressed.connect(func() -> void:
		_warband.visible = not _warband.visible
		_warband.refresh())
	row.add_child(_warband_button)
	var back := _button("Map (C)")
	back.pressed.connect(func() -> void: EventBus.world_map_requested.emit())
	row.add_child(back)


func _build_build_menu() -> void:
	_build_menu = PanelContainer.new()
	_build_menu.add_theme_stylebox_override("panel", _panel_style(0.8, 8))
	_build_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_build_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_menu.offset_bottom = -34
	add_child(_build_menu)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_build_menu.add_child(row)
	var title := _label("Build", 16, Color(1.0, 0.9, 0.65))
	row.add_child(title)
	for type: String in Economy.rules.types:
		if Economy.rules.is_perimeter(type) or type == "keep":
			continue
		var b := _button("")
		b.custom_minimum_size = Vector2(138, 64)
		b.pressed.connect(func() -> void: view.start_placing(type))
		row.add_child(b)
		_build_buttons[type] = b


func _build_side_panel() -> void:
	_side_panel = PanelContainer.new()
	_side_panel.add_theme_stylebox_override("panel", _panel_style(0.85, 8))
	_side_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_side_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_side_panel.offset_top = 58
	_side_panel.offset_right = -12
	_side_panel.custom_minimum_size = Vector2(330, 0)
	_side_panel.visible = false
	add_child(_side_panel)
	# The panel scrolls when its content (the barracks) is taller than the
	# space between the top bar and the build menu.
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_panel.add_child(_side_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(box)
	_side_box = box
	var head := HBoxContainer.new()
	box.add_child(head)
	_side_title = _label("", 20, Color(1.0, 0.9, 0.65))
	_side_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_side_title)
	var close := _button("×")
	close.custom_minimum_size = Vector2(30, 0)
	close.pressed.connect(func() -> void: view.select(-1))
	head.add_child(close)
	_side_level = _label("", 15, MUTED)
	box.add_child(_side_level)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 18)
	_progress.show_percentage = false
	box.add_child(_progress)
	_side_text = RichTextLabel.new()
	_side_text.bbcode_enabled = true
	_side_text.fit_content = true
	_side_text.scroll_active = false
	_side_text.custom_minimum_size = Vector2(306, 0)
	_side_text.add_theme_color_override("default_color", TEXT)
	_side_text.add_theme_font_size_override("normal_font_size", 14)
	_side_text.add_theme_font_size_override("bold_font_size", 14)
	box.add_child(_side_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_upgrade_button = _button("Upgrade")
	_upgrade_button.pressed.connect(func() -> void: view.upgrade_selected())
	buttons.add_child(_upgrade_button)
	_move_button = _button("Move")
	_move_button.pressed.connect(func() -> void: view.start_moving())
	buttons.add_child(_move_button)
	_cancel_button = _button("Cancel construction")
	_cancel_button.pressed.connect(func() -> void: view.cancel_selected())
	buttons.add_child(_cancel_button)
	_recruit = preload("res://scripts/ui/recruit_panel.gd").new()
	_recruit.hud = self
	_recruit.visible = false
	box.add_child(_recruit)


func _build_queue_panel() -> void:
	_queue_panel = PanelContainer.new()
	_queue_panel.add_theme_stylebox_override("panel", _panel_style(0.75, 8))
	_queue_panel.position = Vector2(12, 58)
	_queue_panel.custom_minimum_size = Vector2(250, 0)
	add_child(_queue_panel)
	_queue_list = VBoxContainer.new()
	_queue_list.add_theme_constant_override("separation", 4)
	_queue_panel.add_child(_queue_list)


# --- Updates --------------------------------------------------------------------

func _process(delta: float) -> void:
	if view == null or view.castle == null:
		return
	var castle: CastleState = view.castle
	var t := Economy.now()
	for id: int in _queue_rows:
		var b := castle.get_building(id)
		if b.is_empty() or b.target <= 0:
			continue
		var bar: ProgressBar = _queue_rows[id]
		var total := castle.rules.build_time(b.type, b.target)
		bar.value = 100.0 * (1.0 - castle.time_left(id, t) / maxf(total, 1.0))
		var label: Label = bar.get_meta("label")
		var what := "new" if b.level == 0 else "level %d" % b.target
		label.text = "%s (%s)   %s" % [castle.rules.display_name(b.type), what, view.format_time(castle.time_left(id, t))]
	if view.selected >= 0:
		var sel := castle.get_building(view.selected)
		if not sel.is_empty() and sel.target > 0:
			var total := castle.rules.build_time(sel.type, sel.target)
			_progress.value = 100.0 * (1.0 - castle.time_left(sel.id, t) / maxf(total, 1.0))
			var left: String = view.format_time(castle.time_left(sel.id, t))
			_side_level.text = ("Being built, %s left" % left) if sel.level == 0 else ("Level %d → %d, %s left" % [sel.level, sel.target, left])
	if _recruit.visible:
		_recruit.update_progress(t)
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func _refresh() -> void:
	if view == null or view.castle == null or not is_inside_tree():
		return
	var castle: CastleState = view.castle
	var rules := castle.rules
	_title.text = castle.castle_name
	var cap := castle.storage_capacity()
	var rates := castle.net_per_hour()
	for r: String in _resource_labels:
		_resource_labels[r].text = "%s %d/%d  %+d/h" % [r.capitalize(), int(castle.resources.get(r, 0.0)), int(cap), int(rates.get(r, 0.0))]
	var total_builders := rules.builders(castle.keep_level())
	_builders_label.text = "Builders %d / %d" % [castle.free_builders(), total_builders]
	_defense_label.text = "Defence %d" % int(castle.defense())
	_troops_label.text = "Garrison %d" % castle.troop_count()
	_troops_label.tooltip_text = "Soldiers in the castle and its warband eat %d food an hour" % int(castle.upkeep_per_hour())
	_warband_button.text = "Warband %d" % castle.field_count()
	_warband.refresh()
	_troops_label.mouse_filter = Control.MOUSE_FILTER_PASS

	for type: String in _build_buttons:
		var b: Button = _build_buttons[type]
		var reason := castle.check_build(type)
		b.text = "%s  %d/%d\n%s\n%s" % [rules.display_name(type), castle.count(type), rules.max_count(type, castle.keep_level()),
			_cost_text(rules.cost(type, 1)), view.format_time(rules.build_time(type, 1))]
		b.disabled = reason != ""
		b.tooltip_text = reason if reason != "" else rules.types[type].get("description", "")

	_refresh_queue(castle)
	_refresh_side_panel()


func _refresh_queue(castle: CastleState) -> void:
	var list := castle.constructions()
	var parts: PackedStringArray = []
	for b in list:
		parts.append("%d:%d" % [b.id, b.target])
	var signature := "|".join(parts)
	if signature == _queue_signature:
		return
	_queue_signature = signature
	for child in _queue_list.get_children():
		_queue_list.remove_child(child)
		child.queue_free()
	_queue_rows.clear()
	_queue_panel.visible = not list.is_empty()
	_queue_list.add_child(_label("Under construction", 15, Color(1.0, 0.9, 0.65)))
	for b in list:
		var label := _label("", 13, TEXT)
		_queue_list.add_child(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(226, 10)
		bar.set_meta("label", label)
		_queue_list.add_child(bar)
		_queue_rows[b.id] = bar
	_queue_panel.reset_size()


func _refresh_side_panel() -> void:
	var castle: CastleState = view.castle
	var b := castle.get_building(view.selected) if view.selected >= 0 else {}
	_side_panel.visible = not b.is_empty()
	if b.is_empty():
		return
	var rules := castle.rules
	var type: String = b.type
	var building: bool = b.target > 0
	_side_title.text = rules.display_name(type)
	var max_level := int(rules.types[type].get("max_level", 10))
	_side_level.text = "Level %d of %d" % [b.level, max_level] if not building else ""
	_progress.visible = building

	var lines: PackedStringArray = []
	lines.append("[color=#c8b89e]%s[/color]" % rules.types[type].get("description", ""))
	var next: int = b.level + 1 if not building else b.target
	var stat_now := _stats(type, b.level)
	var stat_next := _stats(type, next) if next <= max_level else ""
	if stat_now != "" or stat_next != "":
		lines.append("")
		lines.append("[b]Now:[/b] %s" % (stat_now if stat_now != "" else "nothing yet"))
		if stat_next != "":
			lines.append("[b]Level %d:[/b] %s" % [next, stat_next])
	if type == "keep":
		lines.append("[b]Builders:[/b] %d, at level %d: %d" % [rules.builders(b.level), mini(b.level + 1, max_level), rules.builders(mini(b.level + 1, max_level))])
		lines.append("Other buildings can reach level %d" % rules.max_level("woodcutter", b.level))
	var reason := castle.check_upgrade(b.id) if view.editable else ""
	if not view.editable:
		pass
	elif not building and next <= max_level:
		lines.append("")
		lines.append("[b]Upgrade:[/b] %s, %s" % [_cost_text(rules.cost(type, next), castle), view.format_time(rules.build_time(type, next))])
		if reason != "":
			lines.append("[color=#ff9a7a]%s[/color]" % reason)
	elif not building:
		lines.append("")
		lines.append("[color=#9fd18a]Fully upgraded[/color]")
	if building and view.editable:
		lines.append("")
		lines.append("Cancelling refunds %d%% of the cost." % int(CastleState.CANCEL_REFUND * 100.0))
	_side_text.text = "\n".join(lines)

	_upgrade_button.visible = view.editable and not building and next <= max_level
	_upgrade_button.disabled = reason != ""
	_upgrade_button.text = "Upgrade to level %d" % next
	_move_button.visible = view.editable and b.cell.x >= 0
	_cancel_button.visible = view.editable and building
	_recruit.visible = type == "barracks" and b.level > 0
	if _recruit.visible:
		_recruit.refresh()
	_fit_side_panel.call_deferred()


func _fit_side_panel() -> void:
	var room := get_viewport().get_visible_rect().size.y - 58.0 - (150.0 if _build_menu.visible else 40.0)
	var want := _side_box.get_combined_minimum_size()
	_side_scroll.custom_minimum_size = Vector2(want.x + 10.0, minf(want.y, room))
	_side_panel.reset_size()


func _stats(type: String, level: int) -> String:
	var rules: BuildingRules = view.castle.rules
	var parts: PackedStringArray = []
	var produces := rules.production(type, level)
	for r: String in produces:
		parts.append("+%d %s/h" % [roundi(produces[r]), r])
	var store := rules.storage(type, level)
	if store > 0.0:
		parts.append("stores %d of each" % roundi(store))
	var def := rules.defense(type, level)
	if def > 0.0:
		parts.append("defence %d" % roundi(def))
	return ", ".join(parts)


func _cost_text(cost: Dictionary, castle: CastleState = null) -> String:
	## "60 wood, 30 stone"; with a castle, resources it lacks are shown in red.
	var parts: PackedStringArray = []
	for r: String in cost:
		var part := "%d %s" % [int(cost[r]), r]
		if castle != null and castle.resources.get(r, 0.0) + 0.0001 < cost[r]:
			part = "[color=#ff8a6a]%s[/color]" % part
		parts.append(part)
	return ", ".join(parts)


func _on_selection_changed(_id: int) -> void:
	_refresh_side_panel()


func _on_mode_changed(mode: int) -> void:
	var rules: BuildingRules = view.castle.rules if view.castle else Economy.rules
	match mode:
		1:
			_hint.text = "Placing a %s: click a free spot. Right-click or Esc to stop." % rules.display_name(view.placing_type).to_lower()
		2:
			_hint.text = "Moving the %s: click its new spot. Right-click or Esc to stop." % rules.display_name(view.placing_type).to_lower()
		_:
			_hint.text = "" if view.editable else "You're visiting this castle; only its lord can build here."
	_build_menu.modulate.a = 0.5 if mode != 0 else 1.0


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 3.0
	_toast.modulate.a = 1.0


# --- Helpers ----------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var normal := _panel_style(0.9, 6)
	normal.bg_color = Color(0.3, 0.22, 0.14, 0.95)
	normal.border_color = Color(0.6, 0.47, 0.28)
	normal.set_border_width_all(1)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.4, 0.3, 0.18, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.22, 0.16, 0.1, 0.95)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.2, 0.17, 0.14, 0.8)
	disabled.border_color = Color(0.35, 0.3, 0.25)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.45))
	return b


func _panel_style(alpha: float, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, alpha)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(10)
	return style
