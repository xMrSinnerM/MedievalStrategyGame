class_name ChanceRing
extends Control
## A ring that fills with the chance of victory, red through gold to green,
## with the percentage in the middle; "?" while the odds are unknown.

const WIN := Color(0.45, 0.85, 0.42)
const EVEN := Color(0.95, 0.78, 0.35)
const LOSS := Color(0.92, 0.36, 0.28)

## 0..1, or below 0 for unknown.
var chance := -1.0:
	set(value):
		chance = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(76, 76)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func colour_for(c: float) -> Color:
	return LOSS.lerp(EVEN, clampf(c * 2.0, 0.0, 1.0)) if c < 0.5 else EVEN.lerp(WIN, clampf(c * 2.0 - 1.0, 0.0, 1.0))


func _draw() -> void:
	var centre := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	draw_circle(centre, r + 5.0, Color(0, 0, 0, 0.35))
	draw_arc(centre, r, 0.0, TAU, 64, Color(0.25, 0.2, 0.14), 7.0, true)
	var font := GameTheme.BOLD_FONT
	var text := "?"
	var colour := GameTheme.TEXT
	if chance >= 0.0:
		colour = colour_for(chance)
		if chance > 0.0:
			draw_arc(centre, r, -PI * 0.5, -PI * 0.5 + TAU * chance, 64, colour, 7.0, true)
		text = "%d%%" % roundi(chance * 100.0)
	var font_size := 22
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, centre + Vector2(-w * 0.5, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
