extends SceneTree
## Validates the actual persistent export preset against the current dynamic
## runtime roots; it does not modify the preset or load/instantiate the game.
const Manifest := preload("res://tools/update_export_manifest.gd")
const Biomes := preload("res://scripts/biome_catalog.gd")

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("EXPORT_MANIFEST_FAIL: "+message)
	quit(1)

func _run() -> void:
	var manifest := Manifest.collect()
	if not manifest.errors.is_empty():
		_fail(str(manifest.errors))
		return
	var preset := ConfigFile.new()
	if preset.load("res://export_presets.cfg") != OK or preset.get_value("preset.0","export_filter","") != "resources":
		_fail("Windows target does not use explicit runtime resources")
		return
	var selected := PackedStringArray(preset.get_value("preset.0","export_files",PackedStringArray()))
	if selected.size() != manifest.resources.size():
		_fail("preset selection was not refreshed after runtime assets changed")
		return
	for path in manifest.resources:
		if not selected.has(path):
			_fail("runtime resource absent from persistent preset: "+path)
			return
	var data_filter := str(preset.get_value("preset.0","include_filter",""))
	for path in manifest.data_files:
		if not data_filter.split(",").has(str(path).trim_prefix("res://")):
			_fail("raw runtime data/attribution absent from preset: "+path)
			return
	if manifest.models.size() != 37 or manifest.lods.size() != 37:
		_fail("character or dynamically loaded LOD set is incomplete")
		return
	for family in ["aerial_grass_rock","brown_mud_leaves_01","mossy_rock"]:
		for suffix in ["Diffuse","nor_gl","Rough"]:
			var scan := "res://Assets/Environment/%s_%s.jpg" % [family,suffix]
			if not selected.has(scan):
				_fail("biome ground/rock PBR map omitted: "+scan)
				return
	var biome_keys := {}
	for arena in range(18):
		biome_keys[Biomes.for_arena(arena).key] = true
	if biome_keys.size()!=6:
		_fail("six campaign biome profiles are unavailable")
		return
	var selected_sfx := 0
	for path in selected:
		if str(path).begins_with("res://Assets/Sfx/") and str(path).ends_with(".mp3"):
			selected_sfx += 1
		if Manifest._forbidden(path):
			_fail("QA/studio content leaked into runtime roots")
			return
	if selected_sfx != 11:
		_fail("attack/death SFX set no longer contains the current eleven cues")
		return
	print("EXPORT_MANIFEST_SMOKE_OK: explicit preset, 37 GLB + 37 LOD, six biome profiles/nine PBR maps, eleven SFX, bundled music, raw routes/attributions, runtime helpers; no QA roots")
	quit(0)
