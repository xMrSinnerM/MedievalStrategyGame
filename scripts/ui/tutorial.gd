extends CanvasLayer
## The tutorial for new players: Steward Bertram walks you through upgrading
## the woodcutter, raising a barracks, training soldiers and beating your
## first robber baron, then hands you over to his quests. The words are in
## data/tutorial.json; this knows when each step is done (by looking at your
## castle, your armies and which screen is open) and points at what to click:
## a glowing frame around a button, or an arrow over a building or a camp.
##
## It only reads the game, so it needs nothing from the server. How far you
## got is kept on this computer (user://tutorial.cfg), per save slot offline
## and per account online. It starts with every new game, and with an online
## castle that hasn't done anything yet; the pause menu replays it.
##
## Buttons it points at are in the group "tutorial_" + name (see _target()).

const PATH := "res://data/tutorial.json"
const STORE := "user://tutorial.cfg"
const CHECK := 0.25            ## seconds between checks of the current step
const WIDTH := 540.0

var main: Node                 ## the game's main node: which screen is open
var steps: Array = []
var narrator := ""
var soldiers := 20             ## spearmen to train before the first attack

var _step := -1                ## -1: not running
var _profile := ""             ## the section of STORE for this game
var _camp := ""                ## the robber baron camp the tutorial picked
var _battle_done := false
var _timer := 0.0
var _skip_armed := 0.0         ## seconds left to confirm "Skip tutorial"
var _card: PanelContainer
var _title: Label
var _count: Label
var _text: Label
var _status: Label
var _next: Button
var _skip: Button
var _pointer: Control
var _slim := false             ## shrunk to one line at the bottom while a window is open


func _ready() -> void:
	layer = 42
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	steps = data.get("steps", [])
	narrator = data.get("narrator", "")
	soldiers = int(data.get("soldiers", 20))
	_build_card()
	_pointer = Pointer.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pointer)
	Economy.attack_resolved.connect(func(report: Dictionary) -> void:
		if report.get("baron", false):
			_battle_done = true)
	visible = false


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", MenuStyle.panel(0.9, 14))
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 64
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var icon := Icons.rect("quests", 30)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	_title = MenuStyle.label("", 19, MenuStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = MenuStyle.label("", 13, MenuStyle.MUTED)
	head.add_child(_count)
	_text = MenuStyle.label("", 15, MenuStyle.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 28, 0)
	box.add_child(_text)
	_status = MenuStyle.label("", 14, MenuStyle.GOLD)
	box.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_skip = Button.new()
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 13)
	_skip.pressed.connect(_on_skip)
	buttons.add_child(_skip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_next = GameTheme.primary(Button.new())
	_next.focus_mode = Control.FOCUS_NONE
	_next.custom_minimum_size = Vector2(130, 0)
	_next.pressed.connect(_advance)
	buttons.add_child(_next)


# --- Starting and stopping ----------------------------------------------------

func profile_for_game() -> String:
	## The section of STORE for the game being played.
	return "online_%s" % Online.email.md5_text() if Economy.online else "slot_%d" % Economy.slot


func begin(fresh: bool) -> void:
	## Called when a game starts. `fresh`: a new game, so the tutorial starts
	## over. Otherwise it carries on where it was left, and a game it has
	## never seen gets it only online, if the castle is still untouched.
	_profile = profile_for_game()
	var cfg := _load_store()
	if fresh:
		_start(0)
	elif cfg.has_section(_profile):
		_camp = String(cfg.get_value(_profile, "camp", ""))
		var step := int(cfg.get_value(_profile, "step", -1))
		if step >= 0 and step < steps.size():
			_start(step)
		else:
			stop()
	elif Economy.online and untouched(Economy.player_castle):
		_start(0)
	else:
		_save_step(-1)
		stop()


func replay() -> void:
	## Starts the tutorial again from the beginning (the pause menu's "Replay tutorial").
	if main == null or not main.in_game():
		return
	_profile = profile_for_game()
	_camp = ""
	_start(0)


func stop() -> void:
	_step = -1
	visible = false


func running() -> bool:
	return _step >= 0


static func untouched(castle: CastleState) -> bool:
	## A castle that hasn't trained, fought or claimed anything yet.
	return castle != null and int(castle.stats.trained) == 0 and int(castle.stats.barons) == 0 \
			and int(castle.quests.story) == 0 and castle.keep_level() <= 1


func _start(step: int) -> void:
	_battle_done = false
	_step = step
	visible = true
	_save_step(step)
	_show_step()


func _advance() -> void:
	## On to the next step that isn't already done.
	if _step < 0:
		return
	_step += 1
	while _step < steps.size() and not steps[_step].has("next") and _is_done(steps[_step].id):
		_step += 1
	if _step >= steps.size():
		_save_step(-1)
		stop()
		return
	_save_step(_step)
	_show_step()


func _on_skip() -> void:
	## Asks once more before skipping, so a stray click doesn't end it.
	if _skip_armed > 0.0:
		_save_step(-1)
		stop()
		return
	_skip_armed = 4.0
	_skip.text = "Click again to skip"


func _load_store() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(STORE)
	return cfg


func _save_step(step: int) -> void:
	## Remembers the step (-1: finished or skipped) and the camp picked.
	var cfg := _load_store()
	cfg.set_value(_profile, "step", step)
	cfg.set_value(_profile, "camp", _camp)
	cfg.save(STORE)


# --- Steps ----------------------------------------------------------------------

func _show_step() -> void:
	var step: Dictionary = steps[_step]
	_title.text = String(step.title)
	_count.text = "%s  ·  %d / %d" % [narrator, _step + 1, steps.size()]
	_text.text = String(step.text).replace("{soldiers}", str(soldiers))
	_next.visible = step.has("next")
	_next.text = String(step.get("next", "Next"))
	_skip_armed = 0.0
	_skip.text = "Skip tutorial"
	_status.text = ""
	_status.visible = false
	_set_slim(_slim, true)
	if step.id == "find_camp" and _in_map():
		_look_at_camp()
	_timer = 0.0


func _process(delta: float) -> void:
	if _step < 0 or main == null or not main.in_game():
		_pointer.visible = false
		return
	if _skip_armed > 0.0:
		_skip_armed -= delta
		if _skip_armed <= 0.0:
			_skip.text = "Skip tutorial"
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK
		var id := String(steps[_step].id)
		if not steps[_step].has("next") and _is_done(id):
			_advance()
			if _step < 0:
				return
			id = String(steps[_step].id)
		_status.text = _status_text(id)
		_status.visible = _status.text != ""
	_set_slim(_window_open())
	_pointer.visible = true
	_point_at(String(steps[_step].id))


func _is_done(id: String) -> bool:
	var castle := Economy.player_castle
	if castle == null:
		return false
	match id:
		"enter_castle":
			return _in_own_castle()
		"upgrade_woodcutter":
			return _best_level(castle, "woodcutter") >= 2
		"build_barracks":
			return _best_level(castle, "barracks") >= 1
		"wait_barracks":
			return castle.barracks_level() >= 1
		"recruit":
			var have := _soldiers_and_recruits(castle)
			return have >= soldiers or (have > 0 and castle.check_recruit("spearman", 1) != "")
		"wait_training":
			return castle.training.is_empty() and castle.troop_count() > 0
		"go_map":
			return _in_map()
		"find_camp":
			return _attack_screen_open() or _marching()
		"send_army":
			return _marching()
		"wait_battle":
			return _battle_done or (int(castle.stats.barons) > 0 and not _marching())
		"claim_quest":
			return int(castle.quests.story) >= 1
	return false


func _status_text(id: String) -> String:
	## A live line under Bertram's words: what's left to wait for.
	var castle := Economy.player_castle
	match id:
		"wait_barracks":
			for b in castle.buildings:
				if b.type == "barracks" and int(b.target) > 0:
					return "Barracks ready in %s" % _clock(castle.time_left(b.id, Economy.now()))
		"recruit":
			return "Spearmen: %d / %d" % [mini(_soldiers_and_recruits(castle), soldiers), soldiers]
		"wait_training":
			return "Soldiers ready: %d, still training: %d (all in %s)" % [castle.troop_count(),
					_in_training(castle), _clock(castle.training_left(Economy.now()))]
		"wait_battle":
			for m: Dictionary in Economy.marches:
				if m.get("state", "") == "out":
					return "Your army reaches the camp in %s" % _clock(float(m.arrive) - Economy.now())
	return ""


# --- Pointing at things ------------------------------------------------------------

func _point_at(id: String) -> void:
	## Frames the button to press, or puts an arrow over a building or camp.
	var p := _pointer as Pointer
	var rect := Rect2()
	var spot := Vector3.INF
	var view: Node = main.castle_view if _in_own_castle() else null
	match id:
		"enter_castle":
			rect = _target("castle_button")
		"upgrade_woodcutter":
			if view != null:
				rect = _selected_or_spot(view, "woodcutter", "upgrade")
				if rect.size == Vector2.ZERO:
					spot = _building_spot(view, "woodcutter")
			else:
				rect = _target("castle_button")
		"build_barracks":
			if view != null and view.mode == 0:   # Mode.SELECT
				rect = _target("build_barracks")
			elif view == null:
				rect = _target("castle_button")
		"recruit":
			if view != null:
				rect = _selected_or_spot(view, "barracks", "recruit_spearman")
				if rect.size == Vector2.ZERO:
					spot = _building_spot(view, "barracks")
			else:
				rect = _target("castle_button")
		"go_map":
			rect = _target("map_button")
		"find_camp", "send_army":
			if _attack_screen_open():
				rect = _target("send_army")
			elif _in_map():
				rect = _target("baron_attack")
				if rect.size == Vector2.ZERO:
					spot = _camp_spot()
			else:
				rect = _target("map_button")
		"claim_quest":
			rect = _target("quest_claim")
			if rect.size == Vector2.ZERO:
				rect = _target("quest_tracker")
	p.rect = rect
	p.avoid = _card.get_global_rect()
	p.spot = Vector2.INF
	if spot != Vector3.INF:
		var camera := get_viewport().get_camera_3d()
		if camera != null and not camera.is_position_behind(spot):
			p.spot = camera.unproject_position(spot)
	p.queue_redraw()


func _target(name: String) -> Rect2:
	## The screen rectangle of the visible button in group "tutorial_" + name.
	for node in get_tree().get_nodes_in_group("tutorial_" + name):
		if node is Control and node.is_visible_in_tree():
			return node.get_global_rect()
	return Rect2()


func _selected_or_spot(view: Node, type: String, button: String) -> Rect2:
	## The panel's button once a building of `type` is selected.
	var sel: Dictionary = view.castle.get_building(view.selected) if view.selected >= 0 else {}
	if not sel.is_empty() and sel.type == type:
		return _target(button)
	return Rect2()


func _building_spot(view: Node, type: String) -> Vector3:
	for b in view.castle.buildings:
		if b.type == type:
			return view.building_position(b.id)
	return Vector3.INF


func _camp_spot() -> Vector3:
	var camp := Economy.get_baron(_pick_camp())
	if camp == null:
		return Vector3.INF
	return Vector3(camp.position.x, GameData.terrain.get_height(camp.position.x, camp.position.y) + 6.0, camp.position.y)


func _pick_camp() -> String:
	## The weakest ordinary robber baron camp nearest your castle; kept once picked.
	if _camp != "" and Economy.get_baron(_camp) != null:
		return _camp
	var home := Economy.home_position()
	var best: BaronCamp = null
	for camp in Economy.barons:
		if camp.fortress or camp.is_invader() or camp.is_horde():
			continue
		if best == null or camp.level < best.level or (camp.level == best.level \
				and camp.position.distance_to(home) < best.position.distance_to(home)):
			best = camp
	_camp = best.id if best != null else ""
	_save_step(_step)
	return _camp


func _look_at_camp() -> void:
	var camp := Economy.get_baron(_pick_camp())
	if camp != null:
		EventBus.map_focus_requested.emit(camp.position)


func _set_slim(slim: bool, force := false) -> void:
	## While a window covers the middle of the screen, the card moves out of
	## its way: one line (the step's hint) at the bottom.
	if slim == _slim and not force:
		return
	_slim = slim
	var step: Dictionary = steps[_step]
	_title.text = String(step.get("hint", step.title)) if slim else String(step.title)
	_text.visible = not slim
	_skip.get_parent().visible = not slim
	_count.visible = not slim
	_card.custom_minimum_size.x = 0.0 if slim else WIDTH
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM if slim else Control.PRESET_CENTER_TOP)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN if slim else Control.GROW_DIRECTION_END
	_card.offset_top = -12.0 if slim else 64.0
	_card.offset_bottom = -12.0 if slim else 64.0
	_card.offset_left = 0.0
	_card.offset_right = 0.0
	_card.reset_size()


func _window_open() -> bool:
	for node in get_tree().get_nodes_in_group("tutorial_window"):
		if node is Control and node.is_visible_in_tree():
			return true
	return false


# --- What's going on -------------------------------------------------------------------

func _in_map() -> bool:
	return main.world_map != null and main.world_map.is_inside_tree()


func _in_own_castle() -> bool:
	var view: Node = main.castle_view
	return view != null and view.is_inside_tree() and view.castle == Economy.player_castle and not view.glimpse


func _attack_screen_open() -> bool:
	return _in_map() and _target("send_army").size != Vector2.ZERO


func _marching() -> bool:
	for m: Dictionary in Economy.marches:
		if m.get("state", "") == "out":
			return true
	return false


static func _best_level(castle: CastleState, type: String) -> int:
	## The highest level of `type`, counting one being built or upgraded.
	var best := 0
	for b in castle.buildings:
		if b.type == type:
			best = maxi(best, maxi(int(b.level), int(b.target)))
	return best


static func _in_training(castle: CastleState) -> int:
	var n := 0
	for batch: Dictionary in castle.training:
		n += int(batch.remaining)
	return n


static func _soldiers_and_recruits(castle: CastleState) -> int:
	return castle.troop_count() + _in_training(castle)


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


class Pointer extends Control:
	const ARROW := 70.0     ## how far an arrow reaches from its tip

	## A pulsing gold frame around `rect`, and a bobbing arrow pointing down at
	## it or at `spot` (a point on screen; INF for none). The arrow comes from
	## below instead when above would put it on `avoid` (Bertram's card) or off
	## the top of the screen.
	var rect := Rect2()
	var spot := Vector2.INF
	var avoid := Rect2()

	func _process(_delta: float) -> void:
		if visible and (rect.size != Vector2.ZERO or spot != Vector2.INF):
			queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001
		var glow := 0.55 + 0.45 * sin(t * 5.0)
		var gold := Color(1.0, 0.82, 0.3, glow)
		var above := Vector2.INF
		var below := Vector2.INF
		if rect.size != Vector2.ZERO:
			var r := rect.grow(4.0 + 2.0 * glow)
			draw_rect(r, Color(1.0, 0.82, 0.3, 0.12 * glow))
			draw_rect(r, gold, false, 3.0)
			above = Vector2(r.get_center().x, r.position.y - 4.0)
			below = Vector2(r.get_center().x, r.end.y + 4.0)
		elif spot != Vector2.INF:
			var radius := 26.0 + 6.0 * glow
			draw_circle(spot, radius, Color(1.0, 0.82, 0.3, 0.22 * glow))
			draw_arc(spot, radius, 0.0, TAU, 40, Color(0.18, 0.1, 0.03, 0.8), 6.0)
			draw_arc(spot, radius, 0.0, TAU, 40, gold, 3.0)
			above = spot - Vector2(0, 36)
			below = spot + Vector2(0, 36)
		else:
			return
		var reach := Rect2(above.x - 18.0, above.y - ARROW, 36.0, ARROW)
		if above.y - ARROW < 60.0 or reach.intersects(avoid):
			_arrow(below, -1.0, t)
		else:
			_arrow(above, 1.0, t)

	func _arrow(tip: Vector2, down: float, t: float) -> void:
		## An arrow whose point is at `tip`, pointing down (1) or up (-1).
		var bob := tip - Vector2(0, down * (6.0 + 6.0 * sin(t * 6.0)))
		_arrow_shape(bob, down, 3.0, Color(0.18, 0.1, 0.03, 0.9))
		_arrow_shape(bob - Vector2(0, down * 3.0), down, 0.0, Color(1.0, 0.85, 0.35))

	func _arrow_shape(at: Vector2, down: float, pad: float, color: Color) -> void:
		var half := 14.0 + pad
		var head := 20.0 + pad
		draw_colored_polygon(PackedVector2Array([at, at + Vector2(-half, -head * down), at + Vector2(half, -head * down)]), color)
		var shaft := 5.0 + pad
		var from := at.y - head * down + down
		var to := at.y - (head + 26.0 + pad) * down
		draw_rect(Rect2(at.x - shaft, minf(from, to), shaft * 2.0, absf(to - from)), color)
