extends VBoxContainer
## The siege workshop part of the castle's building panel: build siege tools,
## see the workshop's queue and the tools in store. Attack tools go with your
## attacks (the attack screen); defence tools are posted on your walls (the
## Defence screen). Read-only when visiting someone else's castle.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const HEAD := Color(1.0, 0.9, 0.65)
const AMOUNTS := [1, 5, 10]

var hud: CanvasLayer     ## the castle HUD, for its view and button style

var _tool_rows := {}      ## tool -> {info, cost, line, buttons, max}
var _tools_box: VBoxContainer
var _queue_box: VBoxContainer
var _queue_signature := "?"
var _queue_bar: ProgressBar
var _queue_first: Label
var _store: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(HSeparator.new())
	add_child(_label("Build siege tools", 16, HEAD))
	_tools_box = VBoxContainer.new()
	_tools_box.add_theme_constant_override("separation", 6)
	add_child(_tools_box)
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 3)
	add_child(_queue_box)
	_store = _label("", 14, TEXT)
	_store.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_store.custom_minimum_size = Vector2(306, 0)
	add_child(_store)


func refresh() -> void:
	var view: Node3D = hud.view
	var castle: CastleState = view.castle
	var rules := castle.rules
	if _tool_rows.is_empty():
		_build_rows(rules)
	for tool: String in _tool_rows:
		var row: Dictionary = _tool_rows[tool]
		var locked := castle.workshop_level() < rules.tool_workshop_level(tool)
		var side := "attack" if rules.tool_side(tool) == "attack" else "defence"
		if locked:
			row.info.text = "%s (%s): unlocks at workshop level %d" % [rules.tool_name(tool), side, rules.tool_workshop_level(tool)]
		else:
			row.info.text = "%s (%s), %d in store\n%s" % [rules.tool_name(tool), side, int(castle.tools.get(tool, 0)),
				String(rules.tools[tool].get("description", ""))]
			row.cost.text = "%s, %s each" % [hud._cost_text(rules.tool_cost(tool)), view.format_time(castle.tool_time(tool))]
		row.info.modulate.a = 0.5 if locked else 1.0
		row.line.visible = not locked
		var can := castle.affordable_tools(tool)
		for b: Button in row.buttons:
			var n: int = b.get_meta("amount")
			var reason := castle.check_craft(tool, n)
			b.visible = view.editable and not locked
			b.disabled = reason != ""
			b.tooltip_text = reason if reason != "" else "Build %d for %s" % [n, hud._cost_text(rules.tool_cost(tool, n))]
		row.max.visible = view.editable and not locked
		row.max.set_meta("amount", can)
		row.max.text = "Max %d" % can
		row.max.disabled = can < 1 or castle.check_craft(tool, can) != ""
	_refresh_queue(castle)
	var lines: PackedStringArray = []
	lines.append("Attack tools: up to %d per wall in an attack (keep level %d)." % [rules.tool_slots(castle.keep_level()), castle.keep_level()])
	lines.append("Defence tools: up to %d per wall (wall level %d), posted in the Defence screen." % [castle.defence_slots(), castle.wall_level()])
	_store.text = "\n".join(lines)


func update_progress(now: float) -> void:
	## Called every frame for a smooth progress bar.
	var castle: CastleState = hud.view.castle
	if _queue_bar == null or castle.crafting.is_empty():
		return
	var batch: Dictionary = castle.crafting[0]
	_queue_bar.value = 100.0 * (1.0 - maxf(batch.next - now, 0.0) / maxf(batch.unit_time, 1.0))
	_queue_first.text = "%s x%d   next in %s, all in %s" % [castle.rules.tool_name(batch.tool), batch.remaining,
		hud.view.format_time(maxf(batch.next - now, 0.0)), hud.view.format_time(castle.crafting_left(now))]


func _build_rows(rules: BuildingRules) -> void:
	for tool: String in rules.tools:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var info := _label("", 14, TEXT)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(306, 0)
		box.add_child(info)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		var cost := _label("", 13, MUTED)
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(cost)
		var buttons: Array[Button] = []
		for n: int in AMOUNTS:
			var b := _small_button("+%d" % n, tool, n)
			line.add_child(b)
			buttons.append(b)
		var max_button := _small_button("Max", tool, 0)
		line.add_child(max_button)
		box.add_child(line)
		_tools_box.add_child(box)
		_tool_rows[tool] = {"info": info, "cost": cost, "line": line, "buttons": buttons, "max": max_button}


func _refresh_queue(castle: CastleState) -> void:
	var parts: PackedStringArray = []
	for c in castle.crafting:
		parts.append("%s:%d" % [c.tool, c.remaining])
	var signature := "|".join(parts) + ("e" if hud.view.editable else "")
	if signature == _queue_signature:
		return
	_queue_signature = signature
	for child in _queue_box.get_children():
		_queue_box.remove_child(child)
		child.queue_free()
	_queue_bar = null
	if castle.crafting.is_empty():
		return
	_queue_box.add_child(_label("In the workshop (%d/%d)" % [castle.crafting.size(), castle.rules.queue_size], 15, HEAD))
	for i in castle.crafting.size():
		var c: Dictionary = castle.crafting[i]
		var row := HBoxContainer.new()
		var l := _label("%s x%d" % [castle.rules.tool_name(c.tool), c.remaining], 13, TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if hud.view.editable:
			var cancel: Button = hud._button("Cancel")
			cancel.add_theme_font_size_override("font_size", 12)
			cancel.tooltip_text = "Refunds %d%% of what the unbuilt tools cost" % int(CastleState.CANCEL_REFUND * 100.0)
			var index := i
			cancel.pressed.connect(func() -> void: hud.view.cancel_crafting(index))
			row.add_child(cancel)
		_queue_box.add_child(row)
		if i == 0:
			_queue_first = l
			_queue_bar = ProgressBar.new()
			_queue_bar.show_percentage = false
			_queue_bar.custom_minimum_size = Vector2(0, 8)
			_queue_box.add_child(_queue_bar)


func _small_button(text: String, tool: String, amount: int) -> Button:
	var b: Button = hud._button(text)
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(34, 0)
	b.set_meta("amount", amount)
	b.pressed.connect(func() -> void: hud.view.craft(tool, int(b.get_meta("amount"))))
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
