extends SceneTree

const GAME_SCENE := preload("res://scenes/game.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("SMOKE_FAIL: " + message)
	quit(1)

func _send_mouse(viewport: Viewport, pos: Vector2, button: int = 0, pressed: bool = false) -> void:
	var event: InputEvent
	if button == 0:
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		event = motion
	else:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.position = pos
		click.global_position = pos
		click.pressed = pressed
		event = click
	viewport.push_input(event, true)

func _click(viewport: Viewport, pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_send_mouse(viewport, pos, button, true)
	_send_mouse(viewport, pos, button, false)

func _run() -> void:
	var game: Node = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var viewport: Viewport = game.get_viewport()
	var original_music_enabled := bool(game.get("music_enabled"))
	if not original_music_enabled:
		game.call("_toggle_music")
	var initial_load_deadline := Time.get_ticks_msec()+30000
	while not game.call("_initial_tower_models_ready") and Time.get_ticks_msec() < initial_load_deadline:
		await create_timer(0.01).timeout
	if not game.call("_initial_tower_models_ready"):
		_fail("initial tower models did not load")
		return
	var enemy_load_deadline := Time.get_ticks_msec()+30000
	while not game.call("_enemy_models_ready") and Time.get_ticks_msec() < enemy_load_deadline:
		await create_timer(0.01).timeout
	if not game.call("_enemy_models_ready"):
		_fail("all rigged enemy GLB models did not load")
		return
	if game.get("menu_root").visible:
		_fail("startup splash is still covering the game")
		return
	var hamlet: Node3D = game.get("terrain_root").find_child("RiversideHamlet",true,false) as Node3D
	if hamlet == null or game.get("ambient_people").size() < 3 or game.get("ambient_animals").size() < 2:
		_fail("the terrain hamlet, background villagers, or farm animals are missing")
		return
	if game.call("_route_clearance",hamlet.global_position) < 10.0:
		_fail("the background settlement overlaps the enemy road")
		return
	var ground: MeshInstance3D = game.get("terrain_root").get_node_or_null("NoiseTexturedGround") as MeshInstance3D
	if ground == null or not (ground.material_override is ShaderMaterial):
		_fail("the procedural terrain surface is missing")
		return
	if game.get("ambient_birds").size() < 2 or game.get("ambient_lizards").is_empty():
		_fail("the background birds or lizards are missing")
		return
	var bird_before: Vector3 = game.get("ambient_birds")[0].root.position
	var lizard_before: Vector3 = game.get("ambient_lizards")[0].root.position
	game.call("_animate_background_life",0.5)
	if bird_before.distance_to(game.get("ambient_birds")[0].root.position) < 0.05 or lizard_before.distance_to(game.get("ambient_lizards")[0].root.position) < 0.05:
		_fail("background birds or lizards do not animate through the terrain update")
		return
	game.call("_show_main_menu")
	await process_frame
	if not game.get("menu_root").visible:
		_fail("main menu could not be opened")
		return
	_click(viewport, game.get("menu_continue_button").get_global_rect().get_center())
	await process_frame
	if game.get("menu_root").visible:
		_fail("main menu did not close")
		return
	var hud_root: Control = game.get("ui_layer").get_child(0)
	if hud_root.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("HUD overlay still captures map input")
		return
	if game.get("music_slider").get_global_rect().position.y > 72.0 or game.get("sfx_slider").get_global_rect().position.y > 72.0:
		_fail("music and SFX controls are not in the top HUD")
		return
	var viewport_size := viewport.get_visible_rect().size
	var panel_width := float(game.get("side_panel").size.x)
	var zoom_focus := Vector2(viewport_size.x*0.42,viewport_size.y*0.52)
	var anchor_before: Vector3 = game.call("_screen_to_ground",zoom_focus)
	game.call("_request_camera_zoom",zoom_focus,0.82)
	for zoom_step in range(16):
		game.call("_update_camera_zoom",0.05)
	var anchor_after: Vector3 = game.call("_screen_to_ground",zoom_focus)
	if anchor_before.distance_to(anchor_after) > 0.08:
		_fail("zoom did not keep the point under the cursor anchored")
		return
	for i in range(80): game.call("_zoom_at",zoom_focus,1.16)
	if absf(float(game.get("camera_size"))-float(game.call("_camera_max_size"))) > 0.02:
		_fail("camera zoom-out was not clamped to the map-fit limit")
		return
	var camera: Camera3D = game.get("camera")
	var map_screen_points := [Vector3(-32,0,-23.04),Vector3(-32,0,23.04),Vector3(32,0,-23.04),Vector3(32,0,23.04)]
	for corner in map_screen_points:
		var projected_corner: Vector2 = camera.unproject_position(corner)
		if projected_corner.x < 0.0 or projected_corner.x > viewport_size.x-panel_width or projected_corner.y < 70.0 or projected_corner.y > viewport_size.y-20.0:
			_fail("full map does not fit in the usable area at minimum zoom")
			return
	var target := Vector3.ZERO
	var target_screen := Vector2.ZERO
	var best_score := INF
	var points: PackedVector3Array = game.get("route_points")
	var interior_spots := 0
	var edge_spots := 0
	for xi in range(-16,17,2):
		for zi in range(-14,15,2):
			if game.call("_valid_spot",Vector3(float(xi),0,float(zi))): interior_spots += 1
	for xi in range(18,29,2):
		for zi in range(-18,19,3):
			if game.call("_valid_spot",Vector3(float(xi),0,float(zi))): edge_spots += 1
	if interior_spots < 8 or edge_spots < 2:
		_fail("build placement is not available across both interior grass and edge grass")
		return
	if game.call("_valid_spot",points[4]):
		_fail("road center was treated as buildable grass")
		return
	if game.get("build_obstacles").is_empty():
		_fail("terrain props are not registered as build blockers")
		return
	var first_obstacle: Dictionary = game.get("build_obstacles")[0]
	if game.call("_valid_spot",Vector3(first_obstacle.position.x,0,first_obstacle.position.y)):
		_fail("tower placement allowed overlap with a tree or rock")
		return
	for xi in range(-60, 61):
		for zi in range(-40, 41):
			var p := Vector3(float(xi)*0.5, 0.0, float(zi)*0.5)
			if not game.call("_valid_spot", p):
				continue
			var screen: Vector2 = game.get("camera").unproject_position(p)
			if screen.x < 20.0 or screen.x > viewport_size.x-panel_width-20.0 or screen.y < 85.0 or screen.y > viewport_size.y-40.0:
				continue
			var near_spawn := INF
			for i in range(1, mini(points.size(), 18)):
				near_spawn = minf(near_spawn, game.call("_distance_to_segment", p, points[i-1], points[i]))
			if near_spawn >= 7.4 and near_spawn <= 10.3 and absf(near_spawn-8.4) < best_score:
				best_score = absf(near_spawn-8.4)
				target = p
				target_screen = screen
	if best_score == INF:
		_fail("no legal placement candidate visible near route")
		return
	var cards: Array = game.get("card_buttons")
	if cards.size() != game.HEROES.size():
		_fail("tower cards are missing")
		return
	_click(viewport, cards[0].get_global_rect().get_center())
	await process_frame
	if int(game.get("selected_type")) != 0:
		_fail("Asta card click did not enter placement mode")
		return
	_send_mouse(viewport, target_screen)
	await process_frame
	var ghost: Node3D = game.get("build_ghost")
	if ghost == null or not ghost.visible:
		_fail("placement ghost is not visible over map")
		return
	var projected: Vector3 = game.call("_screen_to_ground", target_screen)
	if ghost.position.distance_to(Vector3(projected.x, 0.0, projected.z)) > 0.25:
		_fail("placement ghost does not follow cursor")
		return
	_click(viewport, target_screen)
	await process_frame
	var towers: Array = game.get("towers")
	if towers.size() != 1 or int(game.get("gold")) != 290 or int(game.get("selected_type")) != -1:
		_fail("valid click did not install tower and debit gold")
		return
	var installed: Dictionary = towers[0]
	if installed.animator == null or str(installed.idle_clip).is_empty() or str(installed.attack_clip).is_empty():
		_fail("tower imported animation names were not mapped to Idle/Attack clips")
		return
	if not installed.range_mesh.visible or not installed.selection_ring.visible:
		_fail("selected tower has no persistent visual selection cue")
		return
	if absf(installed.node.position.distance_to(projected)) > 0.25:
		_fail("tower position differs from cursor position")
		return
	var minimum_tower_spacing: float = game.call("_minimum_tower_spacing")
	if minimum_tower_spacing > 1.60:
		_fail("tower spacing still rejects visually separate nearby models: %.2f" % minimum_tower_spacing)
		return
	if game.call("_tower_spacing_valid",installed.node.position+Vector3(minimum_tower_spacing-0.05,0.0,0.0)):
		_fail("tower footprint overlap was accepted")
		return
	if not game.call("_tower_spacing_valid",installed.node.position+Vector3(minimum_tower_spacing+0.05,0.0,0.0)):
		_fail("tower footprint clearance is larger than the actual base plus safety gap")
		return
	var close_grass_position := Vector3.ZERO
	var close_grass_found := false
	for angle_index in range(64):
		var angle := TAU*float(angle_index)/64.0
		for extra_gap in [0.05,0.18,0.32,0.48]:
			var candidate: Vector3 = installed.node.position+Vector3(cos(angle),0.0,sin(angle))*(minimum_tower_spacing+float(extra_gap))
			if game.call("_valid_spot",candidate):
				close_grass_position = candidate
				close_grass_found = true
				break
		if close_grass_found:
			break
	if not close_grass_found:
		_fail("no legal grass location was available close to an existing tower")
		return
	if float(installed.range) > 9.1 or float(installed.detect_range) <= float(installed.range):
		_fail("attack and detection radii were not reduced/separated")
		return
	var route_point: Vector3 = points[4]
	var invalid_screen: Vector2 = game.get("camera").unproject_position(route_point)
	_click(viewport, cards[1].get_global_rect().get_center())
	await process_frame
	if int(game.get("selected_type")) != 1:
		_fail("Yuno card click did not enter placement mode")
		return
	_send_mouse(viewport, invalid_screen)
	await process_frame
	var ghost_mat: StandardMaterial3D = game.get("ghost_material")
	if ghost_mat.albedo_color.r < ghost_mat.albedo_color.g:
		_fail("road position is not marked red")
		return
	_click(viewport, invalid_screen)
	await process_frame
	if towers.size() != 1 or int(game.get("gold")) != 290 or int(game.get("selected_type")) != 1:
		_fail("invalid road click placed tower or exited placement mode")
		return
	_send_mouse(viewport, invalid_screen, MOUSE_BUTTON_RIGHT, true)
	_send_mouse(viewport, invalid_screen, MOUSE_BUTTON_RIGHT, false)
	await process_frame
	if int(game.get("selected_type")) != -1 or game.get("build_ghost") != null:
		_fail("right-click did not cancel placement")
		return
	_click(viewport,cards[1].get_global_rect().get_center())
	await process_frame
	var pan_start := Vector2(viewport_size.x*0.40,viewport_size.y*0.50)
	_send_mouse(viewport,pan_start)
	_send_mouse(viewport,pan_start,MOUSE_BUTTON_RIGHT,true)
	_send_mouse(viewport,pan_start+Vector2(-18.0,4.0))
	var panel_release: Vector2 = game.get("side_panel").get_global_rect().get_center()
	_send_mouse(viewport,panel_release,MOUSE_BUTTON_RIGHT,false)
	await process_frame
	if bool(game.get("panning")) or bool(game.get("right_dragged")) or int(game.get("selected_type")) != 1:
		_fail("releasing a map drag over the HUD left panning stuck or cancelled construction")
		return
	var ghost_resume_screen := Vector2(viewport_size.x*0.43,viewport_size.y*0.52)
	var camera_after_pan: Vector3 = game.get("camera_target")
	_send_mouse(viewport,ghost_resume_screen)
	await process_frame
	var resumed_ghost: Node3D = game.get("build_ghost")
	var resumed_position: Vector3 = game.call("_screen_to_ground",ghost_resume_screen)
	if resumed_ghost == null or resumed_ghost.position.distance_to(resumed_position) > 0.25 or game.get("camera_target").distance_to(camera_after_pan) > 0.001:
		_fail("ghost following did not resume after releasing a pan over the HUD")
		return
	_click(viewport,ghost_resume_screen,MOUSE_BUTTON_RIGHT)
	await process_frame
	var second_target := Vector3.ZERO
	var second_screen := Vector2.ZERO
	var found_second := false
	for xi in range(-60, 61):
		for zi in range(-40, 41):
			var p := Vector3(float(xi)*0.5, 0.0, float(zi)*0.5)
			if not game.call("_valid_spot", p):
				continue
			var screen: Vector2 = game.get("camera").unproject_position(p)
			if screen.x < 20.0 or screen.x > viewport_size.x-panel_width-20.0 or screen.y < 85.0 or screen.y > viewport_size.y-40.0:
				continue
			second_target = p
			second_screen = screen
			found_second = true
			break
		if found_second:
			break
	if not found_second:
		_fail("no second legal placement spot")
		return
	_click(viewport, cards[1].get_global_rect().get_center())
	await process_frame
	_send_mouse(viewport, second_screen)
	await process_frame
	_click(viewport, second_screen)
	await process_frame
	if towers.size() != 2 or int(game.get("gold")) != 190 or int(game.get("selected_type")) != -1:
		_fail("second hero did not place correctly or gold was not charged")
		return
	var yuno: Dictionary = towers[1]
	var tower_screen: Vector2 = game.get("camera").unproject_position(installed.node.position)
	_click(viewport, tower_screen)
	await process_frame
	if game.get("selected_tower").is_empty():
		_fail("clicking tower did not select it")
		return
	if game.get("selected_tower").node != installed.node:
		_fail("clicking the first tower selected the wrong object")
		return
	var upgrade_load_deadline := Time.get_ticks_msec()+30000
	var rank_two := "res://Assets/Heroes/asta_L2.glb"
	while not game.get("tower_model_cache").has(rank_two) and Time.get_ticks_msec() < upgrade_load_deadline:
		await create_timer(0.01).timeout
	if not game.get("tower_model_cache").has(rank_two):
		_fail("Asta upgrade model did not load")
		return
	game.call("_refresh_selection")
	if game.get("upgrade_button").disabled:
		_fail("upgrade control remained disabled after the selected tower model loaded")
		return
	var upgrade_center: Vector2 = game.get("upgrade_button").get_global_rect().get_center()
	_send_mouse(viewport,upgrade_center)
	await process_frame
	var hovered: Control = viewport.gui_get_hovered_control()
	if hovered != game.get("upgrade_button"):
		_fail("upgrade button is outside the visible/clickable part of the panel")
		return
	_click(viewport,upgrade_center)
	await process_frame
	if int(installed.level) != 1 or int(game.get("gold")) != 110 or installed.damage <= 17.0:
		_fail("upgrade button failed: rank=%d gold=%d damage=%.2f disabled=%s visible=%s rect=%s selected=%s" % [int(installed.level),int(game.get("gold")),float(installed.damage),str(game.get("upgrade_button").disabled),str(game.get("upgrade_button").is_visible_in_tree()),str(game.get("upgrade_button").get_global_rect()),str(not game.get("selected_tower").is_empty())])
		return
	if installed.detect_range <= installed.range:
		_fail("tower detection radius did not upgrade with its attack range")
		return
	# Space must work even after a control held keyboard focus.
	game.get("speed_select").grab_focus()
	var wave_key := InputEventKey.new()
	wave_key.keycode = KEY_SPACE
	wave_key.pressed = true
	viewport.push_input(wave_key,true)
	await process_frame
	if not bool(game.get("wave_running")):
		_fail("wave did not start")
		return
	var wait_frames := 0
	while game.get("enemies").is_empty() and wait_frames < 80:
		await create_timer(0.05).timeout
		wait_frames += 1
	var enemies: Array = game.get("enemies")
	if enemies.is_empty():
		_fail("wave did not spawn an enemy")
		return
	var enemy: Dictionary = enemies[0]
	if enemy.model == null or enemy.animator == null:
		_fail("spawned enemy is missing its skinned 3D model or AnimationPlayer")
		return
	var enemy_skeleton := _find_node_class(enemy.model,"Skeleton3D") as Skeleton3D
	var enemy_mesh_count := _count_skinned_meshes(enemy.model)
	if enemy_skeleton == null or enemy_skeleton.get_bone_count() < 15 or enemy_mesh_count < 1:
		_fail("spawned NPC reverted to primitive geometry instead of its rigged GLB")
		return
	if not str(enemy.animator.current_animation).ends_with("_Run"):
		_fail("spawned NPC is not playing its skeletal Run animation")
		return
	var expected_run_scale: float = game.call("_enemy_run_animation_speed",enemy,1.0)
	if absf(float(enemy.animator.speed_scale)-expected_run_scale) > 0.02:
		_fail("NPC gait scale does not match route movement speed")
		return
	game.call("_set_speed",2)
	expected_run_scale = game.call("_enemy_run_animation_speed",enemy,1.0)
	if absf(float(enemy.animator.speed_scale)-expected_run_scale) > 0.02:
		_fail("3x game speed did not keep NPC gait synchronized with movement")
		return
	game.call("_set_speed",0)
	var enemy_before_menu: Vector3 = enemy.node.position
	game.call("_show_main_menu")
	await create_timer(0.06).timeout
	if not bool(game.get("paused")) or absf(float(enemy.animator.speed_scale)) > 0.001 or enemy.node.position.distance_to(enemy_before_menu) > 0.001:
		_fail("opening the menu did not pause movement and the skeletal NPC animation together")
		return
	game.call("_continue_game")
	if bool(game.get("paused")) or float(enemy.animator.speed_scale) <= 0.0:
		_fail("closing the menu did not resume the actual NPC gait")
		return
	var nearest := INF
	var nearest_distance := 0.0
	for i in range(points.size()):
		var dist: float = installed.node.position.distance_to(points[i])
		if dist < nearest:
			nearest = dist
			nearest_distance = game.get("route_lengths")[i]
	if nearest > float(installed.range):
		_fail("tower range does not cover a route segment")
		return
	enemy.distance = nearest_distance
	enemy.node.position = game.call("_path_at", nearest_distance)
	enemy.hp = 100000.0
	enemy.max_hp = enemy.hp
	game.call("_update_towers", 1.0)
	if game.get("bolts").is_empty():
		_fail("tower did not fire at an in-range enemy")
		return
	if installed.animator.current_animation != installed.attack_clip or not installed.animator.is_playing():
		_fail("tower attack did not start its actual prefixed skeletal animation clip")
		return
	var bolt_node: Node3D = game.get("bolts")[0].node
	if bolt_node.get_child_count() < 2:
		_fail("spell projectile is still a single plain sphere")
		return
	var hp_before: float = enemy.hp
	game.call("_update_bolts", 0.5)
	if enemy.hp >= hp_before:
		_fail("projectile did not damage target")
		return
	var effects: Node3D = game.get("magic_effects")
	var impact_counts: Dictionary = effects.debug_counts()
	if int(impact_counts.active_impacts) < 1:
		_fail("projectile damage did not spawn its elemental impact")
		return
	effects.tick(2.0)
	if int(effects.debug_counts().active_impacts) != 0:
		_fail("elemental impacts did not expire and return to their pool")
		return
	for burst in range(160): effects.impact(burst%5,Vector3(0,1,0))
	if int(effects.debug_counts().active_impacts) > int(effects.debug_counts().max_impacts):
		_fail("overlapping spell bursts exceeded the bounded effect capacity")
		return
	effects.tick(2.0)
	if int(effects.debug_counts().active_impacts) != 0:
		_fail("pooled spell bursts remained active after their lifetime")
		return
	var stress_effects: Node3D = load("res://scripts/magic_effects.gd").new()
	root.add_child(stress_effects)
	var stress_flights: Array[Node3D] = []
	for flight_index in range(int(stress_effects.debug_counts().max_flights)+8):
		stress_flights.append(stress_effects.acquire_flight(flight_index%5))
	if int(stress_effects.debug_counts().active_flights) > int(stress_effects.debug_counts().max_flights) or int(stress_effects.debug_counts().overflow_flights) == 0:
		_fail("spell flight overload did not preserve its bounded rendered capacity")
		return
	# A stage transition/reset must also release unrendered overflow projectiles.
	stress_effects.clear_all()
	if int(stress_effects.debug_counts().active_flights) != 0 or int(stress_effects.debug_counts().overflow_flights) != 0:
		_fail("clearing the arena left active or overflow spell flights behind")
		return
	stress_flights.clear()
	stress_effects.queue_free()
	if enemy.hit_time <= 0.0 or not str(enemy.animator.current_animation).ends_with("_Hit"):
		_fail("damage did not switch the rigged NPC into its Hit animation")
		return
	_click(viewport, game.get("sell_button").get_global_rect().get_center())
	await process_frame
	if int(game.get("gold")) != 260 or towers.size() != 1:
		_fail("Asta sale did not refund purchase plus upgrade price")
		return
	var yuno_screen: Vector2 = game.get("camera").unproject_position(yuno.node.position)
	var support_spot: Vector3 = yuno.node.position
	var support_screen: Vector2 = game.get("camera").unproject_position(support_spot)
	_click(viewport, yuno_screen)
	await process_frame
	_click(viewport, game.get("sell_button").get_global_rect().get_center())
	await process_frame
	if int(game.get("gold")) != 360 or not towers.is_empty():
		_fail("Yuno sale did not refund its full purchase price")
		return
	_click(viewport,cards[3].get_global_rect().get_center())
	await process_frame
	_send_mouse(viewport,support_screen)
	await process_frame
	_click(viewport,support_screen)
	await process_frame
	if towers.size() != 1 or int(towers[0].type) != 3:
		_fail("Vanessa could not be placed on the freed legal grass position")
		return
	var vanessa: Dictionary = towers[0]
	var nearby_asta_position := Vector3.ZERO
	var nearby_asta_found := false
	for angle_index in range(64):
		var angle := TAU*float(angle_index)/64.0
		var candidate: Vector3 = support_spot+Vector3(cos(angle),0.0,sin(angle))*(minimum_tower_spacing+0.16)
		if game.call("_valid_spot",candidate):
			nearby_asta_position = candidate
			nearby_asta_found = true
			break
	if not nearby_asta_found:
		_fail("could not find a valid close placement next to Vanessa")
		return
	var nearby_asta_screen: Vector2 = game.get("camera").unproject_position(nearby_asta_position)
	_click(viewport,cards[0].get_global_rect().get_center())
	await process_frame
	_send_mouse(viewport,nearby_asta_screen)
	await process_frame
	_click(viewport,nearby_asta_screen)
	await process_frame
	if towers.size() != 2 or int(towers[1].type) != 0:
		_fail("tower spacing rejected a legal Asta placement beside Vanessa")
		return
	var nearby_asta: Dictionary = towers[1]
	game.call("_select_tower",0)
	game.call("_set_aura","damage")
	var aura_bonuses: Dictionary = game.call("_aura_bonuses_for",nearby_asta)
	if absf(float(aura_bonuses.damage_multiplier)-1.30) > 0.01:
		_fail("Vanessa damage aura did not affect the nearby tower by its displayed 30 percent")
		return
	if not game.get("aura_damage_button").button_pressed or game.get("aura_speed_button").button_pressed:
		_fail("active Vanessa damage aura is not shown as the selected control")
		return
	if not nearby_asta.aura_light.visible:
		_fail("aura recipients do not receive the character-light cue")
		return
	game.call("_select_tower",1)
	var damage_stats: String = game.get("selection_label").text
	if not damage_stats.contains("17 (+30% → 22)"):
		_fail("selected tower does not show base damage, aura percent and actual resulting damage together")
		return
	game.call("_select_tower",0)
	if not nearby_asta.aura_damage_indicator.visible or nearby_asta.aura_speed_indicator.visible:
		_fail("Vanessa's active damage aura is not visible on the supported tower")
		return
	game.call("_set_aura","speed")
	if nearby_asta.aura_damage_indicator.visible or not nearby_asta.aura_speed_indicator.visible:
		_fail("switching Vanessa's aura did not switch the supported-tower indicator")
		return
	if not game.get("aura_speed_button").button_pressed or game.get("aura_damage_button").button_pressed:
		_fail("Vanessa active control did not switch to attack-speed aura")
		return
	game.call("_select_tower",1)
	if not str(game.get("selection_label").text).contains("1.18 (+30% → 1.53)"):
		_fail("selected tower does not show the actual aura-adjusted attacks per second")
		return
	game.call("_select_tower",0)
	game.call("_set_aura","damage")
	if absf(float(vanessa.range_mesh.mesh.outer_radius)-float(vanessa.aura_range)) > 0.01 or float(vanessa.range) != 0.0:
		_fail("Vanessa aura range is still coupled to an attack range")
		return
	var original_music := float(game.get("music_volume"))
	var original_sfx := float(game.get("sfx_volume"))
	game.call("_set_music_volume",original_music*0.7)
	if absf(float(game.get("sfx_volume"))-original_sfx) > 0.01:
		_fail("music slider changed SFX level")
		return
	game.call("_set_sfx_volume",original_sfx*0.7)
	if absf(float(game.get("music_volume"))-original_music*0.7) > 0.01:
		_fail("SFX slider changed music level")
		return
	game.call("_set_music_volume",original_music)
	game.call("_set_sfx_volume",original_sfx)
	if not game.get("sfx_stream_cache").has("res://Assets/Sfx/asta-slash.mp3") or not game.get("sfx_stream_cache").has("res://Assets/Sfx/death-orc.mp3"):
		_fail("attack or enemy-death audio assets did not load")
		return
	var loaded_music: PackedStringArray = game.get("music_tracks")
	if loaded_music.is_empty() or game.get("music_player").stream == null:
		_fail("music playlist could not load its bundled track")
		return
	if not game.get("music_player").finished.is_connected(Callable(game,"_advance_music")):
		_fail("music playlist does not advance when a track finishes")
		return
	var bad_track_path := "user://kdtd-invalid-audio-smoke.mp3"
	var bad_track := FileAccess.open(bad_track_path,FileAccess.WRITE)
	bad_track.store_string("This deliberately corrupt MP3 must be skipped by the playlist.")
	bad_track.close()
	if game.call("_load_music_track",bad_track_path) != null or game.call("_load_music_track","user://kdtd-missing-audio-smoke.mp3") != null:
		_fail("invalid or missing music was accepted as a playable track")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_track_path))
	game.call("_advance_music")
	if game.get("music_player").stream == null:
		_fail("the music playlist stopped instead of wrapping to a valid track")
		return
	if not original_music_enabled:
		game.call("_toggle_music")
	var gold_before_death := int(game.get("gold"))
	game.call("_kill_enemy",enemy)
	if not game.get("enemies").is_empty() or game.get("enemy_death_visuals").is_empty():
		_fail("killed NPC was not removed from combat and kept for a death animation")
		return
	var dying: Dictionary = game.get("enemy_death_visuals")[0]
	if dying.animator == null or not str(dying.animator.current_animation).ends_with("_Death"):
		_fail("killed NPC did not play its skeletal Death animation")
		return
	game.set("gold",gold_before_death)
	var pending_deadline := Time.get_ticks_msec()+30000
	var all_loaded := false
	while Time.get_ticks_msec() < pending_deadline:
		all_loaded = true
		for path in game.get("tower_model_paths"):
			if not game.get("tower_model_cache").has(path) and not game.get("tower_model_failures").has(path):
				all_loaded = false
				break
		if all_loaded:
			break
		await create_timer(0.01).timeout
	if not all_loaded:
		_fail("outstanding upgrade model requests did not complete before shutdown")
		return
	print("SMOKE_OK: startup/menu, detailed terrain, hamlet villagers, goats, flying birds, ground lizards, legal grass placement, close tower spacing, invalid terrain, selected tower UI, upgrades, Vanessa aura, wave, rigged NPC Run/Hit/Death, targeting, projectile damage, full refunds, effective aura stats and selected modes, menu pauses skeletons, global Space shortcut, smooth cursor zoom, independent audio and resilient looping playlist")
	var music_player: AudioStreamPlayer = game.get("music_player")
	music_player.stop()
	music_player.stream = null
	game.get("enemy_death_visuals").clear()
	game.get("enemies").clear()
	enemy = {}
	dying = {}
	installed = {}
	yuno = {}
	vanessa = {}
	nearby_asta = {}
	ghost_mat = null
	game.queue_free()
	await process_frame
	await process_frame
	# Allow deferred renderer/threaded resource releases to finish in an uncapped
	# headless run; two process frames can otherwise elapse in under a millisecond.
	await create_timer(0.20).timeout
	# Let the coroutine release its local Resource references before quitting.
	call_deferred("_finish_success")

func _finish_success() -> void:
	quit(0)

func _find_node_class(node: Node, wanted_class: String) -> Node:
	if node.get_class() == wanted_class:
		return node
	for child in node.get_children():
		var found := _find_node_class(child,wanted_class)
		if found != null:
			return found
	return null

func _count_skinned_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D and node.skin != null else 0
	for child in node.get_children():
		total += _count_skinned_meshes(child)
	return total
