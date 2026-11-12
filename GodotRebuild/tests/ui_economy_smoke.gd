extends SceneTree
## Uses production HUD, buttons and arena-transition code, without loading any
## character/world assets or writing the player's saved sound settings.

const FROST_UI := preload("res://scripts/ui_theme_frost.gd")

class EffectHarness extends Node3D:
	var clears := 0
	func clear_all() -> void:
		clears += 1

class GameHarness extends "res://scripts/game.gd":
	var rebuilt_arenas := 0
	var ghost_requests := 0
	func _ready() -> void:
		terrain_root = Node3D.new()
		add_child(terrain_root)
		tower_root = Node3D.new()
		add_child(tower_root)
		magic_effects = EffectHarness.new()
		add_child(magic_effects)
		for hero in HEROES:
			for rank in range(1,6):
				tower_model_cache["res://Assets/Heroes/%s_L%d.glb" % [hero.id,rank]] = PackedScene.new()
		_build_hud()
		_build_main_menu()
		menu_root.hide()
		_update_ui_layout()
		_refresh_hud()
		_refresh_selection()
	func _process(_delta: float) -> void:
		pass
	func _exit_tree() -> void:
		pass
	func _initial_tower_models_ready() -> bool:
		return true
	func _enemy_models_ready() -> bool:
		return true
	func _build_arena() -> void:
		rebuilt_arenas += 1
	func _screen_to_ground(_screen_point: Vector2) -> Vector3:
		return Vector3.ZERO
	func _create_build_ghost(_index: int) -> void:
		ghost_requests += 1

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("UI_ECONOMY_FAIL: "+message)
	quit(1)

func _mock_tower(game: Node3D, hero_type: int, investment: int) -> Dictionary:
	var actor := Node3D.new()
	game.add_child(actor)
	return {"node":actor,"type":hero_type,"level":0,"invested":investment,"damage":17.0,"range":9.0,"detect_range":10.5,"rate":0.85,"aura_range":10.5,"power":0.30,"aura":"damage","animator":null,"range_mesh":null,"selection_ring":null,"selection_light":null}

func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600,900)
	var game := GameHarness.new()
	root.add_child(game)
	await process_frame
	await process_frame
	# Each rendered style is genuinely textured; disabled controls remain dark.
	var style := FROST_UI.frame_style()
	if not style is StyleBoxTexture or style.texture == null:
		_fail("right-panel artwork is missing")
		return
	var frame_image := style.texture.get_image()
	var report_dir := ProjectSettings.globalize_path("res://Builds")
	if DirAccess.make_dir_recursive_absolute(report_dir) != OK:
		_fail("could not create the UI report directory")
		return
	if frame_image.save_png(report_dir.path_join("ui-frost-frame.png")) != OK:
		_fail("could not save the UI frame report")
		return
	if frame_image.get_pixel(2,2).is_equal_approx(frame_image.get_pixel(96,96)):
		_fail("forged frame and stone inset have collapsed into one flat color")
		return
	var disabled_image := FROST_UI.button_style("disabled").texture.get_image()
	var disabled_center := disabled_image.get_pixel(96,96)
	if maxf(disabled_center.r,maxf(disabled_center.g,disabled_center.b)) > 0.18:
		_fail("disabled controls became pale/white again")
		return
	# Check the complete, worst-height panel with both Vanessa aura actions shown.
	var vanessa := _mock_tower(game,3,115)
	game.towers.append(vanessa)
	game.selected_tower = vanessa
	game._refresh_selection()
	var controls: Array[Control] = [game.start_button,game.pause_button,game.speed_select,game.upgrade_button,game.sell_button,game.aura_damage_button,game.aura_speed_button,game.selection_label]
	for card in game.card_buttons:
		controls.append(card)
	var layout_cases := 0
	for viewport_size in [Vector2i(1600,900),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = viewport_size
		game._update_ui_layout()
		await process_frame
		await process_frame
		var panel_rect: Rect2 = game.side_panel.get_global_rect()
		for control in controls:
			var rect := control.get_global_rect()
			if not control.is_visible_in_tree() or not panel_rect.grow(1.0).encloses(rect):
				_fail("control %s escapes panel at %s: %s in %s" % [str(control),str(viewport_size),str(rect),str(panel_rect)])
				return
		for first in range(controls.size()):
			for second in range(first+1,controls.size()):
				if controls[first].get_global_rect().intersection(controls[second].get_global_rect()).get_area() > 0.1:
					_fail("controls overlap at %s" % str(viewport_size))
					return
		if game.side_scroll.get_v_scroll_bar().visible or game.side_scroll.get_h_scroll_bar().visible:
			_fail("right panel still needs a scrollbar")
			return
		for sound_control in [game.music_slider,game.sfx_slider]:
			if not sound_control.is_visible_in_tree() or sound_control.get_global_rect().end.y > 70.0:
				_fail("independent sound controls left the top bar")
				return
		layout_cases += 1
	# Exercise actual connected aura and tempo button callbacks after restyling.
	game.aura_speed_button.pressed.emit()
	if vanessa.aura != "speed" or not game.aura_speed_button.button_pressed or game.aura_damage_button.button_pressed:
		_fail("restyled aura control lost its connected behavior")
		return
	game.aura_damage_button.pressed.emit()
	if vanessa.aura != "damage" or not game.selection_label.text.contains("УРОН +30%"):
		_fail("restyled damage-aura control lost its displayed state")
		return
	game.speed_select.item_selected.emit(2)
	if game.game_speed != 3.0:
		_fail("tempo selection no longer reaches 3x")
		return
	game.towers.clear()
	game.selected_tower = {}
	vanessa.node.queue_free()
	for index in range(game.HEROES.size()):
		game.card_buttons[index].pressed.emit()
		if game.selected_type != index:
			_fail("tower card no longer enters the correct placement mode")
			return
	if game.ghost_requests != game.HEROES.size():
		_fail("tower-card signals do not request one preview per selection")
		return
	# Exact integer carryover, independent from money invested in old towers.
	var economy_cases := 0
	for remaining in [0,9,10,19,999,1000]:
		var expected := 220+int(floor(float(remaining)/10.0))
		for destination in [1,8,17]:
			var old_tower := _mock_tower(game,0,12345)
			game.towers.append(old_tower)
			game.gold = remaining
			game.arena = destination-1
			game.wave = 15
			game.stage_ready = true
			game.wave_running = false
			game.game_over = false
			game.start_button.pressed.emit()
			if game.gold != expected or game.arena != destination or game.wave != 0 or game.wave_running or game.spawn_left != 0 or game.stage_ready or not game.towers.is_empty():
				_fail("transition differs from 220+floor(%d/10): got %d on arena %d" % [remaining,game.gold,destination+1])
				return
			if not game.status_label.text.contains("%d перенос" % (expected-220)) or not game.hud_gold.tooltip_text.contains("%d" % remaining):
				_fail("transition does not explain carried and base gold to the player")
				return
			# The transition leaves a safe preparation phase; only a second click starts wave one.
			game.start_button.pressed.emit()
			if game.gold != expected or game.arena != destination or game.wave != 1 or not game.wave_running:
				_fail("repeated start click applied an arena transfer twice")
				return
			game.start_button.pressed.emit()
			if game.gold != expected or game.wave != 1:
				_fail("a click during an active wave applied an arena transfer twice")
				return
			for hero in game.HEROES:
				if int(hero.price) > game.gold:
					_fail("zero-carry first-wave budget cannot buy a basic hero on a later arena")
					return
			if game.gold < int(game.HEROES[0].price)+int(game.HEROES[1].price):
				_fail("later arena budget cannot buy the Asta and Yuno opening pair")
				return
			economy_cases += 1
	game.menu_new_button.pressed.emit()
	if game.arena != 0 or game.gold != 360 or game.wave_running or not game.hud_gold.tooltip_text.contains("360") or game.hud_gold.tooltip_text.contains("перенос"):
		_fail("new campaign preserved the previous arena budget or its tooltip")
		return
	print("UI_ECONOMY_OK: %d full-panel layouts without scrolling/overlap; top audio, six placement callbacks, auras and 3x; %d exact 10%% carry transitions including late arenas, no tower refund or duplicate transfer. Zero carry leaves 220; 999 leaves 319." % [layout_cases,economy_cases])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
