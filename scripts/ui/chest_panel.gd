extends PanelContainer
## The treasure screen (a tab of the quest window): your treasure chests and
## the Wheel of Fortune that opens them. Picking a chest shows its wheel;
## opening it spins the wheel to the prize the rules picked (ChestRules) and
## gives it.

const DONE := Color(0.55, 0.9, 0.45)
const SPIN_TIME := 3.6
const TURNS := 5

var _kind := "wooden"
var _buttons := {}           ## kind -> {button, count}
var _wheel: Wheel
var _title: Label
var _odds: Label
var _open: Button
var _status: Label
var _spinning := false
var _signature := ""


## The wheel: eight slices with their prizes, turned by `angle`, and a
## pointer at the top.
class Wheel extends Control:
	var slots: Array = []        ## [{reward, weight, jackpot?}]
	var color := Color(0.6, 0.4, 0.2)
	var angle := 0.0:
		set(v):
			angle = v
			queue_redraw()
	var lit := -1                ## the slot that won, drawn bright

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 12.0
		var n := maxi(slots.size(), 1)
		var step := TAU / n
		draw_circle(c, r + 8.0, Color(0.12, 0.09, 0.05))
		draw_arc(c, r + 8.0, 0, TAU, 96, GameTheme.RIM, 3.0, true)
		for i in slots.size():
			var a0 := angle - PI / 2.0 - step / 2.0 + i * step
			var points := PackedVector2Array([c])
			for k in 17:
				points.append(c + Vector2.from_angle(a0 + step * k / 16.0) * r)
			var shade := color.darkened(0.15) if i % 2 == 0 else color.darkened(0.45)
			if slots[i].get("jackpot", false):
				shade = Color(0.62, 0.14, 0.1)
			if i == lit:
				shade = shade.lightened(0.35)
			draw_colored_polygon(points, shade)
			draw_line(c, c + Vector2.from_angle(a0) * r, Color(0.1, 0.07, 0.04), 2.0, true)
			var mid := c + Vector2.from_angle(a0 + step / 2.0) * r * 0.66
			_draw_prize(mid, slots[i].reward, slots[i].get("jackpot", false))
		draw_circle(c, r * 0.16, Color(0.18, 0.12, 0.06))
		draw_arc(c, r * 0.16, 0, TAU, 48, GameTheme.GOLD, 3.0, true)
		# The pointer, at the top.
		var tip := Vector2(c.x, c.y - r + 18.0)
		draw_colored_polygon(PackedVector2Array([tip, Vector2(c.x - 16, c.y - r - 14), Vector2(c.x + 16, c.y - r - 14)]), GameTheme.GOLD)
		draw_polyline(PackedVector2Array([tip, Vector2(c.x - 16, c.y - r - 14), Vector2(c.x + 16, c.y - r - 14), tip]), Color(0.2, 0.1, 0.03), 2.0, true)

	func _draw_prize(at: Vector2, reward: Dictionary, jackpot: bool) -> void:
		## One icon and a number for the slice's main prize.
		var icon := "rewards" if jackpot else ""
		var amount := 0
		for k: String in ["resources", "troops", "tools", "chests"]:
			var part: Dictionary = reward.get(k, {})
			if part.is_empty() or icon != "":
				continue
			var first: String = part.keys()[0]
			icon = {"tools": "battle", "chests": "rewards"}.get(k, first)
			amount = int(part[first])
		var tex := Icons.get_icon(icon, 34)
		if tex != null:
			draw_texture(tex, at - Vector2(17, 24))
		var font := GameTheme.BOLD_FONT
		var text := "JACKPOT" if jackpot else _short(amount)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		draw_string_outline(font, at + Vector2(-w / 2.0, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0.08, 0.05, 0.02))
		draw_string(font, at + Vector2(-w / 2.0, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GameTheme.GOLD if jackpot else GameTheme.TEXT)

	static func _short(n: int) -> String:
		return "%.1fk" % (n / 1000.0) if n >= 10000 else str(n)


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1000, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Treasure", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	set_meta("window_close", close)
	var help := MenuStyle.label("Treasure chests come from the Steward's Coffer (wooden), day 7 of the Royal Gift (iron), achievement tiers (wooden, iron or golden) and the season's track and prizes (golden). Opening one spins its Wheel of Fortune: every slice is a prize, and the rarer slices are thinner in the odds. Resources grow with your keep; prizes are given in full, even past your storage. Chests can't be bought.", 14, MenuStyle.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	set_meta("window_help", help)
	box.add_child(help)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var chests := VBoxContainer.new()
	chests.add_theme_constant_override("separation", 10)
	chests.custom_minimum_size = Vector2(260, 0)
	row.add_child(chests)
	chests.add_child(MenuStyle.label("Your chests", 19, MenuStyle.GOLD))
	for kind: String in ChestRules.ORDER:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(250, 70)
		b.toggle_mode = true
		b.pressed.connect(_pick.bind(kind))
		var line := HBoxContainer.new()
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 10
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		var pic := Icons.rect("rewards", 48)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(pic)
		var words := VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(words)
		var name := MenuStyle.label("", 17, MenuStyle.TEXT)
		words.add_child(name)
		var n := MenuStyle.label("", 15, MenuStyle.MUTED)
		words.add_child(n)
		chests.add_child(b)
		_buttons[kind] = {"button": b, "name": name, "count": n, "picture": pic}
	_odds = MenuStyle.label("", 14, MenuStyle.MUTED)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odds.custom_minimum_size = Vector2(250, 0)
	chests.add_child(_odds)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_title = MenuStyle.label("", 22, MenuStyle.GOLD)
	_title.add_theme_font_override("font", GameTheme.TITLE_FONT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_title)
	_wheel = Wheel.new()
	_wheel.custom_minimum_size = Vector2(400, 400)
	_wheel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(_wheel)
	_open = Button.new()
	_open.text = "Open and spin"
	_open.focus_mode = Control.FOCUS_NONE
	_open.custom_minimum_size = Vector2(240, 44)
	_open.add_theme_font_size_override("font_size", 18)
	_open.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_open.pressed.connect(_on_open)
	GameTheme.primary(_open)
	right.add_child(_open)
	_status = MenuStyle.label("", 17, DONE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_fill())


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if not _spinning:
		_status.text = ""
		# Start on a chest you have.
		var rules := Economy.chest_rules
		if rules != null and rules.count(Economy.player_castle, _kind) == 0:
			for kind: String in ChestRules.ORDER:
				if rules.count(Economy.player_castle, kind) > 0:
					_kind = kind
					break
	_signature = ""
	_wheel.lit = -1
	_fill()
	visible = true


func close_panel() -> void:
	visible = false


func _pick(kind: String) -> void:
	if _spinning:
		return
	_kind = kind
	_wheel.lit = -1
	_wheel.angle = 0.0
	_status.text = ""
	_signature = ""
	_fill()


func _on_open() -> void:
	if _spinning:
		return
	var out := Economy.open_chest(_kind)
	if out.error != "":
		Audio.play("denied")
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		_status.text = out.error
		return
	_spinning = true
	_open.disabled = true
	_status.text = ""
	_wheel.lit = -1
	# Turn so the winning slice ends under the pointer, a few turns from here.
	var n := _wheel.slots.size()
	var slot := int(out.slot)
	var target := -slot * TAU / n + randf_range(-0.35, 0.35) * TAU / n
	var from := fposmod(_wheel.angle, TAU)
	_wheel.angle = from
	var to := target - TAU * TURNS
	while to > from - TAU * TURNS:
		to -= TAU
	Audio.play("click")
	var tween := create_tween()
	tween.tween_property(_wheel, "angle", to, SPIN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await tween.finished
	_wheel.lit = slot
	_spinning = false
	var jackpot: bool = _wheel.slots[slot].get("jackpot", false)
	Audio.play("reward")
	_status.add_theme_color_override("font_color", MenuStyle.GOLD if jackpot else DONE)
	_status.text = ("JACKPOT! " if jackpot else "You won: ") + Economy.reward_text(out.reward)
	_signature = ""
	_fill()


func _fill() -> void:
	var rules := Economy.chest_rules
	var castle := Economy.player_castle
	if rules == null or castle == null:
		return
	var sig := str([castle.chests, _kind, castle.keep_level(), _spinning])
	if sig == _signature:
		return
	_signature = sig
	for kind: String in ChestRules.ORDER:
		var parts: Dictionary = _buttons[kind]
		var def: Dictionary = rules.kinds.get(kind, {})
		parts.name.text = String(def.get("name", kind))
		var n := rules.count(castle, kind)
		parts.count.text = "%d to open" % n if n > 0 else "none yet"
		parts.picture.modulate = Color(String(def.get("color", "#ffffff"))).lightened(0.25)
		parts.button.set_pressed_no_signal(kind == _kind)
		parts.button.modulate = Color(1, 1, 1) if n > 0 or kind == _kind else Color(1, 1, 1, 0.6)
	var def: Dictionary = rules.kinds[_kind]
	_title.text = "%s    (%d)" % [def.name, rules.count(castle, _kind)]
	var slots: Array = []
	var sum := 0
	for i in def.wheel.size():
		sum += int(def.wheel[i].weight)
	var odds: PackedStringArray = []
	for i in def.wheel.size():
		var slot: Dictionary = def.wheel[i]
		var reward := rules.slot_reward(_kind, i, castle.keep_level())
		slots.append({"reward": reward, "weight": slot.weight, "jackpot": slot.get("jackpot", false)})
		odds.append("%d%%  %s" % [roundi(100.0 * int(slot.weight) / sum), Economy.reward_text(reward)])
	_wheel.slots = slots
	_wheel.color = Color(String(def.color))
	_wheel.queue_redraw()
	_odds.text = "Prizes and odds:\n" + "\n".join(odds)
	_open.disabled = _spinning or rules.count(castle, _kind) <= 0
	_open.text = "Open and spin" if rules.count(castle, _kind) > 0 else "No %s" % String(def.name).to_lower()
