extends SceneTree
## Read-only package inspector. Run with an empty --path directory, never the
## game scene. Mounting the embedded PCK does not instantiate any game resource.

var package_files: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _walk(directory: String) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	access.include_hidden = true
	access.list_dir_begin()
	var entry := access.get_next()
	while not entry.is_empty():
		if entry not in [".",".."]:
			var path := directory.path_join(entry)
			if access.current_is_dir():
				_walk(path)
			else:
				# These two files belong to the deliberately empty inspector
				# project, not to the mounted game package.
				if path in ["res://project.godot","res://.gdignore"]:
					entry = access.get_next()
					continue
				var file := FileAccess.open(path,FileAccess.READ)
				if file != null:
					package_files.append({"path":path,"bytes":file.get_length()})
		entry = access.get_next()
	access.list_dir_end()

func _dependency_graph(seeds: Array[String]) -> Dictionary:
	var queue := seeds.duplicate()
	var visited := {}
	var imported := {}
	while not queue.is_empty():
		var path: String = queue.pop_back()
		if visited.has(path):
			continue
		visited[path] = true
		if not ResourceLoader.exists(path):
			continue
		var import_path := path+".import"
		if FileAccess.file_exists(import_path):
			var config := ConfigFile.new()
			if config.load(import_path) == OK:
				for key in config.get_section_keys("remap"):
					if key == "path" or key.begins_with("path."):
						var target: String = str(config.get_value("remap",key))
						imported[target] = path
		for raw in ResourceLoader.get_dependencies(path):
			var parts: PackedStringArray = raw.split("::")
			var dependency: String = parts[-1]
			if dependency.begins_with("res://"):
				queue.append(dependency)
	return {"resources":visited.keys(),"imported_files":imported}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- PACKAGE_EXE REPORT_JSON")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(args[0]):
		push_error("Cannot mount embedded PCK: "+args[0])
		quit(1)
		return
	_walk("res://")
	package_files.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.bytes > b.bytes)
	var seeds: Array[String] = ["res://scenes/game.tscn","res://Assets/Icons/black-bulls-emblem.png"]
	for hero in ["asta","yuno","magna","vanessa","noelle"]:
		for rank in range(1,6):
			seeds.append("res://Assets/Heroes/%s_L%d.glb" % [hero,rank])
	for enemy in ["goblin","orc","uruk","warg","troll","nazgul"]:
		seeds.append("res://Assets/Enemies/%s.glb" % enemy)
	var count := 0
	var total := 0
	var groups := {}
	var imported_sources := {}
	for file in package_files:
		var path: String = file.path
		if not path.ends_with(".import"):
			continue
		var config := ConfigFile.new()
		if config.load(path) == OK and config.has_section("remap"):
			for key in config.get_section_keys("remap"):
				if key == "path" or key.begins_with("path."):
					imported_sources[str(config.get_value("remap",key))] = path.trim_suffix(".import")
	var live_models := _dependency_graph(seeds)
	var live_model_paths: Array = live_models.resources
	var buckets := {}
	var hashes := {}
	for file in package_files:
		count += 1
		total += int(file.bytes)
		var relative: String = str(file.path).trim_prefix("res://")
		var prefix: String = relative.get_slice("/",0)
		if not groups.has(prefix):
			groups[prefix] = {"files":0,"bytes":0}
		groups[prefix].files += 1
		groups[prefix].bytes += int(file.bytes)
		var source: String = imported_sources.get(str(file.path),str(file.path))
		file.source = source
		var bucket := "other"
		if source.begins_with("res://Builds/"):
			bucket = "development_builds"
		elif source.begins_with("res://Assets/Heroes/") or source.begins_with("res://Assets/Enemies/"):
			if source.ends_with(".png"):
				bucket = "active_character_texture" if live_model_paths.has(source) else "unused_character_texture"
			elif source.ends_with(".glb"):
				bucket = "active_character_geometry" if live_model_paths.has(source) else "unused_character_geometry"
			elif source.ends_with(".import"):
				bucket = "character_import_metadata"
		elif source.begins_with("res://Assets/"):
			bucket = source.get_slice("/",3)
		elif source.begins_with("res://tests/") or source.begins_with("res://tools/") or source.contains("model_studio"):
			bucket = "development_code"
		file.bucket = bucket
		if not buckets.has(bucket):
			buckets[bucket] = {"files":0,"bytes":0}
		buckets[bucket].files += 1
		buckets[bucket].bytes += int(file.bytes)
		if str(file.path).ends_with(".ctex"):
			var input := FileAccess.open(file.path,FileAccess.READ)
			var context := HashingContext.new()
			context.start(HashingContext.HASH_SHA256)
			while input.get_position() < input.get_length():
				context.update(input.get_buffer(1024*1024))
			var digest := context.finish().hex_encode()
			file.sha256 = digest
			if not hashes.has(digest):
				hashes[digest] = []
			hashes[digest].append({"path":file.path,"source":source,"bytes":file.bytes,"bucket":bucket})
	var duplicate_textures: Array = []
	for digest in hashes:
		if hashes[digest].size()>1:
			duplicate_textures.append({"sha256":digest,"copies":hashes[digest]})
	var music_path := "res://Assets/Music/Everlasting-Shine.mp3"
	var runtime_checks := {"main_scene_exists":ResourceLoader.exists("res://scenes/game.tscn"),"route_data_exists":FileAccess.file_exists("res://Assets/Maps/routes.json"),"bundled_music_directory_files":DirAccess.get_files_at("res://Assets/Music"),"bundled_music_resource_exists":ResourceLoader.exists(music_path),"bundled_music_file_exists":FileAccess.file_exists(music_path)}
	var report := {"package":args[0],"files":count,"file_bytes":total,"top_level":groups,"buckets":buckets,"entries":package_files,"model_and_main_scene_dependencies":live_models,"duplicate_packed_textures":duplicate_textures,"runtime_availability":runtime_checks}
	var out := FileAccess.open(args[1],FileAccess.WRITE)
	if out == null:
		push_error("Cannot write audit report: "+args[1])
		quit(1)
		return
	out.store_string(JSON.stringify(report,"\t"))
	out.close()
	print("PACKAGE_AUDIT_OK: %d packed files; %d bytes; buckets=%s" % [count,total,JSON.stringify(buckets)])
	quit(0)
