class_name OrnateBox
extends StyleBox
## The game's window frame: a dark leather board with a fine grain, darker
## towards its edges, inside a double gold rim with filigree corners and gold
## studs. Big windows get a crimson title band with a gold rule under it.
## Used for every panel through GameTheme.panel_box.

var bg := Color(0.05, 0.042, 0.034, 0.95)
var rim := Color(0.72, 0.55, 0.28)
var inner := Color(0.45, 0.34, 0.17, 0.55)
var shadow := 8.0
var filigree := true
## Height of the title row: a crimson band with a gold rule under it is drawn
## on big windows; 0 for none.
var header := 0.0

const BAND_TOP := Color(0.42, 0.08, 0.06)
const BAND_BOTTOM := Color(0.22, 0.04, 0.03)

static var _grain: Texture2D


static func grain() -> Texture2D:
	## A soft leather grain, stretched faintly over boards.
	if _grain != null:
		return _grain
	var size := 320
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_LA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y)
			var v := clampf(0.5 + n * 0.9 + rng.randf_range(-0.12, 0.12), 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_grain = ImageTexture.create_from_image(img)
	return _grain


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var a := bg.a
	var big := rect.size.x > 260.0 and rect.size.y > 120.0
	# Shadow: a few widening, fading layers, a little lower than the frame.
	for k in range(4, 0, -1):
		var grow := shadow * k / 4.0
		rs.canvas_item_add_rect(to_canvas_item, rect.grow(grow).grow_side(SIDE_BOTTOM, 4.0), Color(0, 0, 0, 0.11 * a))
	# The board: a little lighter at the top.
	var top := Color(bg.r + 0.035, bg.g + 0.027, bg.b + 0.018, a)
	var bottom := Color(bg.r * 0.8, bg.g * 0.8, bg.b * 0.8, a)
	_gradient(to_canvas_item, rect, top, bottom)
	if big:
		rs.canvas_item_add_texture_rect(to_canvas_item, rect, grain().get_rid(), false, Color(0.75, 0.58, 0.36, 0.05 * a))
		# Darker towards the edges.
		var edge := minf(48.0, rect.size.y * 0.2)
		var dark := Color(0, 0, 0, 0.32 * a)
		var none := Color(0, 0, 0, 0)
		_gradient(to_canvas_item, Rect2(rect.position.x, rect.end.y - edge, rect.size.x, edge), none, dark)
		_hgradient(to_canvas_item, Rect2(rect.position, Vector2(edge, rect.size.y)), dark, none)
		_hgradient(to_canvas_item, Rect2(rect.end.x - edge, rect.position.y, edge, rect.size.y), none, dark)
	else:
		# A faint warm glow at the top of small boards.
		var glow := Rect2(rect.position, Vector2(rect.size.x, minf(rect.size.y * 0.3, 90.0)))
		_gradient(to_canvas_item, glow, Color(0.55, 0.38, 0.18, 0.07 * a), Color(0.55, 0.38, 0.18, 0.0))
	if header > 0.0 and rect.size.x > 380.0 and rect.size.y > header * 4.0:
		_band(to_canvas_item, Rect2(rect.position + Vector2(5, 5), Vector2(rect.size.x - 10.0, header - 5.0)), a)
	# Double rim: a bright outer line with a darker one inside it, then a
	# fine inner line a few pixels in.
	_frame(to_canvas_item, rect, 2.0, Color(rim.lightened(0.08), rim.a))
	_frame(to_canvas_item, rect.grow(-2.0), 1.0, Color(0.16, 0.1, 0.04, 0.9 * a))
	if rect.size.x > 60.0 and rect.size.y > 40.0:
		_frame(to_canvas_item, rect.grow(-5.0), 1.0, inner)
	if filigree and rect.size.x > 80.0 and rect.size.y > 40.0:
		# Full filigree on windows, a plain bracket on small boxes.
		var arm := 30.0 if big else 10.0
		_corner(to_canvas_item, rect.position, Vector2(1, 1), arm)
		_corner(to_canvas_item, Vector2(rect.end.x, rect.position.y), Vector2(-1, 1), arm)
		_corner(to_canvas_item, rect.end, Vector2(-1, -1), arm)
		_corner(to_canvas_item, Vector2(rect.position.x, rect.end.y), Vector2(1, -1), arm)
		if big and rect.size.x > 500.0:
			# A gold diamond in the middle of the top and bottom edges.
			_diamond(to_canvas_item, Vector2(rect.get_center().x, rect.position.y), 6.0, rim.lightened(0.25))
			_diamond(to_canvas_item, Vector2(rect.get_center().x, rect.end.y), 6.0, rim.lightened(0.25))


func _band(item: RID, r: Rect2, a: float) -> void:
	## The crimson title band, shaded like cloth, with a gold rule beneath.
	_gradient(item, r, Color(BAND_TOP, 0.92 * a), Color(BAND_BOTTOM, 0.92 * a))
	RenderingServer.canvas_item_add_texture_rect(item, r, grain().get_rid(), false, Color(1, 0.7, 0.6, 0.06 * a))
	# A soft light along the top of the band.
	_gradient(item, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.4)), Color(1, 0.75, 0.6, 0.1 * a), Color(1, 0.75, 0.6, 0.0))
	var y := r.end.y
	RenderingServer.canvas_item_add_rect(item, Rect2(r.position.x, y - 1.0, r.size.x, 1.0), Color(0.08, 0.02, 0.01, 0.9 * a))
	RenderingServer.canvas_item_add_rect(item, Rect2(r.position.x, y, r.size.x, 2.0), Color(rim.lightened(0.1), a))
	RenderingServer.canvas_item_add_rect(item, Rect2(r.position.x, y + 2.0, r.size.x, 1.0), Color(0, 0, 0, 0.5 * a))
	_rule(item, Vector2(r.position.x + 30.0, y + 5.0), r.size.x - 60.0)


func _frame(item: RID, r: Rect2, width: float, colour: Color) -> void:
	var rs := RenderingServer
	rs.canvas_item_add_rect(item, Rect2(r.position, Vector2(r.size.x, width)), colour)
	rs.canvas_item_add_rect(item, Rect2(Vector2(r.position.x, r.end.y - width), Vector2(r.size.x, width)), colour)
	rs.canvas_item_add_rect(item, Rect2(r.position, Vector2(width, r.size.y)), colour)
	rs.canvas_item_add_rect(item, Rect2(Vector2(r.end.x - width, r.position.y), Vector2(width, r.size.y)), colour)


func _gradient(item: RID, r: Rect2, top: Color, bottom: Color) -> void:
	var points := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	RenderingServer.canvas_item_add_polygon(item, points, PackedColorArray([top, top, bottom, bottom]))


func _hgradient(item: RID, r: Rect2, left: Color, right: Color) -> void:
	var points := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	RenderingServer.canvas_item_add_polygon(item, points, PackedColorArray([left, right, right, left]))


func _rule(item: RID, from: Vector2, length: float) -> void:
	## A gold hairline that fades out at both ends.
	var mid := from + Vector2(length * 0.5, 0)
	var gold := Color(rim, 0.55)
	var none := Color(rim, 0.0)
	for side in [-1.0, 1.0]:
		var end := mid + Vector2(length * 0.5 * side, 0)
		var points := PackedVector2Array([mid, end, end + Vector2(0, 1), mid + Vector2(0, 1)])
		RenderingServer.canvas_item_add_polygon(item, points, PackedColorArray([gold, none, none, gold]))


func _diamond(item: RID, c: Vector2, r: float, colour: Color) -> void:
	RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			PackedColorArray([colour]))
	var dark := Color(0.2, 0.12, 0.04)
	var s := r * 0.4
	RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]),
			PackedColorArray([dark]))


func _corner(item: RID, at: Vector2, d: Vector2, arm: float) -> void:
	## Gold filigree for one corner; d points into the window.
	var rs := RenderingServer
	var gold := rim.lightened(0.2)
	var deep := rim.darkened(0.35)
	# A heavier L bracket over the rim, with a dark edge for depth.
	rs.canvas_item_add_rect(item, Rect2(at + d, Vector2(d.x * arm, d.y * 3.0)).abs(), deep)
	rs.canvas_item_add_rect(item, Rect2(at + d, Vector2(d.x * 3.0, d.y * arm)).abs(), deep)
	rs.canvas_item_add_rect(item, Rect2(at, Vector2(d.x * arm, d.y * 3.0)).abs(), gold)
	rs.canvas_item_add_rect(item, Rect2(at, Vector2(d.x * 3.0, d.y * arm)).abs(), gold)
	if arm < 14.0:
		return
	# Two gold arcs across the corner with a stud on the outer one.
	for ring: Array in [[17.0, 1.6, gold], [11.0, 1.0, Color(gold, 0.6)]]:
		var r: float = ring[0]
		var pts := PackedVector2Array()
		for k in 10:
			var t := k / 9.0 * PI * 0.5
			pts.append(at + Vector2(d.x * r * cos(t), d.y * r * sin(t)))
		rs.canvas_item_add_polyline(item, pts, PackedColorArray([ring[2]]), ring[1], true)
	var stud := at + d * 17.0 * 0.7071
	rs.canvas_item_add_circle(item, stud + Vector2(0, 1), 3.5, Color(0, 0, 0, 0.5))
	rs.canvas_item_add_circle(item, stud, 3.5, gold)
	rs.canvas_item_add_circle(item, stud - Vector2(0.8, 0.8), 1.3, Color(1, 0.96, 0.8))
	_diamond(item, at + d * Vector2(arm + 4.0, 1.5), 3.0, gold)
	_diamond(item, at + d * Vector2(1.5, arm + 4.0), 3.0, gold)
