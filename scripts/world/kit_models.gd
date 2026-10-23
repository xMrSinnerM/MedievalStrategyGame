class_name KitModels
extends RefCounted
## Builds one mesh from pieces of the KayKit Medieval Hexagon pack (CC0,
## assets/kaykit). Pieces share one atlas texture, so a whole settlement or
## building merges into a single surface with one material per team colour.

const ROOT := "res://assets/kaykit/"
const SHADER := preload("res://shaders/kit.gdshader")
const ATLAS := preload("res://assets/kaykit/buildings/hexagons_medieval.png")
const FOLDERS := ["buildings/", "nature/", "props/"]

static var _pieces := {}      ## name -> Array of [Mesh, Transform3D]
static var _materials := {}   ## "team:fog" -> ShaderMaterial

var _tool := SurfaceTool.new()
var _empty := true


func _init() -> void:
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)


func add(piece: String, xform: Transform3D) -> void:
	## Adds a piece by file name without extension; "_blue" buildings carry the team colour.
	for part in _load(piece):
		var mesh: Mesh = part[0]
		for s in mesh.get_surface_count():
			_tool.append_from(mesh, s, xform * part[1])
			_empty = false


func commit(team: Color, map_fog := false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _empty:
		return mesh
	_tool.commit(mesh)
	mesh.surface_set_material(0, material(team, map_fog))
	return mesh


static func material(team: Color, map_fog := false) -> ShaderMaterial:
	var key := "%s:%s" % [team.to_html(false), map_fog]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("atlas", ATLAS)
		m.set_shader_parameter("team", team)
		m.set_shader_parameter("map_fog_on", map_fog)
		if map_fog:
			MapStyle.apply_common(m)
		_materials[key] = m
	return _materials[key]


static func _load(piece: String) -> Array:
	if _pieces.has(piece):
		return _pieces[piece]
	var parts := []
	for folder in FOLDERS:
		var path: String = ROOT + folder + piece + ".gltf"
		if not ResourceLoader.exists(path):
			continue
		var scene: Node3D = load(path).instantiate()
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var t := mi.transform
			var p := mi.get_parent()
			while p != scene and p is Node3D:
				t = (p as Node3D).transform * t
				p = p.get_parent()
			parts.append([mi.mesh, t])
		scene.free()
		break
	if parts.is_empty():
		push_warning("KitModels: no piece named %s" % piece)
	_pieces[piece] = parts
	return parts
