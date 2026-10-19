extends PanelContainer
## Online: shown on the world map when you click another player's castle: who
## they are, their castle level, whether beginner protection still shelters
## them (or they are too small for you to attack), what your spy last saw there, and buttons to send a spy or open the
## attack screen. For members of your alliance: buttons to send them resources
## or defenders, what you have on the way, and a button to call defenders home.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const NAME := Color(0.62, 0.84, 1.0)

var player_name := ""

var _title: Label
var _level: Label
var _details: Label
var _note: Label
var _spy: Button
var _attack: Button
var _help_buttons: HBoxContainer
var _recall: Button
var _timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.85, 12))
	custom_minimum_size = Vector2(320, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = _label(20, NAME)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: show_player(""))
	head.add_child(close)
	_level = _label(15, MUTED)
	box.add_child(_level)
	_details = _label(14, TEXT)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details)
	_note = _label(14, Color(1.0, 0.75, 0.5))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_spy = Button.new()
	_spy.focus_mode = Control.FOCUS_NONE
	_spy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spy.pressed.connect(_send_spy)
	buttons.add_child(_spy)
	_attack = Button.new()
	_attack.text = "Prepare attack"
	_attack.focus_mode = Control.FOCUS_NONE
	_attack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attack.pressed.connect(func() -> void: EventBus.attack_screen_requested.emit("player:" + player_name))
	buttons.add_child(_attack)
	_help_buttons = HBoxContainer.new()
	_help_buttons.add_theme_constant_override("separation", 8)
	box.add_child(_help_buttons)
	for kind: String in ["resources", "troops"]:
		var b := Button.new()
		b.text = "Send resources" if kind == "resources" else "Send defenders"
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: EventBus.help_screen_requested.emit(player_name, kind))
		_help_buttons.add_child(b)
	_recall = Button.new()
	_recall.text = "Call your defenders home"
	_recall.focus_mode = Control.FOCUS_NONE
	_recall.pressed.connect(_call_home)
	box.add_child(_recall)
	EventBus.player_selected.connect(show_player)
	for clears in [EventBus.party_selected, EventBus.settlement_selected, EventBus.baron_selected]:
		clears.connect(func(id: String) -> void:
			if id != "":
				show_player(""))
	Economy.changed.connect(_refresh)
	Economy.others_changed.connect(_refresh)
	Economy.aid_changed.connect(_refresh)
	Economy.spy_returned.connect(func(who: String) -> void:
		if who == player_name:
			_note.text = ""
		_refresh())


func show_player(who: String) -> void:
	player_name = who
	_note.text = ""
	visible = who != "" and not Economy.get_other(who).is_empty()
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if visible and _timer <= 0.0:
		_timer = 1.0
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	var p := Economy.get_other(player_name)
	if p.is_empty():
		visible = false
		return
	var tag := String(p.get("tag", ""))
	var ally: bool = p.get("ally", false)
	_title.text = ("[%s] " % tag if tag != "" else "") + player_name
	_level.text = "Player castle, level %d" % int(p.get("level", 1))
	var lines: PackedStringArray = []
	var shielded: bool = p.get("protected", false)
	var small := Economy.too_small(int(p.get("level", 1)))
	if ally:
		lines.append("A member of your alliance.")
	elif shielded:
		lines.append("Under beginner protection: can't be attacked yet.")
	elif small:
		lines.append("Too small for you to attack.")
	lines.append("March: %s each way" % _clock(Economy.march_time_to_player(player_name)))
	var seen: Dictionary = Economy.spy_reports.get(player_name, {})
	if ally:
		pass
	elif seen.is_empty():
		lines.append("You haven't spied on this castle yet.")
	else:
		lines.append("Your spy saw, %s ago:" % _clock(Economy.now() - float(seen.get("at", Economy.now()))))
		var troops: Dictionary = seen.get("troops", {})
		var total := 0
		for unit: String in troops:
			total += int(troops[unit])
		if total == 0:
			lines.append("    No soldiers at home")
		for unit: String in troops:
			lines.append("    %d %s" % [int(troops[unit]), Economy.rules.unit_plural(unit)])
		lines.append("    Walls: defenders +%d%% defence" % roundi((float(seen.get("wall", 1.0)) - 1.0) * 100.0))
		var layout: Variant = seen.get("layout")
		if Battle.check_layout(layout) == "":
			lines.append("    Posts: left %d%%, front %d%%, right %d%%, courtyard %d%%" % [int(layout.left), int(layout.front),
					int(layout.right), int(layout.courtyard)])
	for r: Dictionary in Economy.raids:
		if r.get("mine", false) and String(r.defender_name) == player_name:
			var out: bool = r.state == "out"
			lines.append("Your army: %s %s" % ["arrives in" if out else "home in",
					_clock((float(r.arrive) if out else float(r.back)) - Economy.now())])
	var now := Economy.now()
	var standing := -1
	for a: Dictionary in Economy.aid_to(player_name):
		if a.kind == "resources":
			lines.append("Your cart: arrives in %s" % _clock(float(a.arrive) - now))
		elif now < float(a.arrive):
			lines.append("Your defenders: arrive in %s" % _clock(float(a.arrive) - now))
			standing = int(a.id)
		elif now < float(a.leave):
			lines.append("Your defenders: in their castle for %s more" % _clock(float(a.leave) - now))
			standing = int(a.id)
		else:
			lines.append("Your defenders: home in %s" % _clock(float(a.back) - now))
	_details.text = "\n".join(lines)
	_spy.get_parent().visible = not ally
	_help_buttons.visible = ally
	_recall.visible = standing >= 0
	_recall.set_meta("aid", standing)
	_spy.text = "Send a spy (%s)" % _cost(Economy.spy_cost())
	_spy.disabled = ally or not Economy.player_castle.can_afford(Economy.spy_cost())
	_attack.disabled = ally or shielded or small or Economy.player_castle.troop_count() <= 0
	_attack.tooltip_text = "Train soldiers first" if Economy.player_castle.troop_count() <= 0 else ""


func _call_home() -> void:
	Economy.recall_defenders(int(_recall.get_meta("aid", -1)))
	_note.text = "Your defenders are coming home."


func _send_spy() -> void:
	var why := Economy.spy(player_name)
	_note.text = why if why != "" else "Your spy is on the way..."


static func _cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in cost:
		parts.append("%d %s" % [int(cost[r]), r])
	return ", ".join(parts)


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
