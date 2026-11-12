extends SceneTree
## Mounts a staging PCK/EXE in an empty inspector project. No game scene, window,
## audio playback, user settings, or world is instantiated. Every model and LOD
## is deserialized to catch missing transitive texture/skin dependencies.

var errors: Array[String] = []
var inspected_files: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _problem(message: String) -> void:
	errors.append(message)
	push_error("PACKAGED_RUNTIME_FAIL: "+message)

func _walk(directory: String) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	access.include_hidden = true
	for child in access.get_directories():
		_walk(directory.path_join(child))
	for filename in access.get_files():
		inspected_files.append(directory.path_join(filename))

func _development_path(path: String) -> bool:
	return path.begins_with("res://Builds/") or path.begins_with("res://tests/") or path.begins_with("res://tools/") or path.contains("model_studio")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()<2:
		_problem("Usage: -- PACKAGE_PCK_OR_EXE ABSOLUTE_EXPORT_MANIFEST_JSON [RESULT_JSON]")
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not manifest is Dictionary:
		_problem("Cannot read expected runtime export manifest")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(args[0]):
		_problem("Cannot mount package: "+args[0])
		quit(1)
		return
	_walk("res://")
	for path in manifest.resources:
		if not ResourceLoader.exists(path):
			_problem("Missing selected runtime resource: "+path)
	for path in manifest.data_files:
		if not FileAccess.file_exists(path):
			_problem("Missing selected data/attribution: "+path)
	for path in inspected_files:
		if _development_path(path):
			_problem("Development-only content was packed: "+path)
		if not path.ends_with(".import"):
			continue
		var source := path.trim_suffix(".import")
		if (source.begins_with("res://Assets/Heroes/") or source.begins_with("res://Assets/Enemies/")) and not manifest.character_runtime_keep.has(source):
			_problem("Unused character image/asset was packed: "+source)
	var models_loaded := 0
	for path in manifest.models:
		var packed := ResourceLoader.load(path) as PackedScene
		if packed == null:
			_problem("Imported character scene failed to deserialize: "+path)
		else:
			models_loaded += 1
		packed = null
	var lods_loaded := 0
	for path in manifest.lods:
		var mesh := ResourceLoader.load(path) as ArrayMesh
		if mesh == null or mesh.get_surface_count()==0:
			_problem("LOD mesh failed to deserialize: "+path)
		else:
			lods_loaded += 1
		mesh = null
	var route_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/Maps/routes.json"))
	if not route_data is Array or route_data.size()!=18:
		_problem("Packaged route data is not the complete 18-arena campaign")
	var biomes: Variant = load("res://scripts/biome_catalog.gd")
	var biome_keys := {}
	if biomes == null:
		_problem("Biome profile helper is unavailable")
	else:
		for arena in range(18):
			var profile: Dictionary = biomes.for_arena(arena)
			biome_keys[profile.key] = true
		if biome_keys.size()!=6:
			_problem("Six packaged biome profiles were not preserved")
	var bundled: Array[String] = []
	var fallback_decoded := false
	var fallback_original_file := FileAccess.file_exists("res://Assets/Music/Everlasting-Shine.mp3")
	var game_script: Variant = load("res://scripts/game.gd")
	if game_script == null:
		_problem("Packaged game script failed to load")
	else:
		# Outside the SceneTree: _ready and _exit_tree/settings saving never run.
		var game: Node3D = game_script.new()
		game.call("_append_resource_music","res://Assets/Music",bundled)
		var fallback := "res://Assets/Music/Everlasting-Shine.mp3"
		if not bundled.has(fallback):
			_problem("Packaged playlist does not discover its imported fallback MP3")
		var stream: AudioStream = game.call("_load_music_track",fallback)
		fallback_decoded = stream != null and stream.get_length()>1.0
		if not fallback_decoded:
			_problem("Packaged fallback MP3 does not decode without an external Music folder")
		stream = null
		game.free()
	var result := {"package":args[0],"models_loaded":models_loaded,"lods_loaded":lods_loaded,"routes":route_data.size() if route_data is Array else 0,"biomes":biome_keys.keys(),"bundled_playlist":bundled,"bundled_music_decodes":fallback_decoded,"bundled_original_file_exists":fallback_original_file,"errors":errors}
	if args.size()>2:
		var output := FileAccess.open(args[2],FileAccess.WRITE)
		if output!=null:
			output.store_string(JSON.stringify(result,"\t"))
			output.close()
	print("PACKAGED_RUNTIME_"+("OK" if errors.is_empty() else "FAIL")+": "+JSON.stringify(result))
	# Release local resources before final shutdown rather than holding meshes in
	# a currently executing stack while the dummy rendering server is destroyed.
	call_deferred("_finish",0 if errors.is_empty() else 1)

func _finish(exit_code: int) -> void:
	quit(exit_code)
