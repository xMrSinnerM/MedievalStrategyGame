class_name CardBox
extends StyleBox
## A card inside a window: a dark plate a shade lighter at the top, with a
## thin gold rim, a fine highlight along its upper edge and small gold ticks
## in its corners. Its colours and rim width can be changed like a
## StyleBoxFlat's (bg_color, border_color, set_border_width_all).

var bg_color := Color(0.11, 0.09, 0.07, 0.6)
var border_color := Color(0.72, 0.55, 0.28, 0.45)
var border_width := 1.0
var ticks := true


func set_border_width_all(width: int) -> void:
	border_width = float(width)


func set_corner_radius_all(_radius: int) -> void:
	pass   # square corners with gold ticks


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var a := bg_color.a
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + Vector2(0, 2), rect.size), Color(0, 0, 0, 0.25 * minf(a * 2.0, 1.0)))
	var top := Color(bg_color.r + 0.045, bg_color.g + 0.035, bg_color.b + 0.022, a)
	var bottom := Color(bg_color.r * 0.75, bg_color.g * 0.75, bg_color.b * 0.75, a)
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	rs.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([top, top, bottom, bottom]))
	var w := border_width
	var c := border_color
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position, Vector2(rect.size.x, w)), c)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, rect.end.y - w, rect.size.x, w), c)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position, Vector2(w, rect.size.y)), c)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.end.x - w, rect.position.y, w, rect.size.y), c)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + Vector2(w + 1, w), Vector2(rect.size.x - 2 * w - 2, 1)), Color(1, 0.92, 0.75, 0.07))
	if ticks and rect.size.x > 40.0 and rect.size.y > 24.0:
		var gold := Color(GameTheme.RIM_BRIGHT, 0.85)
		var arm := 7.0
		for corner: Array in [[rect.position, Vector2(1, 1)], [Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)],
				[rect.end, Vector2(-1, -1)], [Vector2(rect.position.x, rect.end.y), Vector2(1, -1)]]:
			var at: Vector2 = corner[0]
			var d: Vector2 = corner[1]
			rs.canvas_item_add_rect(to_canvas_item, Rect2(at, Vector2(d.x * arm, d.y * 2.0)).abs(), gold)
			rs.canvas_item_add_rect(to_canvas_item, Rect2(at, Vector2(d.x * 2.0, d.y * arm)).abs(), gold)
