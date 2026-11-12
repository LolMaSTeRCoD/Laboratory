extends SceneTree
## Projected UI regression; no character resources or GPU rendering required.

const GAME_SCRIPT := preload("res://scripts/game.gd")

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("HEALTH_BAR_FAIL: "+message)
	quit(1)

func _run() -> void:
	root.size = Vector2i(1600,900)
	# Keep the game script outside the tree: this isolates the actual health-bar
	# helpers without loading a world or changing the player's saved settings.
	var game: Node3D = GAME_SCRIPT.new()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.current = true
	game.set("camera",camera)
	game.set("paused",true)
	var actor := Node3D.new()
	actor.scale = Vector3.ONE*1.17
	root.add_child(actor)
	# Same two layers of scale as a late-arena troll: actor scale on the parent,
	# and a separate 1.5x model beneath it. Height must account for both once.
	var model := Node3D.new()
	model.scale = Vector3.ONE*1.5
	actor.add_child(model)
	var source_model_height := 2.322
	var local_model_height := source_model_height*model.scale.y
	var bar: MeshInstance3D = game.call("_create_enemy_health_bar",local_model_height)
	actor.add_child(bar)
	var enemy := {"node":actor,"model":model,"bar":bar,"hp":100.0,"max_hp":100.0}
	game.get("enemies").append(enemy)
	game.set("camera_target",Vector3(0,2.5,0))
	game.set("camera_size",15.0)
	var cases := 0
	for yaw in [0.0,1.2]:
		for pitch in [deg_to_rad(25.0),deg_to_rad(70.0)]:
			for heading in [0.0,2.1,PI]:
				actor.rotation.y = heading
				game.set("camera_yaw",yaw)
				game.set("camera_pitch",pitch)
				# This exercises the real camera update path while the game is paused.
				game.call("_update_camera")
				for fraction in [1.0,0.37,0.0]:
					enemy.hp = 100.0*fraction
					game.call("_update_enemy_health_bar",enemy)
					await process_frame
					if bar.visible != (fraction>0.0):
						_fail("bar visibility does not match living/dead HP")
						return
					if fraction == 0.0:
						cases += 1
						continue
					var left := bar.global_transform*Vector3(-0.45,0,0)
					var right := bar.global_transform*Vector3(0.45,0,0)
					var screen_left := camera.unproject_position(left)
					var screen_right := camera.unproject_position(right)
					if absf(screen_left.y-screen_right.y)>0.02 or screen_right.x<=screen_left.x:
						_fail("projected bar is not horizontal and left-to-right at camera yaw/pitch and NPC heading")
						return
					if bar.global_basis.z.normalized().dot(camera.global_basis.z.normalized())<0.999:
						_fail("bar face does not follow the camera")
						return
					var scale_value := 1.17
					var expected_width: float = 0.9*scale_value*float(fraction)
					if absf(left.distance_to(right)-expected_width)>0.0005:
						_fail("HP fill or actor scale changed the bar's bounded world-space width")
						return
					var head_anchor := Vector3(0,(local_model_height+0.28)*scale_value,0)
					var expected_left := head_anchor-camera.global_basis.x.normalized()*0.45*scale_value
					if left.distance_to(expected_left)>0.0005:
						_fail("HP fill moved the left edge or double-applied the model/parent height scale")
						return
					cases += 1
	# Zoom must change screen size, not make a fixed-pixel UI bar grow in world space.
	enemy.hp = 100.0
	game.call("_update_enemy_health_bar",enemy)
	var left := bar.global_transform*Vector3(-0.45,0,0)
	var right := bar.global_transform*Vector3(0.45,0,0)
	var old_screen_width := camera.unproject_position(right).x-camera.unproject_position(left).x
	game.set("camera_size",30.0)
	game.call("_update_camera")
	await process_frame
	var new_screen_width := camera.unproject_position(right).x-camera.unproject_position(left).x
	if absf(new_screen_width/old_screen_width-0.5)>0.005:
		_fail("health bar screen size does not track normal orthographic zoom")
		return
	game.get("enemies").clear()
	game.free()
	actor.queue_free()
	camera.queue_free()
	await process_frame
	print("HEALTH_BAR_SMOKE_OK: %d camera-yaw/pitch, NPC-heading and HP-fill cases; screen-horizontal, camera-facing, left anchored, parent/model scale and bounded zoom"%cases)
	quit(0)
