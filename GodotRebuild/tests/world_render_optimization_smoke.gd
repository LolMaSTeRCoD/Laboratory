extends SceneTree
## CPU geometry/submission inventory, NOT a GPU timing/draw-call measurement.
const Opt = preload("res://scripts/world_render_opt.gd")
const Life = preload("res://scripts/biome_life.gd")
const Catalog = preload("res://scripts/biome_catalog.gd")
const GAME_SCENE = preload("res://scenes/game.tscn")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if value: return
	failures.append(message)
	push_error("WORLD_RENDER_OPT_FAIL: "+message)

func _shape(parent: Node3D, shape: Mesh, mat: Material, p: Vector3, scale_value: Vector3=Vector3.ONE) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=shape
	node.material_override=mat
	node.position=p
	node.scale=scale_value
	parent.add_child(node)
	return node

func _corner_key(p: Vector3, uv: Vector2, color: Color) -> String:
	return str(p.snapped(Vector3.ONE*0.001))+"|"+str(uv.snapped(Vector2.ONE*0.001))+"|"+str(color)

func _signature(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var world: Transform3D=node.global_transform
		for surface in range(node.mesh.get_surface_count()):
			var mat: Material=node.material_override
			if mat==null: mat=node.get_surface_override_material(surface)
			if mat==null: mat=node.mesh.surface_get_material(surface)
			var mat_id:=mat.get_instance_id() if mat!=null else 0
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count:=indices.size() if not indices.is_empty() else vertices.size()
			for corner in range(0,count,3):
				var triangle: Array[String]=[]
				for j in range(3):
					var i:=indices[corner+j] if not indices.is_empty() else corner+j
					triangle.append(_corner_key(world*vertices[i],uv[i] if i<uv.size() else Vector2.ZERO,colors[i] if i<colors.size() else Color.WHITE))
				triangle.sort()
				var key:=str(mat_id)+"|"+str(node.cast_shadow)+"|"+str(node.layers)+"|"+";".join(triangle)
				result[key]=int(result.get(key,0))+1
	for child in node.get_children(): _signature(child,result)

func _shading_vertices(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var world: Transform3D=node.global_transform
		var normal_basis:=world.basis.inverse().transposed()
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var uv2: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
			for i in range(vertices.size()):
				var key:=str((world*vertices[i]).snapped(Vector3.ONE*0.001))+"|"+str((uv[i] if i<uv.size() else Vector2.ZERO).snapped(Vector2.ONE*0.001))
				if not result.has(key): result[key]=[]
				result[key].append({"normal":(normal_basis*normals[i]).normalized(),"tangent":(world.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized() if i*4+3<tangents.size() else Vector3.ZERO,"uv2":uv2[i] if i<uv2.size() else Vector2.ZERO})
	for child in node.get_children(): _shading_vertices(child,result)

func _test_exact_merge() -> void:
	var fixture:=Node3D.new()
	root.add_child(fixture)
	fixture.position=Vector3(3,2,-7)
	fixture.rotation.y=PI*0.5
	fixture.scale=Vector3(1.3,0.7,1.1)
	var stone:=StandardMaterial3D.new()
	stone.albedo_color=Color(0.4,0.5,0.6)
	var wood:=StandardMaterial3D.new()
	wood.albedo_color=Color(0.4,0.2,0.1)
	for i in range(5):
		_shape(fixture,BoxMesh.new(),stone,Vector3(float(i)*1.7,0,0),Vector3(1,1+float(i)*0.13,0.8))
	var nested:=Node3D.new()
	fixture.add_child(nested)
	nested.position=Vector3(1,3,2)
	nested.rotation.z=PI*0.5
	_shape(nested,CylinderMesh.new(),wood,Vector3(0,1,0))
	_shape(nested,CylinderMesh.new(),wood,Vector3(0,-1,0),Vector3(0.7,0.9,1.1))
	var no_shadow:=_shape(fixture,BoxMesh.new(),stone,Vector3(0,0,3))
	no_shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var animated:=Node3D.new()
	fixture.add_child(animated)
	_shape(animated,SphereMesh.new(),wood,Vector3(0,1,0))
	var signature_before: Dictionary={}
	_signature(fixture,signature_before)
	var shading_before: Dictionary={}
	_shading_vertices(fixture,shading_before)
	var before:=Opt.inventory(fixture)
	var excluded: Array[Node]=[animated]
	var report:=Opt.merge_static_subtree(fixture,excluded)
	var after:=Opt.inventory(fixture)
	var signature_after: Dictionary={}
	_signature(fixture,signature_after)
	var shading_after: Dictionary={}
	_shading_vertices(fixture,shading_after)
	_check(before.triangles==after.triangles,"exact merge changed triangle count")
	_check(signature_before==signature_after,"exact merge changed world vertices, UVs, colors, materials or shadows")
	for key in shading_before:
		_check(shading_after.has(key),"merged shading vertex disappeared")
		if not shading_after.has(key): continue
		for original: Dictionary in shading_before[key]:
			var matched:=false
			for actual: Dictionary in shading_after[key]:
				if original.normal.distance_to(actual.normal)<0.002 and original.uv2.distance_to(actual.uv2)<0.0001 and (original.tangent==Vector3.ZERO or original.tangent.distance_to(actual.tangent)<0.002):
					matched=true
					break
			_check(matched,"merge changed transformed normals/tangents or UV2")
	_check(int(after.surface_submissions)<int(before.surface_submissions),"exact merge did not reduce CPU surface submissions")
	_check(is_instance_valid(animated) and animated.get_child_count()==1,"animation handle was destroyed by static merge")
	animated.rotation.x=0.4
	_check(is_equal_approx(animated.rotation.x,0.4),"excluded animation pivot stopped responding")
	print("EXACT_MERGE_INVENTORY: before=%s after=%s report=%s (CPU potential surface submissions, not GPU draw calls)"%[before,after,report])
	fixture.free()

func _visible_box(camera: Camera3D, box: AABB) -> bool:
	var inverse:=camera.global_transform.affine_inverse()
	var lo:=Vector3(INF,INF,INF)
	var hi:=Vector3(-INF,-INF,-INF)
	for i in range(8):
		var p:=inverse*box.get_endpoint(i)
		lo=lo.min(p)
		hi=hi.max(p)
	var half_y:=camera.size*0.5
	var half_x:=half_y*float(root.size.x)/float(root.size.y)
	return hi.x>=-half_x and lo.x<=half_x and hi.y>=-half_y and lo.y<=half_y and hi.z>=-camera.far and lo.z<=-camera.near

func _test_world_batches(game: Node3D) -> void:
	var art: Node3D=game.get("world_art")
	art.set_process(false)
	var batches: Array=art.get("spatial_batches")
	_check(not batches.is_empty(),"world did not build near spatial batches")
	var scene_static: Dictionary=art.get("static_merge_report")
	_check(scene_static.before.triangles==scene_static.after.triangles,"hamlet merge changed its triangle count")
	_check(scene_static.after.surface_submissions<scene_static.before.surface_submissions,"hamlet merge did not reduce submissions")
	print("HAMLET_EXACT_INVENTORY: before=%s after=%s"%[scene_static.before,scene_static.after])
	var total_source:=0
	var total_chunk:=0
	var visible_near:=0
	var camera: Camera3D=game.get("camera")
	game.set("camera_size",14.0)
	game.set("camera_zoom_active",false)
	game.set("camera_target",Vector3.ZERO)
	game.call("_update_camera")
	for batch in batches:
		var source: MultiMeshInstance3D=batch.source
		var stored: Array=source.get_meta("instance_transforms")
		var stored_colors: Array=source.get_meta("instance_colors",[])
		var found: Dictionary={}
		var expected:=0
		for transform: Transform3D in stored:
			if transform.origin.y>=-900.0: expected+=1
		for chunk: MultiMeshInstance3D in batch.chunks:
			_check(chunk.multimesh.mesh==source.multimesh.mesh and chunk.material_override==source.material_override,"chunk replaced original mesh/material")
			_check(chunk.cast_shadow==source.cast_shadow and chunk.layers==source.layers,"chunk changed shadows/layers")
			var ids: Array=chunk.get_meta("source_indices")
			var transforms: Array=chunk.get_meta("instance_transforms")
			var colors: Array=chunk.get_meta("instance_colors",[])
			for j in range(ids.size()):
				var i: int=ids[j]
				_check(not found.has(i),"instance occurs in two near chunks")
				found[i]=true
				var before: Transform3D=source.global_transform*stored[i]
				var after: Transform3D=chunk.global_transform*transforms[j]
				_check(before.is_equal_approx(after),"chunk changed a world-space instance transform")
				if source.multimesh.use_colors: _check(stored_colors[i].is_equal_approx(colors[j]),"chunk changed per-instance color")
				var bounds: AABB=transforms[j]*chunk.multimesh.mesh.get_aabb()
				_check(chunk.custom_aabb.grow(0.001).encloses(bounds),"chunk bounds clip geometry")
			if _visible_box(camera,chunk.global_transform*chunk.custom_aabb): visible_near+=chunk.multimesh.instance_count
			_check(not chunk.visible,"near chunks draw together with initial far batch")
		_check(found.size()==expected,"chunking dropped or duplicated a playable instance")
		total_source+=expected
		total_chunk+=found.size()
	_check(total_source==total_chunk,"overall near instance parity failed")
	_check(visible_near<total_source*0.6,"near spatial culling does not reduce the projected instance budget")
	var far:=Opt.inventory(art)
	var expect_near:=not OS.get_cmdline_user_args().has("--disable-spatial-chunks")
	for requested in [false,true]:
		_check(Opt.use_near_chunks(requested)==(requested and expect_near),"diagnostic flag selected the wrong representation eligibility")
	art.call("_set_near_chunks_active",true)
	for batch in batches:
		_check(batch.source.multimesh.visible_instance_count==(0 if expect_near else -1),"wrong source batch activation for diagnostic mode")
		for chunk in batch.chunks: _check(chunk.visible==expect_near,"wrong near chunk activation for diagnostic mode")
	var near:=Opt.inventory(art)
	if not expect_near:
		_check(near==far and not bool(art.get("near_chunks_active")),"disable-spatial-chunks did not retain the original far representation at near zoom")
	art.call("_update_spatial_representation")
	_check(bool(art.get("near_chunks_active"))==expect_near,"camera refresh bypassed the diagnostic chunk flag")
	# Source-only buried reservations are absent in chunks; no near triangle can
	# be missing from the original source. Camera culling further cuts the budget.
	_check(int(near.instances)<=int(far.instances),"active inventory counted both representations")
	art.call("_set_near_chunks_active",false)
	_check(Opt.inventory(art)==far,"return to far mode did not restore the original batch inventory")
	print("WORLD_SPATIAL_INVENTORY: near_chunks_enabled=%s source_active_instances=%d near_equal_instances=%d projected_near_instances=%d far=%s near=%s (no GPU timing claim)"%[str(expect_near),total_source,total_chunk,visible_near,far,near])

func _run() -> void:
	root.size=Vector2i(1600,900)
	_test_exact_merge()
	var animal_parent:=Node3D.new()
	root.add_child(animal_parent)
	for arena_index in range(6):
		var profile:=Catalog.for_arena(arena_index)
		var bird:=Life.make_bird(animal_parent,Vector3.ZERO,0.0,profile)
		var animal:=Life.make_ground_animal(animal_parent,Vector3.ZERO,0.0,profile)
		for data in [bird,animal]:
			var report: Dictionary=data.root.get_meta("render_opt_inventory")
			_check(report.before.triangles==report.after.triangles,"wildlife exact merge changed triangles for "+str(profile.key))
			_check(report.after.surface_submissions<report.before.surface_submissions,"wildlife merge did not reduce submissions for "+str(profile.key))
		_check(is_instance_valid(animal.tail) and animal.legs.size()==4 and bird.wings.size()==2,"wildlife lost animation pivots")
		print("WILDLIFE_EXACT_INVENTORY: biome=%s bird=%s ground=%s"%[profile.key,bird.root.get_meta("render_opt_inventory"),animal.root.get_meta("render_opt_inventory")])
		bird.root.free()
		animal.root.free()
	animal_parent.free()
	var game: Node3D=GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var deadline:=Time.get_ticks_msec()+30000
	while not game.call("_initial_tower_models_ready") or not game.call("_enemy_models_ready"):
		if Time.get_ticks_msec()>deadline:
			_check(false,"character loading did not complete")
			break
		await create_timer(0.01).timeout
	game.set_process(false)
	_test_world_batches(game)
	game.get("music_player").stop()
	game.get("music_player").stream=null
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	call_deferred("_finish")

func _finish() -> void:
	if failures.is_empty():
		print("WORLD_RENDER_OPT_SMOKE_OK: exact geometry/material/shadow/UV parity, six animated wildlife species, spatial transform/color/bounds parity, exclusive near/far batches")
		quit(0)
	else:
		print("WORLD_RENDER_OPT_SMOKE_FAILED: %d"%failures.size())
		quit(1)
