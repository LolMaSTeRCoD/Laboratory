extends SceneTree
## Imported rigs must launch spells from the moving hands, including after
## model rotation/scaling and when the effects container has its own transform.

class EffectsHarness extends Node3D:
	func acquire_flight(_hero: int) -> Node3D:
		var flight := Node3D.new()
		add_child(flight)
		return flight

class GameHarness extends "res://scripts/game.gd":
	func _ready() -> void:
		set_process(false)
		magic_effects = EffectsHarness.new()
		add_child(magic_effects)
		camera = Camera3D.new()
		add_child(camera)
	func _play_sfx(_path: String,_position: Vector3) -> void:
		pass
	func _exit_tree() -> void:
		pass

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SPELL_ORIGIN_FAIL: "+message)

func _run() -> void:
	var game := GameHarness.new()
	root.add_child(game)
	game.position = Vector3(3,2,-4)
	game.magic_effects.position = Vector3(-2,0.3,1)
	game.magic_effects.rotation.y = -0.4
	for hero in range(game.HEROES.size()):
		for level in [1,5]:
			var tag: String = "%s L%d" % [game.HEROES[hero].id,level]
			var packed := load("res://Assets/Heroes/%s_L%d.glb" % [game.HEROES[hero].id,level]) as PackedScene
			_expect(packed != null,tag+" loads")
			if packed == null:
				continue
			var holder := Node3D.new()
			game.add_child(holder)
			holder.position = Vector3(8,0,-6)
			holder.rotation.y = 1.14
			holder.scale = Vector3.ONE*1.23
			var tower := {"type":hero,"level":level-1,"node":holder,"model_root":holder}
			game.tower_model_cache["res://Assets/Heroes/%s_L%d.glb" % [game.HEROES[hero].id,level]] = packed
			game._load_tower_model(tower)
			var skeleton: Skeleton3D = tower.get("skeleton")
			var player: AnimationPlayer = tower.get("animator")
			_expect(skeleton != null and player != null,tag+" has rig and animation")
			if skeleton == null or player == null:
				holder.queue_free()
				await process_frame
				continue
			var right := skeleton.find_bone("hand.R")
			var left := skeleton.find_bone("hand.L")
			_expect(right >= 0 and left >= 0,tag+" has both launch hands")
			if right < 0 or left < 0:
				holder.queue_free()
				await process_frame
				continue
			var attack: String = game._find_animation_clip(player,"Attack")
			var ability: String = game._find_animation_clip(player,"Ability")
			_expect(not attack.is_empty() and not ability.is_empty(),tag+" has attack and upgrade ability clips")
			if attack.is_empty():
				holder.queue_free()
				await process_frame
				continue
			player.play(attack)
			var target_node := Node3D.new()
			game.add_child(target_node)
			target_node.position = Vector3(20,0,10)
			var target := {"node":target_node,"height":2.0}
			var first := Vector3.ZERO
			var travel := 0.0
			for fraction in [0.0,0.15,0.35,0.65,0.85]:
				player.seek(player.get_animation(attack).length*fraction,true)
				player.advance(0.0)
				skeleton.force_update_all_bone_transforms()
				var hand := skeleton.get_bone_global_pose(right).origin
				if hero == 5:
					hand = (hand+skeleton.get_bone_global_pose(left).origin)*0.5
				var expected := skeleton.global_transform*hand+skeleton.global_basis.y.normalized()*0.045
				var actual: Vector3 = game.magic_effects.to_global(game._tower_projectile_origin(tower))
				_expect(actual.distance_to(expected) < 0.0001,tag+" launch remains attached to animated hands at "+str(fraction))
				game._fire_bolt(tower,target,17.0)
				var projectile: Node3D = game.bolts.back().node
				_expect(projectile.global_position.distance_to(expected) < 0.0001,tag+" real fired projectile uses the attached hand at "+str(fraction))
				game.bolts.clear()
				projectile.free()
				if fraction == 0.0:
					first = actual
				travel = maxf(travel,first.distance_to(actual))
			_expect(travel > 0.08,tag+" animated launch hand moves, rather than a fixed muzzle")
			target_node.queue_free()
			holder.queue_free()
			await process_frame
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("SPELL_ORIGIN_OK: %d checks; 12 imported rigs, attack motion, Charmy two-hand midpoint, transformed parents" % checks)
	call_deferred("quit",0 if failures.is_empty() else 1)
