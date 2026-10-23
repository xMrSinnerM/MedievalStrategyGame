class_name Soldiers
extends RefCounted
## Marching soldiers for the world map, from the KayKit Adventurers pack (CC0,
## assets/kaykit/characters, baked by tools/bake_characters.gd). A troop is a
## few figures merged into one mesh for each of two walk frames; swapping the
## frames makes it march.

const ROOT := "res://assets/kaykit/characters/"
const SHADER := preload("res://shaders/unit.gdshader")
## Character -> atlas it is painted with.
const KINDS := {
	"knight": "knight_texture",
	"crossbowman": "rogue_texture",
	"barbarian": "barbarian_texture",
	"bandit": "rogue_texture",
}
## Atlas -> swatches (row * 8 + column) that take the owner's colour.
const TEAM_CELLS := {
	"knight_texture": Vector4i(8, 18, -1, -1),
	"rogue_texture": Vector4i(8, 9, 17, -1),
	"barbarian_texture": Vector4i(8, 9, 18, -1),
}
## Turns the characters, modelled facing +z, to face -z like the rest of the map.
const FACE := Basis(Vector3.UP, PI)

static var _meshes := {}      ## "kind_frame" -> Mesh
static var _materials := {}   ## "atlas:team" -> ShaderMaterial


static func figure(kind: String, pos: Vector3, size := 1.0) -> Array:
	## One entry for troop(): a character standing at pos, scaled by size.
	return [kind, Transform3D(FACE.scaled(Vector3.ONE * size), pos)]


static func troop(figures: Array, team: Color) -> Array[ArrayMesh]:
	## figures: entries from figure(). Returns the two walk frames; neighbours
	## step out of phase so the column doesn't march in lockstep.
	var frames: Array[ArrayMesh] = []
	for frame in 2:
		var tools := {}   # atlas -> SurfaceTool
		for k in figures.size():
			var kind: String = figures[k][0]
			var atlas: String = KINDS[kind]
			if not tools.has(atlas):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[atlas] = st
			var mesh := _mesh(kind, (frame + k) % 2)
			(tools[atlas] as SurfaceTool).append_from(mesh, 0, figures[k][1])
		var out := ArrayMesh.new()
		for atlas: String in tools:
			(tools[atlas] as SurfaceTool).commit(out)
			out.surface_set_material(out.get_surface_count() - 1, _material(atlas, team))
		frames.append(out)
	return frames


static func _mesh(kind: String, frame: int) -> Mesh:
	var key := "%s_%d" % [kind, frame]
	if not _meshes.has(key):
		_meshes[key] = load(ROOT + key + ".res")
	return _meshes[key]


static func _material(atlas: String, team: Color) -> ShaderMaterial:
	var key := "%s:%s" % [atlas, team.to_html(false)]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("atlas", load(ROOT + atlas + ".png"))
		m.set_shader_parameter("team", team)
		m.set_shader_parameter("team_cells", TEAM_CELLS[atlas])
		MapStyle.apply_common(m)
		_materials[key] = m
	return _materials[key]
