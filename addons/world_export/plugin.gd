@tool
extends EditorPlugin
## Exported games can't read world/heightmap.exr: export keeps only imported
## copies, and the web build's EXR decoder needs threads it doesn't have. So
## every export gets the heights as plain floats next to it (TerrainData reads
## them back), made fresh from the .exr each time.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = WorldExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)


class WorldExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "WorldExport"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_config.json"))
		var path := String(config.files.heightmap)
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			push_error("World export: can't read %s." % path)
			return
		add_file(TerrainData.packed_path(path), TerrainData.pack_heights(image), false)
