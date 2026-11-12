extends SceneTree
## Cross-arena layout regression: tests complete generated maps, not just arena 0.

const GAME_SCENE := preload("res://scenes/game.tscn")
const BIOMES := preload("res://scripts/biome_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _problem(arena_index: int, message: String) -> void:
	var detail := "Arena %d: %s" % [arena_index+1,message]
	failures.append(detail)
	push_error("WORLD_LAYOUT_FAIL: "+detail)

func _distance_to_route(p: Vector3, points: PackedVector3Array) -> float:
	var best := INF
	for i in range(1,points.size()):
		var a := Vector2(points[i-1].x,points[i-1].z)
		var b := Vector2(points[i].x,points[i].z)
		var q := Vector2(p.x,p.z)
		best=minf(best,q.distance_to(Geometry2D.get_closest_point_to_segment(q,a,b)))
	return best

func _finite_vector(p: Vector3) -> bool:
	return is_finite(p.x) and is_finite(p.y) and is_finite(p.z)

func _geometry(node: Node) -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	if node is MeshInstance3D or node is MultiMeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_geometry(child))
	return result

func _top_surface_faces_up(mesh: Mesh) -> bool:
	for surface in range(mesh.get_surface_count()):
		var arrays:=mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count:=indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0,count-2,3):
			var a:=indices[offset] if not indices.is_empty() else offset
			var b:=indices[offset+1] if not indices.is_empty() else offset+1
			var c:=indices[offset+2] if not indices.is_empty() else offset+2
			var cross:=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
			if cross.length_squared()<0.00000001:continue
			# Godot's own PlaneMesh has clockwise top triangles: geometric cross
			# points down while its shading normal points up. Culling uses winding.
			if cross.normalized().dot(Vector3.UP)>-0.50:return false
			if normals.size()!=vertices.size() or normals[a].dot(Vector3.UP)<0.50:return false
	return true

func _check_biome(game: Node3D, arena_index: int) -> void:
	var expected:=BIOMES.for_arena(arena_index)
	var art: Node3D=game.get("world_art")
	var terrain: Node3D=game.get("terrain_root")
	if art.get_meta("biome","")!=expected.key or art.get_meta("season","")!=expected.season:
		_problem(arena_index,"arena did not select its campaign biome/season")
	var weather:=art.get_node_or_null("BiomeWeather") as MultiMeshInstance3D
	if weather==null or weather.get_meta("weather","")!=expected.weather or weather.multimesh.instance_count>320:
		_problem(arena_index,"missing/wrong/unbounded instanced biome weather")
	var trees:=art.get_node_or_null("BranchingTreeTrunks")
	if trees==null or trees.get_meta("tree_style","")!=expected.tree:
		_problem(arena_index,"wrong biome-specific tree geometry")
	var pond:=terrain.get_node_or_null("RiversideHamlet/HamletPond") as MeshInstance3D
	if pond==null or pond.get_meta("water_state","")!=expected.water:
		_problem(arena_index,"pond does not reflect its seasonal water state")
	elif int((pond.material_override as ShaderMaterial).get_shader_parameter("water_state"))!=(1 if expected.water=="ice" else (2 if expected.water=="boiling" else 0)):
		_problem(arena_index,"pond rendering mode disagrees with water state")
	if expected.water=="boiling" and art.get("steam_sources").size()<10:
		_problem(arena_index,"volcanic hot spring has no modeled steam")
	if expected.key=="winter" and art.get_node_or_null("BiomeSnowRockCaps0")==null:
		_problem(arena_index,"winter rocks have no snow cover geometry")
	if expected.key=="desert" and art.get_node_or_null("BiomeCactusGroves")==null:
		_problem(arena_index,"desert lacks its cactus geometry")
	if expected.key=="autumn" and art.get_node_or_null("BiomeAutumnLeafLitter")==null:
		_problem(arena_index,"autumn has no leaf litter")
	if expected.key=="volcanic" and (art.get_node_or_null("BiomeEmberFissures")==null or art.get_node_or_null("IndividualLeafCanopies")!=null):
		_problem(arena_index,"volcanic biome needs charred branches/embers, not a leafy green forest")
	var people: Array=game.get("ambient_people")
	for i in range(people.size()):
		if people[i].root.get_meta("wardrobe","")!=expected.wardrobe or people[i].activity!=expected.chores[i]:
			_problem(arena_index,"villager outfit or daily chore does not match climate")
	var birds: Array=game.get("ambient_birds")
	if birds.size()<2:
		_problem(arena_index,"no ambient bird pair")
	for bird in birds:
		if bird.root.get_meta("species","")!=expected.bird or bird.wings.size()!=2:
			_problem(arena_index,"bird species/hinged wings mismatch")
		elif expected.bird!="bat" and int(bird.root.get_meta("modeled_feathers",0))<20:
			_problem(arena_index,"bird has no individually modeled feather/tail geometry")
	var animals: Array=game.get("ambient_lizards")
	if animals.size()<2: _problem(arena_index,"ground wildlife pair is missing")
	for animal in animals:
		if animal.root.get_meta("species","")!=expected.ground_animal or animal.legs.size()!=4:
			_problem(arena_index,"ground wildlife does not fit the biome")
	# Evaluate the actual animation path, not merely the presence of actor nodes.
	var before: Vector3=birds[0].root.position if not birds.is_empty() else Vector3.ZERO
	game.call("_animate_background_life",0.2)
	if not birds.is_empty() and birds[0].root.position.is_equal_approx(before):
		_problem(arena_index,"background birds do not move")
	for animal in animals:
		if not _finite_vector(animal.root.position) or _distance_to_route(animal.root.position,game.get("route_points"))<1.7:
			_problem(arena_index,"background animal leaves its safe grass area")

func _run() -> void:
	root.size=Vector2i(1600,900)
	var game: Node3D=GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var loading_deadline := Time.get_ticks_msec()+30000
	while not game.call("_initial_tower_models_ready") or not game.call("_enemy_models_ready"):
		if Time.get_ticks_msec()>loading_deadline:
			_problem(-1,"initial character loading did not complete")
			quit(1)
			return
		await create_timer(0.01).timeout
	game.set_process(false)
	var constants: Dictionary=game.get_script().get_script_constant_map()
	var base_radius: float=constants.TOWER_BASE_RADIUS
	var road_half_width: float=constants.ROAD_OUTER_WIDTH*0.5
	var total_legal:=0
	var arena_count: int=game.get("route_patterns").size()
	var biome_counts: Dictionary={}
	var previous_biome := ""
	if arena_count<18:
		_problem(-1,"campaign has fewer than the required 18 maps")
	for arena_index in range(arena_count):
		if arena_index>0:
			for child in game.get("terrain_root").get_children(): child.free()
			game.set("arena",arena_index)
			game.call("_build_arena")
		_check_biome(game,arena_index)
		var profile:=BIOMES.for_arena(arena_index)
		biome_counts[profile.key]=int(biome_counts.get(profile.key,0))+1
		if profile.key==previous_biome: _problem(arena_index,"neighboring arenas repeat the same biome")
		previous_biome=profile.key
		var size_value: float=game.get("world_size")
		var ground: MeshInstance3D=game.get("terrain_root").get_node("NoiseTexturedGround")
		if ground.mesh==null or not _top_surface_faces_up(ground.mesh):
			_problem(arena_index,"terrain winding/normals face below the map and will be culled from above")
		for road in game.get("terrain_root").get_children():
			if road is MeshInstance3D and road!=ground and road.mesh!=null and not _top_surface_faces_up(road.mesh):
				_problem(arena_index,"road winding/normals do not face the viewing side")
				break
		var half_width:=size_value*0.5
		var half_depth:=size_value*0.36
		var path: PackedVector3Array=game.get("route_points")
		if path.size()<2 or not is_finite(float(game.get("route_length"))) or float(game.get("route_length"))<=0.0:
			_problem(arena_index,"route is empty, non-finite or has no length")
			continue
		for p in path:
			if not _finite_vector(p) or absf(p.x)+road_half_width>half_width or absf(p.z)+road_half_width>half_depth:
				_problem(arena_index,"road geometry escapes the ground boundary at "+str(p))
				break
		for i in range(0,path.size(),maxi(1,int(path.size()/20))):
			if game.call("_valid_spot",path[i]):
				_problem(arena_index,"tower is buildable on the enemy road")
				break
		# Check clear grass throughout the actual central AND outer playable regions.
		# The generous physical clearance makes these independent of exact placement epsilon.
		var central_legal:=0
		var outer_legal:=0
		var blocked: Array=game.get("build_obstacles")
		for iz in range(17):
			for ix in range(25):
				var p:=Vector3(lerpf(-half_width+base_radius*2.0,half_width-base_radius*2.0,float(ix)/24.0),0.0,lerpf(-half_depth+base_radius*2.0,half_depth-base_radius*2.0,float(iz)/16.0))
				if _distance_to_route(p,path)<road_half_width+base_radius*1.8: continue
				var clear:=true
				for obstacle in blocked:
					if Vector2(p.x,p.z).distance_to(obstacle.position)<float(obstacle.radius)+base_radius*1.8:
						clear=false
						break
				if not clear: continue
				if not game.call("_valid_spot",p):
					_problem(arena_index,"unobstructed grass is incorrectly forbidden at "+str(p))
				elif absf(p.x)<half_width*0.55 and absf(p.z)<half_depth*0.55:
					central_legal+=1
				else:
					outer_legal+=1
		if central_legal==0 or outer_legal==0:
			_problem(arena_index,"no legal sampled grass in the center or near map edges")
		total_legal+=central_legal+outer_legal
		# Decorative obstacles must never occupy the route. Cave footprints are intentional.
		for obstacle in blocked:
			var p:=Vector3(obstacle.position.x,0.0,obstacle.position.y)
			if p.distance_to(Vector3(path[0].x,0,path[0].z))<0.1 or p.distance_to(Vector3(path[-1].x,0,path[-1].z))<0.1: continue
			if _distance_to_route(p,path)<road_half_width:
				_problem(arena_index,"a decorative obstacle is centered on the enemy road")
				break
		var hamlet:=game.get("terrain_root").get_node_or_null("RiversideHamlet") as Node3D
		if hamlet==null or game.get("ambient_people").size()<3 or game.get("ambient_animals").size()<2:
			_problem(arena_index,"hamlet, three villagers or two farm animals are missing")
		else:
			for visual in _geometry(hamlet):
				if visual is MeshInstance3D and visual.mesh==null: continue
				if visual is MultiMeshInstance3D and visual.multimesh==null: continue
				var bounds: AABB=visual.global_transform*visual.get_aabb()
				if bounds.position.x < -half_width or bounds.end.x > half_width or bounds.position.z < -half_depth or bounds.end.z > half_depth:
					_problem(arena_index,"settlement geometry leaves the map: "+str(visual.get_path()))
					break
			for person in game.get("ambient_people"):
				if _distance_to_route(person.root.global_position,path)<road_half_width:
					_problem(arena_index,"background villager starts on the combat road")
			for animal in game.get("ambient_animals"):
				if _distance_to_route(animal.root.global_position,path)<road_half_width:
					_problem(arena_index,"farm animal starts on the combat road")
		var art: Node3D=game.get("world_art")
		for label in ["EntranceCave","ExitCave"]:
			var cave:=art.get_node_or_null(label) as Node3D
			var tunnel:=cave.get_node_or_null("RecedingRockTunnel") as MeshInstance3D if cave!=null else null
			if tunnel==null or tunnel.mesh==null or tunnel.get_aabb().size.z<2.0 or tunnel.get_aabb().size.y<2.0:
				_problem(arena_index,"cave has no substantial interior geometry: "+label)
		var max_size: float=game.call("_camera_max_size")
		if not is_finite(max_size) or max_size<=0.0:
			_problem(arena_index,"camera fit is zero or non-finite")
		else:
			game.call("_zoom_at",Vector2(640,450),100.0)
			var fitted_size: float=game.get("camera_size")
			game.call("_zoom_at",Vector2(640,450),100.0)
			if not is_equal_approx(fitted_size,max_size) or not is_equal_approx(float(game.get("camera_size")),max_size) or not _finite_vector(game.get("camera_target")):
				_problem(arena_index,"camera cannot remain at its map fit limit")
		print("WORLD_LAYOUT_ARENA: arena=%d biome=%s center_grass=%d outer_grass=%d obstacles=%d"%[arena_index+1,profile.key,central_legal,outer_legal,blocked.size()])
		await process_frame
	if biome_counts.size()!=6:
		_problem(-1,"campaign does not contain all six distinct biomes")
	for key in biome_counts:
		if int(biome_counts[key])!=3: _problem(-1,"expected three arenas per biome: "+str(key))
	game.get("music_player").stop()
	game.get("music_player").stream=null
	game.free()
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("WORLD_LAYOUT_SMOKE_OK: %d maps, six biomes x3, %d unobstructed build samples, road bounds/blocks, seasonal settlements/wildlife/weather/water, physical tunnels, finite bounded camera"%[arena_count,total_legal])
		call_deferred("_finish",0)
	else:
		print("WORLD_LAYOUT_SMOKE_FAILED: %d layout violations"%failures.size())
		call_deferred("_finish",1)

func _finish(exit_code: int) -> void:
	# Return from _run first so temporary geometry/resource references in its
	# coroutine have been released before the engine checks ObjectDB at exit.
	quit(exit_code)
