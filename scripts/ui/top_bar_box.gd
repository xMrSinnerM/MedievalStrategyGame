class_name TopBarBox
extends StyleBox
## The board along the top of the screen: dark leather lit from above, with
## a gold edge, a crimson stripe and a fine gold line along its foot, and a
## shadow falling on the map below.

var bg := Color(0.075, 0.058, 0.042, 0.96)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var a := bg.a
	for k in range(4, 0, -1):
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, rect.end.y, rect.size.x, 2.0 * k + 4.0), Color(0, 0, 0, 0.09 * a))
	var top := Color(bg.r + 0.05, bg.g + 0.038, bg.b + 0.024, a)
	var bottom := Color(bg.r * 0.6, bg.g * 0.6, bg.b * 0.6, a)
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	rs.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([top, top, bottom, bottom]))
	rs.canvas_item_add_texture_rect(to_canvas_item, rect, OrnateBox.grain().get_rid(), false, Color(0.75, 0.58, 0.36, 0.05 * a))
	var y := rect.end.y
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, y - 6.0, rect.size.x, 1.0), Color(GameTheme.RIM, 0.9 * a))
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, y - 5.0, rect.size.x, 3.0), Color(0.42, 0.08, 0.06, a))
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, y - 2.0, rect.size.x, 2.0), Color(GameTheme.RIM_BRIGHT, 0.9 * a))
	rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0), Color(1, 0.9, 0.7, 0.06 * a))
