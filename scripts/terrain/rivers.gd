extends Node3D
## River ribbons built from world/rivers.json. Each point carries its own water
## height and width, so rivers widen and step down towards the sea.

const RIVER_SHADER := preload("res://shaders/river.gdshader")


func build() -> void:
	var terrain: TerrainData = GameData.terrain
	var material := ShaderMaterial.new()
	material.shader = RIVER_SHADER
	MapStyle.apply_common(material)
	material.set_shader_parameter("wave_noise", MapStyle.noise_texture(23, 0.015))

	for i in terrain.rivers.size():
		var points: Array = terrain.rivers[i].get("points", [])
		if points.size() < 2:
			continue
		var river := MeshInstance3D.new()
		river.name = "River_%d" % i
		river.mesh = _ribbon(points)
		river.material_override = material
		river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(river)


func _ribbon(points: Array) -> ArrayMesh:
	# Smooth the polyline a little so the grid steps don't show.
	var centre: Array[Vector3] = []
	var widths: Array[float] = []
	for k in points.size():
		var a: Array = points[maxi(k - 1, 0)]
		var b: Array = points[k]
		var c: Array = points[mini(k + 1, points.size() - 1)]
		var x: float = (a[0] + 2.0 * b[0] + c[0]) * 0.25
		var z: float = (a[1] + 2.0 * b[1] + c[1]) * 0.25
		centre.append(Vector3(x, b[2], z))
		widths.append(b[3])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for k in centre.size():
		var prev := centre[maxi(k - 1, 0)]
		var next := centre[mini(k + 1, centre.size() - 1)]
		var dir := Vector3(next.x - prev.x, 0.0, next.z - prev.z).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x) * widths[k] * 0.5
		if k > 0:
			along += centre[k].distance_to(centre[k - 1])
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, along))
		st.add_vertex(centre[k] - side)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, along))
		st.add_vertex(centre[k] + side)
	for k in centre.size() - 1:
		var i := k * 2
		st.add_index(i)
		st.add_index(i + 2)
		st.add_index(i + 1)
		st.add_index(i + 1)
		st.add_index(i + 2)
		st.add_index(i + 3)
	return st.commit()
