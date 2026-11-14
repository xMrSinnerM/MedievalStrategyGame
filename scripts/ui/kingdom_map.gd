class_name KingdomMap
extends Control
## The painted map of one of the other kingdoms (data/kingdoms.json): its
## island, your castle there, the robber barons' camps with their levels,
## your armies on the march and the ships carrying its good home. The land
## is painted once per kingdom from its seed, so it is the same for everyone.
## Click a camp or the castle to pick it.

signal camp_picked(camp_id: String)
signal castle_picked

const PIXELS := 320              ## resolution of the painted land
const PICK_RADIUS := 26.0        ## screen pixels around a camp that pick it
const MARGIN := 0.13             ## share of the kingdom's map left off each edge of the sheet (open sea)
const FRAME := Color(0.27, 0.17, 0.08)
const INK := Color(0.16, 0.1, 0.05)
const CAMP := Color(0.72, 0.16, 0.12)
const CAMP_DOWN := Color(0.45, 0.42, 0.4)
const OURS := Color(0.86, 0.2, 0.14)
const GOLD := Color(0.96, 0.8, 0.4)

## How each kind of land is painted: the sea, the shore, low and high ground,
## the peaks and the patches of trees or oases.
const LOOKS := {
	"snow": {
		"deep": Color(0.12, 0.2, 0.3), "shallow": Color(0.36, 0.52, 0.62), "shore": Color(0.78, 0.84, 0.88),
		"low": Color(0.88, 0.91, 0.94), "high": Color(0.97, 0.98, 1.0), "peak": Color(0.5, 0.52, 0.58),
		"patch": Color(0.16, 0.27, 0.22), "patch_amount": 0.5,
	},
	"desert": {
		"deep": Color(0.1, 0.3, 0.4), "shallow": Color(0.3, 0.62, 0.66), "shore": Color(0.93, 0.86, 0.66),
		"low": Color(0.9, 0.76, 0.48), "high": Color(0.84, 0.62, 0.36), "peak": Color(0.6, 0.36, 0.24),
		"patch": Color(0.36, 0.52, 0.24), "patch_amount": 0.2,
	},
}

static var _pictures := {}       ## kingdom id -> ImageTexture

var kingdom := ""
var selected := ""               ## the camp picked ("" for none)
var _font: Font


func _init() -> void:
	custom_minimum_size = Vector2(500, 500)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = GameTheme.BOLD_FONT


func show_kingdom(id: String) -> void:
	kingdom = id
	selected = ""
	queue_redraw()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()   # armies and ships move


static func picture(id: String, def: Dictionary) -> ImageTexture:
	## The painted land of a kingdom, made the first time it is asked for.
	if not _pictures.has(id):
		_pictures[id] = ImageTexture.create_from_image(paint(def))
	return _pictures[id]


static func paint(def: Dictionary) -> Image:
	## Paints the kingdom's island from its seed: land rises around the castle
	## and the camps, so they always stand on dry ground.
	var look: Dictionary = LOOKS.get(String(def.get("biome", "snow")), LOOKS.snow)
	var extent := float(def.get("size", 600.0))
	var relief := FastNoiseLite.new()
	relief.seed = int(def.get("seed", 1))
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief.fractal_octaves = 5
	relief.frequency = 0.006
	var patches := FastNoiseLite.new()
	patches.seed = int(def.get("seed", 1)) + 53
	patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patches.fractal_octaves = 3
	patches.frequency = 0.02
	var sites: Array = [def.get("castle", [extent * 0.5, extent * 0.5])]
	for c: Dictionary in def.get("camps", []):
		sites.append(c.position)
	var side := PIXELS
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for py in side:
		for px in side:
			var x := (MARGIN + (px + 0.5) / side * (1.0 - 2.0 * MARGIN)) * extent
			var y := (MARGIN + (py + 0.5) / side * (1.0 - 2.0 * MARGIN)) * extent
			var d := Vector2(x - extent * 0.5, y - extent * 0.5).length() / (extent * 0.5)
			var h := 0.42 + relief.get_noise_2d(x, y) * 0.34 - pow(d, 2.4) * 0.55
			for s: Array in sites:
				var near := Vector2(x - float(s[0]), y - float(s[1])).length_squared()
				h += 0.16 * exp(-near / 2600.0)
			heights[py * side + px] = h
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	var sea := 0.3
	for py in side:
		for px in side:
			var h := heights[py * side + px]
			var color: Color
			if h < sea:
				color = (look.deep as Color).lerp(look.shallow, smoothstep(sea - 0.22, sea, h))
			else:
				var t := (h - sea) / 0.5
				color = (look.shore as Color).lerp(look.low, smoothstep(0.0, 0.08, t))
				color = color.lerp(look.high, smoothstep(0.15, 0.55, t))
				color = color.lerp(look.peak, smoothstep(0.62, 0.9, t))
				var x := (MARGIN + (px + 0.5) / side * (1.0 - 2.0 * MARGIN)) * extent
				var y := (MARGIN + (py + 0.5) / side * (1.0 - 2.0 * MARGIN)) * extent
				var grove := smoothstep(1.0 - float(look.patch_amount) * 1.2, 1.0 - float(look.patch_amount) * 0.6,
						patches.get_noise_2d(x, y) * 0.5 + 0.5)
				color = color.lerp(look.patch, grove * (1.0 - smoothstep(0.35, 0.6, t)) * smoothstep(0.02, 0.1, t))
				# Light from the north-west.
				var left := heights[py * side + maxi(px - 1, 0)]
				var up := heights[maxi(py - 1, 0) * side + px]
				var shade := clampf(((h - left) + (h - up)) * 9.0, -0.35, 0.35)
				color = color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
			# The sheet darkens a little towards its edges, like an old map.
			var edge := Vector2((px + 0.5) / side - 0.5, (py + 0.5) / side - 0.5).length()
			image.set_pixel(px, py, color.darkened(smoothstep(0.42, 0.75, edge) * 0.45))
	return image


func _def() -> Dictionary:
	return Economy.kingdom_rules.kingdoms.get(kingdom, {}) if Economy.kingdom_rules != null else {}


func _to_screen(p: Vector2) -> Vector2:
	var side := minf(size.x, size.y)
	var unit := p / float(_def().get("size", 600.0))
	return (size - Vector2(side, side)) * 0.5 + (unit - Vector2(MARGIN, MARGIN)) / (1.0 - 2.0 * MARGIN) * side


func _castle_pos() -> Vector2:
	var spot: Array = _def().get("castle", [300.0, 300.0])
	return Vector2(float(spot[0]), float(spot[1]))


func _draw() -> void:
	var def := _def()
	if def.is_empty():
		return
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	draw_texture_rect(picture(kingdom, def), rect, false)
	draw_rect(rect, FRAME, false, 4.0)
	draw_rect(rect.grow(-5.0), Color(GOLD, 0.35), false, 1.0)
	var founded: bool = Economy.kingdoms.has(kingdom)
	var now := Economy.now()
	var home := _to_screen(_castle_pos())
	if not founded:
		# Unreached: the camps are only rumours.
		for c: Dictionary in def.get("camps", []):
			_tent(_to_screen(Vector2(float(c.position[0]), float(c.position[1]))), Color(CAMP_DOWN, 0.6), "?")
		_tower(home, Color(0.5, 0.48, 0.45, 0.7))
		return
	# The tracks from your castle to each camp.
	for camp in Economy.kingdom_camps(kingdom):
		draw_dashed_line(home, _to_screen(camp.position), Color(INK, 0.35), 1.5, 6.0)
	for camp in Economy.kingdom_camps(kingdom):
		var at := _to_screen(camp.position)
		if camp.id == selected:
			draw_arc(at, 22.0, 0.0, TAU, 40, GOLD, 2.5, true)
		_tent(at, CAMP if camp.is_ready(now) else CAMP_DOWN, str(camp.level))
		_caption(at + Vector2(0, 26), camp.camp_name, 12)
	_tower(home, OURS)
	_caption(home + Vector2(0, 30), String(def.get("castle_name", "")), 14, GOLD)
	# Your armies: they land by your castle, march out and come back.
	for m: Dictionary in Economy.marches:
		var camp := Economy.get_baron(String(m.get("camp", "")))
		if camp == null or camp.kingdom != kingdom:
			continue
		var out: bool = m.state == "out"
		var f := clampf((now - float(m.depart if out else m.arrive)) / maxf(float(m.arrive if out else m.back) - float(m.depart if out else m.arrive), 0.01), 0.0, 1.0)
		var from := home if out else _to_screen(camp.position)
		var to := _to_screen(camp.position) if out else home
		var p := from.lerp(to, f)
		draw_circle(p + Vector2(0, 1.5), 7.0, Color(0, 0, 0, 0.45))
		draw_circle(p, 7.0, OURS)
		draw_arc(p, 7.0, 0.0, TAU, 20, GOLD, 1.5, true)
		_caption(p - Vector2(0, 20), _clock(float(m.arrive if out else m.back) - now), 12, GOLD)
	# Ships: from your castle's shore south to the edge of the sheet.
	for boat: Dictionary in Economy.kingdom_ships(kingdom):
		var f := clampf((now - float(boat.depart)) / maxf(float(boat.arrive) - float(boat.depart), 0.01), 0.0, 1.0)
		var p := (home + Vector2(30, 40)).lerp(Vector2(rect.position.x + side * 0.56, rect.end.y - 18.0), f)
		_ship(p)
		_caption(p + Vector2(0, 16), "%d %s  %s" % [int(boat.amount), String(boat.good), _clock(float(boat.arrive) - now)], 12, GOLD)


func _tower(at: Vector2, color: Color) -> void:
	## A small keep with battlements and a flag.
	draw_rect(Rect2(at + Vector2(-11, -8) + Vector2(0, 2), Vector2(22, 20)), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(at + Vector2(-11, -8), Vector2(22, 20)), Color(0.82, 0.78, 0.7))
	for k in 3:
		draw_rect(Rect2(at + Vector2(-11 + k * 8.5, -13), Vector2(5, 6)), Color(0.82, 0.78, 0.7))
	draw_rect(Rect2(at + Vector2(-11, -8), Vector2(22, 20)), INK, false, 1.5)
	draw_rect(Rect2(at + Vector2(-3, 2), Vector2(6, 10)), INK)
	draw_line(at + Vector2(0, -13), at + Vector2(0, -26), INK, 1.5)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -26), at + Vector2(11, -22), at + Vector2(0, -18)]), color)


func _tent(at: Vector2, color: Color, text: String) -> void:
	## A camp: a tent with its level on a plate.
	draw_colored_polygon(PackedVector2Array([at + Vector2(-13, 10), at + Vector2(0, -11), at + Vector2(13, 10)]) , Color(0, 0, 0, 0.4))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-12, 8), at + Vector2(0, -12), at + Vector2(12, 8)]), color)
	draw_polyline(PackedVector2Array([at + Vector2(-12, 8), at + Vector2(0, -12), at + Vector2(12, 8), at + Vector2(-12, 8)]), INK, 1.5, true)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 8), at + Vector2(0, -1), at + Vector2(3, 8)]), INK)
	var plate := at + Vector2(13, -10)
	draw_circle(plate, 9.5, INK)
	draw_circle(plate, 8.0, Color(0.93, 0.86, 0.68))
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(_font, plate + Vector2(-width * 0.5, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)


func _ship(at: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-11, 0), at + Vector2(11, 0), at + Vector2(7, 6), at + Vector2(-7, 6)]), Color(0.42, 0.26, 0.12))
	draw_line(at + Vector2(0, 0), at + Vector2(0, -15), INK, 1.5)
	draw_colored_polygon(PackedVector2Array([at + Vector2(1, -14), at + Vector2(10, -3), at + Vector2(1, -3)]), Color(0.95, 0.92, 0.84))


func _caption(at: Vector2, text: String, font_size: int, color := Color(0.97, 0.93, 0.84)) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := at + Vector2(-width * 0.5, font_size * 0.35)
	draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(INK, 0.9))
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not Economy.kingdoms.has(kingdom):
		return
	accept_event()
	var best := ""
	var best_d := PICK_RADIUS
	for camp in Economy.kingdom_camps(kingdom):
		var d := _to_screen(camp.position).distance_to(event.position)
		if d < best_d:
			best_d = d
			best = camp.id
	if best == "" and _to_screen(_castle_pos()).distance_to(event.position) < PICK_RADIUS:
		castle_picked.emit()
		return
	selected = best
	camp_picked.emit(best)
	queue_redraw()


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]
