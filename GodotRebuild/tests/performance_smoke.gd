extends SceneTree

const GAME_SCENE := preload("res://scenes/game.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var initial_load_deadline := Time.get_ticks_msec()+30000
	while not game.call("_initial_tower_models_ready") and Time.get_ticks_msec() < initial_load_deadline:
		await create_timer(0.01).timeout
	if not game.call("_initial_tower_models_ready"):
		push_error("PERF_FAIL: base tower resources did not load")
		quit(1)
		return
	var enemy_load_deadline := Time.get_ticks_msec()+30000
	while not game.call("_enemy_models_ready") and Time.get_ticks_msec() < enemy_load_deadline:
		await create_timer(0.01).timeout
	if not game.call("_enemy_models_ready"):
		push_error("PERF_FAIL: skinned enemy models did not load")
		quit(1)
		return
	var music: AudioStreamPlayer = game.get("music_player")
	if music != null: music.stop()
	game.set("gold",100000)
	var placed := 0
	for xi in range(-54,55,3):
		for zi in range(-36,37,3):
			var point := Vector3(float(xi),0,float(zi))
			if game.call("_valid_spot",point):
				game.call("_select_type",placed%game.HEROES.size())
				game.call("_place_tower",point)
				placed += 1
				if placed >= 18: break
		if placed >= 18: break
	if placed < 12:
		push_error("PERF_FAIL: could not arrange a representative tower set")
		quit(1)
		return
	game.set("wave",15)
	game.set("spawn_left",100)
	for i in range(100): game.call("_spawn_enemy")
	var enemies: Array = game.get("enemies")
	if enemies.size() != 100:
		push_error("PERF_FAIL: expected 100 instantiated rigged NPCs, got %d" % enemies.size())
		quit(1)
		return
	var route_length: float = game.get("route_length")
	for i in range(enemies.size()):
		enemies[i].distance = route_length*(0.05+0.68*float(i+1)/float(enemies.size()+1))
		enemies[i].node.position = game.call("_path_at",enemies[i].distance)
		enemies[i].hp = 1000000.0
		enemies[i].max_hp = 1000000.0
	var samples: Array[float] = []
	for frame in range(180):
		var began := Time.get_ticks_usec()
		for enemy in game.get("enemies").duplicate():
			game.call("_update_enemy",enemy,1.0/60.0)
		game.call("_update_towers",1.0/60.0)
		game.call("_update_bolts",1.0/60.0)
		var elapsed_ms := float(Time.get_ticks_usec()-began)/1000.0
		if frame >= 30: samples.append(elapsed_ms)
		if frame%10 == 0: await process_frame
	samples.sort()
	var total := 0.0
	for value in samples: total += value
	var average := total/maxf(1.0,float(samples.size()))
	var p95 := samples[mini(samples.size()-1,roundi(float(samples.size()-1)*0.95))]
	print("PERF_SMOKE: towers=%d enemies=%d nodes=%d sim_mean_ms=%.3f sim_p95_ms=%.3f sim_max_ms=%.3f renderer=headless (GPU timing unavailable)" % [game.get("towers").size(),game.get("enemies").size(),Performance.get_monitor(Performance.OBJECT_NODE_COUNT),average,p95,samples[-1]])
	if music != null:
		music.stop()
		music.stream = null
	for voice in game.get("sfx_players"):
		voice.stop()
		voice.stream = null
	game.get("sfx_stream_cache").clear()
	game.get("enemies").clear()
	enemies.clear()
	music = null
	game.queue_free()
	await process_frame
	await process_frame
	# An uncapped headless frame can last less than a millisecond; let deferred
	# renderer/resource releases complete, then leave this coroutine's scope.
	await create_timer(0.20).timeout
	call_deferred("_finish_success")

func _finish_success() -> void:
	quit(0)
