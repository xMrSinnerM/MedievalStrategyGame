class_name MenuBanner
extends MarginContainer
## A crimson cloth banner hanging from a wooden rod, with a gold border, a
## swallowtail hem and the realm's crest at the top. Children sit inside the
## cloth; the margins leave room for the crest and the tails.

const CLOTH_TOP := Color(0.55, 0.1, 0.08)
const CLOTH_BOTTOM := Color(0.3, 0.05, 0.05)
const GOLD := Color(0.9, 0.7, 0.34)
const GOLD_DARK := Color(0.55, 0.38, 0.14)
const WOOD := Color(0.33, 0.2, 0.1)
const ROD := 16.0       ## height of the rod
const TAIL := 70.0      ## depth of the swallowtail cut
const CREST := 118.0    ## room for the crest under the rod


func _init() -> void:
	add_theme_constant_override("margin_left", 46)
	add_theme_constant_override("margin_right", 46)
	add_theme_constant_override("margin_top", int(ROD + CREST))
	add_theme_constant_override("margin_bottom", int(TAIL + 34))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# A soft shadow on the scene behind, then the cloth.
	var shadow := _cloth(w, h, Vector2(10, 12))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	var cloth := _cloth(w, h, Vector2.ZERO)
	var colours := PackedColorArray()
	for p in cloth:
		colours.append(CLOTH_TOP.lerp(CLOTH_BOTTOM, clampf(p.y / h, 0.0, 1.0)))
	draw_polygon(cloth, colours)
	# Light falling on the folds: faint vertical stripes.
	for k in range(1, 6):
		var x := w * k / 6.0
		draw_line(Vector2(x, ROD), Vector2(x, h - TAIL * 0.9), Color(1, 1, 1, 0.025), 18.0)
	# Gold trim: an outer edge and an inner border following the hem.
	var edge := cloth.duplicate()
	edge.append(cloth[0])
	draw_polyline(edge, GOLD_DARK, 3.0, true)
	var inner := _cloth(w, h, Vector2.ZERO, 12.0)
	inner.append(inner[0])
	draw_polyline(inner, GOLD, 2.5, true)
	# The rod with round gold finials.
	draw_rect(Rect2(-22, 0, w + 44, ROD), WOOD)
	draw_rect(Rect2(-22, 0, w + 44, 4), WOOD.lightened(0.25))
	for x in [-26.0, w + 26.0]:
		draw_circle(Vector2(x, ROD * 0.5), 11.0, GOLD_DARK)
		draw_circle(Vector2(x, ROD * 0.5), 8.0, GOLD)
	_draw_crest(Vector2(w * 0.5, ROD + 16.0))


func _cloth(w: float, h: float, offset: Vector2, inset := 0.0) -> PackedVector2Array:
	## The cloth's outline (or a line inset inside it), clockwise from top left.
	var top := ROD + inset * 0.6
	return PackedVector2Array([
		Vector2(inset, top) + offset,
		Vector2(w - inset, top) + offset,
		Vector2(w - inset, h - inset * 1.2) + offset,
		Vector2(w * 0.5, h - TAIL + inset * 0.4) + offset,
		Vector2(inset, h - inset * 1.2) + offset,
	])


func _draw_crest(top: Vector2) -> void:
	## A gold-rimmed shield with a white castle on it.
	var sw := 76.0
	var sh := 90.0
	var shield := PackedVector2Array()
	shield.append(top + Vector2(-sw * 0.5, 0))
	shield.append(top + Vector2(sw * 0.5, 0))
	for k in range(0, 11):
		var t := k / 10.0
		var y := lerpf(sh * 0.45, sh, t)
		var x := sw * 0.5 * cos(t * PI * 0.5)
		shield.append(top + Vector2(x, y))
	for k in range(9, -1, -1):
		var t := k / 10.0
		var y := lerpf(sh * 0.45, sh, t)
		var x := -sw * 0.5 * cos(t * PI * 0.5)
		shield.append(top + Vector2(x, y))
	var rim := PackedVector2Array()
	var centre := top + Vector2(0, sh * 0.5)
	for p in shield:
		rim.append(centre + (p - centre) * 1.12)
	draw_colored_polygon(rim, GOLD_DARK)
	draw_colored_polygon(shield, Color(0.16, 0.2, 0.36))
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_polyline(outline, GOLD, 3.0, true)
	# The castle: a gate tower between two towers, with battlements.
	var stone := Color(0.93, 0.9, 0.82)
	var base := top + Vector2(0, 66)
	draw_rect(Rect2(base + Vector2(-26, -26), Vector2(52, 26)), stone)
	draw_rect(Rect2(base + Vector2(-26, -40), Vector2(14, 40)), stone)
	draw_rect(Rect2(base + Vector2(12, -40), Vector2(14, 40)), stone)
	draw_rect(Rect2(base + Vector2(-8, -48), Vector2(16, 48)), stone)
	for x in [-26.0, -16.0, 12.0, 22.0, -8.0, 4.0]:
		var y := -54.0 if absf(x + 2.0) < 7.0 else -46.0
		draw_rect(Rect2(base + Vector2(x, y), Vector2(4, 6)), stone)
	draw_rect(Rect2(base + Vector2(-5, -14), Vector2(10, 14)), Color(0.16, 0.2, 0.36))
	# A red pennant on the keep.
	draw_line(base + Vector2(0, -54), base + Vector2(0, -68), GOLD, 2.0)
	draw_colored_polygon(PackedVector2Array([base + Vector2(1, -68), base + Vector2(15, -64), base + Vector2(1, -60)]), Color(0.75, 0.12, 0.1))
