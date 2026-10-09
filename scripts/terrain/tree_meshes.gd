class_name TreeMeshes
extends RefCounted
## Placeholder low-poly trees built from primitives, flat shaded.
## Each mesh has two surfaces: 0 = trunk, 1 = foliage, so they can take
## different materials. Replace with CC0 models later by swapping what these
## functions return.

enum Part { TRUNK, FOLIAGE }


static func conifer() -> ArrayMesh:
	var trunk := _begin()
	_add(trunk, _cylinder(0.35, 0.45, 2.2, 5), Transform3D(Basis(), Vector3(0, 1.1, 0)))
	var foliage := _begin()
	_add(foliage, _cone(2.6, 4.6, 7), Transform3D(Basis(), Vector3(0, 4.0, 0)))
	_add(foliage, _cone(2.0, 3.8, 7), Transform3D(Basis().rotated(Vector3.UP, 0.4), Vector3(0, 6.1, 0)))
	_add(foliage, _cone(1.3, 3.0, 6), Transform3D(Basis().rotated(Vector3.UP, 0.9), Vector3(0, 8.0, 0)))
	return _finish(trunk, foliage)


static func broadleaf() -> ArrayMesh:
	var trunk := _begin()
	_add(trunk, _cylinder(0.35, 0.55, 3.0, 5), Transform3D(Basis(), Vector3(0, 1.5, 0)))
	var foliage := _begin()
	_add(foliage, _blob(2.9, 2.4), Transform3D(Basis(), Vector3(0, 5.0, 0)))
	_add(foliage, _blob(1.9, 1.6), Transform3D(Basis().rotated(Vector3.UP, 0.7), Vector3(1.2, 6.4, 0.6)))
	return _finish(trunk, foliage)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shading
	return st


static func _finish(trunk: SurfaceTool, foliage: SurfaceTool) -> ArrayMesh:
	trunk.generate_normals()
	foliage.generate_normals()
	var mesh := trunk.commit()
	return foliage.commit(mesh)


static func _add(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D) -> void:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for idx in indices:
		st.add_vertex(xform * verts[idx])


static func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	m.cap_top = false
	m.cap_bottom = false
	return m


static func _cone(radius: float, height: float, sides: int) -> CylinderMesh:
	var m := _cylinder(0.0, radius, height, sides)
	m.cap_bottom = true
	return m


static func _blob(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height * 2.0
	m.radial_segments = 7
	m.rings = 4
	return m
