extends PanelContainer
## Sets how a castle's garrison mans its defences (CastleState.layout): the
## share of soldiers on the left, front and right walls and in the courtyard,
## where they make a last stand once a wall is broken (Battle.siege()). Spies
## who scout the castle see this layout.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const HEAD := Color(1.0, 0.9, 0.65)
const BAD := Color(1.0, 0.6, 0.48)
const GOOD := Color(0.62, 0.82, 0.54)
const POSTS := ["left", "front", "right", "courtyard"]
const NAMES := {"left": "Left wall", "front": "Front wall", "right": "Right wall", "courtyard": "Courtyard"}

var hud: CanvasLayer     ## the castle HUD, for its view and button style

var _sliders := {}       ## post -> HSlider
var _shares := {}        ## post -> Label with the percentage
var _counts := {}        ## post -> Label with the soldiers there
var _total: Label
var _save: Button
var _quiet := false


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


func refresh() -> void:
	## Shows the castle's current layout.
	_show(hud.view.castle.layout)


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
