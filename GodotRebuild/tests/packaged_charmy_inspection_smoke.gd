extends SceneTree
## Run the Godot console host with --headless --path EMPTY_QA_PROJECT
## --main-pack KDTD.exe --script ABSOLUTE_THIS_FILE. Standard release templates
## disable external --script overrides. All res:// code/models come from PCK.
const GameScene := preload("res://scenes/game.tscn")
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		push_error("PACKAGED_CHARMY_FAIL: "+message)
		quit(1)
	return condition

func _mouse(viewport: Viewport, point: Vector2, button: int = 0, pressed: bool = false) -> void:
	if button == 0:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		viewport.push_input(motion,true)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event,true)

func _click(viewport: Viewport, point: Vector2) -> void:
	_mouse(viewport,point,MOUSE_BUTTON_LEFT,true)
	_mouse(viewport,point,MOUSE_BUTTON_LEFT,false)

func _wait_for_model(game: Node, path: String) -> bool:
	var deadline := Time.get_ticks_msec()+60000
	while not game.tower_model_cache.has(path) and Time.get_ticks_msec()<deadline:
		game._poll_tower_model_loading()
		await create_timer(0.01).timeout
	return game.tower_model_cache.has(path)

func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600,900)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	var deadline := Time.get_ticks_msec()+60000
	while (not game._initial_tower_models_ready() or not game._enemy_models_ready()) and Time.get_ticks_msec()<deadline:
		await create_timer(0.01).timeout
	if not _check(game._initial_tower_models_ready() and game._enemy_models_ready(),"packed hero/enemy resources did not load"): return
	game.set_process(false)
	await process_frame
	if not _check(game.card_buttons.size()==6 and not game.menu_root.visible,"six cards and an unobstructed startup field are required"): return
	var position := Vector3.ZERO
	var route_index := -1
	for i in range(8,game.route_points.size()-8,3):
		for offset in [Vector3(0,0,4),Vector3(4,0,0),Vector3(0,0,-4),Vector3(-4,0,0)]:
			var candidate: Vector3 = game.route_points[i]+offset
			if game._valid_spot(candidate):
				position = candidate
				route_index = i
				break
		if route_index >= 0: break
	if not _check(route_index>=0,"no legal near-road Charmy placement"): return
	var viewport: Viewport = game.get_viewport()
	var price: int = game.HEROES[5].price
	var starting_gold: int = game.gold
	_click(viewport,game.card_buttons[5].get_global_rect().get_center())
	await process_frame
	if not _check(game.selected_type==5 and game.build_ghost!=null,"Charmy card did not start placement"): return
	var projected: Vector2 = game.camera.unproject_position(position)
	_mouse(viewport,projected)
	if not _check(game.build_ghost.position.distance_to(position)<0.1,"real placement ghost did not follow the cursor"): return
	_click(viewport,projected)
	await process_frame
	if not _check(game.towers.size()==1 and game.gold==starting_gold-price,"Charmy was not installed and charged exactly once"): return
	var tower: Dictionary = game.towers[0]
	if not _check(tower.animator!=null and tower.attack_clip=="charmy_Attack","packed Charmy rig/attack clip missing"): return
	game._start_wave()
	game._spawn_enemy()
	var enemy: Dictionary = game.enemies[0]
	enemy.distance = game.route_lengths[route_index]
	enemy.node.position = game._path_at(enemy.distance)
	enemy.hp = 5000.0
	enemy.max_hp = 5000.0
	game._update_enemy_health_bar(enemy)
	var enemy_screen: Vector2 = game.camera.unproject_position(enemy.node.position+Vector3.UP*enemy.height*0.5)
	_click(viewport,enemy_screen)
	await process_frame
	if not _check(not game.selected_enemy.is_empty() and game.selected_enemy.node==enemy.node,"screen click did not select the packed enemy model"): return
	if not _check(game.selection_label.text.contains("5000 / 5000") and game.selection_label.text.contains("Броня:") and game.selection_label.text.contains("Награда:"),"enemy inspector does not show live HP/armor/reward"): return
	if not _check(not game.upgrade_button.visible and enemy.selection_ring.visible,"enemy selection is not visually separated from tower upgrades"): return
	game._select_tower(0)
	game.gold = 10000
	game._refresh_hud()
	for rank in range(2,6):
		var path := "res://Assets/Heroes/charmy_L%d.glb" % rank
		if not _check(await _wait_for_model(game,path),"missing packed Charmy upgrade "+path): return
		game._refresh_selection()
		game.upgrade_button.pressed.emit()
		if not _check(tower.level==rank-1,"upgrade callback failed at rank %d" % rank): return
	if not _check(game.selection_label.text.contains("Хлопковый таран") and tower.attack_clip=="charmy_Attack","maximum rank ability/model is missing"): return
	game._fire_bolt(tower,enemy,100.0)
	if not _check(game.bolts.size()==1 and game.bolts[0].type==5 and game.bolts[0].node.get_child_count()>1,"Charmy did not create its own volumetric spell"): return
	game._update_bolts(1.0)
	if not _check(enemy.hp<5000.0 and enemy.armor_shred==14.0,"real Charmy projectile did not apply damage and armor shred"): return
	if not _check(game.magic_effects.debug_counts().active_impacts>0,"packed cotton impact effect did not execute"): return
	game._select_enemy(0)
	game._refresh_selection()
	if not _check(game.selection_label.text.contains("броня ослаблена"),"live enemy inspector did not update the armor debuff"): return
	game._kill_enemy(enemy)
	if not _check(game.selected_enemy.is_empty() and not game.enemy_death_visuals.is_empty(),"enemy death did not clear inspection and retain a death animation"): return
	for voice in game.sfx_players:
		voice.stop()
		voice.stream = null
	game.music_player.stop()
	game.music_player.stream = null
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	print("PACKAGED_CHARMY_UI_OK: %d checks; executable resources, real card/mouse placement, exact gold debit, NPC screen selection and HP/armor/reward UI, all five skinned Charmy ranks, connected upgrades, cotton projectile/impact, armor shred and death cleanup" % checks)
	quit(0)
