extends SceneTree
## Generates world/heightmap.exr, world/biome_mask.png and world/rivers.json
## from the seed in data/terrain_config.json.
##
## Run from the project folder:
##   godot --headless --script res://scripts/tools/generate_world.gd
##
## This overwrites any hand edits in those three files, so only run it when you
## want a fresh continent (for example after changing the seed).

const CONFIG_PATH := "res://data/terrain_config.json"
const RIVER_COUNT := 18
const BIOME_MASK_SIZE := 512


func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var files: Dictionary = config.files
	var started := Time.get_ticks_msec()
	print("Generating world with seed %d" % int(config.seed))

	var gen := WorldGenerator.new(config)
	gen.generate_heights()
	print("Tracing rivers")
	gen.generate_rivers(RIVER_COUNT)
	print("  %d rivers" % gen.rivers.size())

	_check(gen.height_image().save_exr(files.heightmap, true), files.heightmap)
	_check(gen.preview_image().save_png("res://world/heightmap_preview.png"), "heightmap_preview.png")
	print("Painting biome mask")
	_check(gen.biome_image(BIOME_MASK_SIZE).save_png(files.biome_mask), files.biome_mask)

	var f := FileAccess.open(files.rivers, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rivers": gen.rivers.map(func(r): return {"points": r})}, "\t"))
	f.close()
	print("Done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()


func _check(err: Error, what: String) -> void:
	if err != OK:
		push_error("Could not write %s (error %d)" % [what, err])
	else:
		print("  wrote %s" % what)
