extends SceneTree

const GAME_SCENE := preload("res://scenes/game.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("CAMERA_ORBIT_FAIL: "+message)
	quit(1)

func _mouse(viewport: Viewport, position: Vector2, button: int=0, pressed: bool=false) -> void:
	if button==0:
		var motion:=InputEventMouseMotion.new()
		motion.position=position
		motion.global_position=position
		viewport.push_input(motion,true)
	else:
		var click:=InputEventMouseButton.new()
		click.position=position
		click.global_position=position
		click.button_index=button
		click.pressed=pressed
		viewport.push_input(click,true)

func _run() -> void:
	root.size=Vector2i(1600,900)
	var game: Node3D=GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var deadline:=Time.get_ticks_msec()+30000
	while not game.call("_initial_tower_models_ready") or not game.call("_enemy_models_ready"):
		if Time.get_ticks_msec()>deadline:
			_fail("initial models did not finish loading")
			return
		await create_timer(0.01).timeout
	var camera: Camera3D=game.get("camera")
	var width: float=game.get("world_size")
	var corners: Array[Vector3]=[]
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]: corners.append(Vector3(width*0.5*x,0.0,width*0.36*z))
	var roundtrips:=0
	for yaw in [0.0,90.0,180.0,270.0]:
		for pitch in [20.0,67.0,80.0]:
			game.set("camera_yaw",deg_to_rad(yaw))
			game.set("camera_pitch",deg_to_rad(pitch))
			game.set("camera_size",game.call("_camera_max_size"))
			game.set("camera_target",game.call("_camera_fit_center"))
			game.call("_update_camera")
			var field: Rect2=game.call("_camera_usable_rect")
			for point in corners+[Vector3.ZERO,Vector3(-12.0,0.0,8.0),Vector3(13.0,0.0,-11.0)]:
				var projected: Vector2=camera.unproject_position(point)
				if not field.has_point(projected):
					_fail("ground outside usable field at yaw=%g pitch=%g: %s"%[yaw,pitch,str(projected)])
					return
				var returned: Vector3=game.call("_screen_to_ground",projected)
				if returned.distance_to(point)>0.015:
					_fail("screen/ground roundtrip changes at yaw=%g pitch=%g"%[yaw,pitch])
					return
				roundtrips+=1
			var cursor:=field.get_center()+Vector2(53.0,-41.0)
			var anchor_before: Vector3=game.call("_screen_to_ground",cursor)
			game.call("_zoom_at",cursor,0.70)
			var anchor_after: Vector3=game.call("_screen_to_ground",cursor)
			if anchor_before.distance_to(anchor_after)>0.02:
				_fail("cursor zoom drift at yaw=%g pitch=%g"%[yaw,pitch])
				return
			game.call("_zoom_at",cursor,1000.0)
			if absf(float(game.get("camera_size"))-float(game.call("_camera_max_size")))>0.001:
				_fail("maximum zoom-out changed at rotated angle")
				return
	# The low/high limits remain useful viewing angles, and yaw wraps through 360°.
	game.call("_reset_camera_view")
	game.call("_orbit_camera",Vector2(10000,10000))
	if absf(float(game.get("camera_pitch"))-deg_to_rad(80.0))>0.001:
		_fail("upper pitch limit is not 80 degrees")
		return
	game.call("_orbit_camera",Vector2(-20000,-20000))
	if absf(float(game.get("camera_pitch"))-deg_to_rad(20.0))>0.001:
		_fail("lower pitch limit is not 20 degrees")
		return
	if float(game.get("camera_yaw"))<0.0 or float(game.get("camera_yaw"))>=TAU:
		_fail("orbit yaw did not wrap into a complete turn")
		return
	# Real input: middle drag can cross the HUD, and its release always ends orbit.
	game.call("_reset_camera_view")
	var field: Rect2=game.call("_camera_usable_rect")
	var start:=field.get_center()
	var panel: Control=game.get("side_panel")
	var over_panel:=panel.get_global_rect().get_center()
	_mouse(root,start,MOUSE_BUTTON_MIDDLE,true)
	await process_frame
	if not bool(game.get("camera_orbiting")):
		_fail("middle button did not begin orbit")
		return
	_mouse(root,start+Vector2(72,24))
	await process_frame
	var moved_yaw: float=game.get("camera_yaw")
	if minf(moved_yaw,TAU-moved_yaw)<0.10:
		_fail("middle drag does not rotate the camera")
		return
	_mouse(root,over_panel,MOUSE_BUTTON_MIDDLE,false)
	await process_frame
	if bool(game.get("camera_orbiting")):
		_fail("middle release over HUD left orbit stuck")
		return
	var released_yaw: float=game.get("camera_yaw")
	_mouse(root,start+Vector2(20,20))
	await process_frame
	if absf(float(game.get("camera_yaw"))-released_yaw)>0.001:
		_fail("camera keeps rotating after middle release")
		return
	var home:=InputEventKey.new()
	home.keycode=KEY_HOME
	home.pressed=true
	root.push_input(home,true)
	await process_frame
	var default_pitch: float = game.get_script().get_script_constant_map()["CAMERA_DEFAULT_PITCH"]
	if absf(float(game.get("camera_yaw")))>0.001 or absf(float(game.get("camera_pitch"))-default_pitch)>0.001 or absf(float(game.get("camera_size"))-float(game.call("_camera_max_size")))>0.001:
		_fail("Home did not reset the map view")
		return
	home = null
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.20).timeout
	call_deferred("_finish_success",roundtrips)

func _finish_success(roundtrips: int) -> void:
	print("CAMERA_ORBIT_SMOKE_OK: %d ground roundtrips, 4 cardinal yaws x3 pitches, fitted map, cursor zoom, pitch/yaw limits, middle-drag HUD release and Home reset"%roundtrips)
	quit(0)
