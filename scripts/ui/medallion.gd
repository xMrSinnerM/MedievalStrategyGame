class_name Medallion
extends Control
## An icon set in a round gold medallion: a dark enamel disc inside a
## polished gold ring, for the resource bar and the map's dock.

var texture: Texture2D
var ring := Color(0.86, 0.66, 0.3)


static func make(icon: String, size := 40) -> Medallion:
	var m := Medallion.new()
	m.texture = Icons.get_icon(icon, int(size * 0.7))
	m.custom_minimum_size = Vector2(size, size)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.45))
	# The ring: darker below, brighter above, with a fine dark edge.
	draw_circle(c, r, ring.darkened(0.45))
	draw_circle(c - Vector2(0, 0.8), r - 0.8, ring)
	draw_arc(c, r - 1.5, PI * 1.1, PI * 1.9, 16, Color(1, 0.95, 0.75, 0.75), 1.2, true)
	# The enamel: deep crimson-brown, lit from the top.
	var inner := r * 0.8
	draw_circle(c, inner, Color(0.14, 0.05, 0.03))
	draw_circle(c - Vector2(0, inner * 0.18), inner * 0.78, Color(0.24, 0.09, 0.05))
	draw_arc(c, inner, 0.0, TAU, 32, Color(0.25, 0.15, 0.05), 1.0, true)
	if texture != null:
		var t := texture.get_size()
		draw_texture(texture, c - t * 0.5)
