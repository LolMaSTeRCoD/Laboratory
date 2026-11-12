extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for kind in ["goblin","orc","uruk","warg","troll","nazgul","boss_troll"]:
		var path := "res://Assets/Enemies/%s.glb" % kind
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("enemy asset failed to import as PackedScene: " + kind)
			return
		var instance := packed.instantiate()
		root.add_child(instance)
		await process_frame
		var skeleton := _find_class(instance,"Skeleton3D") as Skeleton3D
		var animator := _find_class(instance,"AnimationPlayer") as AnimationPlayer
		var mesh_count := _count_skinned_meshes(instance)
		if skeleton == null or skeleton.get_bone_count() < 15:
			_fail("enemy does not have a usable skeleton: " + kind)
			return
		if animator == null or mesh_count < 1:
			_fail("enemy is missing its animated 3D mesh: " + kind)
			return
		for clip_name in animator.get_animation_list():
			if not str(clip_name).begins_with("enemy_"+kind+"_"):
				_fail("%s GLB contains another enemy's animation: %s" % [kind,str(clip_name)])
				return
		var mesh := _find_class(instance,"MeshInstance3D") as MeshInstance3D
		if mesh == null or mesh.get_aabb().position.y < -0.05 or mesh.get_aabb().position.y > 0.12:
			_fail("enemy mesh origin is not aligned to the ground: " + kind)
			return
		var extras: Dictionary = mesh.get_meta("extras",{})
		if str(extras.get("enemy_pipeline","")) != "anatomical-v3":
			_fail("legacy enemy geometry was loaded instead of the rebuilt anatomical model: "+kind)
			return
		if kind != "warg" and skeleton.get_bone_count() < 160:
			_fail("rebuilt humanoid is missing its anatomical/finger skeleton: "+kind)
			return
		var vertex_count := 0
		for surface in range(mesh.mesh.get_surface_count()):
			vertex_count += mesh.mesh.surface_get_array_len(surface)
		if vertex_count < (1200 if kind=="warg" else 15000):
			_fail("rebuilt model has insufficient anatomical geometry: "+kind)
			return
		for clip in ["Idle","Run","Hit","Death"]:
			var clip_name := "enemy_%s_%s" % [kind,clip]
			if not animator.has_animation(clip_name):
				_fail("missing %s animation on %s" % [clip,kind])
				return
			if animator.get_animation(clip_name).get_track_count() < 5:
				_fail("%s clip does not animate enough rig tracks on %s" % [clip,kind])
				return
		var left_leg_bone := skeleton.find_bone("thigh.L")
		if left_leg_bone < 0:
			_fail("enemy skin has no independently animated leg bone: " + kind)
			return
		var run_clip_name := "enemy_%s_Run" % kind
		animator.get_animation(run_clip_name).loop_mode = Animation.LOOP_LINEAR
		animator.play(run_clip_name)
		animator.seek(0.06,true)
		skeleton.force_update_all_bone_transforms()
		var leg_rotation_a := skeleton.get_bone_pose_rotation(left_leg_bone)
		animator.seek(0.31,true)
		skeleton.force_update_all_bone_transforms()
		var leg_rotation_b := skeleton.get_bone_pose_rotation(left_leg_bone)
		if leg_rotation_a.angle_to(leg_rotation_b) < 0.15:
			_fail("Run clip is static or only twists the leg on " + kind)
			return
		var foot_bone := skeleton.find_bone("foot.L")
		var run_length := animator.get_animation(run_clip_name).length
		var metadata_cycle = _find_meta(instance,"run_cycle_seconds")
		if metadata_cycle == null or absf(run_length-float(metadata_cycle))>0.002:
			_fail("Run duration differs from its physical stride metadata on "+kind)
			return
		var stance_start := 0.55 if kind == "warg" else 0.05
		var swing_sample := 0.19 if kind == "warg" else 0.69
		animator.seek(run_length*stance_start,true)
		skeleton.force_update_all_bone_transforms()
		var planted_a := skeleton.get_bone_global_pose(foot_bone).origin
		animator.seek(run_length*(stance_start+0.20),true)
		skeleton.force_update_all_bone_transforms()
		var planted_b := skeleton.get_bone_global_pose(foot_bone).origin
		# A stance foot travels backwards with almost constant height. This
		# catches the old airborne/swimming gait and static-pose false positive.
		if absf(planted_a.y-planted_b.y) > 0.045 or planted_a.distance_to(planted_b) < 0.17:
			_fail("Run has no stable planted-foot phase on " + kind)
			return
		var rest_ankle_height := skeleton.get_bone_global_rest(foot_bone).origin.y
		if absf(planted_a.y-rest_ankle_height)>0.035 or absf(planted_b.y-rest_ankle_height)>0.035:
			_fail("Run stance foot floats above or sinks below its grounded anatomical ankle on "+kind)
			return
		animator.seek(run_length*swing_sample,true)
		skeleton.force_update_all_bone_transforms()
		var raised := skeleton.get_bone_global_pose(foot_bone).origin
		if raised.y < planted_a.y+0.075:
			_fail("Run does not lift the swing foot clear of the surface on " + kind)
			return
		var hit_name := "enemy_%s_Hit" % kind
		var chest_bone := skeleton.find_bone("chest")
		animator.play(hit_name)
		animator.seek(0.0,true)
		var hit_start := skeleton.get_bone_pose_rotation(chest_bone)
		animator.seek(animator.get_animation(hit_name).length*0.5,true)
		var hit_peak := skeleton.get_bone_pose_rotation(chest_bone)
		if hit_start.angle_to(hit_peak) < 0.15:
			_fail("Hit does not visibly react to impact on " + kind)
			return
		var death_name := "enemy_%s_Death" % kind
		animator.play(death_name)
		animator.seek(0.0,true)
		skeleton.force_update_all_bone_transforms()
		var head_bone := skeleton.find_bone("head")
		var upright_head := skeleton.get_bone_global_pose(head_bone).origin
		animator.seek(animator.get_animation(death_name).length,true)
		skeleton.force_update_all_bone_transforms()
		var fallen_head := skeleton.get_bone_global_pose(head_bone).origin
		if fallen_head.y > upright_head.y-0.45:
			_fail("Death returns to standing or never reaches a fallen pose on " + kind)
			return
		print("ENEMY_MODEL_OK: %s bones=%d skinned_meshes=%d" % [kind,skeleton.get_bone_count(),mesh_count])
		instance.queue_free()
	print("ENEMY_MODELS_SMOKE_OK: seven skinned GLBs; changing leg poses, grounded stance, raised swing feet and permanent fallen Death endpoints")
	await process_frame
	await create_timer(0.2).timeout
	call_deferred("quit",0)

func _find_class(node: Node, wanted_class: String) -> Node:
	if node.get_class() == wanted_class:
		return node
	for child in node.get_children():
		var found := _find_class(child,wanted_class)
		if found != null:
			return found
	return null

func _find_meta(node: Node, key: String):
	var extras: Dictionary = node.get_meta("extras",{})
	if extras.has(key): return extras[key]
	for child in node.get_children():
		var found = _find_meta(child,key)
		if found!=null:return found
	return null

func _count_skinned_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D and node.skin != null else 0
	for child in node.get_children():
		total += _count_skinned_meshes(child)
	return total

func _fail(message: String) -> void:
	push_error("ENEMY_MODELS_SMOKE_FAIL: " + message)
	quit(1)
