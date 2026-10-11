class_name ResourceBar
extends HBoxContainer
## A row of resource counters for the top of the screen: each resource's icon,
## how much is stored out of the storehouse limit, a small bar filling up as
## it nears the limit and how much it gains an hour; then builders, defence
## and soldiers. Call show_castle(castle) whenever it changes.

const RESOURCES := ["wood", "stone", "food", "gold"]
const GAIN := Color(0.62, 0.9, 0.5)
const LOSS := Color(1.0, 0.5, 0.4)
const FULL := Color(1.0, 0.62, 0.3)

var show_builders := true      ## the castle screen shows builders and defence, the map doesn't
var _amounts := {}             ## resource -> Label
var _rates := {}               ## resource -> Label
var _fills := {}               ## resource -> ProgressBar
var _stats := {}               ## builders/defence/soldiers -> Label
var _chips := {}               ## name -> the chip's Control, for tooltips


func _init() -> void:
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	for r: String in RESOURCES:
		var chip := _chip(r)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.get_child(0).add_child(col)
		var amount := _label(16, GameTheme.TEXT)
		amount.add_theme_font_override("font", GameTheme.BOLD_FONT)
		col.add_child(amount)
		var under := HBoxContainer.new()
		under.add_theme_constant_override("separation", 6)
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(under)
		var fill := ProgressBar.new()
		fill.show_percentage = false
		fill.custom_minimum_size = Vector2(56, 6)
		fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		under.add_child(fill)
		var rate := _label(13, GAIN)
		under.add_child(rate)
		_amounts[r] = amount
		_rates[r] = rate
		_fills[r] = fill
	for stat in ["builders", "defence", "soldiers"]:
		var chip := _chip(stat)
		var value := _label(16, GameTheme.TEXT)
		value.add_theme_font_override("font", GameTheme.BOLD_FONT)
		chip.get_child(0).add_child(value)
		_stats[stat] = value


func show_castle(castle: CastleState, away := 0) -> void:
	## Fills the counters from a castle; `away` is soldiers out marching.
	if castle == null:
		return
	var cap := castle.storage_capacity()
	var rates := castle.net_per_hour()
	for r: String in RESOURCES:
		var have := int(castle.resources.get(r, 0.0))
		var rate := int(rates.get(r, 0.0))
		_amounts[r].text = "%s / %s" % [_short(have), _short(int(cap))]
		_rates[r].text = "%+d/h" % rate
		_rates[r].add_theme_color_override("font_color", LOSS if rate < 0 else GAIN)
		var fill: ProgressBar = _fills[r]
		fill.max_value = maxf(cap, 1.0)
		fill.value = have
		fill.modulate = FULL if have >= cap else Color.WHITE
		_chips[r].tooltip_text = "%s: %d of %d the storehouses hold, %+d an hour%s" % [r.capitalize(), have, int(cap),
				rate, " (full: build storehouses to keep more)" if have >= cap else ""]
	var rules := castle.rules
	_chips.builders.visible = show_builders
	_chips.defence.visible = show_builders
	_stats.builders.text = "%d / %d" % [castle.free_builders(), rules.builders(castle.keep_level())]
	_chips.builders.tooltip_text = "Builders free to start a building, of all your builders"
	_stats.defence.text = str(int(castle.defense()))
	_chips.defence.tooltip_text = "Castle defence from walls, towers and the gatehouse"
	_stats.soldiers.text = str(castle.troop_count()) if away <= 0 else "%d  (+%d away)" % [castle.troop_count(), away]
	_chips.soldiers.tooltip_text = "Soldiers at home%s; they eat %d food an hour" % [
			"" if away <= 0 else ", and %d marching" % away, int(castle.upkeep_per_hour())]


func _chip(icon: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.035, 0.02, 0.55)
	box.border_color = Color(GameTheme.BRONZE_DARK, 0.8)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 6
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var pic := Icons.rect(icon, 30)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pic)
	add_child(chip)
	_chips[icon] = chip
	return chip


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", GameTheme.INK)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func _short(n: int) -> String:
	## 1250 -> "1250", 15400 -> "15.4k", 2300000 -> "2.3M".
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
