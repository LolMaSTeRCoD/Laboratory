extends SceneTree
## Updates only the resource selection of the Windows preset. Dynamic runtime
## loads are explicit roots; Godot follows their imported/transitive dependencies.
## Run after imports and CharacterLOD generation, immediately before exporting.

const PRESET := "res://export_presets.cfg"
const REPORT := "res://Builds/export-runtime-manifest.json"
const HEROES := ["asta","yuno","magna","vanessa","noelle","charmy"]
const ENEMIES := ["goblin","orc","uruk","warg","troll","nazgul","boss_troll"]
const RESOURCE_EXTENSIONS := ["png","jpg","jpeg","webp","svg","tga","hdr","exr","ktx","ktx2","mp3","ogg","wav","tres","res","gdshader","gdshaderinc","tscn","scn","gd"]
const DATA_EXTENSIONS := ["json","txt","md"]
const EXCLUSIONS := "Builds/*,Builds/**/*,tests/*,tests/**/*,tools/*,tools/**/*,scenes/model_studio.tscn,scripts/model_studio.gd,Assets/Heroes/*_preview.png,Assets/Heroes/*_front.png,Assets/Heroes/*_side.png,Assets/Heroes/*_back.png,Assets/Enemies/*_preview.png,Assets/Heroes/Textures/*,Assets/Heroes/TexturesV2/*,Assets/Heroes/Atlases/*,Assets/Enemies/Textures/*,Assets/Enemies/TexturesV3/*,Assets/Enemies/Atlases/*"

func _initialize() -> void:
	call_deferred("_run")

static func _add_unique(paths: Array[String], path: String) -> void:
	if not paths.has(path):
		paths.append(path)

static func _forbidden(path: String) -> bool:
	return path.begins_with("res://Builds/") or path.begins_with("res://tests/") or path.begins_with("res://tools/") or path.contains("model_studio") or path.get_basename().ends_with("_preview") or path.get_basename().ends_with("_front") or path.get_basename().ends_with("_side") or path.get_basename().ends_with("_back")

static func _collect_directory(directory: String, resources: Array[String], data: Array[String], include_data: bool) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	for subdir in access.get_directories():
		_collect_directory(directory.path_join(subdir),resources,data,include_data)
	for filename in access.get_files():
		var path := directory.path_join(filename)
		if _forbidden(path):
			continue
		var extension := filename.get_extension().to_lower()
		if extension in RESOURCE_EXTENSIONS:
			_add_unique(resources,path)
		elif include_data and extension in DATA_EXTENSIONS:
			_add_unique(data,path)

static func _dependency_closure(roots: Array[String]) -> Array[String]:
	var queue := roots.duplicate()
	var visited: Array[String] = []
	while not queue.is_empty():
		var path: String = queue.pop_back()
		if visited.has(path):
			continue
		visited.append(path)
		if not ResourceLoader.exists(path):
			continue
		for raw in ResourceLoader.get_dependencies(path):
			var dependency: String = str(raw).split("::")[-1]
			if dependency.begins_with("res://"):
				queue.append(dependency)
	visited.sort()
	return visited

static func collect() -> Dictionary:
	var resources: Array[String] = ["res://scenes/game.tscn"]
	var data: Array[String] = ["res://Assets/Heroes/ASSET_CREDITS.md","res://Assets/Enemies/ASSET_CREDITS.md"]
	var models: Array[String] = []
	var lods: Array[String] = []
	var errors: Array[String] = []
	for hero in HEROES:
		for rank in range(1,6):
			models.append("res://Assets/Heroes/%s_L%d.glb" % [hero,rank])
	for enemy in ENEMIES:
		models.append("res://Assets/Enemies/%s.glb" % enemy)
	for model in models:
		resources.append(model)
		var lod := "res://Assets/CharacterLOD/"+model.trim_prefix("res://Assets/").get_basename()+".res"
		lods.append(lod)
		resources.append(lod)
	# These directories are runtime libraries. Character texture/workshop output
	# directories are intentionally absent: imported GLBs pull only the maps used.
	for directory in ["res://Assets/Environment","res://Assets/Sfx","res://Assets/Music","res://Assets/Icons","res://Assets/Maps","res://Assets/CharacterLOD","res://Assets/Shaders","res://shaders"]:
		_collect_directory(directory,resources,data,directory!="res://Assets/CharacterLOD")
	# Explicitly retain every runtime helper, including the opt-in benchmark and
	# LOD helper. Editor-only model_studio is filtered out, not removed on disk.
	_collect_directory("res://scripts",resources,data,false)
	for path in resources:
		if not ResourceLoader.exists(path):
			errors.append("Missing/unimported runtime resource: "+path)
		if _forbidden(path):
			errors.append("Development content selected as runtime: "+path)
	for path in data:
		if not FileAccess.file_exists(path):
			errors.append("Missing runtime data/attribution: "+path)
	if not data.has("res://Assets/Maps/routes.json"):
		errors.append("Campaign route JSON was not selected")
	if not resources.has("res://Assets/Music/Everlasting-Shine.mp3"):
		errors.append("Bundled fallback music was not selected")
	if not resources.has("res://scripts/render_benchmark.gd"):
		errors.append("Opt-in render benchmark helper was not selected")
	if not resources.has("res://scripts/character_lod.gd"):
		errors.append("Character LOD runtime helper was not selected")
	resources.sort()
	data.sort()
	var closure := _dependency_closure(resources)
	var character_keep: Array[String] = []
	for path in closure:
		if _forbidden(path):
			errors.append("Runtime dependency reaches development content: "+path)
		if path.begins_with("res://Assets/Heroes/") or path.begins_with("res://Assets/Enemies/") or path.begins_with("res://Assets/CharacterLOD/"):
			character_keep.append(path)
	return {"resources":resources,"data_files":data,"models":models,"lods":lods,"transitive_dependencies":closure,"character_runtime_keep":character_keep,"errors":errors}

func _run() -> void:
	var manifest := collect()
	if not manifest.errors.is_empty():
		for message in manifest.errors:
			push_error(message)
		quit(1)
		return
	var config := ConfigFile.new()
	if config.load(PRESET) != OK:
		push_error("Cannot read Windows export preset")
		quit(1)
		return
	if str(config.get_value("preset.0","name","")) != "Windows Desktop":
		push_error("Preset 0 is not the permanent Windows Desktop target")
		quit(1)
		return
	config.set_value("preset.0","export_filter","resources")
	config.set_value("preset.0","export_files",PackedStringArray(manifest.resources))
	var raw_filters: Array[String] = []
	for path in manifest.data_files:
		raw_filters.append(str(path).trim_prefix("res://"))
	config.set_value("preset.0","include_filter",",".join(raw_filters))
	config.set_value("preset.0","exclude_filter",EXCLUSIONS)
	if config.save(PRESET) != OK:
		push_error("Cannot save explicit Windows runtime resource manifest")
		quit(1)
		return
	manifest["export_filter"] = "resources"
	manifest["exclude_filter"] = EXCLUSIONS
	manifest["source_file_sha256"] = FileAccess.get_sha256("res://scripts/game.gd")
	var report := FileAccess.open(REPORT,FileAccess.WRITE)
	if report == null:
		push_error("Cannot write runtime export manifest report")
		quit(1)
		return
	report.store_string(JSON.stringify(manifest,"\t"))
	report.close()
	# Keep the separate cleanup proposal conservative as new runtime LODs arrive.
	# This changes its keep-list only; it never removes a source or cache file.
	var cleanup_path := "res://Builds/asset-cleanup-candidates.json"
	if FileAccess.file_exists(cleanup_path):
		var cleanup: Variant = JSON.parse_string(FileAccess.get_file_as_string(cleanup_path))
		if cleanup is Dictionary:
			var keep: Array = cleanup.get("active_character_resources",[])
			for path in manifest.character_runtime_keep:
				if not keep.has(path):
					keep.append(path)
			var lod_data := "res://Assets/CharacterLOD/manifest.json"
			keep.erase(lod_data)
			keep.sort()
			cleanup["active_character_resources"] = keep
			cleanup["runtime_export_manifest"] = REPORT
			cleanup["runtime_lod_count"] = manifest.lods.size()
			cleanup["development_required_resources"] = [lod_data]
			var cleanup_file := FileAccess.open(cleanup_path,FileAccess.WRITE)
			if cleanup_file != null:
				cleanup_file.store_string(JSON.stringify(cleanup,"\t"))
				cleanup_file.close()
	print("EXPORT_MANIFEST_OK: %d explicit runtime roots, %d data/attribution files, %d character models, %d LOD meshes; QA and unused character maps excluded" % [manifest.resources.size(),manifest.data_files.size(),manifest.models.size(),manifest.lods.size()])
	quit(0)
