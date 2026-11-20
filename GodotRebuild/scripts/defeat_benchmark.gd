extends Node
## Opt-in native EXE visual/renderer QA. No normal game UI entry point.
var game: Node3D
var output := ""
var report: Dictionary = {}
var serial := 0
var labels: Array[Node3D] = []
var mute_before := false
var battle_stress := false
var lod_clock := 0.0

func start(subject: Node3D) -> void:
	game = subject
	output = ProjectSettings.globalize_path("user://Benchmarks/defeat-render.json")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--benchmark-output="): output = argument.trim_prefix("--benchmark-output=")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	call_deferred("_run")

func _run() -> void:
	var deadline := Time.get_ticks_msec()+60000
	while not game._initial_tower_models_ready() or not game._enemy_models_ready():
		if Time.get_ticks_msec()>deadline:
			push_error("DEFEAT_BENCHMARK_FAIL: model loading timeout")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	game.set_process(false)
	game.paused = false
	game.game_speed = 1.0
	game.menu_root.hide()
	game.terrain_root.hide()
	var bus := AudioServer.get_bus_index("SFX")
	mute_before = AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus,true)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(80,80)
	floor.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color(0.24,0.29,0.23); material.roughness=0.95
	floor.material_override = material
	game.add_child(floor)
	game.camera_target = Vector3(3.0,0,0)
	game.camera_yaw = 0.0
	game.camera_pitch = deg_to_rad(55.0)
	game.camera_size = 17.0
	game.camera_zoom_active = false
	game._update_camera()
	report = {"build_version":ProjectSettings.get_setting("application/config/version"),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"engine_max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"showcase":[],"stress":{},
		"method":"Native standalone renderer: forest,18 towers,100 live enemies with production combat ticks plus48 slow-motion corpses/24 instanced bursts. Geometry LOD with full animation sampling; monotonic wall-frame samples and GPU timestamps; screenshots excluded. Synthetic sustained death stress, not campaign throughput."}
	var names := ["Антимагия","Ветер","Огонь","Нити","Вода","Лёд","Хлопок","Без магии"]
	for i in range(8):
		var position := Vector3((i%4-1.5)*4.0,0.035,(floorf(float(i)/4.0)-0.5)*6.0)
		_spawn("orc",position,i)
		var label := Label3D.new(); label.text=names[i]; label.font_size=48; label.pixel_size=0.012
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		game.add_child(label); label.position=position+Vector3.UP*3.2; labels.append(label)
	var elapsed := 0.0
	for moment in [0.30,0.95,1.55,2.35]:
		while elapsed+0.0001 < moment:
			var dt := minf(1.0/60.0,moment-elapsed)
			_step(dt); elapsed+=dt
			await get_tree().process_frame
		report.showcase.append({"time":moment,"image":await _capture("death-%03d.png"%roundi(moment*100)),"corpses":game.enemy_death_visuals.size(),"effects":game.defeat_effects.debug_counts()})
	for label in labels: label.queue_free()
	labels.clear()
	var views := [] if OS.get_cmdline_user_args().has("--defeat-preview-only") else ["far","near"]
	if not views.is_empty():
		floor.hide()
		game.terrain_root.show()
		var battle: Node = load("res://scripts/render_benchmark.gd").new()
		battle.game = game
		if not battle._populate_stress_scene():
			push_error("DEFEAT_BENCHMARK_FAIL: cannot create battle background")
			battle.free(); get_tree().quit(1); return
		battle.free()
		battle_stress = true
		game.camera_target = game._camera_fit_center()
	for view in views:
		game._clear_enemy_death_visuals()
		game.camera_size = game._camera_max_size() if view=="far" else 16.0
		game._update_camera()
		for i in range(48):
			_spawn(str(game.ENEMY_KINDS[i%game.ENEMY_KINDS.size()]),game.camera_target+Vector3((i%8-3.5)*3.0,0.035,(floorf(float(i)/8.0)-2.5)*3.5),i%8)
		for warmup in range(90):
			_step(1.0/600.0)
			await get_tree().process_frame
		var frames: Array[float] = []; var gpu_times: Array[float] = []; var cpu_times: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in range(300):
			var began := Time.get_ticks_usec()
			_step(1.0/600.0)
			cpu_times.append(float(Time.get_ticks_usec()-began)/1000.0)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now-last)/1000.0); last=now
			gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		var frame_stats := _stats(frames)
		report.stress[view] = {"frames":300,"fps_mean":1000.0/float(frame_stats.mean),"frame_ms":frame_stats,"gpu_ms":_stats(gpu_times),"step_cpu_ms":_stats(cpu_times),
			"corpses":game.enemy_death_visuals.size(),"live_enemies":game.enemies.size(),"towers":game.towers.size(),"effects":game.defeat_effects.debug_counts(),"camera_size":game.camera_size,"image":await _capture("death-stress-"+view+".png")}
	game._update_death_visuals(5.0)
	await get_tree().process_frame
	report.final_counts = {"corpses":game.enemy_death_visuals.size(),"effects":game.defeat_effects.debug_counts()}
	report.passed = game.enemy_death_visuals.is_empty() and game.defeat_effects.debug_counts().active_bursts==0
	AudioServer.set_bus_mute(bus,mute_before)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DEFEAT_BENCHMARK_OK: "+output if report.passed else "DEFEAT_BENCHMARK_FAIL: resources remain")
	get_tree().quit(0 if report.passed else 1)

func _spawn(kind: String, position: Vector3, style: int) -> void:
	var enemy: Dictionary = game._make_enemy(kind)
	game.enemy_root.add_child(enemy.node)
	enemy.node.position = position
	enemy.hp=1.0; enemy.max_hp=1.0; enemy.reward=0
	enemy.boss=kind=="boss_troll"
	if enemy.animator != null:
		enemy.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		enemy.animator.advance(0.25)
	game.enemies.append(enemy)
	var source_kind: int = [0,1,2,3,4,4,5,-1][style]
	game._damage_enemy(enemy,100000.0,1.0,false,{"kind":source_kind,"direction":Vector3(1,0,0.25),"freeze":style==5})
	serial+=1

func _step(dt: float) -> void:
	if battle_stress:
		var battle_dt := 1.0/60.0
		game.clock += battle_dt
		for enemy in game.enemies:
			if float(enemy.distance)>float(game.route_length)-3.0: enemy.distance=0.0
			game._update_enemy(enemy,battle_dt)
		game._update_towers(battle_dt)
		game._update_bolts(battle_dt)
		game.magic_effects.tick(battle_dt)
	lod_clock += 1.0/60.0
	var update_lod := lod_clock>=0.12
	if update_lod:
		lod_clock=0.0
		for actors in [game.towers,game.enemies,game.enemy_death_visuals]:
			for actor in actors:
				var lod: Dictionary = actor.get("lod",{})
				if lod.is_empty(): continue
				var animator: Variant = lod.get("animator")
				lod.animator=null
				game.CharacterLOD.update(lod,game.camera,false)
				lod.animator=animator
	for death in game.enemy_death_visuals:
		if death.animator != null: death.animator.advance(dt)
	game._update_death_visuals(dt)

func _capture(name: String) -> String:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	report.resolution = {"width":image.get_width(),"height":image.get_height()}
	var path := output.get_base_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	image.save_png(path)
	return path

func _stats(samples: Array[float]) -> Dictionary:
	var ordered := samples.duplicate(); ordered.sort()
	var total := 0.0
	for value in ordered: total+=value
	return {"mean":total/ordered.size(),"p50":ordered[floori(ordered.size()*0.5)],"p95":ordered[mini(ordered.size()-1,roundi(ordered.size()*0.95))],"max":ordered[-1]}
