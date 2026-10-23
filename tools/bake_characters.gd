extends SceneTree
## Bakes the marching soldiers for the world map from the KayKit Adventurers
## character pack (CC0, github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0).
## Each character is posed in two frames of its walk and saved as small static
## meshes, so the game doesn't ship the 3.6 MB rigged and animated originals.
## Run:
##   godot --path . --script res://tools/bake_characters.gd -- src=<pack>/addons/kaykit_character_pack_adventures
## (not --headless: skinning needs a renderer, so run it with a window or xvfb-run).

const OUT := "res://assets/kaykit/characters/"
const WALK := "Walking_A"
## Output name -> [source file, nodes to keep].
const CHARACTERS := {
	"knight": ["Knight", ["Knight_ArmLeft", "Knight_ArmRight", "Knight_Body", "Knight_Head", "Knight_LegLeft", "Knight_LegRight", "Knight_Helmet", "Knight_Cape", "1H_Sword", "Badge_Shield"]],
	"crossbowman": ["Rogue", ["Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_Body", "Rogue_Head", "Rogue_LegLeft", "Rogue_LegRight", "Rogue_Cape", "1H_Crossbow"]],
	"barbarian": ["Barbarian", ["Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_Body", "Barbarian_Head", "Barbarian_LegLeft", "Barbarian_LegRight", "Barbarian_Hat", "Barbarian_Cape", "1H_Axe", "Barbarian_Round_Shield"]],
	"bandit": ["Rogue_Hooded", ["Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_Body", "Rogue_Head_Hooded", "Rogue_LegLeft", "Rogue_LegRight", "Rogue_Cape", "Knife", "Knife_Offhand"]],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var src := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("src="):
			src = arg.substr(4)
	if src.is_empty():
		push_error("pass src=<path to addons/kaykit_character_pack_adventures>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for out_name: String in CHARACTERS:
		var spec: Array = CHARACTERS[out_name]
		await _bake(src, out_name, spec[0], spec[1])
	var tex_dir := src + "/Textures/"
	for tex in ["knight", "rogue", "barbarian"]:
		DirAccess.copy_absolute(tex_dir + tex + "_texture.png", ProjectSettings.globalize_path(OUT + tex + "_texture.png"))
	DirAccess.copy_absolute(src + "/LICENSE.txt", ProjectSettings.globalize_path(OUT + "LICENSE.txt"))
	quit()


func _bake(src: String, out_name: String, file: String, keep: Array) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src + "/Characters/gltf/" + file + ".glb", state) != OK:
		push_error("could not read " + file)
		return
	var scene: Node3D = doc.generate_scene(state)
	root.add_child(scene)
	await process_frame
	var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var length := player.get_animation(WALK).length
	for frame in 2:
		player.play(WALK)
		player.seek(length * (0.12 + 0.5 * frame), true)
		skeleton.force_update_all_bone_transforms()
		await process_frame
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if not keep.has(String(mi.name)):
				continue
			var mesh: Mesh = mi.mesh
			var xform := Transform3D()
			if mi.skin != null:
				mesh = mi.bake_mesh_from_current_skeleton_pose()
				xform = _relative(mi, scene)
			else:
				var attach := mi.get_parent() as BoneAttachment3D
				if attach != null:
					xform = _relative(skeleton, scene) * skeleton.get_bone_global_pose(attach.bone_idx) * mi.transform
				else:
					xform = _relative(mi, scene)
			for s in mesh.get_surface_count():
				st.append_from(mesh, s, xform)
		var out := st.commit()
		var path := OUT + "%s_%d.res" % [out_name, frame]
		ResourceSaver.save(out, path, ResourceSaver.FLAG_COMPRESS)
		print("baked ", path, " ", out.get_faces().size() / 3, " triangles, ", out.get_aabb())
	scene.queue_free()


func _relative(node: Node3D, scene: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != scene and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
