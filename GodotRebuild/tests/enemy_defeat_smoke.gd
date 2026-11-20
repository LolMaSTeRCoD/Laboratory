extends SceneTree
## Production defeat regression. Cheap geometry and a manual death clip replace
## imported art; damage, impact attribution, corpse management and audio use the
## real game methods. Run with --headless --audio-driver Dummy.

const Defeat = preload("res://scripts/enemy_defeat_effects.gd")

class FlightsHarness extends Node3D:
	func acquire_flight(_hero: int) -> Node3D:
		var flight := Node3D.new()
		add_child(flight)
		return flight
	func release_flight(flight: Node3D) -> void:
		if is_instance_valid(flight): flight.queue_free()
	func impact(_hero: int, _point: Vector3) -> void: pass
	func tick(_delta: float) -> void: pass

class GameHarness extends "res://scripts/game.gd":
	func _ready() -> void:
		set_process(false)
		rng.seed = 20261120
		presentation_rng.seed = 91721
		for actor_name in ["terrain_root","tower_root","enemy_root","bolt_root"]:
			var actor := Node3D.new()
			set(actor_name,actor)
			add_child(actor)
		magic_effects = FlightsHarness.new()
		add_child(magic_effects)
		defeat_effects = Defeat.new()
		add_child(defeat_effects)
		status_label = Label.new()
		selection_label = Label.new()
		start_button = Button.new()
		pause_button = Button.new()
		upgrade_button = Button.new()
		sell_button = Button.new()
		aura_damage_button = Button.new()
		aura_speed_button = Button.new()
		for control in [status_label,selection_label,start_button,pause_button,upgrade_button,sell_button,aura_damage_button,aura_speed_button]:
			add_child(control)
		camera = Camera3D.new()
		add_child(camera)
		camera.position = Vector3(0,18,18)
		camera.look_at(Vector3.ZERO,Vector3.UP)
		camera.make_current()
		route_points = PackedVector3Array([Vector3.ZERO,Vector3(1000,0,0)])
		route_lengths = PackedFloat32Array([0,1000])
		route_length = 1000.0
	func _exit_tree() -> void: pass
	func _initial_tower_models_ready() -> bool: return true
	func _poll_tower_model_loading() -> void: pass
	func _poll_enemy_model_loading() -> void: pass
	func _animate_background_life(_delta: float) -> void: pass
	func _apply_frame_limit() -> void: pass
	func _update_camera_zoom(_delta: float) -> void: pass

var failures: Array[String] = []
var checks := 0
var body_material := StandardMaterial3D.new()

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("ENEMY_DEFEAT_SMOKE_FAIL: "+message)

func _near(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	_expect(absf(actual-expected) <= tolerance,"%s (actual %.6f, expected %.6f)" % [message,actual,expected])

func _enemy(game: GameHarness, position: Vector3 = Vector3.ZERO, hp: float = 1.0, clip_length: float = 0.9) -> Dictionary:
	var actor := Node3D.new()
	actor.position = position
	game.enemy_root.add_child(actor)
	var model := Node3D.new()
	model.name = "Model"
	actor.add_child(model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.surface_set_material(0,body_material)
	model.add_child(mesh)
	var animator := AnimationPlayer.new()
	actor.add_child(animator)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := Animation.new()
	clip.length = clip_length
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track,NodePath("Model:rotation:x"))
	clip.track_insert_key(track,0.0,0.0)
	clip.track_insert_key(track,clip_length,-1.2)
	var library := AnimationLibrary.new()
	library.add_animation("enemy_orc_Death",clip)
	animator.add_animation_library("",library)
	var bar := game._create_enemy_health_bar(1.8)
	actor.add_child(bar)
	var enemy := {"kind":"orc","name":"Defeat test","node":actor,"model":model,"animator":animator,"bar":bar,"lod":{},"height":1.8,"hp":hp,"max_hp":hp,"armor":0.0,"reward":17,"speed":0.0,"distance":0.0,"phase":0.0,"boss":false,"slow":1.0,"slow_until":0.0,"hit_time":0.0,"animation":"Run","burn_dps":0.0,"burn_until":0.0,"armor_shred":0.0,"shred_until":0.0,"test_mesh":mesh}
	game.enemies.append(enemy)
	return enemy

func _tower(game: GameHarness, kind: int, level: int = 4) -> Dictionary:
	var actor := Node3D.new()
	actor.position = Vector3(-4,0,0)
	game.tower_root.add_child(actor)
	var tower := {"type":kind,"level":level,"node":actor,"damage":100.0,"range":8.0,"detect_range":10.0,"rate":1.0,"cooldown":0.0,"animator":null,"attack_clip":"","idle_clip":"","aura":"","aura_range":10.0,"power":0.0,"lod":{}}
	game.towers.append(tower)
	return tower

func _clear(game: GameHarness) -> void:
	game._clear_enemy_selection()
	game.selected_tower = {}
	game.selected_type = -1
	for bolt in game.bolts.duplicate(): game._release_bolt(bolt)
	for enemy in game.enemies:
		if is_instance_valid(enemy.node): enemy.node.queue_free()
	game.enemies.clear()
	for tower in game.towers:
		if is_instance_valid(tower.node): tower.node.queue_free()
	game.towers.clear()
	game._clear_enemy_death_visuals()
	game.clock = 0.0
	game.gold = 0
	game.paused = false
	game.game_speed = 1.0
	game.wave_running = false
	game.stage_ready = false
	game.game_over = false
	game.arena = 0
	game.wave = 0

func _direct_causes(game: GameHarness) -> void:
	for cause in [{"kind":0},{"kind":1},{"kind":2},{"kind":3},{"kind":4},{"kind":5},{"kind":-1},{"kind":4,"freeze":true}]:
		var expected_style := 7 if cause.get("freeze",false) else 6 if cause.kind < 0 else int(cause.kind)
		var target := _enemy(game)
		game._select_enemy(0)
		game._damage_enemy(target,100.0,0.0,true,cause)
		var label := "style %d" % expected_style
		_expect(game.enemies.is_empty() and game.gold == 17,label+" removes its combat target and awards gold immediately")
		_expect(game.selected_enemy.is_empty() and not target.selection_ring.visible,label+" clears selected target")
		_expect(not target.bar.visible,label+" hides its health bar")
		_expect(game.enemy_death_visuals.size() == 1,label+" retains exactly one corpse")
		if game.enemy_death_visuals.is_empty():
			_clear(game)
			continue
		var death: Dictionary = game.enemy_death_visuals[0]
		_expect(int(death.style) == expected_style,label+" uses fatal cause")
		_expect(target.node.is_inside_tree() and not target.node.is_queued_for_deletion(),label+" retains body after combat removal")
		_expect(target.animator.assigned_animation == "enemy_orc_Death" and target.animator.is_playing(),label+" starts the real AnimationPlayer death clip")
		_expect(not target.animator.get_animation("enemy_orc_Death").loop_mode,label+" death animation does not loop")
		_expect(float(death.duration) > 0.9 and float(death.fade_start) < float(death.duration),label+" reserves a visible fade interval after collapse")
		_near(float(target.test_mesh.get_instance_shader_parameter("defeat_fade")),0.0,label+" starts fully visible")
		_near(game._damage_enemy(target,100.0),0.0,label+" rejects repeated damage")
		game._kill_enemy(target)
		_expect(game.gold == 17 and game.enemy_death_visuals.size() == 1,label+" rejects repeated rewards and corpse creation")
		target.animator.advance(0.45)
		_expect(target.model.rotation.x < -0.1,label+" collapse clip advances its pose")
		game._update_death_visuals(0.20)
		_expect(not target.node.is_queued_for_deletion() and game.enemy_death_visuals.size() == 1,label+" keeps its body during collapse")
		var middle := lerpf(float(death.fade_start),float(death.duration),0.5)
		game._update_death_visuals(middle-float(death.age))
		var fade := float(target.test_mesh.get_instance_shader_parameter("defeat_fade"))
		_expect(fade > 0.0 and fade < 1.0,label+" reaches a partial dissolve before release")
		game._update_death_visuals(float(death.time_left)-0.001)
		_expect(game.enemy_death_visuals.size() == 1 and not target.node.is_queued_for_deletion(),label+" survives until the complete presentation deadline")
		game._update_death_visuals(0.002)
		_expect(game.enemy_death_visuals.is_empty() and target.node.is_queued_for_deletion(),label+" releases the body after its fade")
		_expect(int(game.defeat_effects.debug_counts().active_bursts) == 0,label+" releases active fragments")
		_clear(game)
	var neutral := _enemy(game)
	game._damage_enemy(neutral,100.0)
	_expect(int(game.enemy_death_visuals[0].style) == 6,"legacy damage call with no cause remains a neutral death")
	_clear(game)

func _projectile_and_dot_causes(game: GameHarness) -> void:
	var wind := _tower(game,1)
	for index in range(4): _enemy(game,Vector3(index*1.5,0,0))
	game._fire_bolt(wind,game.enemies[0],100.0)
	for hop in range(4): game._update_bolts(1.0)
	_expect(game.enemies.is_empty() and game.enemy_death_visuals.size() == 4,"production wind chain defeats all four targets")
	for death in game.enemy_death_visuals:
		_expect(int(death.style) == 1 and death.direction.x > 0.0,"each production chain hit retains wind cause and incoming direction")
	_clear(game)
	for kind in [2,5]:
		var caster := _tower(game,kind)
		var primary := _enemy(game)
		_enemy(game,Vector3(1,0,0))
		game._fire_bolt(caster,primary,100.0)
		game._update_bolts(1.0)
		_expect(game.enemies.is_empty() and game.enemy_death_visuals.size() == 2,"production type %d splash defeats primary and neighbour" % kind)
		for death in game.enemy_death_visuals:
			_expect(int(death.style) == kind,"production type %d splash propagates cause to every victim" % kind)
		_clear(game)
	var frozen := _enemy(game)
	var water := _tower(game,4)
	game._fire_bolt(water,frozen,100.0)
	game._update_bolts(1.0)
	_expect(int(game.enemy_death_visuals[0].style) == 7,"production high rank Noelle impact selects ice")
	_clear(game)
	var burning := _enemy(game,Vector3.ZERO,300.0)
	var strong := {"type":2,"damage":100.0,"burn":true,"impact_direction":Vector3.RIGHT}
	var weak := {"type":2,"damage":10.0,"burn":true,"impact_direction":Vector3.LEFT}
	game._hit_with_bolt(strong,burning,1.0)
	game._hit_with_bolt(weak,burning,1.0)
	game._hit_with_bolt({"type":4,"damage":1.0,"freeze":false,"slow":0.55,"impact_direction":Vector3.BACK},burning,1.0)
	_expect(burning.burn_cause.kind == 2 and burning.burn_cause.direction == Vector3.RIGHT,"weaker burn and later nonfatal hit preserve the strongest DOT source")
	_near(float(burning.burn_dps),10.0,"DOT retains strongest damage rate")
	burning.hp = 0.5
	game.clock = 0.1
	game._update_enemy(burning,0.1)
	_expect(game.enemies.is_empty() and int(game.enemy_death_visuals[0].style) == 2,"actual DOT kill uses fire instead of the last nonfatal water impact")
	_expect(game.enemy_death_visuals[0].direction == Vector3.RIGHT,"actual DOT kill uses strongest burn direction")
	_clear(game)

func _wind_and_pause(game: GameHarness) -> void:
	game.enemy_root.rotation.y = 0.65
	var target := _enemy(game,Vector3(3,0,4))
	target.node.rotation.y = 1.1
	target.distance = 37.0
	var route := game.route_points.duplicate()
	var origin: Vector3 = target.node.global_position
	var original_basis: Basis = target.node.global_basis
	game._damage_enemy(target,100.0,0.0,true,{"kind":1,"direction":Vector3(0.0,12.0,5.0)})
	var death: Dictionary = game.enemy_death_visuals[0]
	game._update_death_visuals(0.35)
	var offset: Vector3 = target.node.global_position-origin
	_expect(offset.z > 0.2 and absf(offset.x) < 0.0001,"wind impulse follows incoming world direction under rotated parent")
	_expect(target.node.global_basis.is_equal_approx(original_basis),"wind retains body scale and heading instead of rigid pitching")
	_near(float(target.distance),37.0,"visual impulse never advances combat route distance")
	_expect(game.route_points == route,"visual impulse never mutates route points")
	var age := float(death.age)
	var position: Vector3 = target.node.global_position
	var fade := float(target.test_mesh.get_instance_shader_parameter("defeat_fade"))
	game._update_death_visuals(0.0)
	_near(float(death.age),age,"zero elapsed time freezes corpse clock")
	game.paused = true
	game._sync_animation_speeds()
	game._process(0.05)
	_near(float(death.age),age,"production pause freezes corpse clock")
	_expect(target.node.global_position.is_equal_approx(position),"production pause freezes wind impulse")
	_near(float(target.test_mesh.get_instance_shader_parameter("defeat_fade")),fade,"production pause freezes dissolve")
	_near(float(target.animator.speed_scale),0.0,"production pause freezes collapse animation")
	game.paused = false
	game.game_speed = 2.0
	game._sync_animation_speeds()
	game._process(0.05)
	_near(float(death.age),age+0.1,"production resume advances corpse at selected game speed")
	_near(float(target.animator.speed_scale),2.0,"resume restores selected animation speed")
	_clear(game)
	game.enemy_root.rotation.y = 0.0

func _shared_materials_and_capacity(game: GameHarness) -> void:
	var first := _enemy(game)
	var second := _enemy(game,Vector3(2,0,0))
	game._damage_enemy(first,100.0,0.0,true,{"kind":2})
	game._damage_enemy(second,100.0,0.0,true,{"kind":4,"freeze":true})
	var a: Dictionary = game.enemy_death_visuals[0]
	var b: Dictionary = game.enemy_death_visuals[1]
	_expect(first.test_mesh.material_override == second.test_mesh.material_override,"corpses using the same source share a dissolve material resource")
	_expect(first.test_mesh.material_override is ShaderMaterial,"dissolve uses a shader material")
	_expect(first.test_mesh.material_override.get_shader_parameter("base_color") == body_material.albedo_color,"shared dissolve preserves source color")
	_near(float(first.test_mesh.material_override.get_shader_parameter("base_roughness")),body_material.roughness,"shared dissolve preserves source roughness")
	_near(float(first.test_mesh.get_instance_shader_parameter("defeat_style")),2.0,"first corpse has fire instance style")
	_near(float(second.test_mesh.get_instance_shader_parameter("defeat_style")),7.0,"second corpse has ice instance style")
	game.defeat_effects.advance(a,lerpf(float(a.fade_start),float(a.duration),0.5))
	_expect(float(first.test_mesh.get_instance_shader_parameter("defeat_fade")) > 0.0,"advancing one corpse changes its dissolve")
	_near(float(second.test_mesh.get_instance_shader_parameter("defeat_fade")),0.0,"advancing one corpse leaves another instance fully visible")
	_near(float(b.age),0.0,"advancing one corpse leaves the other's age unchanged")
	_expect(first.test_mesh.get_instance_shader_parameter("defeat_seed") != second.test_mesh.get_instance_shader_parameter("defeat_seed"),"simultaneous corpses have isolated noise seeds")
	_clear(game)
	var first_actor: Node3D
	for index in range(Defeat.MAX_CORPSES+12):
		var target := _enemy(game,Vector3(index,0,0))
		if index == 0: first_actor = target.node
		game._damage_enemy(target,100.0,0.0,true,{"kind":index%6})
		var counts: Dictionary = game.defeat_effects.debug_counts()
		_expect(game.enemy_death_visuals.size() <= Defeat.MAX_CORPSES,"corpse capacity holds during burst kill %d" % index)
		_expect(int(counts.active_bursts) <= Defeat.MAX_BURSTS,"fragment capacity holds during burst kill %d" % index)
	_expect(game.enemy_death_visuals.size() == Defeat.MAX_CORPSES,"overload retains the configured maximum corpses")
	_expect(first_actor.is_queued_for_deletion(),"overload releases the oldest corpse")
	_expect(game.enemies.is_empty() and game.gold == 17*(Defeat.MAX_CORPSES+12),"presentation capacity never drops a reward or retains combat enemies")
	_clear(game)
	var counts: Dictionary = game.defeat_effects.debug_counts()
	_expect(int(counts.active_bursts) == 0,"clearing all corpses releases every active burst")
	_expect(int(counts.pooled_bursts) <= Defeat.MAX_FREE_BURSTS,"clearing retains only the bounded free pool")
	_expect(int(counts.material_cache) == 1,"a common source material does not create per-death resources")
	game._clear_enemy_death_visuals()
	_expect(int(game.defeat_effects.debug_counts().active_bursts) == 0,"repeated corpse cleanup remains harmless")
	var pooled := int(counts.pooled_bursts)
	var reuse := _enemy(game)
	game._damage_enemy(reuse,100.0)
	_expect(int(game.defeat_effects.debug_counts().pooled_bursts) == pooled-1,"new corpse reuses a pooled burst")
	game._update_death_visuals(20.0)
	_expect(game.enemy_death_visuals.is_empty() and int(game.defeat_effects.debug_counts().active_bursts) == 0,"a long elapsed step releases completed corpse and active FX")
	_clear(game)

func _stop_voices(game: GameHarness) -> void:
	for voice in game.sfx_players: voice.stop()

func _playing(game: GameHarness, first: int, count: int) -> int:
	var total := 0
	for index in range(first,first+count):
		if game.sfx_players[index].playing: total += 1
	return total

func _audio_digest(stream: AudioStream) -> String:
	# Exported builds retain the imported stream; the raw res:// MP3 need not
	# exist as a FileAccess file. Compare the audio bytes actually being played.
	if not stream is AudioStreamMP3: return ""
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update((stream as AudioStreamMP3).data)
	return digest.finish().hex_encode()

func _audio(game: GameHarness) -> void:
	game._build_sfx()
	_expect(game.sfx_players.size() == 16,"production SFX builder creates sixteen bounded voices")
	_expect(game.ATTACK_VOICES == 10 and game.DEATH_VOICES == 6,"production SFX pools reserve ten attack and six death voices")
	var variants := 0
	for kind in game.DEATH_SFX_VARIANTS:
		var digests: Dictionary = {_audio_digest(game.sfx_stream_cache[game.DEATH_SFX[kind]]):true}
		for path in game.DEATH_SFX_VARIANTS[kind]:
			variants += 1
			_expect(game.sfx_stream_cache.has(path) and game.sfx_stream_cache[path].get_length() > 0.1,"death variant is a real loaded audio resource: "+path)
			var digest := _audio_digest(game.sfx_stream_cache.get(path) as AudioStream)
			_expect(not digest.is_empty() and not digests.has(digest),"death variant differs from its other takes: "+path)
			digests[digest] = true
	_expect(variants == 4,"four additional death takes are available")
	var silence := AudioStreamWAV.new()
	silence.format = AudioStreamWAV.FORMAT_16_BITS
	silence.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050*2*4)
	silence.data = samples
	game.sfx_stream_cache["defeat-test"] = silence
	var combat_rng_state := game.rng.state
	var cosmetic_rng_state := game.presentation_rng.state
	for index in range(10):
		_expect(game._try_play_sfx("defeat-test",Vector3(index,0,0)),"attack voice %d can start" % index)
	_expect(_playing(game,0,10) == 10 and _playing(game,10,6) == 0,"attack sounds occupy only their reserved pool")
	var pitches: Array[float] = []
	for voice in game.sfx_players: pitches.append(voice.pitch_scale)
	_expect(not game._try_play_sfx("defeat-test",Vector3(100,0,0)),"saturated attacks return false instead of stealing a voice")
	for index in range(10):
		_near(game.sfx_players[index].global_position.x,float(index),"attack saturation preserves existing voice %d position" % index)
		_near(game.sfx_players[index].pitch_scale,pitches[index],"attack saturation preserves existing voice %d pitch" % index)
	for index in range(6):
		_expect(game._try_play_sfx("defeat-test",Vector3(index,0,0),true),"death voice %d starts while attack pool is full" % index)
	_expect(_playing(game,10,6) == 6,"death sounds occupy the reserved death pool")
	_expect(not game._try_play_sfx("defeat-test",Vector3.ZERO,true),"saturated death pool returns false without stealing")
	_expect(game.rng.state == combat_rng_state,"audio selection and pitch never consume gameplay RNG")
	_expect(game.presentation_rng.state != cosmetic_rng_state,"audio pitch uses the separate presentation RNG")
	for index in range(10): game.sfx_players[index].stop()
	game._play_sfx("defeat-test",Vector3.ZERO)
	_expect(_playing(game,0,10) == 1 and _playing(game,10,6) == 6,"legacy void SFX API still plays with death pool saturated")
	_stop_voices(game)
	game.sfx_volume = 0.0
	_expect(not game._try_play_sfx("defeat-test",Vector3.ZERO,true),"muted SFX does not start a voice")
	game.sfx_volume = 28.0
	_expect(not game._try_play_sfx("missing-resource",Vector3.ZERO,true),"missing SFX fails without starting a voice")
	for kind in game.DEATH_SFX_VARIANTS:
		var choices: Array = [game.DEATH_SFX[kind]]
		choices.append_array(game.DEATH_SFX_VARIANTS[kind])
		game.death_sound_variants.erase(kind)
		for index in range(choices.size()+1):
			_stop_voices(game)
			game.last_death_sound = -100.0
			game.death_sound_times[kind] = -100.0
			game._play_enemy_death_sound(kind,Vector3.ZERO)
			var expected: AudioStream = game.sfx_stream_cache[choices[index%choices.size()]]
			var found := false
			for voice_index in range(10,16):
				if game.sfx_players[voice_index].playing and game.sfx_players[voice_index].stream == expected: found = true
			_expect(found,"production %s death cycles variant %d and wraps" % [kind,index])
	_stop_voices(game)

func _run() -> void:
	body_material.albedo_color = Color(0.42,0.61,0.37)
	body_material.roughness = 0.43
	var game := GameHarness.new()
	root.add_child(game)
	await process_frame
	_clear(game)
	_direct_causes(game)
	_projectile_and_dot_causes(game)
	_wind_and_pause(game)
	_shared_materials_and_capacity(game)
	await process_frame
	_expect(game.defeat_effects.get_child_count() <= Defeat.MAX_FREE_BURSTS,"released fragment nodes leave only the bounded pool after deferred deletion")
	_audio(game)
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("ENEMY_DEFEAT_SMOKE_OK: %d checks; eight causes, direct/chain/splash/DOT attribution, once-only economy, articulated clip/fade, wind, pause/resume, bounded pooling, shared materials and isolated uniforms, real audio takes and reserved non-stealing voices" % checks)
		quit(0)
	else:
		print("ENEMY_DEFEAT_SMOKE_FAILED: %d / %d checks failed" % [failures.size(),checks])
		quit(1)
