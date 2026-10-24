class_name OrnateBox
extends StyleBox
## The game's window frame: a near-black board with a thin gold rim, a fine
## inner line and gold filigree in the corners. Used for every panel through
## GameTheme.panel_box.

var bg := Color(0.05, 0.042, 0.034, 0.95)
var rim := Color(0.72, 0.55, 0.28)
var inner := Color(0.45, 0.34, 0.17, 0.55)
var shadow := 8.0
var filigree := true
## Height of the title row: a fading gold rule is drawn under it on big
## windows; 0 for none.
var header := 0.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	# Shadow: a few widening, fading layers, a little lower than the frame.
	for k in range(3, 0, -1):
		var grow := shadow * k / 3.0
		rs.canvas_item_add_rect(to_canvas_item, rect.grow(grow).grow_side(SIDE_BOTTOM, 3.0), Color(0, 0, 0, 0.13 * bg.a))
	rs.canvas_item_add_rect(to_canvas_item, rect, bg)
	# A faint warm glow at the top of the board.
	var glow := Rect2(rect.position, Vector2(rect.size.x, minf(rect.size.y * 0.3, 90.0)))
	var warm := Color(0.55, 0.38, 0.18, 0.07 * bg.a)
	var clear := Color(0.55, 0.38, 0.18, 0.0)
	_gradient(to_canvas_item, glow, warm, clear)
	_frame(to_canvas_item, rect, 1.0, rim)
	var big := rect.size.x > 60.0 and rect.size.y > 40.0
	if big:
		_frame(to_canvas_item, rect.grow(-4.0), 1.0, inner)
	if header > 0.0 and rect.size.x > 380.0 and rect.size.y > header * 4.0:
		_rule(to_canvas_item, Vector2(rect.position.x + 14.0, rect.position.y + header), rect.size.x - 28.0)
	if filigree and rect.size.x > 80.0 and rect.size.y > 40.0:
		# Full filigree on windows, a plain bracket on small boxes.
		var arm := 22.0 if rect.size.x > 260.0 and rect.size.y > 120.0 else 10.0
		_corner(to_canvas_item, rect.position, Vector2(1, 1), arm)
		_corner(to_canvas_item, Vector2(rect.end.x, rect.position.y), Vector2(-1, 1), arm)
		_corner(to_canvas_item, rect.end, Vector2(-1, -1), arm)
		_corner(to_canvas_item, Vector2(rect.position.x, rect.end.y), Vector2(1, -1), arm)


func _frame(item: RID, r: Rect2, width: float, colour: Color) -> void:
	var rs := RenderingServer
	rs.canvas_item_add_rect(item, Rect2(r.position, Vector2(r.size.x, width)), colour)
	rs.canvas_item_add_rect(item, Rect2(Vector2(r.position.x, r.end.y - width), Vector2(r.size.x, width)), colour)
	rs.canvas_item_add_rect(item, Rect2(r.position, Vector2(width, r.size.y)), colour)
	rs.canvas_item_add_rect(item, Rect2(Vector2(r.end.x - width, r.position.y), Vector2(width, r.size.y)), colour)


func _gradient(item: RID, r: Rect2, top: Color, bottom: Color) -> void:
	var points := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	RenderingServer.canvas_item_add_polygon(item, points, PackedColorArray([top, top, bottom, bottom]))


func _rule(item: RID, from: Vector2, length: float) -> void:
	## A gold hairline that fades out at both ends.
	var mid := from + Vector2(length * 0.5, 0)
	var gold := Color(rim, 0.8)
	var none := Color(rim, 0.0)
	for side in [-1.0, 1.0]:
		var end := mid + Vector2(length * 0.5 * side, 0)
		var points := PackedVector2Array([mid, end, end + Vector2(0, 1), mid + Vector2(0, 1)])
		RenderingServer.canvas_item_add_polygon(item, points, PackedColorArray([gold, none, none, gold]))


func _corner(item: RID, at: Vector2, d: Vector2, arm: float) -> void:
	## Gold filigree for one corner; d points into the window.
	var rs := RenderingServer
	var gold := rim.lightened(0.2)
	# A heavier L bracket over the rim.
	rs.canvas_item_add_rect(item, Rect2(at, Vector2(d.x * arm, d.y * 2.0)).abs(), gold)
	rs.canvas_item_add_rect(item, Rect2(at, Vector2(d.x * 2.0, d.y * arm)).abs(), gold)
	if arm < 14.0:
		return
	# A finer bracket over the inner line and a small diamond between them.
	var inset := at + d * 4.0
	var fine := arm * 0.55
	rs.canvas_item_add_rect(item, Rect2(inset, Vector2(d.x * fine, d.y)).abs(), gold)
	rs.canvas_item_add_rect(item, Rect2(inset, Vector2(d.x, d.y * fine)).abs(), gold)
	var c := at + d * 10.0
	var r := 3.0
	rs.canvas_item_add_polygon(item, PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			PackedColorArray([gold]))
