class_name Icons
extends RefCounted
## Small pictures for resources and castle stats, drawn from SVG so the game
## needs no image files: Icons.get_icon("wood"). Each is made once, at the
## size asked for, and kept.

const OUTLINE := "#2a1a0c"

const SVG := {
	# Two stacked logs with their cut ends showing.
	"wood": """
		<rect x="6" y="30" width="50" height="14" rx="7" fill="#9a6232" stroke="%s" stroke-width="3"/>
		<rect x="10" y="16" width="46" height="14" rx="7" fill="#b07440" stroke="%s" stroke-width="3"/>
		<circle cx="13" cy="37" r="6" fill="#e2b77a" stroke="%s" stroke-width="2.5"/>
		<circle cx="17" cy="23" r="6" fill="#e9c58c" stroke="%s" stroke-width="2.5"/>
		<circle cx="13" cy="37" r="2" fill="#9a6232"/><circle cx="17" cy="23" r="2" fill="#b07440"/>
		<rect x="8" y="48" width="44" height="6" rx="3" fill="#7a4a24" stroke="%s" stroke-width="2.5"/>""",
	# A heap of cut stone blocks.
	"stone": """
		<path d="M6 50 L12 32 L30 28 L36 50 Z" fill="#9b9ea6" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M30 50 L34 26 L54 24 L58 50 Z" fill="#b8bbc2" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M18 30 L22 12 L42 10 L46 28 Z" fill="#cfd2d8" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M24 16 L38 15" stroke="#ffffff" stroke-width="2" opacity="0.6"/>
		<path d="M36 30 L50 29" stroke="#ffffff" stroke-width="2" opacity="0.5"/>""",
	# A sheaf of wheat tied in the middle.
	"food": """
		<path d="M32 58 L32 26 M32 58 L20 30 M32 58 L44 30" stroke="#c99a3c" stroke-width="4" fill="none" stroke-linecap="round"/>
		<ellipse cx="32" cy="16" rx="6" ry="12" fill="#f0c95a" stroke="%s" stroke-width="3"/>
		<ellipse cx="18" cy="22" rx="5.5" ry="11" fill="#e8bd4c" stroke="%s" stroke-width="3" transform="rotate(-24 18 22)"/>
		<ellipse cx="46" cy="22" rx="5.5" ry="11" fill="#e8bd4c" stroke="%s" stroke-width="3" transform="rotate(24 46 22)"/>
		<rect x="23" y="40" width="18" height="7" rx="2" fill="#8c3b22" stroke="%s" stroke-width="2.5"/>""",
	# A small stack of gold coins.
	"gold": """
		<ellipse cx="26" cy="46" rx="18" ry="8" fill="#c8901c" stroke="%s" stroke-width="3"/>
		<ellipse cx="26" cy="40" rx="18" ry="8" fill="#e8b22e" stroke="%s" stroke-width="3"/>
		<ellipse cx="26" cy="33" rx="18" ry="8" fill="#f5c842" stroke="%s" stroke-width="3"/>
		<ellipse cx="42" cy="22" rx="16" ry="16" fill="#f8d257" stroke="%s" stroke-width="3"/>
		<ellipse cx="42" cy="22" rx="10" ry="10" fill="none" stroke="#b5821a" stroke-width="2.5"/>
		<path d="M37 17 L45 15" stroke="#fff4c0" stroke-width="2.5" stroke-linecap="round"/>""",
	# A nasal helmet, for soldiers.
	"soldiers": """
		<path d="M12 40 C12 18 52 18 52 40 L52 46 L12 46 Z" fill="#a9adb5" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<rect x="29" y="30" width="6" height="24" rx="2" fill="#8d9199" stroke="%s" stroke-width="2.5"/>
		<rect x="8" y="44" width="48" height="7" rx="3" fill="#7d6040" stroke="%s" stroke-width="2.5"/>
		<path d="M22 24 C26 20 32 19 36 20" stroke="#ffffff" stroke-width="2.5" fill="none" opacity="0.6" stroke-linecap="round"/>""",
	# A builder's hammer.
	"builders": """
		<rect x="27" y="22" width="8" height="36" rx="3" fill="#a46c3a" stroke="%s" stroke-width="3" transform="rotate(35 31 40)"/>
		<path d="M10 20 L40 6 L48 18 L18 32 Z" fill="#9aa0a8" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M16 22 L40 11" stroke="#ffffff" stroke-width="2" opacity="0.55"/>""",
	# A heater shield with a cross.
	"defence": """
		<path d="M32 6 L54 12 C54 34 46 50 32 58 C18 50 10 34 10 12 Z" fill="#3f5f9a" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M32 10 L32 54 M14 26 L50 26" stroke="#e8c45a" stroke-width="6"/>
		<path d="M32 6 L54 12 C54 34 46 50 32 58" fill="none" stroke="#1d2f52" stroke-width="2" opacity="0.5"/>""",
	# A crown, for might on the leaderboard.
	"might": """
		<path d="M8 22 L20 34 L32 12 L44 34 L56 22 L52 50 L12 50 Z" fill="#f2c443" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<rect x="12" y="46" width="40" height="8" rx="2" fill="#d19d22" stroke="%s" stroke-width="3"/>
		<circle cx="32" cy="38" r="4" fill="#c0392b" stroke="%s" stroke-width="2"/>
		<circle cx="8" cy="20" r="3.5" fill="#f2c443" stroke="%s" stroke-width="2"/>
		<circle cx="32" cy="10" r="3.5" fill="#f2c443" stroke="%s" stroke-width="2"/>
		<circle cx="56" cy="20" r="3.5" fill="#f2c443" stroke="%s" stroke-width="2"/>""",
	# An hourglass, for time.
	"time": """
		<rect x="14" y="6" width="36" height="6" rx="2" fill="#8a5a2e" stroke="%s" stroke-width="3"/>
		<rect x="14" y="52" width="36" height="6" rx="2" fill="#8a5a2e" stroke="%s" stroke-width="3"/>
		<path d="M19 12 L45 12 C45 24 36 28 34 32 C36 36 45 40 45 52 L19 52 C19 40 28 36 30 32 C28 28 19 24 19 12 Z" fill="#e8e2d0" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M24 48 L40 48 C38 42 34 40 32 38 C30 40 26 42 24 48 Z" fill="#e0b048"/>""",
}

static var _cache := {}


static func get_icon(icon: String, size := 24) -> Texture2D:
	## The icon called `icon`, `size` pixels square (null if there's no such icon).
	var key := "%s@%d" % [icon, size]
	if _cache.has(key):
		return _cache[key]
	if not SVG.has(icon):
		return null
	var body: String = SVG[icon]
	body = body.replace("%s", OUTLINE)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">%s</svg>' % body
	var image := Image.new()
	image.load_svg_from_string(svg, size / 64.0)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func rect(icon: String, size := 24) -> TextureRect:
	## A TextureRect showing the icon, ready to put in a box.
	var r := TextureRect.new()
	r.texture = get_icon(icon, size)
	r.custom_minimum_size = Vector2(size, size)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
