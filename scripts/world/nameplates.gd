class_name Nameplates
extends CanvasLayer
## Name plates over the world map, in the style of the castle games: a dark
## board with a thin gold rim for each place, a shield with its level on the
## left, its resource on the right and who holds it on a small plate below.
##
## The map's layers keep making their Label3D labels as before (text, colour,
## when they show); a label marked with the meta "plate" is drawn here instead,
## as a plate, and its own 3D text is hidden. The meta names the plate's kind
## ("town", "castle", "village", "camp", "army", "party", "siege" or "tag"),
## which sets its size and how much it matters: when plates would overlap, the
## more important one shows and the other waits until there is room.

const KINDS := {
	#          font size, title font, priority
	"town":    [19, true, 8],
	"castle":  [16, true, 6],
	"village": [14, false, 3],
	"camp":    [14, false, 5],
	"army":    [13, false, 4],
	"party":   [13, false, 4],
	"siege":   [15, true, 9],
	"tag":     [13, false, 2],
}
const RESOURCES := ["wood", "stone", "food", "gold"]
const BOARD := Color(0.06, 0.047, 0.036, 0.84)
const BOARD_RED := Color(0.2, 0.05, 0.035, 0.86)
const RIM := Color(0.72, 0.55, 0.28, 0.9)
const RIM_BRIGHT := Color(1.0, 0.82, 0.45)
const SHIELD := Color(0.5, 0.1, 0.07)
const SHIELD_GOLD := Color(0.92, 0.72, 0.32)
const INK := Color(0.07, 0.045, 0.025)
const GAP := 3.0                   ## room kept between two plates

var _plates: Array[Dictionary] = []
var _canvas: Control
var _level_font: Font


func _ready() -> void:
	layer = 0   # under the HUD and its windows
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_plates)
	add_child(_canvas)
	_level_font = GameTheme.BOLD_FONT
	get_tree().node_added.connect(_on_node_added)
	_scan(get_parent())


func _scan(node: Node) -> void:
	for child in node.get_children():
		if child is Label3D:
			_adopt(child)
		_scan(child)


func _on_node_added(node: Node) -> void:
	if node is Label3D:
		# Layers may mark the label right after adding it.
		_adopt.call_deferred(node)


func _adopt(label: Label3D) -> void:
	if not is_instance_valid(label) or not label.has_meta("plate") or label.has_meta("plate_taken"):
		return
	if not get_parent().is_ancestor_of(label):
		return
	label.set_meta("plate_taken", true)
	label.layers = 0   # the plate shows it instead
	var kind := String(label.get_meta("plate"))
	if not KINDS.has(kind):
		kind = "tag"
	_plates.append({"label": label, "kind": kind, "text": ""})


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_plates() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen := _canvas.get_rect().grow(40.0)
	var shown: Array[Dictionary] = []
	var alive: Array[Dictionary] = []
	for p in _plates:
		if not is_instance_valid(p.label):
			continue   # freed with its place
		var label: Label3D = p.label
		alive.append(p)
		if not label.is_visible_in_tree() or label.modulate.a <= 0.01:
			continue
		var at := label.global_position
		if camera.is_position_behind(at):
			continue
		var point := camera.unproject_position(at)
		if not screen.has_point(point):
			continue
		if not p.has("name") or p.text != label.text:
			_parse(p, label.text)
		p.point = point
		shown.append(p)
	_plates = alive
	# The most important plates first; the others give way where they overlap.
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _priority(a) > _priority(b))
	var taken: Array[Rect2] = []
	var placed: Array[Dictionary] = []
	for p in shown:
		var r := _rect(p)
		var clash := false
		for t in taken:
			if t.intersects(r):
				clash = true
				break
		if clash:
			continue
		taken.append(r.grow(GAP))
		placed.append(p)
	# Draw the least important first, so the important ones sit on top.
	placed.reverse()
	for p in placed:
		_draw_plate(p)


func _priority(p: Dictionary) -> float:
	var label: Label3D = p.label
	var base: float = KINDS[p.kind][2]
	if _is_gold(label.modulate):
		base += 4.0   # yours
	# Nearer the middle of the screen breaks ties.
	return base - p.point.distance_to(_canvas.size * 0.5) * 0.0001


func _parse(p: Dictionary, text: String) -> void:
	## Splits a label's text into the plate's parts: name, level, resource,
	## troop count and the line below.
	p.text = text
	var lines := text.split("\n")
	var head := lines[0].strip_edges()
	var sub := ""
	if lines.size() > 1:
		sub = "  ".join(lines.slice(1)).strip_edges()
	var level := ""
	var resource := ""
	var count := ""
	var prefix := ""
	for word in ["Invaders: ", "Horde: "]:
		if head.begins_with(word):
			prefix = word.trim_suffix(": ")
			head = head.substr(word.length())
	var lv := RegEx.create_from_string("^(.*?)\\s+Lv ?(\\d+)(?:\\s+(\\w+))?$").search(head)
	if lv != null:
		head = lv.get_string(1)
		level = lv.get_string(2)
		if RESOURCES.has(lv.get_string(3)):
			resource = lv.get_string(3)
	else:
		var troops := RegEx.create_from_string("^(.*?)\\s*\\((\\d+)\\)$").search(head)
		if troops != null:
			head = troops.get_string(1)
			count = troops.get_string(2)
	# A fortress shows its level on the line below.
	var sub_lv := RegEx.create_from_string("^Lv ?(\\d+)\\s*(.*)$").search(sub)
	if sub_lv != null and level == "":
		level = sub_lv.get_string(1)
		sub = sub_lv.get_string(2).strip_edges()
	if prefix != "":
		sub = (prefix + "  " + sub).strip_edges()
	p.name = head
	p.level = level
	p.resource = resource
	p.count = count
	p.sub = sub


func _font(p: Dictionary) -> Font:
	return GameTheme.TITLE_FONT if KINDS[p.kind][1] else GameTheme.BOLD_FONT


func _size(p: Dictionary) -> int:
	return KINDS[p.kind][0]


func _main_size(p: Dictionary) -> Vector2:
	var fs := _size(p)
	var h := float(fs) + 12.0
	var w := _font(p).get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	if p.level != "":
		w += h * 0.8
	if p.resource != "":
		w += fs + 8.0
	if p.count != "":
		w += _count_width(p) + 6.0
	return Vector2(w, h)


func _sub_size(p: Dictionary) -> Vector2:
	if p.sub == "":
		return Vector2.ZERO
	var fs := maxi(_size(p) - 4, 11)
	return Vector2(GameTheme.BOLD_FONT.get_string_size(p.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0, fs + 6.0)


func _count_width(p: Dictionary) -> float:
	var fs := _size(p) - 1
	return GameTheme.BOLD_FONT.get_string_size(p.count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs + 10.0


func _rect(p: Dictionary) -> Rect2:
	## The whole plate, its foot on the label's spot.
	var main := _main_size(p)
	var sub := _sub_size(p)
	var w := maxf(main.x, sub.x)
	var h := main.y + (sub.y - 2.0 if sub.y > 0.0 else 0.0)
	return Rect2(p.point.x - w * 0.5, p.point.y - h, w, h)


func _draw_plate(p: Dictionary) -> void:
	var c := _canvas
	var label: Label3D = p.label
	var colour := Color(label.modulate, 1.0)
	var alpha := label.modulate.a
	var mine := _is_gold(colour)
	var fs := _size(p)
	var font := _font(p)
	var main := _main_size(p)
	var sub := _sub_size(p)
	var whole := _rect(p)
	var box := Rect2(whole.position.x + (whole.size.x - main.x) * 0.5, whole.position.y, main.x, main.y)
	var board := BOARD_RED if p.kind == "camp" or p.kind == "siege" else BOARD
	if mine:
		board = Color(0.2, 0.13, 0.04, 0.88)   # yours: a warm gold-brown board
	board.a *= alpha
	var rim := Color(RIM_BRIGHT if mine else RIM, RIM.a * alpha)

	# Ribbon tails behind a town's plate.
	if p.kind == "town":
		for side: float in [-1.0, 1.0]:
			var x: float = box.position.x if side < 0 else box.end.x
			var y0 := box.position.y + 4.0
			var y1 := box.end.y - 4.0
			var tip := x + side * 14.0
			var notch := x + side * 8.0
			var tail := PackedVector2Array([Vector2(x, y0), Vector2(tip, y0), Vector2(notch, (y0 + y1) * 0.5), Vector2(tip, y1), Vector2(x, y1)])
			c.draw_colored_polygon(tail, Color(0.42, 0.08, 0.06, 0.92 * alpha) if not mine else Color(0.62, 0.44, 0.14, 0.95 * alpha))
			c.draw_polyline(tail, rim, 1.0)

	# Shadow, board, a fine highlight along the top and the rim.
	var sb := StyleBoxFlat.new()
	sb.bg_color = board
	sb.border_color = rim
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.35 * alpha)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	c.draw_style_box(sb, box)
	c.draw_line(box.position + Vector2(4, 1.5), Vector2(box.end.x - 4, box.position.y + 1.5), Color(1, 0.9, 0.7, 0.12 * alpha), 1.0)

	var x := box.position.x + 10.0
	var mid := box.position.y + box.size.y * 0.5
	if p.level != "":
		var h := box.size.y + 6.0
		var w := h * 0.78
		var sx := box.position.x - 2.0
		var top := box.position.y - 3.0
		_shield(Rect2(sx, top, w, h), SHIELD_GOLD if mine else (Color(0.16, 0.03, 0.02) if p.kind == "camp" else SHIELD), rim, alpha)
		var lfs := int(fs * 0.9)
		var tw := _level_font.get_string_size(p.level, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		c.draw_string(_level_font, Vector2(sx + (w - tw) * 0.5, top + h * 0.5 + lfs * 0.32), p.level,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(INK if mine else Color(1, 0.9, 0.62), alpha))
		x = sx + w + 6.0
	var ascent := font.get_ascent(fs)
	var descent := font.get_descent(fs)
	var baseline := mid + (ascent - descent) * 0.5
	c.draw_string_outline(font, Vector2(x, baseline), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(INK, 0.8 * alpha))
	c.draw_string(font, Vector2(x, baseline), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(colour, alpha))
	x += font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
	if p.resource != "":
		var icon := Icons.get_icon(p.resource, fs + 6)
		if icon != null:
			c.draw_texture(icon, Vector2(x - 3.0, mid - (fs + 6) * 0.5), Color(1, 1, 1, alpha))
	if p.count != "":
		var cw := _count_width(p)
		var chip := Rect2(box.end.x - cw - 5.0, box.position.y + 3.0, cw, box.size.y - 6.0)
		var cb := StyleBoxFlat.new()
		cb.bg_color = Color(0.0, 0.0, 0.0, 0.4 * alpha)
		cb.set_corner_radius_all(3)
		c.draw_style_box(cb, chip)
		var cfs := fs - 1
		var icon := Icons.get_icon("soldiers", cfs)
		if icon != null:
			c.draw_texture(icon, Vector2(chip.position.x + 3.0, chip.position.y + (chip.size.y - cfs) * 0.5), Color(1, 1, 1, alpha))
		c.draw_string(GameTheme.BOLD_FONT, Vector2(chip.position.x + cfs + 6.0, baseline), p.count, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs,
				Color(1, 0.92, 0.75, alpha))

	if sub.y > 0.0:
		var sbox := Rect2(whole.position.x + (whole.size.x - sub.x) * 0.5, box.end.y - 2.0, sub.x, sub.y)
		var s2 := StyleBoxFlat.new()
		s2.bg_color = Color(0.03, 0.025, 0.02, 0.78 * alpha)
		s2.border_color = Color(rim, 0.5 * alpha)
		s2.set_border_width_all(1)
		s2.set_corner_radius_all(3)
		c.draw_style_box(s2, sbox)
		var sfs := maxi(fs - 4, 11)
		var sb_line := sbox.position.y + sbox.size.y * 0.5 + (GameTheme.BOLD_FONT.get_ascent(sfs) - GameTheme.BOLD_FONT.get_descent(sfs)) * 0.5
		c.draw_string(GameTheme.BOLD_FONT, Vector2(sbox.position.x + 7.0, sb_line), p.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs,
				Color(colour.lerp(Color(0.95, 0.9, 0.8), 0.25), alpha))


func _shield(r: Rect2, fill: Color, rim: Color, alpha: float) -> void:
	## A heater shield: straight top, sides curving to a point.
	var pts := PackedVector2Array()
	pts.append(r.position)
	pts.append(Vector2(r.end.x, r.position.y))
	var steps := 6
	for k in range(1, steps + 1):
		var t := float(k) / steps
		var y := r.position.y + r.size.y * 0.45 + r.size.y * 0.55 * t
		var x := r.end.x - r.size.x * 0.5 * (t * t)
		pts.append(Vector2(x, y))
	for k in range(steps - 1, 0, -1):
		var t := float(k) / steps
		var y := r.position.y + r.size.y * 0.45 + r.size.y * 0.55 * t
		var x := r.position.x + r.size.x * 0.5 * (t * t)
		pts.append(Vector2(x, y))
	pts.append(Vector2(r.position.x, r.position.y + r.size.y * 0.45))
	_canvas.draw_colored_polygon(pts, Color(fill, alpha))
	# A lighter band at the top for a bit of shine.
	var shine := PackedVector2Array([r.position + Vector2(2, 2), Vector2(r.end.x - 2, r.position.y + 2),
			Vector2(r.end.x - 2, r.position.y + r.size.y * 0.3), Vector2(r.position.x + 2, r.position.y + r.size.y * 0.3)])
	_canvas.draw_colored_polygon(shine, Color(1, 1, 1, 0.1 * alpha))
	var outline := pts.duplicate()
	outline.append(pts[0])
	_canvas.draw_polyline(outline, Color(rim, alpha), 1.5, true)


static func _is_gold(c: Color) -> bool:
	## The map writes your own places in gold.
	return c.r > 0.95 and c.g > 0.78 and c.g < 0.95 and c.b < 0.66
