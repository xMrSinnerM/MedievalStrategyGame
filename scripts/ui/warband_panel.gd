extends PanelContainer
## Moves soldiers between your castle's garrison and your warband. Only works
## while the warband stands at the castle; the castle feeds both either way.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const HEAD := Color(1.0, 0.9, 0.65)

var hud: CanvasLayer     ## the castle HUD, for its view and button style

var _status: Label
var _grid: GridContainer
var _summary: Label
var _rows := {}          ## unit -> {name, garrison, field: Label, buttons: Array[Button]}


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label("Your warband", 20, HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close: Button = hud._button("×")
	close.custom_minimum_size = Vector2(30, 0)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	_status = _label("", 14, MUTED)
	box.add_child(_status)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)
	for text in ["", "In the castle", "", "", "In the warband", "", ""]:
		var h := _label(text, 13, MUTED)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(h)
	for unit: String in Economy.rules.units:
		var row := {"name": _label(Economy.rules.unit_name(unit), 15, TEXT),
			"garrison": _label("", 15, TEXT), "field": _label("", 15, TEXT), "buttons": []}
		row.garrison.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.field.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.garrison.custom_minimum_size = Vector2(90, 0)
		row.field.custom_minimum_size = Vector2(100, 0)
		row.buttons.append(_move_button("Send 10", unit, 10, true))
		row.buttons.append(_move_button("Send all", unit, 1 << 30, true))
		row.buttons.append(_move_button("Recall 10", unit, 10, false))
		row.buttons.append(_move_button("Recall all", unit, 1 << 30, false))
		for cell in [row.name, row.garrison, row.buttons[0], row.buttons[1], row.field, row.buttons[2], row.buttons[3]]:
			_grid.add_child(cell)
		_rows[unit] = row
	_summary = _label("", 14, TEXT)
	box.add_child(_summary)


func refresh() -> void:
	if not visible:
		return
	var castle: CastleState = hud.view.castle
	var home: bool = Economy.warband_home
	_status.text = "Your warband is at the castle: send soldiers out or call them back." if home \
		else "Your warband is away. Bring it to your castle on the world map to move soldiers."
	for unit: String in _rows:
		var row: Dictionary = _rows[unit]
		var g: int = castle.troops.get(unit, 0)
		var f: int = castle.field.get(unit, 0)
		var shown := g > 0 or f > 0
		for key in ["name", "garrison", "field"]:
			row[key].visible = shown
		row.garrison.text = str(g)
		row.field.text = str(f)
		for b: Button in row.buttons:
			b.visible = shown
			var to_field: bool = b.get_meta("to_field")
			b.disabled = not home or (g == 0 if to_field else f == 0)
	var eats := 0.0
	for unit: String in castle.field:
		eats += castle.field[unit] * castle.rules.unit_upkeep(unit)
	if castle.troop_count() + castle.field_count() == 0:
		_summary.text = "No soldiers yet. Train some in the barracks."
	else:
		_summary.text = "Warband: %d soldiers, eating %d food an hour from this castle's stores." % [castle.field_count(), int(eats)]
	reset_size()


func _move_button(text: String, unit: String, amount: int, to_field: bool) -> Button:
	var b: Button = hud._button(text)
	b.add_theme_font_size_override("font_size", 13)
	b.set_meta("to_field", to_field)
	b.pressed.connect(func() -> void: hud.view.move_troops(unit, amount, to_field))
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
