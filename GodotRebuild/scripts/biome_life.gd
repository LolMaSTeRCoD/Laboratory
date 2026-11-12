extends RefCounted
## Lightweight background animals: modeled feathers/webs, independent hinged wings,
## species-specific silhouettes. Never participate in combat or placement collisions.
const RenderOpt = preload("res://scripts/world_render_opt.gd")

static func _material(color: Color, roughness: float=0.9) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=roughness
	return mat

static func _mesh(parent: Node3D, geometry: Mesh, mat: Material, position: Vector3, scale_value: Vector3=Vector3.ONE) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=geometry
	node.material_override=mat
	node.position=position
	node.scale=scale_value
	parent.add_child(node)
	return node

static func _sphere(parent: Node3D, position: Vector3, scale_value: Vector3, mat: Material) -> MeshInstance3D:
	var shape:=SphereMesh.new()
	shape.radius=0.5
	shape.height=1.0
	shape.radial_segments=14
	shape.rings=7
	return _mesh(parent,shape,mat,position,scale_value)

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot front faces are clockwise. These authored convex feather surfaces
	# use the conventional outward order, so reverse once for culling/normals.
	for v in [a,c,b]: st.add_vertex(v)

static func _feather(parent: Node3D, start: Vector3, end: Vector3, width: float, mat: Material) -> void:
	var axis: Vector3=(end-start).normalized()
	var side: Vector3=axis.cross(Vector3.UP).normalized()*width
	var middle: Vector3=start.lerp(end,0.42)
	var crown: Vector3=middle+Vector3.UP*width*0.22
	var bottom: Vector3=middle-Vector3.UP*width*0.10
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangle(st,start,middle+side,crown)
	_triangle(st,middle+side,end,crown)
	_triangle(st,end,middle-side,crown)
	_triangle(st,middle-side,start,crown)
	_triangle(st,start,bottom,middle+side)
	_triangle(st,middle+side,bottom,end)
	_triangle(st,end,bottom,middle-side)
	_triangle(st,middle-side,bottom,start)
	st.generate_normals()
	_mesh(parent,st.commit(),mat,Vector3.ZERO).name="ModeledFeather"

static func _batch_feathers(parent: Node3D) -> void:
	# Feathers retain their individual closed geometry, but share one surface per
	# material/hinge. Two flying birds should not add fifty tiny draw calls.
	var batches: Dictionary={}
	for child in parent.get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("ModeledFeather"): continue
		var key: int=child.material_override.get_instance_id()
		if not batches.has(key):
			var surface:=SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key]={"surface":surface,"material":child.material_override}
		batches[key].surface.append_from(child.mesh,0,child.transform)
		parent.remove_child(child)
		child.free()
	for batch in batches.values():
		var surface: SurfaceTool=batch.surface
		surface.index()
		_mesh(parent,surface.commit(),batch.material,Vector3.ZERO).name="BatchedFeatherGeometry"

static func make_bird(parent: Node3D, origin: Vector3, phase: float, profile: Dictionary) -> Dictionary:
	var species: String=profile.bird
	var bird:=Node3D.new()
	bird.name="BackgroundBird_"+species
	bird.position=origin
	bird.set_meta("species",species)
	parent.add_child(bird)
	var body_color: Color=profile.bird_color
	var feathers:=_material(body_color)
	var tips:=_material(body_color.lightened(0.09))
	var accent:=_material(Color(0.54,0.10,0.045) if species=="parrot" else body_color.lightened(0.16))
	var beak:=_material(Color(0.58,0.41,0.15))
	var eyes:=_material(Color(0.012,0.016,0.014),0.25)
	_sphere(bird,Vector3.ZERO,Vector3(0.43,0.19,0.21),feathers)
	_sphere(bird,Vector3(0.19,0.045,0),Vector3(0.19,0.17,0.16),feathers)
	for side in [-1.0,1.0]:
		_sphere(bird,Vector3(0.235,0.075,side*0.067),Vector3(0.027,0.028,0.018),eyes)
	var beak_mesh:=CylinderMesh.new()
	beak_mesh.bottom_radius=0.048
	beak_mesh.top_radius=0.004
	beak_mesh.height=0.16
	beak_mesh.radial_segments=8
	var beak_node:=_mesh(bird,beak_mesh,beak,Vector3(0.32,0.033,0))
	beak_node.rotation.z=-PI*0.5
	var wings: Array[Node3D]=[]
	var feather_count:=0
	for side in [-1.0,1.0]:
		var wing:=Node3D.new()
		wing.name="HingedWing"
		wing.position=Vector3(0.015,0.015,side*0.07)
		bird.add_child(wing)
		if species=="bat":
			var web:=SurfaceTool.new()
			web.begin(Mesh.PRIMITIVE_TRIANGLES)
			for finger in range(5):
				var a:=Vector3(0.07-float(finger)*0.09,0.0,side*(0.57-absf(2.0-float(finger))*0.08))
				var b:=Vector3(-0.02-float(finger)*0.09,-0.035,side*(0.57-absf(1.0-float(finger))*0.065))
				_triangle(web,Vector3.ZERO,a,b)
			web.generate_normals()
			var membrane:=_material(Color(0.26,0.105,0.085))
			membrane.cull_mode=BaseMaterial3D.CULL_DISABLED
			_mesh(wing,web.commit(),membrane,Vector3.ZERO).name="BatWingMembrane"
			for finger in range(5):
				_feather(wing,Vector3.ZERO,Vector3(0.07-float(finger)*0.09,0.005,side*(0.57-absf(2.0-float(finger))*0.08)),0.011,feathers)
		else:
			_sphere(wing,Vector3(-0.025,0,side*0.19),Vector3(0.31,0.07,0.38),feathers)
			for feather in range(9):
				var t:=float(feather)/8.0
				var base:=Vector3(0.11-t*0.28,0.0,side*(0.10+t*0.18))
				var end:=Vector3(0.08-t*0.47,0.018+sin(t*PI)*0.025,side*(0.46+sin(t*PI)*0.19))
				_feather(wing,base,end,0.032 if species=="swallow" else 0.048,tips if feather>5 else accent)
				feather_count+=1
		wings.append(wing)
		_batch_feathers(wing)
	for i in range(5):
		var spread:=float(i-2)*0.037
		var length_value:=0.36 if species in ["parrot","swallow"] else 0.25
		_feather(bird,Vector3(-0.15,0.015,spread*0.4),Vector3(-0.15-length_value,0.0,spread*2.0),0.034,accent)
		feather_count+=1
	_batch_feathers(bird)
	if species=="bat":
		for side in [-1.0,1.0]:
			_sphere(bird,Vector3(0.18,0.13,side*0.055),Vector3(0.07,0.17,0.045),feathers)
	if species in ["kite","raven"]: bird.scale=Vector3.ONE*1.32
	elif species=="parrot": bird.scale=Vector3.ONE*1.12
	bird.set_meta("modeled_feathers",feather_count)
	var before:=RenderOpt.inventory(bird)
	var excluded: Array[Node]=[]
	excluded.assign(wings)
	RenderOpt.merge_static_subtree(bird,excluded)
	for wing in wings: RenderOpt.merge_static_subtree(wing)
	bird.set_meta("render_opt_inventory",{"before":before,"after":RenderOpt.inventory(bird)})
	return {"root":bird,"wings":wings,"origin":origin,"phase":phase,"radius":4.2+phase,"speed":0.25 if species=="kite" else 0.32,"flap_rate":4.1 if species=="kite" else (10.0 if species=="bat" else 7.3),"flap_size":0.36 if species=="kite" else 0.72}

static func make_ground_animal(parent: Node3D, origin: Vector3, phase: float, profile: Dictionary) -> Dictionary:
	var species: String=profile.ground_animal
	var animal:=Node3D.new()
	animal.name="BackgroundAnimal_"+species
	animal.position=origin
	animal.set_meta("species",species)
	parent.add_child(animal)
	var primary:=_material(Color(0.72,0.75,0.73) if species=="hare" else (Color(0.13,0.095,0.06) if species=="salamander" else Color(0.26,0.34,0.13)))
	var belly:=_material(Color(0.82,0.81,0.74) if species=="hare" else Color(0.43,0.38,0.23))
	var eyes:=_material(Color(0.025,0.018,0.01),0.24)
	_sphere(animal,Vector3(0,0.11,0),Vector3(0.52,0.22,0.28) if species in ["lizard","salamander"] else Vector3(0.54,0.34,0.34),primary)
	_sphere(animal,Vector3(0.25,0.13,0),Vector3(0.20,0.16,0.17),belly)
	for side in [-1.0,1.0]:
		_sphere(animal,Vector3(0.30,0.17,side*0.064),Vector3(0.027,0.027,0.021),eyes)
	var tail:=_sphere(animal,Vector3(-0.38,0.08,0),Vector3(0.48,0.075,0.09) if species in ["lizard","salamander"] else Vector3(0.10,0.10,0.10),primary)
	if species=="hare":
		var ear_skin:=_material(Color(0.61,0.43,0.41))
		for side in [-1.0,1.0]:
			_sphere(animal,Vector3(0.18,0.35,side*0.07),Vector3(0.085,0.36,0.08),primary)
			_sphere(animal,Vector3(0.195,0.36,side*0.07),Vector3(0.070,0.24,0.035),ear_skin)
	elif species=="hedgehog":
		var spines:=SurfaceTool.new()
		spines.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(78):
			var a:=float(i)*2.39996
			var radius:=sqrt(float(i)/78.0)
			var p:=Vector3(cos(a)*radius*0.24,0.12+sqrt(1.0-radius*radius)*0.19,sin(a)*radius*0.16)
			var tip:=p+Vector3(-0.075,0.10,0)
			_triangle(spines,p+Vector3(0.018,0,0.01),tip,p-Vector3(0.018,0,0.01))
			_triangle(spines,p+Vector3(0.0,0,0.02),p-Vector3(0,0,0.02),tip)
		spines.generate_normals()
		_mesh(animal,spines.commit(),_material(Color(0.30,0.23,0.12)),Vector3.ZERO).name="HedgehogSpines"
	elif species=="salamander":
		var spot_material:=_material(Color(0.80,0.34,0.03))
		for i in range(8):
			_sphere(animal,Vector3(-0.18+float(i)*0.05,0.22,0.05*sin(float(i)*2.0)),Vector3(0.043,0.020,0.042),spot_material)
	var legs: Array[Node3D]=[]
	for x in [-0.16,0.17]:
		for side in [-1.0,1.0]:
			var leg:=Node3D.new()
			leg.position=Vector3(x,0.08,side*0.12)
			animal.add_child(leg)
			_sphere(leg,Vector3(0.02,-0.03,side*0.03),Vector3(0.14,0.075,0.07),belly)
			legs.append(leg)
	var before:=RenderOpt.inventory(animal)
	var excluded: Array[Node]=[]
	excluded.assign(legs)
	excluded.append(tail)
	RenderOpt.merge_static_subtree(animal,excluded)
	animal.set_meta("render_opt_inventory",{"before":before,"after":RenderOpt.inventory(animal)})
	return {"root":animal,"legs":legs,"tail":tail,"origin":origin,"phase":phase,"radius":0.67,"speed":0.78,"species":species}
