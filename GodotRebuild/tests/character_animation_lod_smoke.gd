extends SceneTree
const LOD=preload("res://scripts/character_lod.gd")
const DT:=1.0/60.0
var model: Node3D
var reference: Node3D
var ap: AnimationPlayer
var ref_ap: AnimationPlayer
var skeleton: Skeleton3D
var ref_skeleton: Skeleton3D
var record: Dictionary
var camera: Camera3D
func _initialize() -> void:call_deferred("_run")
func _find(node: Node,wanted: String) -> Node:
	if node.get_class()==wanted:return node
	for child in node.get_children():
		var found:=_find(child,wanted)
		if found!=null:return found
	return null
func _fail(message: String) -> bool:
	push_error("CHARACTER_ANIMATION_LOD_FAIL: "+message)
	quit(1)
	return false
func _same(label: String) -> bool:
	if absf(ap.current_animation_position-ref_ap.current_animation_position)>.0001:return _fail(label+" phase differs: "+str(ap.current_animation_position)+" vs "+str(ref_ap.current_animation_position))
	skeleton.force_update_all_bone_transforms();ref_skeleton.force_update_all_bone_transforms()
	for bone in ["foot.L","foot.R","thigh.L","head"]:
		var a:=skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		var b:=ref_skeleton.get_bone_global_pose(ref_skeleton.find_bone(bone))
		if a.origin.distance_to(b.origin)>.0002 or a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())>.001:return _fail(label+" pose differs: "+bone)
	return true
func _step(speed: float=1.0,duplicate: bool=false) -> void:
	await process_frame
	ap.speed_scale=speed;ref_ap.speed_scale=speed
	LOD.tick(record,DT)
	if duplicate:LOD.tick(record,DT)
	if ref_ap.active:ref_ap.advance(DT)
func _freeze_after_deferred_restore() -> void:
	# process_frame resumes before node internal callbacks. Freeze the harness
	# player before its next native callback; this does not alter the record's
	# stored original callback mode, and tests the previous frame's bridge only.
	await process_frame
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
func _run() -> void:
	Engine.max_fps=0
	root.size=Vector2i(1600,900)
	var packed:=load("res://Assets/Enemies/goblin.glb") as PackedScene
	model=packed.instantiate();reference=packed.instantiate()
	root.add_child(model);root.add_child(reference)
	ap=_find(model,"AnimationPlayer");ref_ap=_find(reference,"AnimationPlayer")
	skeleton=_find(model,"Skeleton3D");ref_skeleton=_find(reference,"Skeleton3D")
	record=LOD.attach(model,"res://Assets/Enemies/goblin.glb")
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ref_ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.play("enemy_goblin_Run");ref_ap.play("enemy_goblin_Run")
	ap.advance(0);ref_ap.advance(0)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera);camera.position=Vector3(0,3,5);camera.look_at(Vector3(0,1,0));camera.current=true;camera.size=70
	await process_frame
	LOD.update(record,camera)
	if not record.animation_lod_enabled or absf(record.animation_interval-LOD.ANIMATION_INTERVAL)>.0001:_fail("visible compact did not enter 30 Hz manual mode");return
	if float(record.animation_pending_delta)!=0.0 or ap.current_animation_position!=0.0:_fail("stagger advanced playback into future");return
	var first_wait:=float(record.animation_wait)
	var other:=packed.instantiate() as Node3D
	root.add_child(other)
	var other_record:=LOD.attach(other,"res://Assets/Enemies/goblin.glb")
	LOD.update(other_record,camera)
	if absf(first_wait-float(other_record.animation_wait))<.000001:_fail("actor deadlines are not staggered");return
	other.queue_free()
	record.animation_wait=LOD.ANIMATION_INTERVAL
	await _step();await _step()
	if not _same("two 60 Hz frames equal one 30 Hz pose"):return
	# A pending half-step is consumed exactly once when restoring high detail.
	record.animation_wait=LOD.ANIMATION_INTERVAL
	await _step()
	if float(record.animation_pending_delta)<=0.0:_fail("pending half-step was not accumulated");return
	await process_frame
	LOD.restore(record)
	LOD.tick(record,DT);ref_ap.advance(DT)
	if not _same("restore before tick consumes current delta once"):return
	await _freeze_after_deferred_restore()
	if not _same("deferred native resume did not double advance"):return
	LOD.update(record,camera)
	record.animation_wait=LOD.ANIMATION_INTERVAL
	await _step()
	# Restore after tick within that same engine frame; duplicate collection
	# membership must not consume the elapsed delta again.
	LOD.restore(record);LOD.tick(record,DT)
	if not _same("restore after tick and duplicate clock"):return
	await _freeze_after_deferred_restore()
	if not _same("restore-after-tick deferred resume"):return
	LOD.update(record,camera)
	record.animation_wait=LOD.ANIMATION_INTERVAL
	await _step(2.0);await _step(2.0)
	LOD._flush_animation(record)
	if not _same("Run speed_scale two"):return
	var held_phase:=ap.current_animation_position
	ap.active=false;ref_ap.active=false
	await _step();await _step()
	LOD._flush_animation(record)
	if ap.current_animation_position!=held_phase or float(record.animation_pending_delta)!=0.0:_fail("inactive mixer advanced or retained pending time");return
	if not _same("inactive mixer stays frozen"):return
	ap.active=true;ref_ap.active=true
	record.animation_wait=LOD.ANIMATION_INTERVAL
	await _step(1.0);await _step(0.0);await _step(0.0);await _step(1.0)
	LOD._flush_animation(record)
	if not _same("pause/unpause does not apply paused pending time"):return
	# Switch with pending Run time: new Death starts at its own zero clock.
	record.animation_wait=LOD.ANIMATION_INTERVAL
	await _step()
	ap.play("enemy_goblin_Death");ref_ap.play("enemy_goblin_Death")
	ap.advance(0);ref_ap.advance(0)
	await _step(1.0,true);await _step(1.0,true)
	LOD._flush_animation(record)
	if not _same("Death uses one clock, drops outgoing Run pending"):return
	# Large-but-offscreen geometry is allowed 10 Hz; coming into view flushes
	# its pending time before native drawing/animation resumes.
	model.position.x=100;camera.size=3
	LOD.update(record,camera)
	if not record.animation_lod_enabled or record.animation_model_visible or absf(record.animation_interval-LOD.OFFSCREEN_ANIMATION_INTERVAL)>.0001:_fail("offscreen high mesh did not enter 10 Hz");return
	await _step();await _step()
	model.position.x=0
	LOD.update(record,camera,true)
	if record.animation_lod_enabled:_fail("selected/forced high did not disable temporal LOD");return
	if not _same("return to visible full detail flushes pending"):return
	await _freeze_after_deferred_restore()
	if not _same("offscreen reentry has no double advance"):return
	model.queue_free();reference.queue_free();camera.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("CHARACTER_ANIMATION_LOD_SMOKE_OK: real Run/Death bones, elapsed-time equality, 30/10 Hz, stagger without future time, speed/pause, pending transitions and one clock")
	quit(0)
