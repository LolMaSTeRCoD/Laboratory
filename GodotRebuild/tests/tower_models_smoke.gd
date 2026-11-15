extends SceneTree

const HEROES := ["asta","yuno","magna","vanessa","noelle","charmy"]
const LEVELS := 5

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for hero in HEROES:
		var geometry_counts: Array[int] = []
		for level in range(1,LEVELS+1):
			var path := "res://Assets/Heroes/%s_L%d.glb" % [hero,level]
			var packed := load(path) as PackedScene
			if packed == null:
				_fail("tower GLB failed to load: " + path)
				return
			var model := packed.instantiate() as Node3D
			if model == null:
				_fail("tower GLB is not a 3D scene: " + path)
				return
			root.add_child(model)
			await process_frame
			var skeleton := _find_class(model,"Skeleton3D") as Skeleton3D
			var animator := _find_class(model,"AnimationPlayer") as AnimationPlayer
			var idle_clip := _find_animation_clip(animator,"Idle")
			var attack_clip := _find_animation_clip(animator,"Attack")
			var meshes := _collect_skinned_meshes(model)
			if skeleton == null or skeleton.get_bone_count() < 163:
				_fail("%s L%d does not have the new anatomical/facial/finger rig" % [hero,level])
				return
			for required_bone in ["jaw","head","eye.L","finger2-3.R","finger5-3.L","cape","upper_arm.R","hand.R"]:
				if skeleton.find_bone(required_bone) < 0:
					_fail("%s L%d missing anatomical bone %s" % [hero,level,required_bone])
					return
			if animator == null or meshes.is_empty():
				_fail("%s L%d is missing its animated skinned 3D mesh" % [hero,level])
				return
			if idle_clip.is_empty() or attack_clip.is_empty():
				_fail("%s L%d is missing Idle or Attack animation: %s" % [hero,level,str(animator.get_animation_list())])
				return
			for clip_name in animator.get_animation_list():
				if not str(clip_name).begins_with(hero+"_"):
					_fail("%s L%d GLB contains another character's animation: %s" % [hero,level,str(clip_name)])
					return
			if animator.get_animation(attack_clip).get_track_count() < 5:
				_fail("%s L%d attack clip has too few skeletal tracks" % [hero,level])
				return
			var vertex_count := 0
			for mesh_instance in meshes:
				var mesh := mesh_instance.mesh
				if mesh == null:
					continue
				for surface in range(mesh.get_surface_count()):
					vertex_count += mesh.surface_get_array_len(surface)
					if mesh.surface_get_material(surface) == null:
						_fail("%s L%d has a material-less mesh surface" % [hero,level])
						return
			if vertex_count < 300:
				_fail("%s L%d has too little skinned geometry (%d vertices)" % [hero,level,vertex_count])
				return
			geometry_counts.append(vertex_count)
			if level == 1:
				animator.play(idle_clip)
				await create_timer(0.42).timeout
				var spine_bone := skeleton.find_bone("spine")
				if spine_bone < 0 or skeleton.get_bone_pose_rotation(spine_bone).angle_to(Quaternion.IDENTITY) < 0.01:
					_fail("%s idle clip does not animate the character body" % hero)
					return
				animator.play(attack_clip)
				animator.advance(0.0)
				var arm_bone := skeleton.find_bone("upper_arm.R")
				var before_strike := skeleton.get_bone_pose_rotation(arm_bone)
				var hand_bone := skeleton.find_bone("hand.R")
				var before_hand := _bone_model_position(model,skeleton,hand_bone)
				animator.advance(0.32)
				var striking := skeleton.get_bone_pose_rotation(arm_bone)
				if arm_bone < 0 or striking.angle_to(before_strike) < 0.1:
					_fail("%s attack clip does not visibly animate the arm" % hero)
					return
				# Imported glTF characters face +Z before gameplay yaw is applied.
				# A changed rotation alone also passes for a hand moving backwards
				# through its own skirt. Check the actual casting/sword hand path.
				var strike_hand := _bone_model_position(model,skeleton,hand_bone)
				if strike_hand.z-before_hand.z < 0.10:
					_fail("%s attack hand does not extend forwards: %s -> %s" % [hero,str(before_hand),str(strike_hand)])
					return
				animator.seek(animator.get_animation(attack_clip).length,true)
				animator.advance(0.0)
				if skeleton.get_bone_pose_rotation(arm_bone).angle_to(before_strike) > 0.08:
					_fail("%s attack does not recover to the idle arm stance" % hero)
					return
			model.queue_free()
			await process_frame
		print("TOWER_MODEL_OK: %s levels=%d bones=%d vertices=%s" % [hero,LEVELS,166,str(geometry_counts)])
		for level in range(1,LEVELS):
			if geometry_counts[level] == geometry_counts[level-1]:
				_fail("%s upgrade L%d has no measurable geometric change from L%d" % [hero,level+1,level])
				return
	print("TOWER_MODELS_SMOKE_OK: 30 skinned 3D hero variants, rigged meshes and articulated attacks")
	quit(0)

func _find_class(node: Node, wanted_class: String) -> Node:
	if node.get_class() == wanted_class:
		return node
	for child in node.get_children():
		var found := _find_class(child,wanted_class)
		if found != null:
			return found
	return null

func _bone_model_position(model: Node3D, skeleton: Skeleton3D, bone: int) -> Vector3:
	return model.to_local(skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))

func _collect_skinned_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.skin != null:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_skinned_meshes(child))
	return result

func _find_animation_clip(animator: AnimationPlayer, suffix: String) -> String:
	if animator == null:
		return ""
	for clip in animator.get_animation_list():
		if clip == suffix or clip.ends_with("_"+suffix):
			return clip
	return ""

func _fail(message: String) -> void:
	push_error("TOWER_MODELS_SMOKE_FAIL: " + message)
	quit(1)
