extends RefCounted
## Two real 3D mesh tiers, one MeshInstance3D and its existing Skeleton/Skin.
## Animation keeps its original frame rate and phase through mesh transitions.
const ROOT:="res://Assets/CharacterLOD/"
const ENTER_LOW_PIXELS:=90.0
const EXIT_LOW_PIXELS:=130.0
const ANIMATION_INTERVAL:=1.0/30.0
const OFFSCREEN_ANIMATION_INTERVAL:=1.0/10.0
static func _find(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.skin!=null:return node
	for child in node.get_children():
		var found:=_find(child)
		if found!=null:return found
	return null
static func attach(model: Node3D,source_path: String) -> Dictionary:
	var instance:=_find(model)
	if instance==null:return {}
	var high:=instance.mesh as ArrayMesh
	var low_path:=ROOT+source_path.trim_prefix("res://Assets/").get_basename()+".res"
	if not ResourceLoader.exists(low_path):return {}
	var low:=load(low_path) as ArrayMesh
	if low==null or high==null or high.get_surface_count()!=low.get_surface_count():return {}
	if int(low.get_meta("source_vertices",-1))!=high.surface_get_array_len(0):return {}
	if int(low.get_meta("source_indices",-1))!=high.surface_get_array_index_len(0):return {}
	if int(low.get_meta("source_skin_bind_count",-1))!=instance.skin.get_bind_count():return {}
	for surface in range(high.get_surface_count()):
		var material:=high.surface_get_material(surface)
		if low.surface_get_material(surface)!=material:low.surface_set_material(surface,material)
	var players:=model.find_children("*","AnimationPlayer",true,false)
	var animator:=players[0] as AnimationPlayer if not players.is_empty() else null
	return {"instance":instance,"high":high,"low":low,"is_low":false,"projected_pixels":0.0,"source":source_path,
		"animator":animator,"animation_native_callback":animator.callback_mode_process if animator!=null else -1,
		"animation_lod_enabled":false,"animation_pending_delta":0.0,"animation_wait":0.0,
		"animation_interval":ANIMATION_INTERVAL,"animation_model_visible":true,
		"animation_pending_speed":1.0,"animation_clip":"","animation_last_position":0.0,
		"animation_last_tick_frame":-1,"animation_restore_frame":-1,"animation_callback_generation":0}
static func projected_height(record: Dictionary,camera: Camera3D) -> float:
	if record.is_empty() or not is_instance_valid(record.get("instance")):return 0.0
	var instance: MeshInstance3D=record.instance
	var bounds: AABB=record.high.get_aabb()
	# unproject_position uses logical viewport coordinates. Multiply by canvas
	# stretch and 3D scale to use actual output pixels without ViewportTexture's
	# doubled-size reporting on stretched root windows.
	var viewport:=camera.get_viewport()
	var scale:=viewport.get_stretch_transform().get_scale()*viewport.scaling_3d_scale
	var minimum:=Vector2(INF,INF)
	var maximum:=Vector2(-INF,-INF)
	var visible_corners:=0
	# Height alone misses quadrupeds, long weapons and rotated poses. Project
	# the complete bound in camera space, then choose its larger screen extent.
	for corner in range(8):
		var world:=instance.to_global(bounds.get_endpoint(corner))
		if camera.is_position_behind(world):continue
		var pixel:=camera.unproject_position(world)*scale
		minimum=minimum.min(pixel);maximum=maximum.max(pixel)
		visible_corners+=1
	if visible_corners==0:return 0.0
	var extent:=maximum-minimum
	return maxf(extent.x,extent.y)
static func update(record: Dictionary,camera: Camera3D,force_high: bool=false) -> void:
	if record.is_empty() or not is_instance_valid(record.get("instance")) or camera==null:return
	var pixels:=projected_height(record,camera)
	record.projected_pixels=pixels
	var want_low:=not force_high and (pixels<EXIT_LOW_PIXELS if bool(record.is_low) else pixels<ENTER_LOW_PIXELS)
	var instance: MeshInstance3D=record.instance
	if want_low!=bool(record.is_low):
		instance.mesh=record.low if want_low else record.high
		record.is_low=want_low
	# Use an expanded volume, not just its centre: a partially visible long
	# model must never be mistaken for an offscreen actor. Checked at mesh-LOD
	# refresh cadence, with roughly one body width of conservative margin.
	var visible:=instance.is_visible_in_tree() and _visible_with_margin(instance,record.high.get_aabb(),camera)
	record.animation_model_visible=visible
	var interval:=0.0
	if not force_high:
		if not visible:interval=OFFSCREEN_ANIMATION_INTERVAL
		elif want_low and pixels<ENTER_LOW_PIXELS:interval=ANIMATION_INTERVAL
	if interval>0.0:_enable_animation_lod(record,interval)
	else:_disable_animation_lod(record)

static func _visible_with_margin(instance: MeshInstance3D,bounds: AABB,camera: Camera3D) -> bool:
	var world: AABB=instance.global_transform*bounds.grow(bounds.size.length()*.5)
	var center:=world.get_center()
	var half:=world.size*.5
	var inside:=camera.global_position-camera.global_basis.z*((camera.near+camera.far)*.5)
	for plane: Plane in camera.get_frustum():
		var sign_inside:=1.0 if plane.distance_to(inside)>=0.0 else -1.0
		var radius:=absf(plane.normal.x)*half.x+absf(plane.normal.y)*half.y+absf(plane.normal.z)*half.z
		if plane.distance_to(center)*sign_inside+radius<0.0:return false
	return true

static func _remember_animation(record: Dictionary,animator: AnimationPlayer) -> void:
	record.animation_clip=animator.current_animation
	record.animation_last_position=animator.current_animation_position if not animator.current_animation.is_empty() else 0.0
	record.animation_pending_speed=animator.speed_scale

static func _flush_animation(record: Dictionary) -> void:
	var animator:=record.get("animator") as AnimationPlayer
	if not is_instance_valid(animator):return
	if not animator.active:
		record.animation_pending_delta=0.0
		_remember_animation(record,animator)
		return
	var pending:=float(record.animation_pending_delta)
	# A new clip/restart has its own clock. Never advance Death by time that
	# belonged to the outgoing Run pose, or advance a newly stopped player.
	var unchanged:=animator.current_animation==str(record.animation_clip)
	if unchanged and not animator.current_animation.is_empty():
		unchanged=absf(animator.current_animation_position-float(record.animation_last_position))<.00001
	if pending>0.0 and unchanged and animator.is_playing():
		var current_speed:=animator.speed_scale
		animator.speed_scale=float(record.animation_pending_speed)
		animator.advance(pending)
		animator.speed_scale=current_speed
	record.animation_pending_delta=0.0
	_remember_animation(record,animator)

static func _enable_animation_lod(record: Dictionary,interval: float=ANIMATION_INTERVAL) -> void:
	var animator:=record.get("animator") as AnimationPlayer
	if not is_instance_valid(animator):return
	if not animator.active:return
	if bool(record.animation_lod_enabled):
		if absf(float(record.animation_interval)-interval)>.000001:
			_flush_animation(record)
			record.animation_interval=interval
			record.animation_wait=interval
		return
	if int(record.animation_native_callback)==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:return
	record.animation_callback_generation+=1
	record.animation_lod_enabled=true
	record.animation_pending_delta=0.0
	record.animation_interval=interval
	# Deterministic scheduling offset, separate from accumulated real time.
	# It distributes pose evaluations without advancing anyone into the future.
	var slot:=int(animator.get_instance_id()%997)*53%997
	record.animation_wait=interval*float(slot+1)/998.0
	record.animation_restore_frame=-1
	_remember_animation(record,animator)
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

static func _finish_animation_restore(record: Dictionary,generation: int) -> void:
	if int(record.animation_callback_generation)!=generation or bool(record.animation_lod_enabled):return
	var animator:=record.get("animator") as AnimationPlayer
	if not is_instance_valid(animator):return
	# A deferred call may still execute before internal node processing in the
	# same frame (for example from a process_frame coroutine). Resume at the
	# next process-frame boundary, never merely at the next message-queue flush.
	await animator.get_tree().process_frame
	if int(record.animation_callback_generation)!=generation or bool(record.animation_lod_enabled):return
	if is_instance_valid(animator):animator.callback_mode_process=int(record.animation_native_callback)
	record.animation_restore_frame=-1

static func _disable_animation_lod(record: Dictionary) -> void:
	if not bool(record.get("animation_lod_enabled",false)):return
	_flush_animation(record)
	record.animation_lod_enabled=false
	record.animation_restore_frame=Engine.get_process_frames()
	record.animation_callback_generation+=1
	# Restoring native processing immediately from a parent's _process could
	# let its child AnimationPlayer consume the same frame delta a second time.
	_finish_animation_restore.bind(record,int(record.animation_callback_generation)).call_deferred()

static func tick(record: Dictionary,delta: float) -> void:
	if record.is_empty():return
	var animator:=record.get("animator") as AnimationPlayer
	if not is_instance_valid(animator):return
	var frame:=Engine.get_process_frames()
	# A dying actor can move collections in the same frame. It has one clock.
	if int(record.animation_last_tick_frame)==frame:return
	record.animation_last_tick_frame=frame
	if not animator.active:
		record.animation_pending_delta=0.0
		_remember_animation(record,animator)
		return
	if not bool(record.animation_lod_enabled):
		if int(record.animation_restore_frame)==frame and animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			animator.advance(maxf(0.0,delta))
		return
	if animator.current_animation!=str(record.animation_clip) or (not animator.current_animation.is_empty() and absf(animator.current_animation_position-float(record.animation_last_position))>=.00001):
		record.animation_pending_delta=0.0
		_remember_animation(record,animator)
	elif animator.speed_scale!=float(record.animation_pending_speed):
		_flush_animation(record)
	if not animator.is_playing():
		record.animation_pending_delta=0.0
		return
	record.animation_pending_delta+=maxf(0.0,delta)
	record.animation_wait-=maxf(0.0,delta)
	if float(record.animation_wait)<=0.0:
		_flush_animation(record)
		var interval:=float(record.animation_interval)
		record.animation_wait+=interval*(floor(-float(record.animation_wait)/interval)+1.0)
static func restore(record: Dictionary) -> void:
	if record.is_empty() or not is_instance_valid(record.get("instance")):return
	record.instance.mesh=record.high
	record.is_low=false
	_disable_animation_lod(record)
