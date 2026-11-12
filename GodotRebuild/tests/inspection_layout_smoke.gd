extends SceneTree
## Production HUD and inspection text at all requested logical resolutions.
## Models/audio are omitted. Real placement and four upgrades prepare each
## hero, then real selection methods populate the UI. Failures are aggregated
## across all cases; text clipping is not accepted just because buttons exist.

class EffectsHarness extends Node3D:
	func clear_all() -> void:
		pass

class GameHarness extends "res://scripts/game.gd":
	func _ready() -> void:
		set_process(false)
		terrain_root = Node3D.new()
		tower_root = Node3D.new()
		enemy_root = Node3D.new()
		for actor_root in [terrain_root,tower_root,enemy_root]:
			add_child(actor_root)
		magic_effects = EffectsHarness.new()
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
	func _load_tower_model(_tower: Dictionary) -> void:
		pass
	func _request_tower_model(_hero_id: String, _rank: int) -> void:
		pass
	func _play_sfx(_path: String, _point: Vector3) -> void:
		pass

var report := {"method":"Production HUD, real placement/upgrades, selection and inspection strings. Six L5 heroes under damage+speed L5 auras; Vanessa modes; all enemy kinds with burn/slow/shred; three logical resolutions. Geometry/text-fit/clip/overlap checks, no rendered-image or artistic claim.","cases":[],"violations":[]}
var current_case := ""
var current_resolution := Vector2i.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _violation(code: String, detail: String) -> void:
	report.violations.append({"resolution":"%dx%d" % [current_resolution.x,current_resolution.y],"case":current_case,"code":code,"detail":detail})
	print("INSPECTION_LAYOUT_VIOLATION "+JSON.stringify(report.violations[-1]))

func _bounds(rect: Rect2) -> Dictionary:
	return {"x":rect.position.x,"y":rect.position.y,"width":rect.size.x,"height":rect.size.y}

func _name(control: Control) -> String:
	if control is Label:
		return "Label:"+control.text.get_slice("\n",0)
	if control is Button:
		return "Button:"+control.text.get_slice("\n",0)
	return control.get_class()+":"+str(control.name)

func _visible_leaves(node: Node) -> Array[Control]:
	var controls: Array[Control] = []
	for child in node.get_children():
		if child is Control and not child.is_visible_in_tree():
			continue
		if child is Label or child is BaseButton or child is Range:
			controls.append(child)
		else:
			controls.append_array(_visible_leaves(child))
	return controls

func _text_fit(control: Control) -> void:
	if control is Label:
		var label := control as Label
		var needed := label.get_line_count()*label.get_line_height()
		if needed > label.size.y+1.0:
			_violation("label_text_height","%s needs %.1f px for %d lines, got %.1f" % [_name(label),needed,label.get_line_count(),label.size.y])
		if label.get_visible_line_count() < label.get_line_count():
			_violation("label_hidden_lines","%s shows %d of %d lines" % [_name(label),label.get_visible_line_count(),label.get_line_count()])
	elif control is Button:
		var button := control as Button
		var font := button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var natural := font.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		var style := button.get_theme_stylebox("disabled" if button.disabled else "normal")
		var available := button.size-style.get_minimum_size()
		if natural.x > available.x+1.0 or natural.y > available.y+1.0:
			_violation("button_text_fit","%s natural=%s available=%s button=%s" % [_name(button),str(natural),str(available),str(button.size)])

func _inspect_layout(game: GameHarness, enemy_selection: bool, vanessa_selection: bool) -> void:
	var before: int = report.violations.size()
	var inspection := game.selection_label.text
	var required_fragments: Array = ["Здоровье:","Броня:","Скорость:","Награда:","Горит","замедлен","броня ослаблена"] if enemy_selection else ["ранг 5/5",game.CombatBalance.capstone_description(int(game.selected_tower.type))]
	if not enemy_selection and not vanessa_selection:
		required_fragments.append_array(["Урон:","Дальность:","Скорость:","Нить судьбы:"])
		if inspection.count("(+65%") < 2:
			_violation("missing_effective_stats","damage and speed aura gains are not both present")
	for fragment in required_fragments:
		if not inspection.contains(str(fragment)):
			_violation("missing_inspection_content","required text missing: "+str(fragment))
	var panel_rect := game.side_panel.get_global_rect()
	var clip_rect := game.side_scroll.get_global_rect().intersection(Rect2(Vector2.ZERO,Vector2(current_resolution)))
	var required: Array[Control] = [game.selection_label,game.start_button,game.pause_button,game.speed_select]
	for card in game.card_buttons:
		required.append(card)
	if not enemy_selection:
		required.append_array([game.upgrade_button,game.sell_button])
	if vanessa_selection:
		required.append_array([game.aura_damage_button,game.aura_speed_button])
	for control in required:
		if not control.is_visible_in_tree():
			_violation("required_hidden",_name(control))
	if enemy_selection and (game.upgrade_button.is_visible_in_tree() or game.sell_button.is_visible_in_tree()):
		_violation("enemy_actions_visible","tower upgrade/sell actions remain visible on enemy inspection")
	if not vanessa_selection and (game.aura_damage_button.is_visible_in_tree() or game.aura_speed_button.is_visible_in_tree()):
		_violation("wrong_aura_controls","aura controls are visible for a non-Vanessa selection")
	var controls := _visible_leaves(game.side_scroll)
	for control in controls:
		var rect := control.get_global_rect()
		if not panel_rect.grow(0.5).encloses(rect):
			_violation("outside_panel","%s rect=%s panel=%s" % [_name(control),str(rect),str(panel_rect)])
		if not clip_rect.grow(0.5).encloses(rect):
			_violation("clipped_by_scroll_or_viewport","%s rect=%s clip=%s" % [_name(control),str(rect),str(clip_rect)])
		_text_fit(control)
	for first in range(controls.size()):
		for second in range(first+1,controls.size()):
			if controls[first].get_global_rect().intersection(controls[second].get_global_rect()).get_area() > 0.5:
				_violation("overlap",_name(controls[first])+" with "+_name(controls[second]))
	if game.side_scroll.scroll_horizontal != 0 or game.side_scroll.scroll_vertical != 0:
		_violation("unexpected_scroll","inspection required a nonzero scroll offset")
	if game.side_scroll.get_v_scroll_bar().visible or game.side_scroll.get_h_scroll_bar().visible:
		_violation("visible_scrollbar","inspection needs a scrollbar")
	for slider in [game.music_slider,game.sfx_slider]:
		if not slider.is_visible_in_tree() or slider.get_global_rect().end.y > 70.0:
			_violation("audio_control","independent audio slider left the visible top bar")
	var label := game.selection_label
	report.cases.append({"resolution":"%dx%d" % [current_resolution.x,current_resolution.y],"selection":current_case,"text":label.text,"lines":label.get_line_count(),"visible_lines":label.get_visible_line_count(),"selection_rect":_bounds(label.get_global_rect()),"clip_rect":_bounds(clip_rect),"violations":report.violations.size()-before})

func _run() -> void:
	report["started_utc"] = Time.get_datetime_string_from_system(true)
	report["build_version"] = ProjectSettings.get_setting("application/config/version","")
	report["source_sha256"] = {"game":FileAccess.get_sha256("res://scripts/game.gd"),"combat_rules":FileAccess.get_sha256("res://scripts/combat_balance.gd"),"probe":FileAccess.get_sha256("res://tests/inspection_layout_smoke.gd")}
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600,900)
	var game := GameHarness.new()
	root.add_child(game)
	await process_frame
	await process_frame
	game.gold = 1000000
	for index in range(game.HEROES.size()):
		game.selected_type = index
		game._place_tower(Vector3(float(index)*2.0,0,0))
		if game.towers.size() != index+1:
			push_error("INSPECTION_LAYOUT_FAIL: production placement fixture failed")
			quit(1)
			return
		for rank in range(4):
			game._upgrade()
		if int(game.towers[-1].level) != 4:
			push_error("INSPECTION_LAYOUT_FAIL: production L5 upgrade fixture failed")
			quit(1)
			return
	game.towers[3].aura = "damage"
	game.selected_type = 3
	game._place_tower(Vector3(12.0,0,0))
	for rank in range(4):
		game._upgrade()
	game.towers[-1].aura = "speed"
	game.clock = 10.0
	for kind in game.ENEMY_KINDS:
		var enemy: Dictionary = game.CombatBalance.enemy_stats(kind,15,17,kind == "boss_troll")
		enemy.node = Node3D.new()
		game.enemy_root.add_child(enemy.node)
		enemy.height = 4.65 if kind == "boss_troll" else 2.2
		enemy.hp = float(enemy.max_hp)*0.613
		enemy.slow = 0.60 if kind == "boss_troll" else 0.12
		enemy.slow_until = 12.0
		enemy.burn_dps = 123.4
		enemy.burn_until = 13.0
		enemy.armor_shred = 14.0
		enemy.shred_until = 13.0
		game.enemies.append(enemy)
	for resolution in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		current_resolution = resolution
		root.size = resolution
		game._update_ui_layout()
		await process_frame
		await process_frame
		for index in range(game.HEROES.size()):
			current_case = "hero_"+str(game.HEROES[index].id)+"_L5_two_auras"
			game._select_tower(index)
			await process_frame
			await process_frame
			_inspect_layout(game,false,index == 3)
		game.towers[3].aura = "speed"
		current_case = "hero_vanessa_L5_speed"
		game._select_tower(3)
		await process_frame
		await process_frame
		_inspect_layout(game,false,true)
		game.towers[3].aura = "damage"
		for index in range(game.enemies.size()):
			current_case = "enemy_"+str(game.enemies[index].kind)+"_burn_slow_shred"
			game._select_enemy(index)
			await process_frame
			await process_frame
			_inspect_layout(game,true,false)
	var file := FileAccess.open("res://Builds/inspection-layout-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	var violations: int = report.violations.size()
	game.queue_free()
	await process_frame
	await process_frame
	if violations > 0:
		push_error("INSPECTION_LAYOUT_FAIL: %d violations across %d cases; see Builds/inspection-layout-report.json" % [violations,report.cases.size()])
		quit(1)
	else:
		print("INSPECTION_LAYOUT_OK: %d cases; six actual L5 heroes, both Vanessa modes, seven enemy types with status effects, three resolutions, text-fit/clip/visibility/overlap" % report.cases.size())
		quit(0)
