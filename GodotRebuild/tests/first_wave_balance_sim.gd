extends SceneTree
## Diagnostic, not a win-condition regression: production targeting, projectile
## travel/damage, NPC spawning/movement, economy and wave completion run at 30 Hz.
## Only imported models, audio and spell artwork are replaced with empty nodes.

class EffectsHarness extends Node3D:
	func acquire_flight(_hero: int) -> Node3D:
		var flight := Node3D.new()
		add_child(flight)
		return flight
	func release_flight(flight: Node3D) -> void:
		flight.queue_free()
	func impact(_hero: int, _point: Vector3) -> void:
		pass
	func tick(_delta: float) -> void:
		pass
	func clear_all() -> void:
		for child in get_children():
			child.queue_free()

class GameHarness extends "res://scripts/game.gd":
	var health_profile := "production"
	var spawned_count := 0
	var killed_count := 0
	var starting_enemy_hp := 0.0
	func _ready() -> void:
		set_process(false)
		rng.seed = 816271
		_load_route_patterns()
		terrain_root = Node3D.new()
		tower_root = Node3D.new()
		enemy_root = Node3D.new()
		bolt_root = Node3D.new()
		for actor_root in [terrain_root,tower_root,enemy_root,bolt_root]:
			add_child(actor_root)
		magic_effects = EffectsHarness.new()
		add_child(magic_effects)
		status_label = Label.new()
		start_button = Button.new()
		for control in [status_label,start_button]:
			add_child(control)
		for hero in HEROES:
			tower_model_cache["res://Assets/Heroes/%s_L1.glb" % hero.id] = PackedScene.new()
	func _exit_tree() -> void:
		pass
	func _initial_tower_models_ready() -> bool:
		return true
	func _enemy_models_ready() -> bool:
		return true
	func _poll_tower_model_loading() -> void:
		pass
	func _poll_enemy_model_loading() -> void:
		pass
	func _animate_background_life(_delta: float) -> void:
		pass
	func _update_camera() -> void:
		pass
	func _load_tower_model(_tower: Dictionary) -> void:
		pass
	func _request_tower_model(_hero_id: String, _rank: int) -> void:
		pass
	func _play_sfx(_path: String, _position: Vector3) -> void:
		pass
	func _make_enemy(kind: String) -> Dictionary:
		var actor := Node3D.new()
		return {"kind":kind,"node":actor,"model":null,"animator":null,"bar":null,"height":1.8,"hp":1.0,"max_hp":1.0,"reward":20,"speed":1.0,"distance":0.0,"phase":0.0,"boss":false,"slow":1.0,"slow_until":0.0,"hit_time":0.0,"animation":"Run"}
	func _spawn_enemy() -> void:
		super._spawn_enemy()
		spawned_count += 1
		var enemy: Dictionary = enemies[-1]
		if health_profile == "legacy":
			enemy.hp = 36.0+wave*18.0+arena*55.0+(145.0 if enemy.boss else 0.0)
			enemy.max_hp = enemy.hp
			var base_reward: int = int({"goblin":20,"orc":24,"uruk":30,"warg":34,"troll":42,"nazgul":54}[enemy.kind])
			enemy.reward = (100+arena*30+wave*4) if enemy.boss else roundi(base_reward*(1.0+arena*0.15+wave*0.035))
		starting_enemy_hp = float(enemy.max_hp)
	func _finish_wave() -> void:
		var before_reward := gold
		super._finish_wave()
		if health_profile == "legacy":
			gold = before_reward+80+arena*25+wave*5
	func _kill_enemy(enemy: Dictionary) -> void:
		if enemies.has(enemy):
			killed_count += 1
		super._kill_enemy(enemy)

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("BALANCE_SIM_FAIL: "+message)
	quit(1)

func _coverage(game: GameHarness, point: Vector3, radius: float) -> float:
	var covered := 0.0
	for index in range(1,game.route_points.size()):
		var a: Vector3 = game.route_points[index-1]
		var b: Vector3 = game.route_points[index]
		if point.distance_to((a+b)*0.5) <= radius:
			covered += a.distance_to(b)
	return covered

func _candidates(game: GameHarness, hero_type: int) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var hero: Dictionary = game.HEROES[hero_type]
	for iz in range(-int(game.world_size*0.35),int(game.world_size*0.35),2):
		for ix in range(-int(game.world_size*0.49),int(game.world_size*0.49),2):
			var point := Vector3(float(ix),0.0,float(iz))
			if not game._valid_spot(point):
				continue
			var covered := _coverage(game,point,float(hero.range))
			if covered > 0.0:
				choices.append({"point":point,"coverage":covered})
	choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.coverage > b.coverage)
	return choices

func _position_pair(game: GameHarness, heroes: Array) -> Array[Vector3]:
	var first_choices := _candidates(game,int(heroes[0]))
	var second_choices := _candidates(game,int(heroes[1]))
	if first_choices.is_empty() or second_choices.is_empty():
		return []
	var best_score := -INF
	var pair: Array[Vector3] = []
	# Strong static positions, including overlap for focus-fire, rather than
	# deliberately placing weak towers at opposite ends of the map.
	for first in first_choices.slice(0,mini(20,first_choices.size())):
		for second in second_choices.slice(0,mini(40,second_choices.size())):
			if first.point.distance_to(second.point) < game._minimum_tower_spacing():
				continue
			var overlap := 0.0
			for index in range(1,game.route_points.size()):
				var a: Vector3 = game.route_points[index-1]
				var b: Vector3 = game.route_points[index]
				var mid := (a+b)*0.5
				if first.point.distance_to(mid) <= float(game.HEROES[int(heroes[0])].range) and second.point.distance_to(mid) <= float(game.HEROES[int(heroes[1])].range):
					overlap += a.distance_to(b)
			var first_dps: float = float(game.HEROES[int(heroes[0])].damage)/float(game.HEROES[int(heroes[0])].rate)
			var second_dps: float = float(game.HEROES[int(heroes[1])].damage)/float(game.HEROES[int(heroes[1])].rate)
			var score: float = float(first.coverage)*first_dps+float(second.coverage)*second_dps+overlap*minf(first_dps,second_dps)*0.4
			if score > best_score:
				best_score = score
				pair.assign([first.point,second.point])
	return pair

func _clean_battle(game: GameHarness) -> void:
	for tower in game.towers:
		tower.node.queue_free()
	for enemy in game.enemies:
		enemy.node.queue_free()
	game._clear_enemy_death_visuals()
	game.magic_effects.clear_all()
	game.towers.clear()
	game.enemies.clear()
	game.bolts.clear()
	game.selected_tower = {}
	game.selected_type = -1
	game.gold = 220
	game.wave = 0
	game.lives = 15
	game.game_over = false
	game.stage_ready = false
	game.wave_running = false
	game.paused = false
	game.spawned_count = 0
	game.killed_count = 0
	game.clock = 0.0
	game.spawn_clock = 0.0
	game.spawn_left = 0
	game.game_speed = 1.0

func _run() -> void:
	var report := {"method":"Production world obstacles, placement, target selection, projectile flight/damage, death, movement and wave completion at 30 Hz. Production uses current runtime HP, enemy rewards and wave bonus; legacy restores the preceding +arena*55 HP and preceding enemy/wave rewards in this test only. No GLB models, artwork, audio, reinforcements or upgrades during wave. Static placements maximize weighted route coverage among coarse-grid candidates; not proof of global optimality.","budget":220,"simulation_limit_seconds":120,"cases":[]}
	for arena_index in [0,8,17]:
		var game := GameHarness.new()
		game.arena = arena_index
		root.add_child(game)
		game._build_arena()
		await process_frame
		var arena_obstacles := game.build_obstacles.size()
		for heroes in [[0,1],[2,0]]:
			_clean_battle(game)
			var positions := _position_pair(game,heroes)
			if positions.size() != 2:
				_fail("no legal pair positions on arena %d" % (arena_index+1))
				return
			for profile in ["legacy","production"]:
				_clean_battle(game)
				game.health_profile = profile
				for index in range(2):
					game.selected_type = int(heroes[index])
					game._place_tower(positions[index])
				if game.towers.size() != 2:
					_fail("actual placement rejected a chosen legal pair")
					return
				var opening_gold := game.gold
				game._start_wave()
				var simulated := 0.0
				while game.wave_running and simulated < 120.0:
					game._process(1.0/30.0)
					simulated += 1.0/30.0
				var position_json: Array = []
				for position in positions:
					position_json.append({"x":position.x,"z":position.z})
				var result := {"arena":arena_index+1,"profile":profile,"heroes":[game.HEROES[int(heroes[0])].short,game.HEROES[int(heroes[1])].short],"opening_gold_after_purchase":opening_gold,"positions":position_json,"route_length":game.route_length,"obstacle_count":arena_obstacles,"enemy_hp":game.starting_enemy_hp,"spawned":game.spawned_count,"kills":game.killed_count,"leaks":15-game.lives,"remaining":game.enemies.size(),"gold_after_wave":game.gold,"lives_after_wave":game.lives,"seconds":snappedf(simulated,0.01),"wave_completed":not game.wave_running and not game.game_over and game.enemies.is_empty() and game.spawn_left == 0}
				report.cases.append(result)
				print("BALANCE_CASE "+JSON.stringify(result))
				if game.spawned_count != game.killed_count+(15-game.lives)+game.enemies.size():
					_fail("enemy accounting does not balance")
					return
				if profile=="production" and (game.killed_count!=8 or game.lives!=15 or not bool(result.wave_completed)):
					_fail("minimum-budget production opening no longer clears all eight enemies on arena %d"%(arena_index+1))
					return
				await process_frame
		_clean_battle(game)
		game.queue_free()
		await process_frame
		await process_frame
	var file := FileAccess.open("res://Builds/first-wave-balance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("BALANCE_SIM_OK: 12 complete first-wave diagnostics; this does not certify the full 270-wave campaign.")
	quit(0)
