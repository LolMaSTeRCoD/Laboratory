extends SceneTree
const LOD=preload("res://scripts/character_lod.gd")
var model_rows:=0
var checked_influences:=0
func _initialize() -> void:call_deferred("_run")
func _find(node: Node,wanted: String) -> Node:
	if node.get_class()==wanted:return node
	for child in node.get_children():
		var found:=_find(child,wanted)
		if found!=null:return found
	return null
func _fail(text: String) -> void:
	push_error("CHARACTER_LOD_FAIL: "+text)
	quit(1)
func _check(path: String) -> bool:
	var packed:=load(path) as PackedScene
	var model:=packed.instantiate()
	# Keep failed diagnostic instances owned by the tree too, so a genuine
	# assertion failure does not mask its cause with unparented RID leaks.
	root.add_child(model)
	var instance:=_find(model,"MeshInstance3D") as MeshInstance3D
	var high:=instance.mesh as ArrayMesh
	var low_path: String=LOD.ROOT+path.trim_prefix("res://Assets/").get_basename()+".res"
	var low:=load(low_path) as ArrayMesh
	if low==null or str(low.get_meta("pipeline",""))!="compacted-import-lod-v1":_fail("missing compacted mesh: "+path);return false
	if str(low.get_meta("source_sha256",""))!=FileAccess.get_sha256(path):_fail("source GLB changed without rebuilding LOD: "+path);return false
	if low.surface_get_array_len(0)>=high.surface_get_array_len(0)*.55:_fail("insufficient vertex reduction: "+path);return false
	var skin:=instance.skin
	var bind_names: Array=low.get_meta("source_bind_names")
	var bind_bones: Array=low.get_meta("source_bind_bones")
	if skin.get_bind_count()!=bind_names.size():_fail("skin bind count differs: "+path);return false
	for bind in range(skin.get_bind_count()):
		if str(skin.get_bind_name(bind))!=bind_names[bind] or skin.get_bind_bone(bind)!=bind_bones[bind]:_fail("skin binding reordered: "+path);return false
	var old:=high.surface_get_arrays(0)
	var compact:=low.surface_get_arrays(0)
	var low_surfaces: Array=low.get("_surfaces")
	var index_lods: Array=low_surfaces[0].get("lods",[])
	var index_stride:=2 if low.surface_get_array_len(0)<=65536 else 4
	for lod_index in range(0,index_lods.size(),2):
		var bytes: PackedByteArray=index_lods[lod_index+1]
		if bytes.size()%(3*index_stride)!=0:_fail("coarser LOD has incomplete triangles: "+path);return false
		for offset in range(0,bytes.size(),index_stride):
			var index:=bytes.decode_u16(offset) if index_stride==2 else bytes.decode_u32(offset)
			if index>=low.surface_get_array_len(0):_fail("coarser LOD references a removed vertex: "+path);return false
	var used: PackedInt32Array=low.get_meta("source_vertex_indices")
	var stride: int=old[Mesh.ARRAY_BONES].size()/high.surface_get_array_len(0)
	for vertex in range(used.size()):
		for influence in range(stride):
			var old_index:=used[vertex]*stride+influence
			var new_index:=vertex*stride+influence
			if compact[Mesh.ARRAY_BONES][new_index]!=old[Mesh.ARRAY_BONES][old_index]:_fail("bone influence index changed: "+path);return false
			if absf(compact[Mesh.ARRAY_WEIGHTS][new_index]-old[Mesh.ARRAY_WEIGHTS][old_index])>.00004:_fail("bone influence weight changed: "+path);return false
			checked_influences+=1
		if vertex%97==0:
			if compact[Mesh.ARRAY_VERTEX][vertex].distance_to(old[Mesh.ARRAY_VERTEX][used[vertex]])>.0005:_fail("geometry differs from selected source LOD: "+path);return false
			if compact[Mesh.ARRAY_TEX_UV][vertex].distance_to(old[Mesh.ARRAY_TEX_UV][used[vertex]])>.0005:_fail("UV atlas position changed: "+path);return false
	model.free()
	model_rows+=1
	return true
func _run() -> void:
	for kind in ["goblin","orc","uruk","troll","nazgul","warg","boss_troll"]:
		if not _check("res://Assets/Enemies/"+kind+".glb"):return
	for hero in ["asta","yuno","magna","vanessa","noelle","charmy"]:
		for level in range(1,6):
			if not _check("res://Assets/Heroes/%s_L%d.glb"%[hero,level]):return
	root.size=Vector2i(1600,900)
	var model:=load("res://Assets/Enemies/goblin.glb").instantiate() as Node3D
	root.add_child(model)
	var instance:=_find(model,"MeshInstance3D") as MeshInstance3D
	var skeleton:=_find(model,"Skeleton3D") as Skeleton3D
	var animator:=_find(model,"AnimationPlayer") as AnimationPlayer
	var original_skin:=instance.skin
	var original_mesh:=instance.mesh
	var original_skeleton_path:=instance.skeleton
	var original_nodes:=model.get_child_count()
	var record: Dictionary=LOD.attach(model,"res://Assets/Enemies/goblin.glb")
	if record.is_empty():_fail("runtime attach failed");return
	if record.low.surface_get_material(0)!=original_mesh.surface_get_material(0):_fail("low does not share original material");return
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.position=Vector3(0,3,5)
	camera.look_at(Vector3(0,1,0))
	camera.current=true
	await process_frame
	animator.play("enemy_goblin_Run")
	animator.seek(.16,true)
	skeleton.force_update_all_bone_transforms()
	var phase:=animator.current_animation_position
	var foot:=skeleton.get_bone_global_pose(skeleton.find_bone("foot.L"))
	camera.size=70
	LOD.update(record,camera)
	if not record.is_low or instance.mesh!=record.low:_fail("far projected size did not select low mesh");return
	if instance.skin!=original_skin or instance.skeleton!=original_skeleton_path or model.get_child_count()!=original_nodes:_fail("LOD duplicated or replaced skeleton/skin");return
	skeleton.force_update_all_bone_transforms()
	if foot.origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone("foot.L")).origin)>.0001 or animator.current_animation_position!=phase:_fail("switch reset gait phase/pose");return
	camera.size=3
	LOD.update(record,camera)
	if record.is_low or instance.mesh!=original_mesh:_fail("near detail did not restore original mesh");return
	# Around the hysteresis band, neither mesh should flicker back and forth.
	var near_pixels: float=LOD.projected_height(record,camera)
	camera.size*=near_pixels/110.0
	LOD.update(record,camera)
	if record.is_low:_fail("high-to-low hysteresis was lost");return
	camera.size=70
	LOD.update(record,camera)
	camera.size=3*near_pixels/110.0
	LOD.update(record,camera)
	if not record.is_low:_fail("low-to-high hysteresis was lost");return
	LOD.update(record,camera,true)
	if record.is_low:_fail("selected/forced-high override did not restore original");return
	# A quadruped can fill hundreds of pixels lengthwise while its vertical
	# centreline is still tiny. Test camera pitch and orbit, not just height.
	var warg:=load("res://Assets/Enemies/warg.glb").instantiate() as Node3D
	root.add_child(warg)
	var warg_lod: Dictionary=LOD.attach(warg,"res://Assets/Enemies/warg.glb")
	for location in [Vector3(0,8,5.6),Vector3(5.6,8,0)]:
		camera.position=location
		camera.look_at(Vector3(0,.6,0))
		camera.size=70
		LOD.update(warg_lod,camera)
		if not warg_lod.is_low:_fail("far warg did not use compact geometry");return
		camera.size=15
		LOD.update(warg_lod,camera)
		if float(warg_lod.projected_pixels)<=LOD.EXIT_LOW_PIXELS or warg_lod.is_low:_fail("long warg stayed low at rotated close camera: "+str(warg_lod.projected_pixels));return
	warg.queue_free()
	model.queue_free();camera.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("CHARACTER_LOD_SMOKE_OK: %d meshes, %d exact bone influences, valid coarser index LODs, source hashes, UV/positions, shared Skin/material, projected size, hysteresis and unchanged Run phase"%[model_rows,checked_influences])
	call_deferred("quit",0)
