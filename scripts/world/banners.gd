class_name Banners
extends RefCounted
## Faction banners drawn in code from factions.json: a field pattern in the
## faction's two colours plus a simple charge, on a swallowtail cloth.
##
## Patterns: plain, per_pale, per_bend, chevron, saltire.
## Charges: crown, wolf, sun, tree, ship (anything else draws no charge).

const FLAG_SHADER := preload("res://shaders/flag.gdshader")
const W := 64
const H := 96

static var _textures := {}
static var _materials := {}


static func texture(faction: Dictionary) -> ImageTexture:
	if _textures.has(faction.id):
		return _textures[faction.id]
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var primary: Color = faction.color
	var secondary: Color = faction.secondary_color
	var banner: Dictionary = faction.get("banner", {})
	var pattern: String = banner.get("pattern", "plain")
	var charge: String = banner.get("charge", "")
	var charge_color := secondary if pattern in ["plain", "chevron", "saltire"] else secondary.lerp(Color.WHITE, 0.25)
	var outline := primary.darkened(0.45)
	for y in H:
		for x in W:
			var u := (x + 0.5) / W
			var v := (y + 0.5) / H
			# Swallowtail notch at the bottom.
			if v > 0.82 and absf(u - 0.5) < (v - 0.82) * 2.2:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := primary if not _field(pattern, u, v) else secondary
			var cv := _charge(charge, (u - 0.5) * 2.0, (v - 0.42) * 2.0 * H / W)
			if cv == 2:
				c = charge_color
			elif cv == 1:
				c = outline
			# Darker hem around the edge.
			if u < 0.04 or u > 0.96 or v < 0.03:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[faction.id] = tex
	return tex


static func material(faction: Dictionary) -> ShaderMaterial:
	if not _materials.has(faction.id):
		var m := ShaderMaterial.new()
		m.shader = FLAG_SHADER
		MapStyle.apply_common(m)
		m.set_shader_parameter("banner", texture(faction))
		_materials[faction.id] = m
	return _materials[faction.id]


static func make(faction: Dictionary, pole_height: float, cloth_height: float) -> Node3D:
	## A pole with the banner hanging from its top; the cloth trails along +x.
	var root := Node3D.new()
	root.name = "Banner"
	var kit := MeshKit.new()
	kit.cylinder(Color(0.32, 0.24, 0.16), Transform3D(), 0.22, pole_height, 6)
	kit.dome(Color(0.85, 0.72, 0.3), Transform3D(Basis(), Vector3(0, pole_height, 0)), 0.45)
	var pole := MeshInstance3D.new()
	pole.mesh = kit.commit()
	root.add_child(pole)

	var cloth_width := cloth_height * float(W) / H
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(cloth_width, cloth_height)
	plane.subdivide_width = 8
	plane.subdivide_depth = 4
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	cloth.mesh = plane
	cloth.material_override = material(faction)
	# Turn the cloth so its texture's top edge hangs from the pole top.
	cloth.position = Vector3(cloth_width * 0.5 + 0.2, pole_height - cloth_height * 0.5 - 0.3, 0)
	root.add_child(cloth)
	return root


static func _field(pattern: String, u: float, v: float) -> bool:
	## True where the secondary colour shows.
	match pattern:
		"per_pale":
			return u > 0.5
		"per_bend":
			return v > u * 1.5 - 0.1
		"chevron":
			var y := 0.62 - absf(u - 0.5) * 0.9
			return v > y and v < y + 0.16
		"saltire":
			var d1 := absf((v - 0.42) - (u - 0.5) * 1.3)
			var d2 := absf((v - 0.42) + (u - 0.5) * 1.3)
			return minf(d1, d2) < 0.07
	return false


static func _charge(charge: String, x: float, y: float) -> int:
	## 2 inside the charge, 1 on its outline, 0 outside. x, y roughly -1..1 at the centre.
	var inside := _charge_inside(charge, x, y)
	if inside:
		return 2
	for o in [Vector2(0.06, 0), Vector2(-0.06, 0), Vector2(0, 0.06), Vector2(0, -0.06)]:
		if _charge_inside(charge, x + o.x, y + o.y):
			return 1
	return 0


static func _charge_inside(charge: String, x: float, y: float) -> bool:
	match charge:
		"crown":
			var band := y > 0.05 and y < 0.3 and absf(x) < 0.45
			var spikes := y <= 0.05 and y > -0.35 and absf(x) < 0.45 and fposmod(x + 0.45, 0.3) < 0.15 - (0.05 - y) * 0.25
			return band or spikes
		"wolf":
			# A wolf's head: a downward wedge with two ears.
			var head := y > -0.25 and y < 0.45 and absf(x) < 0.4 * (0.45 - y) / 0.7 + 0.05
			var ears := y > -0.5 and y <= -0.25 and absf(absf(x) - 0.22) < (y + 0.5) * 0.35
			return head or ears
		"sun":
			var r := Vector2(x, y).length()
			var rays := r < 0.55 and absf(sin(atan2(y, x) * 6.0)) > 0.55
			return r < 0.3 or rays
		"tree":
			var crown := y < 0.15 and absf(x) < (y + 0.5) * 0.6 and y > -0.5
			var trunk := y >= 0.15 and y < 0.4 and absf(x) < 0.07
			return crown or trunk
		"ship":
			var hull := y > 0.15 and y < 0.35 and absf(x) < 0.5 - (y - 0.15) * 1.2
			var sail := y > -0.45 and y <= 0.1 and x > -0.3 and x < 0.3 - (y + 0.45) * 0.2
			var mast := absf(x) < 0.04 and y > -0.5 and y <= 0.15
			return hull or sail or mast
	return false
