extends Node
## Opt-in executable benchmark: KDTD.exe -- --render-benchmark
## Measures real presented-frame intervals and CPU process time. No GPU timer claim.

const OUTPUT := "res://Builds/render-benchmark.json"
const WARMUP_FRAMES := 180
const SAMPLE_FRAMES := 300
var sample_frames := SAMPLE_FRAMES
# Editor/source diagnostics follow the project; packaged games use writable user data.
var output_path := ProjectSettings.globalize_path(OUTPUT if OS.has_feature("editor") else "user://Benchmarks/render-benchmark.json")
var phase_events: Array[Dictionary] = []
var game: Node3D
var phase := "loading"
var phase_frames := 0
var samples: Array[Dictionary] = []
var result: Dictionary = {}
var previous_frame_us := 0
var errors: Array[String] = []

func start(subject: Node3D) -> void:
	game = subject
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var args:=OS.get_cmdline_user_args()
	sample_frames=1200 if args.has("--power-profile") else SAMPLE_FRAMES
	for argument in args:
		if argument.begins_with("--benchmark-output="):
			output_path=argument.trim_prefix("--benchmark-output=")
	_phase_event("loading")
	call_deferred("_prepare")

func _phase_event(label: String) -> void:
	var event: Dictionary={"phase":label,"unix_time":Time.get_unix_time_from_system(),"utc":Time.get_datetime_string_from_system(true,true),"monotonic_ms":Time.get_ticks_msec(),"engine_max_fps":Engine.max_fps,"character_lod":_lod_counters()}
	phase_events.append(event)
	print("RENDER_BENCHMARK_PHASE: "+JSON.stringify(event))

func _set_phase(label: String) -> void:
	phase=label
	phase_frames=0
	_phase_event(label)

func _lod_counters() -> Dictionary:
	var counts: Dictionary={"high":0,"compact":0,"missing":0,"source_vertices":0,"active_mesh_vertices":0}
	if game==null:return counts
	for actors in [game.towers,game.enemies,game.enemy_death_visuals]:
		for actor in actors:
			var record: Dictionary=actor.get("lod",{})
			if record.is_empty() or not is_instance_valid(record.get("instance")):
				counts.missing+=1
				continue
			var low: bool=record.get("is_low",false)
			counts["compact" if low else "high"]+=1
			var original: Mesh=record.high
			var submitted: Mesh=record.instance.mesh
			for surface in range(original.get_surface_count()):counts.source_vertices+=original.surface_get_array_len(surface)
			for surface in range(submitted.get_surface_count()):counts.active_mesh_vertices+=submitted.surface_get_array_len(surface)
	return counts

func _prepare() -> void:
	var deadline := Time.get_ticks_msec()+60000
	while not game._initial_tower_models_ready() or not game._enemy_models_ready():
		if Time.get_ticks_msec() > deadline:
			_fail("model_loading_timeout")
			return
		await get_tree().process_frame
	game.menu_root.hide()
	game.gold = 100000
	game.paused = false
	game.wave = 10
	game.spawn_left = 0
	game.wave_running = false
	game.game_speed = 1.0
	game.camera_zoom_active = false
	if not _populate_stress_scene():
		_fail("could_not_place_18_legal_towers")
		return
	game.status_label.text = "Измерение рендеринга: общий вид, затем приближение. Игра закроется после замера."
	game._refresh_hud()
	game.camera_size = game._camera_max_size()
	game.camera_target = game._camera_fit_center()
	game._update_camera()
	var rect: Rect2 = game.get_viewport().get_visible_rect()
	var target_size := game.get_viewport().get_texture().get_size()
	result = {
		"schema_version":4,"timestamp":Time.get_datetime_string_from_system(),
		"build_version":ProjectSettings.get_setting("application/config/version","unknown"),
		"renderer":RenderingServer.get_current_rendering_method(),
		"gpu":{"name":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"api":RenderingServer.get_video_adapter_api_version()},
		"engine_max_fps":Engine.max_fps,"vsync_mode":DisplayServer.window_get_vsync_mode(),
		"profile_mode":"capped60" if OS.get_cmdline_user_args().has("--benchmark-capped") else "uncapped",
		"power_profile":OS.get_cmdline_user_args().has("--power-profile"),"force_high_detail":game.force_high_detail,
		# A root ViewportTexture.get_size() includes the canvas stretch transform;
		# it is not necessarily the size of the underlying GPU image. Fill the
		# actual output resolution from the post-draw Image readback instead.
		"resolution":{},
		"resolution_source":"post-draw ViewportTexture.get_image() Image dimensions",
		"reported_viewport_texture_size":{"width":target_size.x,"height":target_size.y},
		"ui_reference_size":{"width":rect.size.x,"height":rect.size.y},
		"scene":{"towers":game.towers.size(),"enemies":game.enemies.size()},
		"warmup_frames":WARMUP_FRAMES,"sample_frames_per_view":sample_frames,
		"gpu_frame_time_source":"RenderingServer viewport GPU timestamps; enabled for this benchmark only",
		"measurement_notes":"Frame intervals use monotonic wall time between process callbacks, not smoothed simulation delta. CPU game logic measures only game._process, excluding native animation/rendering jobs and OS CPU utilization. Viewport GPU/CPU render timestamps and frame setup CPU time are recorded. Readback screenshots, the no-load hero showcase and unloaded biome gallery happen outside timing samples. Jungle/winter far stress each independently use 18 legal towers, 100 enemies, 90 warmup and 300 measured intervals. Output Image size, logical UI size, native window size, stretch scale and 3D render scale are recorded separately. VSync/frame caps affect intervals."
	}
	result["display_configuration"] = _display_configuration()
	result.measurement_notes=result.measurement_notes.replace("300 measured intervals","%d measured intervals"%sample_frames)
	_set_phase("warmup")
	phase_frames = 0

func _populate_stress_scene() -> bool:
	game.gold = 100000
	game.paused = false
	game.wave = 10
	game.spawn_left = 0
	game.wave_running = false
	game.game_speed = 1.0
	game.camera_zoom_active = false
	# Spread legal tower foundations along the road, rather than stacking them.
	for index in range(18):
		var distance: float = game.route_length*(float(index)+0.5)/18.0
		var center: Vector3 = game._path_at(distance)
		var direction: Vector3 = (game._path_at(minf(game.route_length,distance+0.5))-center).normalized()
		var side := Vector3(-direction.z,0.0,direction.x)
		var chosen := Vector3.ZERO
		var found := false
		for offset in [4.5,5.8,7.2,8.6,10.0]:
			for sign in [-1.0,1.0]:
				var candidate: Vector3 = center+side*float(offset)*float(sign)
				if game._valid_spot(candidate):
					chosen = candidate
					found = true
					break
			if found: break
		if not found:
			for x in range(-28,29,2):
				for z in range(-19,20,2):
					var candidate := Vector3(x,0,z)
					if game._valid_spot(candidate):
						chosen = candidate
						found = true
						break
				if found: break
		if not found:
			return false
		game._select_type(index%game.HEROES.size())
		game._place_tower(chosen)
	game.selected_tower = {}
	game.selected_type = -1
	game._clear_build_ghost()
	game._sync_tower_selection_visuals()
	for index in range(100):
		_add_enemy(index)
	game.wave_running = true
	game._refresh_hud()
	game._refresh_selection()
	return game.towers.size()==18 and game.enemies.size()==100

func _add_enemy(index: int) -> void:
	var kinds := ["goblin","orc","uruk","warg","troll","nazgul"]
	var enemy: Dictionary = game._make_enemy(kinds[index%kinds.size()])
	enemy.hp = 1000000.0
	enemy.max_hp = enemy.hp
	enemy.reward = 0
	enemy.speed = 4.5 if str(enemy.kind) != "troll" else 3.1
	enemy.distance = game.route_length*float(index%100)/100.0
	enemy.node.position = game._path_at(enemy.distance)
	game.enemies.append(enemy)
	game.enemy_root.add_child(enemy.node)
	if enemy.animator != null:
		enemy.animator.speed_scale = game._enemy_run_animation_speed(enemy)

func _process(delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var elapsed_ms := float(now_us-previous_frame_us)/1000.0 if previous_frame_us>0 else delta*1000.0
	previous_frame_us = now_us
	if phase in ["loading","finished","capturing","showcase_loading"]: return
	if phase == "showcase":
		phase_frames += 1
		if phase_frames < 90: return
		_set_phase("capturing")
		await RenderingServer.frame_post_draw
		var showcase_path := output_path.get_base_dir()+"/final-heroes.png"
		var showcase_image := _capture_png(showcase_path)
		if showcase_image != null:
			result["showcase"] = {
				"screenshot":showcase_path,"output_image_size":_size_dict(showcase_image.get_size()),
				"display_configuration":_display_configuration(),
				"towers":game.towers.size(),"enemies":game.enemies.size(),
				"camera_size":game.camera_size,"camera_pitch_degrees":rad_to_deg(game.camera_pitch),
				"camera_yaw_degrees":rad_to_deg(game.camera_yaw),
				"camera_parameters":_camera_parameters(),
				"included_in_fps_samples":false
			}
		await _capture_biome_gallery()
		_set_phase("finished")
		_save()
		get_tree().quit(0 if errors.is_empty() else 1)
		return
	# Keep population constant even on a slow graphics device or after leaks.
	_wrap_stress_enemies()
	phase_frames += 1
	if phase == "hamlet":
		if phase_frames < 30: return
		_set_phase("capturing")
		await RenderingServer.frame_post_draw
		var image_path := output_path.get_base_dir()+"/final-hamlet.png"
		var image := _capture_png(image_path)
		if image != null:
			result["hamlet"] = {"screenshot":image_path,"output_image_size":_size_dict(image.get_size()),"display_configuration":_display_configuration(),"camera_parameters":_camera_parameters(),"villagers":game.ambient_people.size(),"animals":game.ambient_animals.size()}
		_begin_showcase()
		return
	if phase == "warmup":
		if phase_frames >= WARMUP_FRAMES:
			if OS.get_cmdline_user_args().has("--gpu-isolation"):
				_set_phase("capturing")
				await _run_gpu_isolation()
				return
			_set_phase("far")
			phase_frames = 0
		return
	if phase == "near_warmup":
		if phase_frames >= 90:
			_set_phase("near")
			phase_frames = 0
		return
	samples.append({
		"frame_ms":elapsed_ms,
		"cpu_game_logic_ms":game.last_cpu_game_logic_ms,
		"cpu_lod_animation_ms":game.last_cpu_lod_animation_ms,
		"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
		"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_memory_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
	})
	if phase_frames < sample_frames: return
	var completed_phase := phase
	result[completed_phase] = _summarize()
	_set_phase("capturing")
	# Read the actual game viewport for final-build art QA, after timing samples.
	await RenderingServer.frame_post_draw
	var image_path := output_path.get_base_dir()+"/final-"+completed_phase+".png"
	var captured := _capture_png(image_path)
	if captured != null:
		result[completed_phase]["screenshot"] = image_path
		result[completed_phase]["output_image_size"] = _size_dict(captured.get_size())
		result[completed_phase]["display_configuration"] = _display_configuration()
		if result.resolution.is_empty():
			result.resolution = _size_dict(captured.get_size())
		elif result.resolution != _size_dict(captured.get_size()):
			result["output_resolution_changed_during_benchmark"] = true
	samples.clear()
	phase_frames = 0
	if completed_phase == "far":
		game.camera_size = 14.0
		game.camera_pitch = deg_to_rad(45.0)
		game.camera_yaw = deg_to_rad(25.0)
		game.camera_target = game.towers[8].node.position
		game.camera_target.x += 2.0
		game._update_camera()
		game.status_label.text = "Измерение рендеринга: приближённая камера."
		_set_phase("near_warmup")
	else:
		var hamlet := game.terrain_root.get_node_or_null("RiversideHamlet") as Node3D
		if hamlet != null:
			game.camera_size = 19.0
			game.camera_pitch = deg_to_rad(45.0)
			game.camera_yaw = deg_to_rad(25.0)
			game.camera_target = hamlet.global_position+Vector3(3.0,0.0,2.0)
			game._update_camera()
			_set_phase("hamlet")
		else:
			_begin_showcase()

func _run_gpu_isolation() -> void:
	# Diagnostic-only A/B: production settings are restored before each pass.
	# No settings file is modified and the test process exits on completion.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	result["isolation_vsync_disabled"]=true
	var viewport:=get_viewport()
	var environment: Environment=game.get_world_3d().environment
	var lights:=game.find_children("*","Light3D",true,false)
	var shadow_settings: Array[bool]=[]
	for light in lights: shadow_settings.append(light.shadow_enabled)
	var original_msaa:=viewport.msaa_3d
	var animators: Array[AnimationPlayer]=[]
	var meshes: Array[MeshInstance3D]=[]
	for actors in [game.towers,game.enemies]:
		for actor in actors:
			if actor.get("animator")!=null:animators.append(actor.animator)
			var record: Dictionary=actor.get("lod",{})
			if not record.is_empty():meshes.append(record.instance)
	result["gpu_isolation"]={}
	for variant in ["production","without_ssao","without_shadows","without_msaa","frozen_animation","hidden_character_meshes","without_terrain"]:
		environment.ssao_enabled=variant!="without_ssao"
		viewport.msaa_3d=Viewport.MSAA_DISABLED if variant=="without_msaa" else original_msaa
		for index in range(lights.size()):lights[index].shadow_enabled=shadow_settings[index] and variant!="without_shadows"
		for animator in animators:animator.active=variant!="frozen_animation"
		for mesh in meshes:mesh.visible=variant!="hidden_character_meshes"
		game.terrain_root.visible=variant!="without_terrain"
		_phase_event("isolation_"+variant+"_warmup")
		for frame in range(90):
			_wrap_stress_enemies()
			await get_tree().process_frame
		_phase_event("isolation_"+variant)
		var measured: Array[Dictionary]=[]
		var previous:=Time.get_ticks_usec()
		for frame in range(300):
			_wrap_stress_enemies()
			await get_tree().process_frame
			var now:=Time.get_ticks_usec()
			measured.append({
				"frame_ms":float(now-previous)/1000.0,"cpu_game_logic_ms":game.last_cpu_game_logic_ms,"cpu_lod_animation_ms":game.last_cpu_lod_animation_ms,
				"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()),
				"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()),
				"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),
				"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				"video_memory_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0})
			previous=now
		result.gpu_isolation[variant]=_summarize_samples(measured)
	_set_phase("finished")
	_save()
	get_tree().quit(0)

func _size_dict(value: Variant) -> Dictionary:
	return {"width":int(value.x),"height":int(value.y)}

func _record_error(message: String) -> void:
	errors.append(message)
	push_error("RENDER_BENCHMARK_FAIL: "+message)

func _capture_png(path: String) -> Image:
	# The caller awaits frame_post_draw, outside all measured intervals.
	var image:=get_viewport().get_texture().get_image()
	if image==null or image.is_empty():
		_record_error("empty_viewport_readback: "+path)
		return null
	var directory_error:=DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error!=OK:
		_record_error("capture_directory_failed_%d: %s"%[directory_error,path])
		return null
	var save_error:=image.save_png(path)
	if save_error!=OK:
		_record_error("capture_save_failed_%d: %s"%[save_error,path])
		return null
	return image

func _wrap_stress_enemies() -> void:
	# Reset before the final route metre so benchmarks exercise rendering/combat,
	# not repeated wave completion or base damage. Maintain exactly 100 actors.
	for enemy in game.enemies:
		if float(enemy.distance)>float(game.route_length)-1.0:
			enemy.distance=0.0
			enemy.node.position=game._path_at(0.0)
	while game.enemies.size()<100:
		_add_enemy(game.enemies.size())

func _clear_combat_scene() -> void:
	game.wave_running=false
	game.spawn_left=0
	game.selected_tower={}
	game.selected_type=-1
	game._clear_build_ghost()
	if game.magic_effects!=null:
		game.magic_effects.clear_all()
	else:
		for bolt in game.bolts:
			if is_instance_valid(bolt.node): bolt.node.queue_free()
	game.bolts.clear()
	for enemy in game.enemies:
		if is_instance_valid(enemy.node): enemy.node.queue_free()
	game.enemies.clear()
	game._clear_enemy_death_visuals()
	for tower in game.towers:
		if is_instance_valid(tower.node): tower.node.queue_free()
	game.towers.clear()
	game._refresh_hud()
	game._refresh_selection()
	await get_tree().process_frame

func _capture_biome_stress(profile: Dictionary) -> void:
	var biome_key: String=profile.key
	if not result.has("biome_stress"): result["biome_stress"]={}
	if not _populate_stress_scene():
		_record_error("biome_stress_could_not_place_18_legal_towers: "+biome_key)
		result.biome_stress[biome_key]={"error":"could_not_populate_18_towers_100_enemies","arena":game.arena+1}
		await _clear_combat_scene()
		return
	game.camera_yaw=0.0
	game.camera_pitch=deg_to_rad(55.0)
	game.camera_size=game._camera_max_size()
	game.camera_target=game._camera_fit_center()
	game._update_camera()
	game.status_label.text="Нагрузочный тест биома: %s · 18 башен / 100 противников"%str(profile.name)
	_phase_event("biome_"+biome_key+"_warmup")
	# Main _process remains in capturing phase throughout this coroutine, so it
	# neither repopulates the cleared gallery nor touches the original samples.
	for frame in range(90):
		_wrap_stress_enemies()
		await get_tree().process_frame
	var biome_samples: Array[Dictionary]=[]
	_phase_event("biome_"+biome_key+"_stress")
	var last_us:=Time.get_ticks_usec()
	for frame in range(sample_frames):
		_wrap_stress_enemies()
		await get_tree().process_frame
		var now_us:=Time.get_ticks_usec()
		biome_samples.append({
			"frame_ms":float(now_us-last_us)/1000.0,
			"cpu_game_logic_ms":game.last_cpu_game_logic_ms,
			"cpu_lod_animation_ms":game.last_cpu_lod_animation_ms,
			"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
			"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
			"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"video_memory_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0})
		last_us=now_us
	var metrics:=_summarize_samples(biome_samples)
	metrics["arena"]=game.arena+1
	metrics["biome"]=biome_key
	metrics["season"]=profile.season
	metrics["weather"]=profile.weather
	metrics["warmup_frames"]=90
	metrics["sample_frames"]=biome_samples.size()
	metrics["sampling_signal"]="process_frame to process_frame monotonic wall interval; previous completed game process CPU"
	metrics["included_in_forest_samples"]=false
	result.biome_stress[biome_key]=metrics
	_phase_event("biome_"+biome_key+"_capture")
	# Image readback occurs after the final sample and before actor teardown.
	await RenderingServer.frame_post_draw
	var path:=output_path.get_base_dir()+"/stress-%s.png"%biome_key
	var image:=_capture_png(path)
	if image!=null:
		metrics["screenshot"]=path
		metrics["output_image_size"]=_size_dict(image.get_size())
		metrics["display_configuration"]=_display_configuration()
	await _clear_combat_scene()

func _capture_biome_gallery() -> void:
	# Native screenshots for shader/season QA, outside all FPS samples.
	_phase_event("gallery_loading")
	await _clear_combat_scene()
	var gallery: Array[Dictionary] = []
	for index in [0,1,2,3,4,5,11,13]:
		for child in game.terrain_root.get_children():
			game.terrain_root.remove_child(child)
			child.queue_free()
		await get_tree().process_frame
		game.arena = index
		game.wave = 0
		game.camera_yaw = 0.0
		game.camera_pitch = deg_to_rad(55.0)
		game._build_arena()
		game.camera_size = game._camera_max_size()
		game.camera_target = game._camera_fit_center()
		game._update_camera()
		game._refresh_hud()
		var profile: Dictionary = game.world_art.profile
		_phase_event("gallery_"+str(profile.key))
		game.status_label.text = "Проверка биома: "+str(profile.name)
		for frame in range(45): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := output_path.get_base_dir()+"/biome-%d-%s.png"%[index+1,str(profile.key)]
		var captured := _capture_png(path)
		var record := {"arena":index+1,"biome":profile.key,"season":profile.season,"water":profile.water,"weather":profile.weather,"included_in_fps_samples":false}
		if captured!=null:
			record["screenshot"]=path
			record["output_image_size"]=_size_dict(captured.get_size())
			record["camera_parameters"]=_camera_parameters()
		if index in [2,4]:
			await _capture_biome_stress(profile)
			# Village close-ups must return to unloaded, unselected presentation.
			game.wave=0
			game._refresh_hud()
			game._refresh_selection()
			game.status_label.text="Проверка биома: "+str(profile.name)
		if index in [4,5]:
			var hamlet := game.terrain_root.get_node_or_null("RiversideHamlet") as Node3D
			if hamlet != null:
				game.camera_pitch = deg_to_rad(45.0)
				game.camera_yaw = deg_to_rad(25.0)
				game.camera_size = 19.0
				game.camera_target = hamlet.global_position+Vector3(3,0,2)
				game._update_camera()
				for frame in range(30): await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var detail_path := output_path.get_base_dir()+"/biome-%d-%s-village.png"%[index+1,str(profile.key)]
				var detail_image:=_capture_png(detail_path)
				if detail_image!=null: record["village_screenshot"] = detail_path
		gallery.append(record)
	result["biome_gallery"] = gallery

func _camera_parameters() -> Dictionary:
	return {
		"projection":game.camera.projection,"orthographic_size":game.camera_size,
		"pitch_degrees":rad_to_deg(game.camera_pitch),"yaw_degrees":rad_to_deg(game.camera_yaw),
		"target":{"x":game.camera_target.x,"y":game.camera_target.y,"z":game.camera_target.z},
		"position":{"x":game.camera.position.x,"y":game.camera.position.y,"z":game.camera.position.z},
		"near_clip":game.camera.near,"far_clip":game.camera.far
	}

func _display_configuration() -> Dictionary:
	var viewport := get_viewport()
	var stretch := viewport.get_stretch_transform().get_scale()
	return {
		"logical_ui_size":_size_dict(viewport.get_visible_rect().size),
		"native_window_client_size":_size_dict(DisplayServer.window_get_size()),
		"window_node_size":_size_dict(get_window().size),
		"canvas_stretch_scale":{"x":stretch.x,"y":stretch.y},
		"render_scale_3d":viewport.scaling_3d_scale,
		"render_scaling_mode_3d":viewport.scaling_3d_mode,
		"content_scale_factor":get_window().content_scale_factor
	}

func _begin_showcase() -> void:
	_set_phase("showcase_loading")
	phase_frames = 0
	game.paused = false
	await _clear_combat_scene()
	var offsets: Array[Vector3] = [Vector3(-2,0,1),Vector3(0,0,1),Vector3(2,0,1),Vector3(-2,0,-1),Vector3(0,0,-1),Vector3(2,0,-1)]
	var chosen := Vector3.ZERO
	var found := false
	var best_distance := INF
	# Use all six legal grass foundations, through the actual placement API.
	for z in range(-16,17,2):
		for x in range(-24,25,2):
			var center := Vector3(x,0,z)
			var legal := true
			for offset in offsets:
				if not game._valid_spot(center+offset):
					legal = false
					break
			if legal and center.length_squared() < best_distance:
				best_distance = center.length_squared()
				chosen = center
				found = true
	if not found:
		result["showcase"] = {"error":"no_legal_six_hero_grass_patch","included_in_fps_samples":false}
		_set_phase("finished")
		_save()
		get_tree().quit(1)
		return
	game.gold = 100000
	for index in range(game.HEROES.size()):
		game._select_type(index)
		game._place_tower(chosen+offsets[index])
	if game.towers.size() != game.HEROES.size():
		_fail("showcase_hero_placement_failed")
		return
	game._select_tower(0)
	game.camera_zoom_active = false
	game.camera_size = 8.0
	game.camera_zoom_goal = 8.0
	game.camera_pitch = deg_to_rad(40.0)
	game.camera_yaw = 0.0
	# Center all six heroes in the usable field rather than placing the last
	# hero behind the right-hand panel. The selected Asta stays on the left.
	game.camera_target = chosen+Vector3.UP+game._camera_fit_center()*(game.camera_size/game._camera_max_size())
	game._update_camera()
	game.status_label.text = "Осмотр шести героев: 3D-модели без боевой нагрузки · выбран Аста."
	game._refresh_hud()
	game._refresh_selection()
	game._sync_animation_speeds()
	phase_frames = 0
	_set_phase("showcase")

func _summarize() -> Dictionary:
	return _summarize_samples(samples)

func _summarize_samples(measured_samples: Array[Dictionary]) -> Dictionary:
	var metrics := {}
	for metric in ["frame_ms","cpu_game_logic_ms","cpu_lod_animation_ms","render_cpu_ms","render_gpu_ms","render_setup_cpu_ms","draw_calls","primitives","objects","video_memory_mib"]:
		var values: Array[float] = []
		var total := 0.0
		for sample in measured_samples:
			var value := float(sample[metric])
			values.append(value)
			total += value
		values.sort()
		metrics[metric] = {"mean":total/float(values.size()),"p50":values[int(ceil(values.size()*0.50))-1],"p95":values[int(ceil(values.size()*0.95))-1],"max":values[-1]}
	metrics["fps_mean"] = 1000.0/maxf(0.001,float(metrics.frame_ms.mean))
	metrics["camera_size"] = game.camera_size
	metrics["camera_parameters"] = _camera_parameters()
	metrics["population"] = {"towers":game.towers.size(),"enemies":game.enemies.size()}
	metrics["character_lod"] = _lod_counters()
	metrics["engine_max_fps"] = Engine.max_fps
	return metrics

func _save() -> void:
	result["phase_events"]=phase_events.duplicate(true)
	if not errors.is_empty(): result["errors"]=errors.duplicate()
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file == null:
		push_error("RENDER_BENCHMARK_FAIL: cannot write " + output_path)
		return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("RENDER_BENCHMARK_OK: "+output_path)
	print(JSON.stringify(result))

func _fail(reason: String) -> void:
	_set_phase("finished")
	# Preserve completed forest measurements if a later QA phase fails.
	result["error"]=reason
	result["timestamp"]=Time.get_datetime_string_from_system()
	_save()
	get_tree().quit(1)
