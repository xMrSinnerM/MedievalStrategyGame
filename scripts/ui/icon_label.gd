class_name IconLabel
extends RichTextLabel
## A line of text that shows amounts of things as their icons: "150 wood,
## 100 stone" reads as [wood] 150  [stone] 100. Words with no icon stay as
## they are. Set the text with show_text(); size and colour as for a Label.

const WORDS := {
	"wood": "wood", "stone": "stone", "food": "food", "gold": "gold",
	"marks": "marks", "gem": "gem", "gems": "gem",
	"soldiers": "soldiers", "spearmen": "spearman", "spearman": "spearman",
	"archers": "archer", "archer": "archer", "swordsmen": "swordsman", "swordsman": "swordsman",
	"horsemen": "horseman", "horseman": "horseman",
}

static var _amount := RegEx.create_from_string("(\\d[\\d,]*)\\s+([A-Za-z]+)")
## "60 wood, 30 stone": the comma between two amounts goes, the icons part them.
static var _list_comma := RegEx.create_from_string("(\\d\\s+(?:wood|stone|food|gold|marks|gems?)),\\s+(?=\\d)")

var font_size := 15
var colour := MenuStyle.TEXT


static func make(text := "", size := 15, color := MenuStyle.TEXT) -> IconLabel:
	var l := IconLabel.new()
	l.font_size = size
	l.colour = color
	l.show_text(text)
	return l


func _init() -> void:
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_font_override("normal_font", GameTheme.BODY_FONT)
	add_theme_font_override("bold_font", GameTheme.BOLD_FONT)
	add_theme_color_override("font_outline_color", GameTheme.INK)
	add_theme_constant_override("outline_size", 2)


func show_text(text: String) -> void:
	clear()
	text = _list_comma.sub(text, "$1   ", true)
	var pic := font_size + (6 if font_size > 13 else 4)
	add_theme_font_size_override("normal_font_size", font_size)
	add_theme_font_size_override("bold_font_size", font_size)
	push_color(colour)
	var at := 0
	for m in _amount.search_all(text):
		var icon := String(WORDS.get(m.get_string(2).to_lower(), ""))
		if icon == "" or Icons.get_icon(icon, pic) == null:
			continue
		add_text(text.substr(at, m.get_start() - at))
		add_image(Icons.get_icon(icon, pic), pic, pic, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		push_bold()
		add_text(" " + m.get_string(1))
		pop()
		at = m.get_end()
	add_text(text.substr(at))
	pop()
	set_meta("plain", text)
