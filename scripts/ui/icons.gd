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
	# A rolled scroll with a red seal, for quests.
	"quests": """
		<rect x="14" y="10" width="36" height="44" rx="3" fill="#ead8ae" stroke="%s" stroke-width="3"/>
		<rect x="10" y="6" width="44" height="9" rx="4.5" fill="#c9a96e" stroke="%s" stroke-width="3"/>
		<rect x="10" y="49" width="44" height="9" rx="4.5" fill="#c9a96e" stroke="%s" stroke-width="3"/>
		<path d="M20 24 H44 M20 31 H44 M20 38 H36" stroke="#8a6a3a" stroke-width="2.5" stroke-linecap="round"/>
		<circle cx="42" cy="42" r="6" fill="#b5281e" stroke="%s" stroke-width="2.5"/>""",
	# A plumed great helm, for commanders.
	"commanders": """
		<path d="M16 26 C16 12 48 12 48 26 L48 52 L16 52 Z" fill="#b8bcc4" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<rect x="20" y="30" width="24" height="5" rx="2" fill="#2b2b30"/>
		<path d="M32 36 V50" stroke="#2b2b30" stroke-width="3"/>
		<path d="M32 14 C36 4 48 4 54 10 C46 10 40 14 36 18 Z" fill="#c0392b" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>""",
	# A wooden watchtower with a pennant, for the outpost.
	"outpost": """
		<path d="M18 58 L24 22 L40 22 L46 58" fill="none" stroke="#8a5a2e" stroke-width="5" stroke-linejoin="round"/>
		<path d="M21 44 L43 44 M22 34 L42 34" stroke="#8a5a2e" stroke-width="4"/>
		<path d="M14 24 L32 10 L50 24 Z" fill="#b5281e" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M32 10 V2 L42 5 L32 8" fill="#e8c45a" stroke="%s" stroke-width="1.5"/>""",
	# A cottage with a red roof, for villages.
	"villages": """
		<rect x="14" y="30" width="36" height="26" fill="#ead8ae" stroke="%s" stroke-width="3"/>
		<path d="M8 32 L32 10 L56 32 Z" fill="#b5281e" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<rect x="27" y="40" width="10" height="16" fill="#7a4a24" stroke="%s" stroke-width="2"/>
		<rect x="40" y="14" width="6" height="12" fill="#8d9199" stroke="%s" stroke-width="2"/>""",
	# Two crossed banners, for the alliance.
	"alliance": """
		<path d="M14 58 L30 8 M50 58 L34 8" stroke="#8a5a2e" stroke-width="4" stroke-linecap="round"/>
		<path d="M30 8 L12 14 L16 26 L27 20 Z" fill="#3f5f9a" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M34 8 L52 14 L48 26 L37 20 Z" fill="#b5281e" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>""",
	# A gold star, for events.
	"events": """
		<path d="M32 6 L39 24 L58 25 L43 37 L48 56 L32 45 L16 56 L21 37 L6 25 L25 24 Z" fill="#f2c443" stroke="%s" stroke-width="3" stroke-linejoin="round"/>""",
	# A key, for the owner's tools.
	"owner": """
		<circle cx="20" cy="22" r="11" fill="none" stroke="#e0b048" stroke-width="6"/>
		<path d="M28 30 L54 56 M44 46 L50 40 M50 52 L56 46" stroke="#e0b048" stroke-width="6" stroke-linecap="round"/>""",
	# A trophy cup, for the leaderboard.
	"leaderboard": """
		<path d="M18 8 H46 V22 C46 34 40 40 32 40 C24 40 18 34 18 22 Z" fill="#f2c443" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M18 14 H8 C8 26 14 30 20 30 M46 14 H56 C56 26 50 30 44 30" fill="none" stroke="%s" stroke-width="3"/>
		<rect x="28" y="40" width="8" height="10" fill="#d19d22" stroke="%s" stroke-width="2.5"/>
		<rect x="18" y="50" width="28" height="8" rx="2" fill="#8a5a2e" stroke="%s" stroke-width="2.5"/>""",
	# A merchant's scales, for the market.
	"market": """
		<path d="M32 8 V52" stroke="#8a5a2e" stroke-width="4" stroke-linecap="round"/>
		<path d="M10 16 H54" stroke="%s" stroke-width="4" stroke-linecap="round"/>
		<path d="M10 16 L4 34 M10 16 L16 34 M54 16 L48 34 M54 16 L60 34" stroke="#c79a52" stroke-width="2" fill="none"/>
		<path d="M3 34 H17 C17 40 3 40 3 34 Z" fill="#f2c443" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M47 34 H61 C61 40 47 40 47 34 Z" fill="#f2c443" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>
		<circle cx="32" cy="10" r="4" fill="#f5c842" stroke="%s" stroke-width="2.5"/>
		<rect x="20" y="52" width="24" height="7" rx="2" fill="#8a5a2e" stroke="%s" stroke-width="2.5"/>""",
	# A sealed treaty, for diplomacy.
	"diplomacy": """
		<rect x="10" y="10" width="44" height="40" rx="3" fill="#ead8ae" stroke="%s" stroke-width="3"/>
		<path d="M17 20 H47 M17 27 H47 M17 34 H38" stroke="#8a6a3a" stroke-width="2.5" stroke-linecap="round"/>
		<path d="M40 44 L36 60 L42 56 L46 60 L46 44" fill="#b5281e" stroke="%s" stroke-width="2"/>
		<circle cx="43" cy="44" r="7" fill="#b5281e" stroke="%s" stroke-width="2.5"/>""",
	# The realm's crest: a gold-rimmed red shield with a white castle.
	"crest": """
		<path d="M32 3 L58 9 C58 36 48 52 32 61 C16 52 6 36 6 9 Z" fill="#9e1d16" stroke="#e6bf6a" stroke-width="4" stroke-linejoin="round"/>
		<path d="M18 44 V26 H22 V30 H26 V22 H30 V26 H34 V22 H38 V30 H42 V26 H46 V44 Z" fill="#f2ead8"/>
		<rect x="29" y="35" width="6" height="9" fill="#9e1d16"/>""",
	# A gold compass rose, for the map controls.
	"compass": """
		<circle cx="32" cy="32" r="24" fill="#1c140c" stroke="#e0b048" stroke-width="3"/>
		<path d="M32 8 L37 32 L32 56 L27 32 Z" fill="#e8c45a" stroke="%s" stroke-width="2" stroke-linejoin="round"/>
		<path d="M8 32 L32 27 L56 32 L32 37 Z" fill="#c9a96e" stroke="%s" stroke-width="2" stroke-linejoin="round"/>
		<path d="M32 8 L37 32 L27 32 Z" fill="#b5281e"/>
		<circle cx="32" cy="32" r="3.5" fill="#f2ead8" stroke="%s" stroke-width="1.5"/>""",
	# A magnifying glass, for zoom.
	"zoom": """
		<circle cx="26" cy="26" r="16" fill="#3b5f7a" stroke="#e0b048" stroke-width="5"/>
		<path d="M38 38 L56 56" stroke="#8a5a2e" stroke-width="8" stroke-linecap="round"/>
		<path d="M18 20 C20 16 24 14 28 14" fill="none" stroke="#cfe3ef" stroke-width="3" stroke-linecap="round"/>""",
	# A target ring, for centring the map on your castle.
	"target": """
		<circle cx="32" cy="32" r="20" fill="none" stroke="#e0b048" stroke-width="4"/>
		<circle cx="32" cy="32" r="9" fill="#b5281e" stroke="%s" stroke-width="2.5"/>
		<path d="M32 4 V16 M32 48 V60 M4 32 H16 M48 32 H60" stroke="#e0b048" stroke-width="4" stroke-linecap="round"/>""",
	# An unrolled parchment map, for the parchment view.
	"parchment": """
		<path d="M8 14 L22 8 L42 14 L56 8 V50 L42 56 L22 50 L8 56 Z" fill="#ead8ae" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M22 8 V50 M42 14 V56" stroke="#a88a55" stroke-width="2"/>
		<path d="M12 40 C18 34 24 38 30 30 C36 22 44 28 52 20" fill="none" stroke="#b5281e" stroke-width="2.5" stroke-dasharray="4 3"/>""",
	# A framed little map, for the minimap.
	"minimap": """
		<rect x="8" y="8" width="48" height="48" rx="4" fill="#5d8a3a" stroke="#e0b048" stroke-width="4"/>
		<path d="M8 36 C20 30 28 44 40 34 C46 29 52 32 56 30" fill="none" stroke="#5aa0d0" stroke-width="4"/>
		<rect x="22" y="18" width="18" height="13" fill="none" stroke="#f2ead8" stroke-width="2.5"/>""",
	# A flower in bloom, for public order and decorations.
	"order": """
		<path d="M32 36 V60" stroke="#4f8a3a" stroke-width="4" stroke-linecap="round"/>
		<path d="M32 52 Q22 44 16 48 Q22 56 32 54" fill="#5fa046" stroke="%s" stroke-width="2.5"/>
		<circle cx="32" cy="14" r="9" fill="#e86a8a" stroke="%s" stroke-width="3"/>
		<circle cx="20" cy="24" r="9" fill="#e86a8a" stroke="%s" stroke-width="3"/>
		<circle cx="44" cy="24" r="9" fill="#e86a8a" stroke="%s" stroke-width="3"/>
		<circle cx="25" cy="37" r="9" fill="#e86a8a" stroke="%s" stroke-width="3"/>
		<circle cx="39" cy="37" r="9" fill="#e86a8a" stroke="%s" stroke-width="3"/>
		<circle cx="32" cy="27" r="7" fill="#f5c842" stroke="%s" stroke-width="3"/>""",
	# A banner on a pole, for your warband.
	"banner": """
		<path d="M18 6 V60" stroke="#8a5a2e" stroke-width="4" stroke-linecap="round"/>
		<path d="M20 8 H50 L42 20 L50 32 H20 Z" fill="#b5281e" stroke="%s" stroke-width="3" stroke-linejoin="round"/>""",
	# A spear, for spearmen.
	"spearman": """
		<path d="M14 58 L46 14" stroke="#8a5a2e" stroke-width="5" stroke-linecap="round"/>
		<path d="M44 6 L56 8 L54 20 L44 18 Z" fill="#c9ced6" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M18 46 L26 52" stroke="#b5281e" stroke-width="4" stroke-linecap="round"/>""",
	# A drawn bow, for archers.
	"archer": """
		<path d="M18 6 C46 14 46 50 18 58" fill="none" stroke="#8a5a2e" stroke-width="5" stroke-linecap="round"/>
		<path d="M18 6 L18 58" stroke="#ead8ae" stroke-width="2"/>
		<path d="M10 32 L52 32" stroke="#c9a96e" stroke-width="3"/>
		<path d="M52 32 L44 27 L44 37 Z" fill="#c9ced6" stroke="%s" stroke-width="2"/>""",
	# A sword with a gold guard, for swordsmen.
	"swordsman": """
		<path d="M32 4 L37 12 L37 40 L27 40 L27 12 Z" fill="#d8dce2" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<rect x="18" y="40" width="28" height="6" rx="2" fill="#e0b048" stroke="%s" stroke-width="2.5"/>
		<rect x="29" y="46" width="6" height="10" fill="#7a4a24" stroke="%s" stroke-width="2"/>
		<circle cx="32" cy="59" r="3.5" fill="#e0b048" stroke="%s" stroke-width="2"/>""",
	# A horse's head, for horsemen.
	"horseman": """
		<path d="M20 58 L22 38 C16 34 12 26 18 20 L28 10 L30 4 L36 10 C46 12 54 22 52 34 L50 58 Z" fill="#9a6232" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M30 8 C38 12 42 20 42 30" fill="none" stroke="#3a2412" stroke-width="5"/>
		<circle cx="26" cy="22" r="2.5" fill="#1c140c"/>""",
	# Crossed swords, for battles.
	"battle": """
		<path d="M10 10 L46 46 M54 10 L18 46" stroke="#d8dce2" stroke-width="6" stroke-linecap="round"/>
		<path d="M40 52 L52 40 M12 40 L24 52" stroke="#e0b048" stroke-width="5" stroke-linecap="round"/>
		<path d="M48 48 L56 56 M16 48 L8 56" stroke="#7a4a24" stroke-width="5" stroke-linecap="round"/>""",
	# A round shield, for the enemy.
	"shield": """
		<circle cx="32" cy="32" r="24" fill="#5a3a1e" stroke="#e0b048" stroke-width="4"/>
		<circle cx="32" cy="32" r="7" fill="#c9ced6" stroke="%s" stroke-width="2.5"/>
		<path d="M32 10 V54 M10 32 H54" stroke="#3a2412" stroke-width="2"/>""",
	# A chest of gold, for rewards.
	"rewards": """
		<rect x="8" y="26" width="48" height="30" rx="3" fill="#8a5a2e" stroke="%s" stroke-width="3"/>
		<path d="M8 30 C8 14 56 14 56 30 Z" fill="#a8743e" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<rect x="27" y="30" width="10" height="10" fill="#e0b048" stroke="%s" stroke-width="2"/>
		<circle cx="20" cy="22" r="4" fill="#f2c443"/><circle cx="44" cy="22" r="4" fill="#f2c443"/>""",
	# An open book with a quill, for the academy's research.
	"research": """
		<path d="M32 16 C24 10 14 10 6 13 L6 52 C14 49 24 49 32 55 Z" fill="#ead8ae" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M32 16 C40 10 50 10 58 13 L58 52 C50 49 40 49 32 55 Z" fill="#f4e6c2" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M12 22 C18 20 23 20 27 23 M12 30 C18 28 23 28 27 31 M12 38 C18 36 23 36 27 39" stroke="#8a6a3a" stroke-width="2" fill="none" stroke-linecap="round"/>
		<path d="M54 4 C46 12 41 22 38 34 L41 35 C45 24 50 15 58 8 Z" fill="#b5281e" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M38 34 L36 41" stroke="#2a1a0c" stroke-width="2.5" stroke-linecap="round"/>""",
	# A gift box tied with a crimson ribbon and a wax seal, for the Royal Gift.
	# A folded letter with a red wax seal.
	"mail": """
		<rect x="6" y="14" width="52" height="36" rx="3" fill="#ead9b0" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M6 16 L32 36 L58 16" fill="none" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M8 48 L26 32 M56 48 L38 32" stroke="#b89e6c" stroke-width="2.5"/>
		<circle cx="32" cy="36" r="7" fill="#b3261e" stroke="%s" stroke-width="2.5"/>
		<circle cx="32" cy="36" r="3" fill="#e0574a"/>""",
	"gift": """
		<rect x="8" y="26" width="48" height="30" rx="3" fill="#2f4f8a" stroke="%s" stroke-width="3"/>
		<rect x="5" y="18" width="54" height="11" rx="2" fill="#3c62a8" stroke="%s" stroke-width="3"/>
		<rect x="28" y="18" width="8" height="38" fill="#b5281e" stroke="%s" stroke-width="2"/>
		<path d="M32 18 C24 6 12 8 16 16 C18 19 26 19 32 18 C38 19 46 19 48 16 C52 8 40 6 32 18 Z" fill="#c8362a" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>
		<circle cx="32" cy="40" r="6" fill="#e0b048" stroke="%s" stroke-width="2"/>""",
	# A gold laurel wreath around a star, for seasons and their honours.
	"laurel": """
		<path d="M24 54 C10 46 6 30 12 14 M40 54 C54 46 58 30 52 14" fill="none" stroke="#8a6a2a" stroke-width="3" stroke-linecap="round"/>
		<g fill="#e0b048" stroke="%s" stroke-width="1.5">
			<ellipse cx="10" cy="22" rx="3.5" ry="7" transform="rotate(-20 10 22)"/>
			<ellipse cx="9" cy="34" rx="3.5" ry="7" transform="rotate(-50 9 34)"/>
			<ellipse cx="14" cy="45" rx="3.5" ry="7" transform="rotate(-70 14 45)"/>
			<ellipse cx="54" cy="22" rx="3.5" ry="7" transform="rotate(20 54 22)"/>
			<ellipse cx="55" cy="34" rx="3.5" ry="7" transform="rotate(50 55 34)"/>
			<ellipse cx="50" cy="45" rx="3.5" ry="7" transform="rotate(70 50 45)"/>
		</g>
		<path d="M32 16 L36 27 L48 27 L38 34 L42 46 L32 38 L22 46 L26 34 L16 27 L28 27 Z" fill="#f5c842" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>
		<path d="M24 56 L32 50 L40 56" fill="none" stroke="#b5281e" stroke-width="4" stroke-linecap="round"/>""",
	# Check boxes: an empty bronze-rimmed box, and one with a gold tick.
	"box": """
		<rect x="8" y="8" width="48" height="48" rx="8" fill="#140d06" stroke="#c79a52" stroke-width="5"/>""",
	"box_ticked": """
		<rect x="8" y="8" width="48" height="48" rx="8" fill="#140d06" stroke="#c79a52" stroke-width="5"/>
		<path d="M18 33 L28 43 L47 20" fill="none" stroke="#f5c842" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>""",
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
