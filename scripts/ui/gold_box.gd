class_name GoldBox
extends StyleBox
## The face of a main action button: polished gold, lighter at the top, with
## a bright rim and a highlight along the upper edge.

var top := Color(1.0, 0.86, 0.52)
var bottom := Color(0.64, 0.43, 0.15)
var rim := Color(1.0, 0.9, 0.62)
var glow := 0.0     ## a warm halo, for the hovered button


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if glow > 0.0:
		for k in range(3, 0, -1):
			rs.canvas_item_add_rect(to_canvas_item, rect.grow(2.0 * k), Color(1.0, 0.78, 0.35, glow * 0.12))
	else:
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + Vector2(0, 2), rect.size), Color(0, 0, 0, 0.45))
	var mid := top.lerp(bottom, 0.45)
	var half := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5))
	var low := Rect2(rect.position + Vector2(0, rect.size.y * 0.5), Vector2(rect.size.x, rect.size.y * 0.5))
	for part in [[half, top, mid], [low, mid, bottom]]:
		var r: Rect2 = part[0]
		var points := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		rs.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([part[1], part[1], part[2], part[2]]))
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, 1)), Color(1, 1, 0.9, 0.55))
	for r in [Rect2(rect.position, Vector2(rect.size.x, 1)), Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1),
			Rect2(rect.position, Vector2(1, rect.size.y)), Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y)]:
		rs.canvas_item_add_rect(to_canvas_item, r, rim)
