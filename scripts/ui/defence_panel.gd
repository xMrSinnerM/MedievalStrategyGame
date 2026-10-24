extends PanelContainer
## Sets how a castle's garrison mans its defences (CastleState.layout): the
## share of soldiers on the left, front and right walls and in the courtyard,
## where they make a last stand once a wall is broken (Battle.siege()), and
## which defence tools from the siege workshop stand on each wall
## (CastleState.defence_tools). Spies who scout the castle see both.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const HEAD := Color(1.0, 0.9, 0.65)
const BAD := Color(1.0, 0.6, 0.48)
const GOOD := Color(0.62, 0.82, 0.54)
const POSTS := ["left", "front", "right", "courtyard"]
const NAMES := {"left": "Left wall", "front": "Front wall", "right": "Right wall", "courtyard": "Courtyard"}
const WALLS := ["left", "front", "right"]

var hud: CanvasLayer     ## the castle HUD, for its view and button style

var _sliders := {}       ## post -> HSlider
var _shares := {}        ## post -> Label with the percentage
var _counts := {}        ## post -> Label with the soldiers there
var _total: Label
var _save: Button
var _quiet := false
var _spins := {}         ## defence tool -> {wall -> SpinBox}
var _tool_info: Label
var _save_tools: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.92, 14))
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label("Defence", 20, HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close: Button = hud._button("×")
	close.custom_minimum_size = Vector2(30, 0)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	var about := _label("Choose where your soldiers stand when the castle is attacked. Attackers must "
			+ "break a wall, then beat the reserve in the courtyard. Spies who scout your castle see this.", 14, MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(520, 0)
	box.add_child(about)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for post: String in POSTS:
		grid.add_child(_label(NAMES[post], 15, TEXT))
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(240, 24)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(func(_v: float) -> void:
			if not _quiet:
				_update())
		grid.add_child(slider)
		_sliders[post] = slider
		var share := _label("", 15, TEXT)
		share.custom_minimum_size = Vector2(48, 0)
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(share)
		_shares[post] = share
		var count := _label("", 14, MUTED)
		count.custom_minimum_size = Vector2(120, 0)
		grid.add_child(count)
		_counts[post] = count
	_total = _label("", 15, TEXT)
	box.add_child(_total)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var reset: Button = hud._button("Default")
	reset.tooltip_text = "25% left, 35% front, 25% right, 15% courtyard"
	reset.pressed.connect(func() -> void: _show(Battle.DEFAULT_LAYOUT))
	buttons.add_child(reset)
	_save = hud._button("Save")
	_save.custom_minimum_size = Vector2(120, 0)
	_save.pressed.connect(_save_layout)
	buttons.add_child(_save)
	_build_tools(box)


func _build_tools(box: VBoxContainer) -> void:
	## The defence tools part: one row per tool, a number for each wall.
	Economy.ensure_loaded()
	var rules: BuildingRules = Economy.rules
	box.add_child(HSeparator.new())
	box.add_child(_label("Defence tools", 17, HEAD))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	grid.add_child(_label("", 14, MUTED))
	for w: String in WALLS:
		grid.add_child(_label(NAMES[w], 14, MUTED))
	for tool: String in rules.tools:
		if rules.tool_side(tool) != "defence":
			continue
		var name_label := _label(rules.tool_plural(tool), 15, TEXT)
		name_label.custom_minimum_size = Vector2(150, 0)
		name_label.tooltip_text = String(rules.tools[tool].get("description", ""))
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(name_label)
		_spins[tool] = {}
		for w: String in WALLS:
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.step = 1
			spin.custom_minimum_size = Vector2(100, 0)
			spin.value_changed.connect(func(_v: float) -> void:
				if not _quiet:
					_update_tools())
			grid.add_child(spin)
			_spins[tool][w] = spin
	_tool_info = _label("", 14, TEXT)
	_tool_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_info.custom_minimum_size = Vector2(520, 0)
	box.add_child(_tool_info)
	_save_tools = hud._button("Save tools")
	_save_tools.custom_minimum_size = Vector2(120, 0)
	_save_tools.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_save_tools.pressed.connect(_save_tool_plan)
	box.add_child(_save_tools)


func refresh() -> void:
	## Shows the castle's current layout and defence tools.
	_show(hud.view.castle.layout)
	_show_tools(hud.view.castle.defence_tools)


func layout() -> Dictionary:
	## The layout as set on the sliders.
	var out := {}
	for post: String in POSTS:
		out[post] = int(_sliders[post].value)
	return out


func _show(values: Dictionary) -> void:
	_quiet = true
	for post: String in POSTS:
		_sliders[post].value = int(values.get(post, 0))
	_quiet = false
	_update()


static func sum_ok(values: Dictionary) -> bool:
	var sum := 0
	for post: String in POSTS:
		sum += int(values[post])
	return sum == 100


func update_counts() -> void:
	## Called when the castle changes: the soldiers at each post (and whether
	## the sliders differ from the saved layout), keeping what is being edited.
	_update()
	_update_tools()


func tool_plan() -> Dictionary:
	## The defence tools as set on the number boxes, {wall: {tool: n}}.
	var out := {}
	for tool: String in _spins:
		for w: String in WALLS:
			var n := int(_spins[tool][w].value)
			if n > 0:
				if not out.has(w):
					out[w] = {}
				out[w][tool] = n
	return out


func _show_tools(group: Dictionary) -> void:
	_quiet = true
	for tool: String in _spins:
		for w: String in WALLS:
			var spin: SpinBox = _spins[tool][w]
			spin.max_value = 999
			spin.value = int(group.get(w, {}).get(tool, 0))
	_quiet = false
	_update_tools()


func _update_tools() -> void:
	var castle: CastleState = hud.view.castle
	var rules := castle.rules
	var slots := castle.defence_slots()
	var editable: bool = hud.view.editable
	var plan := tool_plan()
	for tool: String in _spins:
		for w: String in WALLS:
			var spin: SpinBox = _spins[tool][w]
			spin.editable = editable and slots > 0
			spin.max_value = maxi(slots, int(spin.value))
	var lines: PackedStringArray = []
	var stock: PackedStringArray = []
	for tool: String in _spins:
		var n := int(castle.tools.get(tool, 0))
		if n > 0:
			stock.append("%d %s" % [n, rules.tool_name(tool).to_lower() if n == 1 else rules.tool_plural(tool).to_lower()])
	if slots < 1:
		lines.append("Build a wall to post defence tools on it.")
	else:
		lines.append("Up to %d tools fit on each wall (wall level %d). Arrow slits and boiling pitch hurt attackers, a moat makes the wall stronger. Tools on a wall that falls are lost." % [slots, castle.wall_level()])
	lines.append("In store: %s. Build more in the siege workshop." % (", ".join(stock) if not stock.is_empty() else "none"))
	var why := castle.check_defence_tools(plan)
	var color := TEXT
	if why != "":
		lines.append(why)
		color = BAD
	elif plan == castle.defence_tools:
		lines.append("These tools stand on your walls now.")
		color = GOOD
	else:
		lines.append("Press Save tools to post them.")
	_tool_info.text = "\n".join(lines)
	_tool_info.add_theme_color_override("font_color", color)
	_save_tools.visible = editable
	_save_tools.disabled = why != "" or plan == castle.defence_tools


func _save_tool_plan() -> void:
	var why := Economy.set_defence_tools(hud.view.castle, tool_plan())
	if why != "":
		hud._show_toast(why)
		return
	hud._show_toast("Your defence tools are posted on the walls.")
	_update_tools()


func _update() -> void:
	var castle: CastleState = hud.view.castle
	var now := layout()
	var posts := Battle.split(castle.troops, now, ["left", "right", "courtyard", "front"])
	var sum := 0
	for post: String in POSTS:
		sum += int(now[post])
		_shares[post].text = "%d%%" % now[post]
		var n := 0
		for unit: String in posts[post]:
			n += int(posts[post][unit])
		_counts[post].text = "%d soldier%s" % [n, "" if n == 1 else "s"] if sum_ok(now) else ""
	var editable: bool = hud.view.editable
	for post: String in POSTS:
		_sliders[post].editable = editable
	if sum != 100:
		_total.text = "Total %d%%: the walls and courtyard must add up to 100%%." % sum
		_total.add_theme_color_override("font_color", BAD)
	elif now == castle.layout:
		_total.text = "Total 100%. This is how your castle is defended now."
		_total.add_theme_color_override("font_color", GOOD)
	else:
		_total.text = "Total 100%. Press Save to use this layout."
		_total.add_theme_color_override("font_color", TEXT)
	if sum == 100:
		var empty: PackedStringArray = []
		for post: String in ["left", "front", "right"]:
			if int(now[post]) == 0:
				empty.append(post)
		if not empty.is_empty():
			_total.text += "\nNobody guards the %s wall%s: attackers walk straight in." % [" and ".join(empty), "s" if empty.size() > 1 else ""]
		if int(now.courtyard) == 0:
			_total.text += "\nNobody waits in the courtyard: one broken wall loses the castle."
	_save.visible = editable
	_save.disabled = sum != 100 or now == castle.layout


func _save_layout() -> void:
	var why := Economy.set_layout(hud.view.castle, layout())
	if why != "":
		hud._show_toast(why)
		return
	hud._show_toast("Your soldiers take up their new posts.")
	_update()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
