extends SceneTree

class GameHarness extends "res://scripts/game.gd":
	var saved: ConfigFile
	func _ready() -> void:
		_build_hud()
		_build_main_menu()
		menu_root.hide()
		_update_ui_layout()
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func _save_settings() -> void: saved=_settings_config()
	func _initial_tower_models_ready() -> bool:return true

func _initialize() -> void:call_deferred("_run")
func _fail(message: String) -> void:
	push_error("FRAME_PACING_FAIL: "+message)
	quit(1)
func _run() -> void:
	root.size=Vector2i(1600,900)
	var game:=GameHarness.new()
	root.add_child(game)
	await process_frame
	await process_frame
	if game.frame_limit!=60:
		_fail("new installations are not capped at 60 FPS")
		return
	for index in range(4):
		var cap: int=[30,60,120,0][index]
		game.frame_limit_select.select(index)
		game.frame_limit_select.item_selected.emit(index)
		if game.frame_limit!=cap or game.saved==null or int(game.saved.get_value("graphics","frame_limit"))!=cap:
			_fail("frame selector does not persist its actual selected cap")
			return
		if game._effective_frame_limit(true,false,false)!=cap or game._effective_frame_limit(false,false,false)!=15:
			_fail("active/background limit policy differs from selection")
			return
		var menu_cap:=mini(cap,30) if cap>0 else 30
		if game._effective_frame_limit(true,true,false)!=menu_cap or game._effective_frame_limit(true,false,true)!=menu_cap:
			_fail("menu/pause fails to reduce rendering while inactive")
			return
	game.music_volume=17.0
	game.sfx_volume=37.0
	var stored:=game._settings_config()
	if float(stored.get_value("audio","music_volume"))!=17.0 or float(stored.get_value("audio","sfx_volume"))!=37.0:
		_fail("new graphics preference loses the independent audio preferences")
		return
	if game.made_by_label.text!="Made by Alex" or game.made_by_label.mouse_filter!=Control.MOUSE_FILTER_IGNORE or game.made_by_label.get_global_rect().end.y>70.0:
		_fail("credit intercepts input or overlaps the game field")
		return
	print("FRAME_PACING_OK: default60, selectable30/60/120/unlimited, menu/pause30, background15, saved graphics+audio, nonblocking Made by Alex")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	call_deferred("quit",0)
