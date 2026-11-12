extends SceneTree
## No playback/world/settings: verifies source + import-descriptor discovery,
## deduplication and imported stream loading through the production helpers.
const Game := preload("res://scripts/game.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := Game.new()
	var tracks: Array[String] = []
	game._append_resource_music("res://Assets/Music",tracks)
	var initial_count := tracks.size()
	game._append_resource_music("res://Assets/Music",tracks)
	var expected := "res://Assets/Music/Everlasting-Shine.mp3"
	var stream: AudioStream = game._load_music_track(expected)
	var passed := initial_count>0 and tracks.size()==initial_count and tracks.has(expected) and stream!=null and stream.get_length()>1.0 and game._load_music_track("res://Assets/Music/__missing_bundled_track__.mp3")==null
	stream = null
	game.free()
	if not passed:
		push_error("BUNDLED_MUSIC_FAIL: source/import descriptors did not yield one decodable fallback without duplicates")
		quit(1)
		return
	print("BUNDLED_MUSIC_OK: source/import discovery deduplicates paths, bundled stream decodes, missing resource rejected; no playback or settings changes")
	quit(0)
