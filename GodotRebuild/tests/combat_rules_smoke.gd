extends SceneTree
## Production combat regression. Only imported artwork, sound and automatic
## frame processing are replaced; damage, projectiles, DOT, selection, camera
## picking, spawning, economy and wave completion are the real game methods.

const Balance = preload("res://scripts/combat_balance.gd")

class EffectsHarness extends Node3D:
	var impact_count := 0
	var active_flights: Dictionary = {}
	func acquire_flight(_hero: int) -> Node3D:
		var flight := Node3D.new()
		add_child(flight)
		active_flights[flight.get_instance_id()] = flight
		return flight
	func release_flight(flight: Node3D) -> void:
		if is_instance_valid(flight):
			active_flights.erase(flight.get_instance_id())
			flight.queue_free()
	func impact(_hero: int, _point: Vector3) -> void:
		impact_count += 1
	func tick(_delta: float) -> void:
		pass
	func clear_all() -> void:
		for child in get_children(): child.queue_free()
		active_flights.clear()

class GameHarness extends "res://scripts/game.gd":
	func _ready() -> void:
		set_process(false)
		rng.seed = 20261107
		for actor_name in ["terrain_root","tower_root","enemy_root","bolt_root"]:
			var actor := Node3D.new()
			set(actor_name,actor)
			add_child(actor)
		magic_effects = EffectsHarness.new()
		add_child(magic_effects)
		status_label = Label.new()
		selection_label = Label.new()
		start_button = Button.new()
		upgrade_button = Button.new()
		sell_button = Button.new()
		aura_damage_button = Button.new()
		aura_speed_button = Button.new()
		for control in [status_label,selection_label,start_button,upgrade_button,sell_button,aura_damage_button,aura_speed_button]:
			add_child(control)
		camera = Camera3D.new()
		add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 24.0
		camera.position = Vector3(0,18,18)
		camera.look_at(Vector3.ZERO,Vector3.UP)
		camera.make_current()
		route_points = PackedVector3Array([Vector3.ZERO,Vector3(1000,0,0)])
		route_lengths = PackedFloat32Array([0,1000])
		route_length = 1000.0
	func _exit_tree() -> void:
		pass
	func _initial_tower_models_ready() -> bool:
		return true
	func _enemy_models_ready() -> bool:
		return true
	func _play_sfx(_path: String,_position: Vector3) -> void:
		pass
	func _poll_tower_model_loading() -> void:
		pass
	func _poll_enemy_model_loading() -> void:
		pass
	func _animate_background_life(_delta: float) -> void:
		pass
	func _apply_frame_limit() -> void:
		pass
	func _update_camera_zoom(_delta: float) -> void:
		pass
	func _make_enemy(kind: String) -> Dictionary:
		return {"kind":kind,"node":Node3D.new(),"model":null,"animator":null,"bar":null,"lod":{},"height":5.01235 if kind == "boss_troll" else 1.8,"hp":1000.0,"max_hp":1000.0,"armor":0.0,"reward":17,"speed":0.0,"distance":0.0,"phase":0.0,"boss":false,"slow":1.0,"slow_until":0.0,"hit_time":0.0,"animation":"Run","burn_dps":0.0,"burn_until":0.0,"armor_shred":0.0,"shred_until":0.0}

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("COMBAT_RULES_SMOKE_FAIL: "+message)

func _near(actual: float,expected: float,message: String,tolerance: float = 0.002) -> void:
	_expect(absf(actual-expected) <= tolerance,"%s (actual %.6f, expected %.6f)" % [message,actual,expected])

func _enemy(game: GameHarness,position: Vector3 = Vector3.ZERO,armor: float = 0.0,hp: float = 1000.0) -> Dictionary:
	var enemy := game._make_enemy("orc")
	enemy.name = "Тестовый орк"
	enemy.node.position = position
	enemy.armor = armor
	enemy.hp = hp
	enemy.max_hp = hp
	game.enemy_root.add_child(enemy.node)
	game.enemies.append(enemy)
	return enemy

func _tower(game: GameHarness,hero: int,level: int = 4,position: Vector3 = Vector3(-4,0,0)) -> Dictionary:
	var actor := Node3D.new()
	actor.position = position
	game.tower_root.add_child(actor)
	var tower := {"type":hero,"level":level,"node":actor,"damage":100.0,"range":8.0,"detect_range":10.0,"rate":1.0,"cooldown":0.0,"animator":null,"attack_clip":"","idle_clip":"","aura":"","aura_range":10.0,"power":0.0,"lod":{},"range_mesh":null,"selection_ring":null,"selection_light":null}
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
	game.lives = 15
	game.wave_running = false
	game.stage_ready = false
	game.game_over = false
	game.arena = 0
	game.wave = 0

func _armor(game: GameHarness) -> void:
	var enemy := _enemy(game,Vector3.ZERO,50.0)
	_near(game._damage_enemy(enemy,100.0,0.0,false),100.0/1.5,"armor mitigates production damage")
	_near(game._damage_enemy(enemy,100.0,0.5,false),100.0/1.25,"armor penetration increases production damage")
	_near(game._damage_enemy(enemy,-100.0,0.0,false),0.0,"negative raw damage cannot heal or damage")
	_near(game._damage_enemy(enemy,100.0,1.0,false),100.0,"full armor penetration is capped at raw damage")
	_clear(game)

func _chain(game: GameHarness) -> void:
	var yuno := _tower(game,1)
	var targets: Array[Dictionary] = []
	for index in range(5): targets.append(_enemy(game,Vector3(index*1.5,0,0)))
	game._fire_bolt(yuno,targets[0],100.0)
	var flight: Dictionary = game.bolts[0]
	for hop in range(4): game._update_bolts(1.0)
	for index in range(4):
		_near(1000.0-float(targets[index].hp),100.0*pow(0.65,index),"Yuno hop %d has geometric falloff" % (index+1))
	_near(targets[4].hp,1000.0,"Yuno cannot hit a fifth target")
	_expect(flight.hit.size() == 4,"Yuno records exactly four distinct hits")
	var unique_nodes: Dictionary = {}
	for enemy in flight.hit: unique_nodes[enemy.node.get_instance_id()] = true
	_expect(unique_nodes.size() == 4,"Yuno never revisits a target in one chain")
	_expect(game.bolts.is_empty(),"Yuno releases its projectile after the fourth target")
	_clear(game)

func _charmy(game: GameHarness) -> void:
	var charmy := _tower(game,5,0)
	var primary := _enemy(game)
	var neighbour := _enemy(game,Vector3(1.4,0,0))
	var distant := _enemy(game,Vector3(3.1,0,0))
	game._fire_bolt(charmy,primary,100.0)
	game._update_bolts(1.0)
	_near(primary.hp,900.0,"Charmy primary receives full damage")
	_near(neighbour.hp,927.5,"Charmy splash falls off with real separation")
	_near(distant.hp,1000.0,"Charmy does not hit beyond her splash radius")
	_clear(game)
	charmy = _tower(game,5,4)
	primary = _enemy(game,Vector3.ZERO,50.0)
	game._fire_bolt(charmy,primary,100.0)
	game._update_bolts(1.0)
	_near(game._effective_enemy_armor(primary),36.0,"Charmy L5 shreds fourteen armor before the impact")
	_near(primary.hp,1000.0-100.0/1.36,"Charmy hit uses the shredded armor value")
	game.clock = 2.999
	_near(game._effective_enemy_armor(primary),36.0,"Charmy armor shred remains before its deadline")
	game.clock = 3.0
	_near(game._effective_enemy_armor(primary),50.0,"Charmy armor shred expires after three seconds")
	_clear(game)

func _magna(game: GameHarness) -> void:
	var magna := _tower(game,2,4)
	var target := _enemy(game,Vector3.ZERO,50.0)
	game._fire_bolt(magna,target,100.0)
	game._update_bolts(1.0)
	game._fire_bolt(magna,target,70.0)
	game._update_bolts(1.0)
	_near(target.burn_dps,10.0,"Magna retains strongest burn instead of stacking burns")
	for step in range(6):
		game.clock += 0.5
		game._update_enemy(target,0.5)
	var expected := 1000.0-(100.0+70.0+30.0)/1.5
	_near(target.hp,expected,"Magna DOT deals three seconds of damage through armor")
	game.clock += 1.0
	game._update_enemy(target,1.0)
	_near(target.hp,expected,"Magna expired burn causes no extra damage")
	_clear(game)

func _noelle(game: GameHarness) -> void:
	var noelle := _tower(game,4,4)
	var boss := _enemy(game)
	boss.boss = true
	boss.speed = 4.0
	game._fire_bolt(noelle,boss,1.0)
	game._update_bolts(1.0)
	_near(boss.slow,0.60,"Noelle L5 boss slow is limited to sixty percent movement")
	game.clock = 0.5
	game._update_enemy(boss,0.5)
	_near(boss.distance,1.2,"boss movement uses the resistance-adjusted slow")
	_clear(game)
	noelle = _tower(game,4,4)
	var ordinary := _enemy(game)
	game._fire_bolt(noelle,ordinary,1.0)
	game._update_bolts(1.0)
	_near(ordinary.slow,0.12,"ordinary enemies retain the full L5 freeze slow")
	var lesser_noelle := _tower(game,4,0,Vector3(-5,0,0))
	game.clock = 0.4
	game._fire_bolt(lesser_noelle,ordinary,1.0)
	game._update_bolts(1.0)
	_near(ordinary.slow,0.12,"a weaker Noelle cannot overwrite a strong freeze")
	_near(ordinary.slow_until,0.7,"a weaker Noelle cannot extend the short strong freeze")
	game.clock = 0.8
	game._fire_bolt(lesser_noelle,ordinary,1.0)
	game._update_bolts(1.0)
	_near(ordinary.slow,0.55,"a weaker slow can apply normally after the freeze expires")
	_near(ordinary.slow_until,2.3,"a fresh weaker slow uses its own duration")
	_clear(game)

func _animation_completion(game: GameHarness) -> void:
	var fighter := _tower(game,0,0)
	fighter.rate = 0.35
	var aura := _tower(game,3,4,Vector3(-4,0,1))
	aura.aura = "speed"
	aura.power = 0.65
	var target := _enemy(game)
	var animator := AnimationPlayer.new()
	fighter.node.add_child(animator)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 1.0
	idle.loop_mode = Animation.LOOP_LINEAR
	var idle_track := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(idle_track,NodePath(".:rotation:x"))
	idle.track_insert_key(idle_track,0.0,0.0)
	idle.track_insert_key(idle_track,1.0,0.01)
	library.add_animation("Idle",idle)
	var attack := Animation.new()
	attack.length = 1.2
	var attack_track := attack.add_track(Animation.TYPE_VALUE)
	attack.track_set_path(attack_track,NodePath(".:rotation:x"))
	attack.track_insert_key(attack_track,0.0,0.0)
	attack.track_insert_key(attack_track,0.6,-0.35)
	attack.track_insert_key(attack_track,1.2,0.0)
	library.add_animation("Attack",attack)
	animator.add_animation_library("",library)
	fighter.animator = animator
	fighter.attack_clip = "Attack"
	fighter.idle_clip = "Idle"
	game._update_towers(0.01)
	_near(fighter.cooldown,0.35/1.65,"speed aura controls the real tower cooldown")
	_expect(animator.is_playing() and animator.assigned_animation == "Attack","production targeting starts an actual articulated attack clip")
	var speed := animator.get_playing_speed()
	_expect(attack.length/speed <= float(fighter.cooldown)*0.85+0.001,"attack playback fits before the aura-shortened next shot")
	animator.advance(float(fighter.cooldown)*0.90)
	_expect(not animator.is_playing() and animator.current_animation.is_empty() and animator.assigned_animation == "Attack","completed AnimationPlayer clears current_animation while retaining assigned_animation")
	game._process(0.016)
	_expect(animator.is_playing() and animator.assigned_animation == "Idle","production frame update returns a completed strike to Idle")
	_expect(target.hp == 1000.0,"the art-only playback check does not advance the inactive battle")
	_clear(game)

func _wave_projectile_cleanup(game: GameHarness) -> void:
	var fighter := _tower(game,0,0)
	var target := _enemy(game,Vector3.ZERO,0.0,1.0)
	game._fire_bolt(fighter,target,100.0)
	game._fire_bolt(fighter,target,100.0)
	var nodes: Array[Node3D] = [game.bolts[0].node,game.bolts[1].node]
	game._damage_enemy(target,100.0)
	_expect(game.enemies.is_empty() and game.bolts.size() == 2,"last enemy can die with other projectiles still in flight")
	game.wave = 1
	game.wave_running = true
	game._finish_wave()
	_expect(game.bolts.is_empty(),"wave completion releases all remaining projectile records")
	_expect(game.magic_effects.active_flights.is_empty(),"wave completion returns all remaining visual flights")
	for node in nodes: _expect(node.is_queued_for_deletion(),"wave completion disposes each remaining flight node")
	_clear(game)

func _auras(game: GameHarness) -> void:
	var fighter := _tower(game,0,0,Vector3.ZERO)
	var damage_low := _tower(game,3,2,Vector3(1,0,0))
	damage_low.aura = "damage"
	damage_low.power = 0.30
	var damage_high := _tower(game,3,3,Vector3(-1,0,0))
	damage_high.aura = "damage"
	damage_high.power = 0.52
	var speed_low := _tower(game,3,2,Vector3(0,0,1))
	speed_low.aura = "speed"
	speed_low.power = 0.25
	var speed_high := _tower(game,3,3,Vector3(0,0,-1))
	speed_high.aura = "speed"
	speed_high.power = 0.40
	var distant := _tower(game,3,4,Vector3(100,0,100))
	distant.aura = "damage"
	distant.power = 10.0
	var bonuses := game._aura_bonuses_for(fighter)
	_near(bonuses.damage_multiplier,1.52,"only the strongest damage aura applies")
	_near(bonuses.speed_multiplier,1.40,"only the strongest speed aura applies")
	_near(bonuses.armor_ignore,0.0,"lower rank and distant auras grant no armor ignore")
	damage_low.level = 4
	bonuses = game._aura_bonuses_for(fighter)
	_near(bonuses.armor_ignore,0.15,"a nearby L5 Vanessa grants fifteen percent armor ignore")
	speed_low.level = 4
	bonuses = game._aura_bonuses_for(fighter)
	_near(bonuses.armor_ignore,0.15,"multiple L5 auras do not stack armor ignore")
	_expect(game._aura_bonuses_for(damage_low).damage_multiplier == 1.0,"Vanessa does not receive her own damage aura")
	fighter.node.position = Vector3(50,0,0)
	bonuses = game._aura_bonuses_for(fighter)
	_near(bonuses.damage_multiplier,1.0,"leaving aura range removes damage bonus")
	_near(bonuses.speed_multiplier,1.0,"leaving aura range removes speed bonus")
	_near(bonuses.armor_ignore,0.0,"leaving aura range removes armor ignore")
	_clear(game)

func _inspection_death_and_leak(game: GameHarness) -> void:
	var target := _enemy(game,Vector3.ZERO,16.0,120.2)
	target.hp = 37.4
	target.reward = 31
	target.name = "Особый орк"
	game._select_enemy(0)
	_expect(game.selected_enemy.get("node") == target.node,"enemy selection persists in game state")
	_expect(target.selection_ring.visible,"selected enemy has a visible ring")
	_expect(game.selection_label.text.contains("Особый орк") and game.selection_label.text.contains("38 / 121"),"enemy inspection shows name and current/max HP")
	_expect(game.selection_label.text.contains("Броня: 16.0") and game.selection_label.text.contains("Награда: 31"),"enemy inspection shows armor and actual reward")
	_expect(not game.upgrade_button.visible and not game.sell_button.visible,"enemy inspection hides tower actions")
	game._damage_enemy(target,100000.0)
	_expect(game.selected_enemy.is_empty(),"killing the selected enemy clears selection")
	_expect(not target.selection_ring.visible,"dead enemy selection ring is hidden")
	_expect(not game.selection_label.text.contains("Особый орк"),"dead enemy inspection text cannot remain stale")
	_expect(game.gold == 31 and game.enemy_death_visuals.size() == 1,"death awards once and preserves a death visual")
	_expect(is_instance_valid(target.node) and target.node.is_inside_tree(),"enemy does not disappear immediately on death")
	_near(game._damage_enemy(target,100000.0),0.0,"a dead enemy cannot be damaged or rewarded again")
	game._kill_enemy(target)
	_expect(game.gold == 31 and game.enemy_death_visuals.size() == 1,"repeated kill calls cannot duplicate rewards or death visuals")
	game._update_death_visuals(0.3)
	_expect(game.enemy_death_visuals.size() == 1,"death visual survives until its animation deadline")
	game._update_death_visuals(0.4)
	_expect(game.enemy_death_visuals.is_empty(),"death visual is released after its deadline")
	_clear(game)
	var escaping := _enemy(game)
	escaping.distance = game.route_length-0.1
	escaping.speed = 1.0
	escaping.life_damage = 2
	game._select_enemy(0)
	game.clock = 0.2
	game._update_enemy(escaping,0.2)
	_expect(game.selected_enemy.is_empty() and game.enemies.is_empty(),"an escaping selected enemy clears inspection")
	_expect(game.lives == 13 and game.gold == 0,"escape deducts its life cost and grants no kill gold")
	_clear(game)

func _picking(game: GameHarness) -> void:
	var left := _enemy(game,Vector3(-3,0,0))
	var right := _enemy(game,Vector3(3,0,0))
	_expect(game._find_enemy_at_screen(game.camera.unproject_position(left.node.global_position+Vector3.UP*0.9)) == 0,"screen ray picks the first enemy body")
	_expect(game._find_enemy_at_screen(game.camera.unproject_position(right.node.global_position+Vector3.UP*0.9)) == 1,"screen ray picks another enemy body")
	_expect(game._find_enemy_at_screen(Vector2(1,1)) == -1,"empty screen space does not select an enemy")
	_clear(game)

func _progression(game: GameHarness) -> void:
	for kind in Balance.ENEMIES:
		for arena in range(18):
			var previous_hp := 0.0
			var previous_armor := -1.0
			for wave in range(1,16):
				var stats := Balance.enemy_stats(kind,wave,arena,kind == "boss_troll")
				_expect(float(stats.hp) > previous_hp,"%s arena %d HP increases at wave %d" % [kind,arena+1,wave])
				_expect(float(stats.armor) > previous_armor,"%s arena %d armor increases at wave %d" % [kind,arena+1,wave])
				previous_hp = stats.hp
				previous_armor = stats.armor
		for wave in range(1,16):
			var previous_hp := 0.0
			var previous_armor := -1.0
			for arena in range(18):
				var stats := Balance.enemy_stats(kind,wave,arena,kind == "boss_troll")
				_expect(float(stats.hp) > previous_hp,"%s wave %d HP increases on arena %d" % [kind,wave,arena+1])
				_expect(float(stats.armor) > previous_armor,"%s wave %d armor increases on arena %d" % [kind,wave,arena+1])
				previous_hp = stats.hp
				previous_armor = stats.armor
	game.wave = 14
	game._start_wave()
	_expect(game.wave == 15 and game.wave_running,"production starts the arena's final wave")
	var count := game.spawn_left
	var maximum_regular_reward := 0
	for index in range(count):
		game._spawn_enemy()
		var enemy: Dictionary = game.enemies[-1]
		if index < count-1:
			_expect(not enemy.boss and enemy.kind != "boss_troll","ordinary enemies precede the final boss")
			maximum_regular_reward = maxi(maximum_regular_reward,int(enemy.reward))
	var boss: Dictionary = game.enemies[-1]
	_expect(boss.boss and boss.kind == "boss_troll" and game.spawn_left == 0,"the last enemy of wave fifteen is the dedicated boss")
	_expect(int(boss.reward) > maximum_regular_reward*3,"the arena boss has a substantially larger gold reward")
	_expect(int(boss.life_damage) > 1,"the boss has an explicit increased breakthrough cost")
	var expected_rewards := 0
	for enemy in game.enemies.duplicate():
		expected_rewards += int(enemy.reward)
		game._damage_enemy(enemy,1e9)
	_expect(game.gold == expected_rewards,"final-wave kills award the actual per-enemy gold")
	game._finish_wave()
	_expect(game.stage_ready and not game.wave_running,"the arena becomes ready only after its final battle completes")
	_expect(game.gold == expected_rewards+Balance.wave_reward(15,0),"completion adds exactly the configured wave reward")
	_expect(Balance.wave_reward(15,0) > Balance.wave_reward(1,0),"later wave completion rewards exceed early wave rewards")
	_clear(game)

func _run() -> void:
	var game := GameHarness.new()
	root.add_child(game)
	await process_frame
	_armor(game)
	_chain(game)
	_charmy(game)
	_magna(game)
	_noelle(game)
	_animation_completion(game)
	_wave_projectile_cleanup(game)
	_auras(game)
	_inspection_death_and_leak(game)
	_picking(game)
	_progression(game)
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("COMBAT_RULES_SMOKE_OK: %d checks; armor, chain falloff, splash/shred, armored non-stacking DOT, boss/weak slow, strongest auras, real Attack-to-Idle playback, projectile cleanup, NPC inspection/picking/death/leak and campaign progression" % checks)
		quit(0)
	else:
		print("COMBAT_RULES_SMOKE_FAILED: %d / %d checks failed" % [failures.size(),checks])
		quit(1)
