extends SceneTree
## Deterministic balance diagnostic, not a promise that every player will win.
## Uses production routes/obstacles, placement, upgrades, wave spawning, target
## selection, projectiles, armor, damage, deaths, income and arena end states.
## Imports, audio, HUD updates and visible spell geometry are omitted only.

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
	var spawned_count := 0
	var killed_count := 0
	var escaped_count := 0
	var abandoned_count := 0
	var boss_spawned := 0
	var boss_killed := 0
	var kill_income := 0
	var wave_income := 0
	var spent := 0
	var boss_samples: Array[Dictionary] = []
	var wave_population: Dictionary = {}
	var record_attack_telemetry := false
	var spread_placement := false
	var leak_samples: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		rng.seed = 773611
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
		pause_button = Button.new()
		hud_gold = Label.new()
		for control in [status_label,start_button,pause_button,hud_gold]:
			add_child(control)
		for hero in HEROES:
			for rank in range(1,6):
				tower_model_cache["res://Assets/Heroes/%s_L%d.glb" % [hero.id,rank]] = PackedScene.new()
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
	func _refresh_hud() -> void:
		pass
	func _refresh_selection() -> void:
		pass
	func _sync_tower_selection_visuals() -> void:
		pass
	func _refresh_aura_indicators() -> void:
		pass
	func _make_enemy(kind: String) -> Dictionary:
		var actor := Node3D.new()
		var actor_scale := 1.0+float(arena)*0.01
		actor.scale = Vector3.ONE*actor_scale
		var height := float(ENEMY_MODEL_HEIGHT.get(kind,2.2))*float(ENEMY_MODEL_SCALE.get(kind,1.0))*actor_scale
		# Omit imported meshes/rigs, but retain the production aiming height and
		# actor scale: projectile flight must not treat a boss as a 1.8 m grunt.
		return {"kind":kind,"node":actor,"model":null,"animator":null,"bar":null,"height":height,"scale":actor_scale,"hp":1.0,"max_hp":1.0,"reward":0,"speed":1.0,"distance":0.0,"phase":0.0,"boss":false,"slow":1.0,"slow_until":0.0,"hit_time":0.0,"animation":"Run","armor":0.0,"armor_shred":0.0,"armor_shred_until":0.0,"burn_damage":0.0,"burn_until":0.0}
	func _spawn_enemy() -> void:
		var count_before := enemies.size()
		super._spawn_enemy()
		if enemies.size() <= count_before:
			return
		spawned_count += 1
		var enemy: Dictionary = enemies[-1]
		var counts: Dictionary = wave_population.get("kinds",{})
		counts[str(enemy.kind)] = int(counts.get(str(enemy.kind),0))+1
		wave_population["kinds"] = counts
		wave_population["health_total"] = float(wave_population.get("health_total",0.0))+float(enemy.max_hp)
		var protection: float = CombatBalance.armor_multiplier(float(enemy.get("armor",0.0)))
		wave_population["effective_health_total"] = float(wave_population.get("effective_health_total",0.0))+float(enemy.max_hp)/maxf(0.001,protection)
		wave_population["reward_potential"] = int(wave_population.get("reward_potential",0))+int(enemy.reward)
		if bool(enemy.get("boss",false)):
			boss_spawned += 1
			boss_samples.append({"arena":arena+1,"wave":wave,"kind":str(enemy.kind),"hp":float(enemy.max_hp),"armor":float(enemy.get("armor",0.0)),"reward":int(enemy.reward),"killed":false,"escaped":false})
	func _kill_enemy(enemy: Dictionary) -> void:
		if enemies.has(enemy):
			killed_count += 1
			kill_income += int(enemy.reward)
			if record_attack_telemetry:
				wave_population["kill_route_progress_total"] = float(wave_population.get("kill_route_progress_total",0.0))+float(enemy.distance)/maxf(0.001,route_length)
			if bool(enemy.get("boss",false)):
				boss_killed += 1
				boss_samples[-1]["killed"] = true
				boss_samples[-1]["route_progress_on_death"] = float(enemy.distance)/maxf(0.001,route_length)
		super._kill_enemy(enemy)
	func _update_enemy(enemy: Dictionary, dt: float) -> void:
		var alive_before := enemies.has(enemy)
		var hp_before := float(enemy.hp)
		var count_before := enemies.size()
		var leaks_before := lives
		super._update_enemy(enemy,dt)
		if alive_before and not enemies.has(enemy) and hp_before > 0.0 and lives < leaks_before:
			escaped_count += 1
			if record_attack_telemetry:
				leak_samples.append({"wave":wave,"kind":str(enemy.kind),"remaining_hp":float(enemy.hp),"max_hp":float(enemy.max_hp),"armor":float(enemy.get("armor",0.0)),"covered_seconds":float(enemy.get("diagnostic_exposure",0.0)),"at_time":clock})
			if bool(enemy.get("boss",false)):
				boss_samples[-1]["escaped"] = true
			# A defeated game immediately disposes of the remaining active army.
			if game_over:
				abandoned_count += maxi(0,count_before-1)
	func _finish_wave() -> void:
		var before := gold
		super._finish_wave()
		wave_income += gold-before
	func _place_tower(point: Vector3) -> void:
		var before := gold
		super._place_tower(point)
		spent += before-gold
	func _upgrade() -> void:
		var before := gold
		super._upgrade()
		spent += before-gold
	func _update_towers(dt: float) -> void:
		if record_attack_telemetry:
			for enemy in enemies:
				for tower in towers:
					if int(tower.type) != 3 and tower.node.position.distance_to(enemy.node.position) <= float(tower.range):
						enemy["diagnostic_exposure"] = float(enemy.get("diagnostic_exposure",0.0))+dt
						wave_population["covered_enemy_seconds"] = float(wave_population.get("covered_enemy_seconds",0.0))+dt
						break
		super._update_towers(dt)
	func _fire_bolt(tower: Dictionary, target: Dictionary, damage: float) -> void:
		if record_attack_telemetry:
			var counts: Dictionary = wave_population.get("shots_by_hero",{})
			var hero: String = HEROES[int(tower.type)].id
			counts[hero] = int(counts.get(hero,0))+1
			wave_population["shots_by_hero"] = counts
		super._fire_bolt(tower,target,damage)

var candidate_cache: Dictionary = {}
var failed := false

func _argument_value(prefix: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return fallback

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	failed = true
	push_error("CAMPAIGN_PROBE_FAIL: "+message)
	quit(1)

func _coverage(game: GameHarness, point: Vector3, radius: float) -> float:
	var total := 0.0
	for index in range(1,game.route_points.size()):
		var a: Vector3 = game.route_points[index-1]
		var b: Vector3 = game.route_points[index]
		if point.distance_to((a+b)*0.5) <= radius:
			total += a.distance_to(b)
	return total

func _candidates(game: GameHarness, hero_type: int) -> Array[Dictionary]:
	if candidate_cache.has(hero_type):
		return candidate_cache[hero_type]
	var choices: Array[Dictionary] = []
	var radius := float(game.HEROES[hero_type].get("aura_range",0.0)) if hero_type == 3 else float(game.HEROES[hero_type].range)
	for iz in range(-int(game.world_size*0.35),int(game.world_size*0.35),2):
		for ix in range(-int(game.world_size*0.49),int(game.world_size*0.49),2):
			var point := Vector3(float(ix),0.0,float(iz))
			if not game._valid_spot(point):
				continue
			var coverage := _coverage(game,point,radius)
			if coverage > 0.0:
				choices.append({"point":point,"coverage":coverage})
	choices.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.coverage > b.coverage)
	candidate_cache[hero_type] = choices
	return choices

func _buy(game: GameHarness, hero_type: int) -> bool:
	if game.gold < int(game.HEROES[hero_type].price):
		return false
	var best_score := -INF
	var best_point := Vector3(99999,0,0)
	var segment_weights: Array[float] = []
	if game.spread_placement and hero_type != 3:
		for index in range(1,game.route_points.size()):
			var a: Vector3 = game.route_points[index-1]
			var b: Vector3 = game.route_points[index]
			var midpoint := (a+b)*0.5
			var existing := 0
			for tower in game.towers:
				if int(tower.type) != 3 and tower.node.position.distance_to(midpoint) <= float(tower.range):
					existing += 1
			segment_weights.append(a.distance_to(b)/(1.0+0.45*float(existing)))
	for candidate in _candidates(game,hero_type):
		var point: Vector3 = candidate.point
		if not game._valid_spot(point):
			continue
		var score := float(candidate.coverage)
		if game.spread_placement and hero_type != 3:
			score = 0.0
			for index in range(1,game.route_points.size()):
				var midpoint: Vector3 = (game.route_points[index-1]+game.route_points[index])*0.5
				if point.distance_to(midpoint) <= float(game.HEROES[hero_type].range):
					score += segment_weights[index-1]
		if hero_type == 3:
			score = 0.0
			for tower in game.towers:
				if int(tower.type) != 3 and tower.node.position.distance_to(point) <= float(game.HEROES[3].aura_range):
					score += float(tower.damage)/maxf(0.1,float(tower.rate))
		else:
			# Prefer a shared defensive area, while avoiding identical footprints.
			for tower in game.towers:
				if tower.node.position.distance_to(point) < 6.0:
					score *= 0.97
		if score > best_score:
			best_score = score
			best_point = point
	if best_point.x > 90000.0:
		return false
	var before := game.towers.size()
	game.selected_type = hero_type
	game._place_tower(best_point)
	if game.towers.size() == before:
		return false
	if hero_type == 3:
		game.towers[-1].aura = "speed"
	return true

func _spend_between_waves(game: GameHarness, policy: String) -> void:
	if policy == "fixed_opening":
		return
	if policy.begins_with("capstone"):
		# A deliberate damage-carry plan: one early rank, fire/support, then
		# unlock the wind chain before spreading purchases over every role.
		for goal in [[1,1],[2,0],[3,0],[1,2],[1,3],[1,4],[4,0],[5,0]]:
			var chosen: Dictionary = {}
			for tower in game.towers:
				if int(tower.type) == int(goal[0]):
					chosen = tower
					break
			if chosen.is_empty():
				if not _buy(game,int(goal[0])):
					return
			elif int(chosen.level) < int(goal[1]):
				if game.gold < int(game.HEROES[int(chosen.type)].costs[int(chosen.level)]):
					return
				game.selected_tower = chosen
				game._upgrade()
	if policy == "capstone_dual_aura":
		var has_damage_aura := false
		for tower in game.towers:
			if int(tower.type) == 3 and str(tower.aura) == "damage":
				has_damage_aura = true
		if not has_damage_aura:
			if not _buy(game,3):
				return
			game.towers[-1].aura = "damage"
	if policy == "control_noelle":
		# A short single-pass route benefits from slowing the whole approaching
		# column before investing heavily into the wind-chain carry.
		for goal in [[2,0],[1,0],[3,0],[1,1],[1,2],[1,3],[1,4],[5,0]]:
			var chosen: Dictionary = {}
			for tower in game.towers:
				if int(tower.type) == int(goal[0]):
					chosen = tower
					break
			if chosen.is_empty():
				if not _buy(game,int(goal[0])):
					return
			elif int(chosen.level) < int(goal[1]):
				if game.gold < int(game.HEROES[int(chosen.type)].costs[int(chosen.level)]):
					return
				game.selected_tower = chosen
				game._upgrade()
	if policy.begins_with("fire_battery"):
		var fire_towers: Array[Dictionary] = []
		for tower in game.towers:
			if int(tower.type) == 2:
				fire_towers.append(tower)
		while fire_towers.size() < 3:
			if not _buy(game,2):
				return
			fire_towers.append(game.towers[-1])
		for utility in [4,3]:
			var present := false
			for tower in game.towers:
				if int(tower.type) == utility:
					present = true
			if not present and not _buy(game,utility):
				return
		for rank in [1,2]:
			for tower in fire_towers:
				if int(tower.level) >= rank:
					continue
				if game.gold < int(game.HEROES[2].costs[int(tower.level)]):
					return
				game.selected_tower = tower
				game._upgrade()
	if policy.begins_with("upgrade_core"):
		# Secure the damaging core before collecting every utility role.
		for target_rank in [1,2]:
			for tower in game.towers:
				if int(tower.type) == 3 or int(tower.level) >= target_rank:
					continue
				if game.gold < int(game.HEROES[int(tower.type)].costs[int(tower.level)]):
					return
				game.selected_tower = tower
				game._upgrade()
	var roster: Array = [0,1,2,4,5,3] if game.HEROES.size() >= 6 else [0,1,2,4,3]
	# At most eight heroes: six roles plus one wind mage and one fire mage.
	# The bot spends only between waves and never sells or adds mid-wave aid.
	for hero_type in roster:
		var present := false
		for tower in game.towers:
			if int(tower.type) == int(hero_type):
				present = true
		if not present and not _buy(game,int(hero_type)):
			return
	if game.wave >= 5 and game.towers.size() < roster.size()+2:
		if not _buy(game,1 if game.towers.size() == roster.size() else 2):
			return
	for attempt in range(40):
		var candidate: Dictionary = {}
		var best_value := -INF
		for tower in game.towers:
			var rank := int(tower.level)
			if rank >= 4:
				continue
			var price := int(game.HEROES[int(tower.type)].costs[rank])
			if price > game.gold:
				continue
			var value := (1.0+0.22*float(rank))/float(price)
			if int(tower.type) == 3:
				value *= 1.3
			if value > best_value:
				best_value = value
				candidate = tower
		if candidate.is_empty():
			break
		game.selected_tower = candidate
		var before := int(candidate.level)
		game._upgrade()
		if before == int(candidate.level):
			break

func _dispose(game: GameHarness) -> void:
	game.magic_effects.clear_all()
	game.bolts.clear()
	game.enemies.clear()
	game.towers.clear()
	game.selected_tower = {}
	game._clear_enemy_death_visuals()
	game.queue_free()

func _reset_case_counters(game: GameHarness) -> void:
	game.spawned_count = 0
	game.killed_count = 0
	game.escaped_count = 0
	game.abandoned_count = 0
	game.boss_spawned = 0
	game.boss_killed = 0
	game.kill_income = 0
	game.wave_income = 0
	game.spent = 0
	game.boss_samples.clear()
	game.wave_population.clear()
	game.leak_samples.clear()

func _play_current_arena(game: GameHarness, budget: int, policy: String) -> Dictionary:
	_reset_case_counters(game)
	game.spread_placement = policy.contains("spread")
	candidate_cache.clear()
	# Baseline opening is deliberately the same across arenas and policies.
	var opening: Array = [4,0] if policy == "control_noelle" else [2,0] if policy.ends_with("_magna") else [5,0] if policy.ends_with("_charmy") else [0,1]
	for hero_type in opening:
		if not _buy(game,int(hero_type)):
			_fail("production placement rejected an affordable legal opening on arena %d" % (game.arena+1))
			return {}
	var waves: Array[Dictionary] = []
	var max_wave := 0
	var all_completed := true
	for next_wave in range(1,16):
		game.wave_population.clear()
		_spend_between_waves(game,policy)
		var opening_gold := game.gold
		var before_spawned := game.spawned_count
		var before_killed := game.killed_count
		var before_escaped := game.escaped_count
		var before_lives := game.lives
		var before_income := game.kill_income+game.wave_income
		game._start_wave()
		if not game.wave_running:
			_fail("a diagnostic wave did not start")
			return {}
		var simulated := 0.0
		var frames := 0
		while game.wave_running and simulated < 360.0:
			game._process(1.0/30.0)
			simulated += 1.0/30.0
			frames += 1
			if frames%300 == 0:
				await process_frame
		# Production also sets game_over on campaign victory, so positive lives
		# and complete enemy accounting distinguish victory from defeat.
		var completed := not game.wave_running and game.lives > 0 and game.enemies.is_empty() and game.spawn_left == 0
		if completed:
			max_wave = next_wave
		else:
			all_completed = false
		var ranks: Array[Dictionary] = []
		for tower in game.towers:
			ranks.append({"hero":str(game.HEROES[int(tower.type)].id),"rank":int(tower.level)+1,"x":tower.node.position.x,"z":tower.node.position.z,"route_coverage_m":snappedf(_coverage(game,tower.node.position,float(tower.range)),0.01)})
		var row := {"wave":next_wave,"completed":completed,"spawned":game.spawned_count-before_spawned,"killed":game.killed_count-before_killed,"escaped":game.escaped_count-before_escaped,"lives_lost":before_lives-game.lives,"remaining":game.enemies.size(),"opening_gold":opening_gold,"ending_gold":game.gold,"income":game.kill_income+game.wave_income-before_income,"lives":game.lives,"seconds":snappedf(simulated,0.01),"towers":ranks,"population":game.wave_population.duplicate(true)}
		waves.append(row)
		if game.spawned_count != game.killed_count+game.escaped_count+game.abandoned_count+game.enemies.size():
			_fail("enemy accounting does not balance: "+JSON.stringify(row))
			return {}
		if game.gold != budget+game.kill_income+game.wave_income-game.spent:
			_fail("gold accounting does not balance: "+JSON.stringify(row))
			return {}
		if completed:
			var expected_count: int = game.CombatBalance.wave_count(next_wave,game.arena)
			if int(row.spawned) != expected_count:
				_fail("completed wave did not spawn its full army: "+JSON.stringify(row))
				return {}
			if next_wave == 15:
				var kinds: Dictionary = game.wave_population.get("kinds",{})
				if int(kinds.get("boss_troll",0)) != 1 or game.boss_samples.is_empty() or str(game.boss_samples[-1].kind) != "boss_troll":
					_fail("arena ended without exactly one real boss_troll spawn")
					return {}
		if not completed:
			break
		await process_frame
	var result := {"arena":game.arena+1,"starting_budget":budget,"policy":policy,"route_length":game.route_length,"obstacles":game.build_obstacles.size(),"completed_waves":max_wave,"arena_completed":all_completed and max_wave==15,"total_spawned":game.spawned_count,"kills":game.killed_count,"escaped":game.escaped_count,"abandoned_on_defeat":game.abandoned_count,"lives":game.lives,"gold":game.gold,"kill_income":game.kill_income,"wave_income":game.wave_income,"spent":game.spent,"boss_spawned":game.boss_spawned,"boss_killed":game.boss_killed,"boss_samples":game.boss_samples.duplicate(true),"leak_samples":game.leak_samples.duplicate(true),"waves":waves}
	print("CAMPAIGN_PROBE_CASE "+JSON.stringify({"arena":result.arena,"budget":budget,"policy":policy,"completed_waves":max_wave,"kills":result.kills,"escaped":result.escaped,"gold":result.gold,"boss_killed":result.boss_killed}))
	return result

func _run_case(arena_index: int, budget: int, policy: String) -> Dictionary:
	var game := GameHarness.new()
	game.arena = arena_index
	game.gold = budget
	game.record_attack_telemetry = OS.get_cmdline_user_args().has("--hard-maps")
	root.add_child(game)
	game._build_arena()
	await process_frame
	var result := await _play_current_arena(game,budget,policy)
	_dispose(game)
	await process_frame
	await process_frame
	return result

func _connected_campaign(policy: String = "adaptive_mixed") -> Dictionary:
	var game := GameHarness.new()
	game.gold = 220
	game.record_attack_telemetry = OS.get_cmdline_user_args().has("--connected-capstone") or OS.get_cmdline_user_args().has("--connected-dual-aura")
	root.add_child(game)
	game._build_arena()
	await process_frame
	var stages: Array[Dictionary] = []
	var transitions: Array[Dictionary] = []
	for arena_index in range(18):
		var budget := game.gold
		var result := await _play_current_arena(game,budget,policy)
		if failed:
			_dispose(game)
			return {}
		stages.append(result)
		if not bool(result.arena_completed) or arena_index >= 17:
			break
		var remainder := game.gold
		var expected := game._next_arena_budget(remainder)
		var previous_towers := game.towers.size()
		game._start_wave()
		if game.arena != arena_index+1 or game.wave != 0 or game.wave_running or game.spawn_left != 0 or game.gold != int(expected.total) or not game.towers.is_empty() or game.lives != 15 or game.stage_ready:
			_fail("production campaign transition violated map/wave/gold/tower/life reset")
			_dispose(game)
			return {}
		transitions.append({"from_arena":arena_index+1,"to_arena":game.arena+1,"remaining_gold":remainder,"base":int(expected.base),"carryover":int(expected.carryover),"actual_gold":game.gold,"discarded_towers":previous_towers,"wave_starts_immediately":false,"wave_after_transfer":game.wave,"pending_spawns":game.spawn_left,"lives_after_reset":game.lives})
		# The transition must leave a real preparation phase. No emergency
		# pause, artificial time stop or direct flag edits are used here.
		await process_frame
	var completed_stages := 0
	var completed_waves := 0
	var income_total := 0
	var spent_total := 0
	var supplied_base_total := 220
	var discarded_gold_total := 0
	var spawned_total := 0
	var killed_total := 0
	var escaped_total := 0
	var final_bosses_spawned := 0
	var final_bosses_killed := 0
	for stage in stages:
		completed_waves += int(stage.completed_waves)
		income_total += int(stage.kill_income)+int(stage.wave_income)
		spent_total += int(stage.spent)
		spawned_total += int(stage.total_spawned)
		killed_total += int(stage.kills)
		escaped_total += int(stage.escaped)
		for sample in stage.boss_samples:
			if str(sample.kind) == "boss_troll":
				final_bosses_spawned += 1
				if bool(sample.killed):
					final_bosses_killed += 1
		if stage.arena_completed:
			completed_stages += 1
	for transition in transitions:
		supplied_base_total += int(transition.base)
		discarded_gold_total += int(transition.remaining_gold)-int(transition.carryover)
	var expected_final_gold := supplied_base_total+income_total-spent_total-discarded_gold_total
	if game.gold != expected_final_gold:
		_fail("connected campaign global gold accounting does not balance")
		_dispose(game)
		return {}
	if completed_stages == 18 and (not game.game_over or game.stage_ready or game.wave != 15 or game.wave_running or transitions.size() != 17):
		_fail("270-wave victory did not reach the production campaign end state")
		_dispose(game)
		return {}
	var economy := {"supplied_base_gold":supplied_base_total,"earned_gold":income_total,"spent_gold":spent_total,"discarded_on_transitions":discarded_gold_total,"expected_final_gold":expected_final_gold,"actual_final_gold":game.gold,"sales_used":false}
	var final_state := {"stages":stages,"transitions":transitions,"policy":policy,"completed_arenas":completed_stages,"completed_waves":completed_waves,"campaign_won":completed_stages==18,"pause_for_building_after_transitions":false,"separate_wave_start_after_transition":true,"global_economy":economy,"total_spawned":spawned_total,"total_killed":killed_total,"total_escaped":escaped_total,"final_bosses_spawned":final_bosses_spawned,"final_bosses_killed":final_bosses_killed}
	_dispose(game)
	await process_frame
	await process_frame
	return final_state

func _full_catalog(rules: GDScript) -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for arena_index in range(18):
		for wave_number in range(1,16):
			var population := {"arena":arena_index+1,"wave":wave_number,"enemies":0,"health_total":0.0,"effective_health_total":0.0,"kill_reward_potential":0,"wave_reward":rules.wave_reward(wave_number,arena_index),"kinds":{}}
			for remaining in range(rules.wave_count(wave_number,arena_index)-1,-1,-1):
				var kind: String = rules.spawn_kind(wave_number,remaining)
				var boss := remaining == 0 and wave_number%5 == 0
				var stats: Dictionary = rules.enemy_stats(kind,wave_number,arena_index,boss)
				population.enemies += 1
				population.health_total += float(stats.hp)
				population.effective_health_total += float(stats.hp)/maxf(0.001,float(rules.armor_multiplier(float(stats.armor))))
				population.kill_reward_potential += int(stats.reward)
				population.kinds[kind] = int(population.kinds.get(kind,0))+1
			catalog.append(population)
	return catalog

func _run() -> void:
	var report := {"method":"Production game logic at 30 Hz with real map routes, scenery obstacles, legal placements, upgrades and finite gold. Models, sound, HUD redraws and spell artwork omitted. Strategies use coarse-grid coverage; not global optimality or human playtesting. Fixed opening never spends after Asta+Yuno. Adaptive mixed fills six roles, adds at most two heroes, then upgrades only between waves. Defeat is a diagnostic outcome, never a reason to weaken assertions.","cases":[]}
	report["started_utc"] = Time.get_datetime_string_from_system(true)
	report["build_version"] = ProjectSettings.get_setting("application/config/version","")
	report["source_sha256"] = {"game":FileAccess.get_sha256("res://scripts/game.gd"),"combat_rules":FileAccess.get_sha256("res://scripts/combat_balance.gd"),"routes":FileAccess.get_sha256("res://Assets/Maps/routes.json"),"probe":FileAccess.get_sha256("res://tests/campaign_balance_probe.gd")}
	report["policy_definitions"] = {"adaptive_mixed":"Asta+Yuno opening, six roles then one extra wind/fire mage, upgrades by rank/cost, at most eight paid towers; no mid-wave shopping.","capstone_yuno":"Asta+Yuno, one wind rank, Magna and speed aura, prioritize Yuno L5, then other roles and intermission upgrades.","capstone_dual_aura":"The early Yuno L5 plan followed by a second paid Vanessa in damage mode. Both distinct strongest aura types are production mechanics. At most eight paid towers; construction and upgrades only between waves."}
	var rules := load("res://scripts/combat_balance.gd")
	var curves: Array[Dictionary] = []
	if rules != null:
		for arena_index in [0,8,17]:
			for wave_number in [1,5,10,15]:
				for kind in ["goblin","orc","uruk","troll","boss_troll"]:
					if kind == "boss_troll" and wave_number != 15:
						continue
					var stats: Dictionary = rules.enemy_stats(kind,wave_number,arena_index,kind == "boss_troll")
					var multiplier: float = rules.armor_multiplier(float(stats.armor))
					curves.append({"arena":arena_index+1,"wave":wave_number,"kind":kind,"hp":snappedf(float(stats.hp),0.01),"armor":snappedf(float(stats.armor),0.01),"effective_hp_without_penetration":snappedf(float(stats.hp)/maxf(0.001,multiplier),0.01),"reward":int(stats.reward)})
	report["curves"] = curves
	if OS.get_cmdline_user_args().has("--connected-capstone") or OS.get_cmdline_user_args().has("--connected-dual-aura"):
		var dual_aura := OS.get_cmdline_user_args().has("--connected-dual-aura")
		report["mode"] = "connected-dual-aura-campaign" if dual_aura else "connected-capstone-campaign"
		report["connected_campaign"] = await _connected_campaign("capstone_dual_aura" if dual_aura else "capstone_yuno")
		if failed:
			return
		var connected_output := "res://Builds/campaign-connected-dual-aura.json" if dual_aura else "res://Builds/campaign-connected-capstone.json"
		var connected_file := FileAccess.open(connected_output,FileAccess.WRITE)
		connected_file.store_string(JSON.stringify(report,"\t"))
		connected_file.close()
		print("CAMPAIGN_CONNECTED_PROBE_OK: real connected campaign with an early wind-chain carry; diagnostic outcomes retained in "+connected_output)
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--hard-maps"):
		report["mode"] = "hard-map-strategy-comparison"
		var policies: Array = ["adaptive_spread_magna","capstone_spread_yuno"] if OS.get_cmdline_user_args().has("--spread-only") else ["capstone_yuno"] if OS.get_cmdline_user_args().has("--capstone-only") else ["adaptive_mixed","adaptive_mixed_magna","adaptive_mixed_charmy","upgrade_core","upgrade_core_magna","upgrade_core_charmy","capstone_yuno"]
		if OS.get_cmdline_user_args().has("--magna-only"):
			policies = ["adaptive_mixed_magna"]
		if OS.get_cmdline_user_args().has("--control-only"):
			policies = ["control_noelle"]
		if OS.get_cmdline_user_args().has("--fire-only"):
			policies = ["fire_battery_magna"]
		if OS.get_cmdline_user_args().has("--dual-aura-only"):
			policies = ["capstone_dual_aura"]
		var hard_budget := int(_argument_value("--starting-budget=","220"))
		for arena_number in _argument_value("--maps=","2,12,14").split(","):
			var arena_index := int(arena_number)-1
			for policy in policies:
				var result := await _run_case(arena_index,hard_budget,policy)
				if failed:
					return
				report.cases.append(result)
		var hard_output := "res://Builds/campaign-placement-strategies.json" if OS.get_cmdline_user_args().has("--spread-only") else "res://Builds/campaign-capstone-strategy.json" if OS.get_cmdline_user_args().has("--capstone-only") else "res://Builds/campaign-hard-map-strategies.json"
		if hard_budget != 220:
			hard_output = "res://Builds/campaign-transition-budget-strategies.json"
		if OS.get_cmdline_user_args().has("--control-only"):
			hard_output = "res://Builds/campaign-control-strategy-%d.json" % hard_budget
		if OS.get_cmdline_user_args().has("--fire-only"):
			hard_output = "res://Builds/campaign-fire-strategy-%d.json" % hard_budget
		if OS.get_cmdline_user_args().has("--dual-aura-only"):
			hard_output = "res://Builds/campaign-dual-aura-strategy-%d.json" % hard_budget
		hard_output = _argument_value("--report-output=",hard_output)
		var hard_file := FileAccess.open(hard_output,FileAccess.WRITE)
		hard_file.store_string(JSON.stringify(report,"\t"))
		hard_file.close()
		print("CAMPAIGN_HARD_MAP_PROBE_OK: %d strategy/map diagnostics; see %s. Defeats are retained." % [report.cases.size(),hard_output])
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--full-campaign"):
		report["mode"] = "full-campaign"
		report["catalog"] = _full_catalog(rules)
		report["minimum_budget_cases"] = []
		for arena_index in range(18):
			var result := await _run_case(arena_index,220,"adaptive_mixed")
			if failed:
				return
			report.minimum_budget_cases.append(result)
		report["connected_campaign"] = await _connected_campaign()
		if failed:
			return
		var full_output := "res://Builds/campaign-balance-full.json"
		var full_file := FileAccess.open(full_output,FileAccess.WRITE)
		if full_file == null:
			_fail("could not write "+full_output)
			return
		full_file.store_string(JSON.stringify(report,"\t"))
		full_file.close()
		print("CAMPAIGN_FULL_PROBE_OK: 18 independent minimum-budget arenas and real connected transitions inspected; wins/losses are diagnostic outcomes. See Builds/campaign-balance-full.json.")
		quit(0)
		return
	var cases: Array = [[0,360,"fixed_opening"],[0,360,"adaptive_mixed"],[0,220,"adaptive_mixed"],[8,220,"adaptive_mixed"],[17,220,"adaptive_mixed"]]
	for specification in cases:
		var result := await _run_case(int(specification[0]),int(specification[1]),str(specification[2]))
		if failed:
			return
		report.cases.append(result)
	var output := "res://Builds/campaign-balance-probe.json"
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		_fail("could not write "+output)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("CAMPAIGN_PROBE_OK: accounting and wave state checked; see five diagnostic strategies in Builds/campaign-balance-probe.json. This does not certify all 270 waves or artistic quality.")
	quit(0)
