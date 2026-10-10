class_name MeshKit
extends RefCounted
## Builds flat-shaded placeholder meshes from simple parts. Parts are grouped
## by colour, one surface per colour, so a whole settlement is a single mesh.

const PROP_SHADER := preload("res://shaders/prop.gdshader")

static var _materials := {}
static var _plain_materials := {}

var _surfaces := {}   ## Color -> SurfaceTool


static func material(color: Color) -> ShaderMaterial:
	## One shared material per colour.
	var key := color.to_html(false)
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = PROP_SHADER
		MapStyle.apply_common(m)
		m.set_shader_parameter("albedo", color)
		_materials[key] = m
	return _materials[key]


static func plain_material(color: Color) -> StandardMaterial3D:
	## Ordinary lit material without the world map's fog, for scenes off the map
	## such as the castle screen.
	var key := color.to_html(false)
	if not _plain_materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		m.metallic_specular = 0.15
		_plain_materials[key] = m
	return _plain_materials[key]


func box(color: Color, xform: Transform3D, size: Vector3) -> void:
	## A box resting on its base: xform.origin is the centre of the bottom face.
	var m := BoxMesh.new()
	m.size = size
	_add(color, m, xform * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)))


func cylinder(color: Color, xform: Transform3D, radius: float, height: float, sides := 8, top_radius := -1.0) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	_add(color, m, xform * Transform3D(Basis(), Vector3(0, height * 0.5, 0)))


func cone(color: Color, xform: Transform3D, radius: float, height: float, sides := 8) -> void:
	cylinder(color, xform, radius, height, sides, 0.0)


func dome(color: Color, xform: Transform3D, radius: float) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 5
	m.is_hemisphere = true
	_add(color, m, xform)


func gable_roof(color: Color, xform: Transform3D, width: float, depth: float, height: float) -> void:
	## A pitched roof whose ridge runs along local x; xform.origin is the eave centre.
	var st := _tool(color)
	var hw := width * 0.5 + 0.3
	var hd := depth * 0.5 + 0.3
	var a := Vector3(-hw, 0, -hd)
	var b := Vector3(hw, 0, -hd)
	var c := Vector3(hw, 0, hd)
	var d := Vector3(-hw, 0, hd)
	var r1 := Vector3(-hw, height, 0)
	var r2 := Vector3(hw, height, 0)
	var centre := Vector3(0, height * 0.3, 0)
	for tri in [[a, r1, r2], [a, r2, b], [d, c, r2], [d, r2, r1], [a, d, r1], [b, r2, c]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		# Godot treats clockwise triangles as front faces: wind every face outwards.
		var outward := (p0 + p1 + p2) / 3.0 - centre
		if (p2 - p0).cross(p1 - p0).dot(outward) < 0.0:
			var swap := p1
			p1 = p2
			p2 = swap
		for v in [p0, p1, p2]:
			st.add_vertex(xform * v)


func commit(plain := false) -> ArrayMesh:
	## plain = true uses plain_material() instead of the fogged map material.
	var mesh := ArrayMesh.new()
	for color: Color in _surfaces:
		var st: SurfaceTool = _surfaces[color]
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, plain_material(color) if plain else material(color))
	return mesh


func _tool(color: Color) -> SurfaceTool:
	if not _surfaces.has(color):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		_surfaces[color] = st
	return _surfaces[color]


func _add(color: Color, mesh: PrimitiveMesh, xform: Transform3D) -> void:
	var st := _tool(color)
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for idx in indices:
		st.add_vertex(xform * verts[idx])
