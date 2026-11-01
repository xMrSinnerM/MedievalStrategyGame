class_name StripedGrid
extends GridContainer
## A table: a grid whose first row is the heading, underlined in gold, and
## whose other rows sit on faint alternating stripes so a long list is easy
## to follow across.

var heading := true


func _ready() -> void:
	sort_children.connect(queue_redraw)


func _draw() -> void:
	var kids: Array[Control] = []
	for child in get_children():
		if child is Control and child.visible:
			kids.append(child)
	if kids.is_empty() or columns < 1:
		return
	var row := 0
	var gap := float(get_theme_constant("v_separation"))
	for i in range(0, kids.size(), columns):
		var top := INF
		var bottom := -INF
		for k in range(i, mini(i + columns, kids.size())):
			top = minf(top, kids[k].position.y)
			bottom = maxf(bottom, kids[k].position.y + kids[k].size.y)
		var r := Rect2(-6.0, top - gap * 0.5, size.x + 12.0, bottom - top + gap)
		if row == 0 and heading:
			draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color(GameTheme.RIM, 0.7))
		elif (row + (1 if heading else 0)) % 2 == 0:
			draw_rect(r, Color(1.0, 0.85, 0.6, 0.045))
		row += 1
