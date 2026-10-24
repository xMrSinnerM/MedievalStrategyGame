class_name OrnateBox
extends StyleBox
## The game's window frame: dark oak with a gold rim, a fine inner gold line,
## gold studs in the corners and a soft shadow. Used for every panel through
## GameTheme.panel_box.

var bg := Color(0.1, 0.065, 0.04, 0.95)
var rim := Color(0.86, 0.66, 0.32)
var inner := Color(0.62, 0.45, 0.2, 0.7)
var shadow := 8.0
var studs := true
## Height of a crimson band across the top for the window's title; 0 for
## none. Only drawn on big windows, so tooltips and small boxes stay plain.
var header := 0.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	# Shadow: a few widening, fading layers, a little lower than the frame.
	for k in range(3, 0, -1):
		var grow := shadow * k / 3.0
		rs.canvas_item_add_rect(to_canvas_item, rect.grow(grow).grow_side(SIDE_BOTTOM, 3.0), Color(0, 0, 0, 0.12 * bg.a))
	rs.canvas_item_add_rect(to_canvas_item, rect, bg)
	# A faint sheen on the upper part of the board.
	var sheen := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35))
	rs.canvas_item_add_rect(to_canvas_item, sheen, Color(1.0, 0.85, 0.6, 0.035 * bg.a))
	if header > 0.0 and rect.size.x > 380.0 and rect.size.y > header * 4.0:
		var band := Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, header))
		var top := Color(0.5, 0.12, 0.08, bg.a)
		var bottom := Color(0.3, 0.07, 0.05, bg.a)
		var corners := PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
		rs.canvas_item_add_polygon(to_canvas_item, corners, PackedColorArray([top, top, bottom, bottom]))
		rs.canvas_item_add_rect(to_canvas_item, Rect2(band.position.x, band.end.y, band.size.x, 2.0), rim)
	_frame(to_canvas_item, rect, 2.0, rim)
	var gap := 5.0 if rect.size.x > 60.0 and rect.size.y > 40.0 else 0.0
	if gap > 0.0:
		_frame(to_canvas_item, rect.grow(-gap), 1.0, inner)
	if studs and rect.size.x > 80.0 and rect.size.y > 60.0:
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			_stud(to_canvas_item, corner)


func _frame(item: RID, r: Rect2, width: float, colour: Color) -> void:
	var rs := RenderingServer
	rs.canvas_item_add_rect(item, Rect2(r.position, Vector2(r.size.x, width)), colour)
	rs.canvas_item_add_rect(item, Rect2(Vector2(r.position.x, r.end.y - width), Vector2(r.size.x, width)), colour)
	rs.canvas_item_add_rect(item, Rect2(r.position, Vector2(width, r.size.y)), colour)
	rs.canvas_item_add_rect(item, Rect2(Vector2(r.end.x - width, r.position.y), Vector2(width, r.size.y)), colour)


func _stud(item: RID, at: Vector2) -> void:
	## A gold diamond with a dark centre over a corner of the rim.
	var s := 7.0
	var outer := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0)])
	RenderingServer.canvas_item_add_polygon(item, outer, PackedColorArray([rim.lightened(0.15)]))
	var c := 2.5
	var core := PackedVector2Array([at + Vector2(0, -c), at + Vector2(c, 0), at + Vector2(0, c), at + Vector2(-c, 0)])
	RenderingServer.canvas_item_add_polygon(item, core, PackedColorArray([Color(0.25, 0.08, 0.05)]))
