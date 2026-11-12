extends Node3D
## Shared volumetric spell geometry, bounded pools and short elemental impacts.
## Flight/target/damage stay in game.gd. This module never owns enemy references.
const MAX_FLIGHTS := 128
const MAX_IMPACTS := 48
const FREE_PER_KIND := 16
const BURST_COUNT := 12
const COLORS := [Color(0.85,0.045,0.10),Color(0.79,0.94,1.0),Color(1.0,0.28,0.025),Color(0.95,0.20,0.50),Color(0.42,0.80,1.0),Color(0.96,0.92,0.77)]
var flights: Dictionary = {}
var overflow_flights: Dictionary = {}
var impacts: Array[Dictionary] = []
var flight_pool: Dictionary = {}
var impact_pool: Dictionary = {}
var meshes: Dictionary = {}
var materials: Dictionary = {}
var serial := 0

func acquire_flight(kind: int) -> Node3D:
	kind = clampi(kind,0,COLORS.size()-1)
	if flights.size() >= MAX_FLIGHTS:
		# Preserve gameplay when visual capacity is reached; no extra meshes/lights.
		var invisible := Node3D.new()
		invisible.name = "UnrenderedProjectile"
		add_child(invisible)
		overflow_flights[invisible.get_instance_id()] = invisible
		return invisible
	var pool: Array = flight_pool.get(kind,[])
	var entry: Dictionary = pool.pop_back() if not pool.is_empty() else _new_flight(kind)
	flight_pool[kind] = pool
	entry.age = 0.0
	entry.node.visible = true
	entry.node.scale = Vector3.ONE
	entry.node.rotation = Vector3.ZERO
	entry.body.rotation = Vector3.ZERO
	for part in entry.parts:
		if part.material_override is ShaderMaterial:
			part.set_instance_shader_parameter("fx_age",0.0)
	flights[entry.node.get_instance_id()] = entry
	return entry.node

func release_flight(node: Node3D) -> void:
	if not is_instance_valid(node): return
	var id := node.get_instance_id()
	if overflow_flights.has(id):
		overflow_flights.erase(id)
		node.queue_free()
		return
	if not flights.has(id):
		node.queue_free()
		return
	var entry: Dictionary = flights[id]
	flights.erase(id)
	node.visible = false
	var pool: Array = flight_pool.get(entry.kind,[])
	if pool.size() < FREE_PER_KIND:
		pool.append(entry)
		flight_pool[entry.kind] = pool
	else:
		node.queue_free()

func impact(kind: int, position: Vector3) -> void:
	kind = clampi(kind,0,COLORS.size()-1)
	if impacts.size() >= MAX_IMPACTS:
		_release_impact(0)
	var pool: Array = impact_pool.get(kind,[])
	var entry: Dictionary = pool.pop_back() if not pool.is_empty() else _new_impact(kind)
	impact_pool[kind] = pool
	entry.age = 0.0
	entry.node.position = position
	entry.node.visible = true
	entry.node.scale = Vector3.ONE
	impacts.append(entry)
	_update_impact(entry)

func tick(dt: float) -> void:
	for entry in flights.values():
		entry.age += dt
		var age: float = entry.age
		var parts: Array = entry.parts
		for part in parts:
			if part.material_override is ShaderMaterial: part.set_instance_shader_parameter("fx_age",age)
		if int(entry.kind) == 1:
			for i in range(3): parts[i].rotation.z = age*(5.5+float(i)*0.8)+float(i)*TAU/3.0
		elif int(entry.kind) == 0:
			parts[0].rotation.z = sin(age*6.0)*0.12
			parts[1].rotation.z = parts[0].rotation.z
		elif int(entry.kind) == 4:
			entry.body.rotation.z = age*1.4
		elif int(entry.kind) == 5:
			entry.body.rotation.z = age*2.0
			entry.body.scale = Vector3.ONE*(1.0+sin(age*13.0)*0.08)
		if entry.embers != null:
			var multi: MultiMesh = entry.embers.multimesh
			for i in range(multi.instance_count):
				var p := fposmod(age*1.9+float(i)*0.167,1.0)
				var angle := float(i)*2.4+age*1.1
				var pos := Vector3(cos(angle)*0.20*p,sin(angle)*0.18*p,p*1.65)
				var size := (1.0-p)*0.7+0.15
				multi.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),pos))
	for index in range(impacts.size()-1,-1,-1):
		var entry: Dictionary = impacts[index]
		entry.age += dt
		if float(entry.age) >= float(entry.duration):
			_release_impact(index)
		else:
			_update_impact(entry)

func clear_all() -> void:
	for entry in flights.values().duplicate(): release_flight(entry.node)
	for node in overflow_flights.values():
		if is_instance_valid(node): node.queue_free()
	overflow_flights.clear()
	for index in range(impacts.size()-1,-1,-1): _release_impact(index)

func debug_counts() -> Dictionary:
	var pooled := 0
	for pool in flight_pool.values(): pooled += pool.size()
	for pool in impact_pool.values(): pooled += pool.size()
	return {"active_flights":flights.size(),"overflow_flights":overflow_flights.size(),"active_impacts":impacts.size(),"pooled_effects":pooled,"max_flights":MAX_FLIGHTS,"max_impacts":MAX_IMPACTS}

func _new_flight(kind: int) -> Dictionary:
	serial += 1
	var node := Node3D.new()
	node.name = "ElementalProjectile%d" % serial
	add_child(node)
	var parts: Array[GeometryInstance3D] = []
	var body := Node3D.new()
	node.add_child(body)
	var embers: MultiMeshInstance3D
	match kind:
		0:
			parts.append(_part(body,_crescent(),_solid_dark(),Vector3.ZERO,Vector3.ONE))
			parts.append(_part(body,_crescent(),_glow(kind,false,true),Vector3(0,0,0.012),Vector3(1.055,1.055,1.15)))
		1:
			for index in range(3):
				var curl := _part(body,_helix(),_glow(kind,false),Vector3.ZERO,Vector3.ONE*(0.85+index*0.1))
				curl.rotation.z = float(index)*TAU/3.0
				parts.append(curl)
		2:
			parts.append(_part(body,_orb(),_fire_material(),Vector3.ZERO,Vector3.ONE*0.29))
			parts.append(_part(body,_flame(),_fire_material(),Vector3(0,0,0.1),Vector3.ONE))
			embers = _multimesh(body,_ember(),_glow(kind,false),6)
		3:
			parts.append(_part(body,_helix(),_glow(kind,false),Vector3.ZERO,Vector3(0.5,0.5,0.8)))
		4:
			for index in range(5):
				var angle := float(index)*TAU/5.0
				var crystal := _part(body,_crystal(),_ice(),Vector3(cos(angle)*0.13,sin(angle)*0.13,0.12 if index>0 else 0),Vector3.ONE*(0.7 if index>0 else 1.2))
				crystal.rotation.z = angle
				parts.append(crystal)
		5:
			# A soft, irregular three-dimensional cotton fist, not an ice bolt.
			for index in range(7):
				var angle := float(index)*TAU/6.0
				var center := Vector3.ZERO if index == 6 else Vector3(cos(angle)*0.25,sin(angle)*0.25,0.10)
				parts.append(_part(body,_orb(),_cotton_material(),center,Vector3(0.27,0.25,0.33)))
	var trail := _part(node,_ribbon(),_glow(kind,false),Vector3(0,0,0.12),Vector3(0.7,0.7,0.65) if kind==4 else Vector3.ONE)
	parts.append(trail)
	return {"node":node,"body":body,"parts":parts,"embers":embers,"kind":kind,"age":0.0}

func _new_impact(kind: int) -> Dictionary:
	serial += 1
	var node := Node3D.new()
	node.name = "ElementalImpact%d" % serial
	add_child(node)
	var particle_mesh: Mesh = _orb() if kind==5 else _crystal() if kind==4 else _crescent() if kind==0 else _helix() if kind==1 or kind==3 else _ember()
	var sparks := _multimesh(node,particle_mesh,_glow(kind,true),BURST_COUNT)
	var shock := _part(node,_orb() if kind==5 else _flame() if kind==2 else _helix() if kind==1 or kind==3 else _crescent() if kind==0 else _crystal(),_glow(kind,true),Vector3.ZERO,Vector3.ONE)
	var directions: Array[Vector3] = []
	for i in range(BURST_COUNT):
		var angle := float(i)*2.399963
		var y := -0.35+float(i)/float(BURST_COUNT)*1.2
		directions.append(Vector3(cos(angle),y,sin(angle)).normalized())
	return {"node":node,"sparks":sparks,"shock":shock,"directions":directions,"kind":kind,"age":0.0,"duration":0.65 if kind==5 else 0.54 if kind==2 else 0.65 if kind==4 else 0.40}

func _update_impact(entry: Dictionary) -> void:
	var t := clampf(float(entry.age)/float(entry.duration),0.0,1.0)
	entry.sparks.set_instance_shader_parameter("fx_age",t)
	entry.shock.set_instance_shader_parameter("fx_age",t)
	var multi: MultiMesh = entry.sparks.multimesh
	for i in range(BURST_COUNT):
		var direction: Vector3 = entry.directions[i]
		var pos := direction*(0.10+t*(1.05 if int(entry.kind)==2 else 0.75))
		if int(entry.kind) == 5:
			pos = Vector3(direction.x*2.8*t,direction.y*0.5*t,direction.z*2.8*t)
		pos.y -= t*t*0.35
		var size := (1.0-t)*0.18+0.015
		if int(entry.kind) == 2: size *= 3.2
		if int(entry.kind) == 5: size *= 2.0
		var orientation := Basis(Vector3.UP,float(i)*2.399+t*3.0).scaled(Vector3.ONE*size)
		multi.set_instance_transform(i,Transform3D(orientation,pos))
	entry.shock.scale = Vector3.ONE*(0.35+t*0.8)
	entry.shock.rotation = Vector3(t*1.4,t*2.0,t*0.5)

func _cotton_material() -> StandardMaterial3D:
	if materials.has("cotton"): return materials.cotton
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.96,0.92,0.80)
	material.roughness = 0.98
	materials.cotton = material
	return material

func _release_impact(index: int) -> void:
	var entry: Dictionary = impacts[index]
	impacts.remove_at(index)
	entry.node.visible = false
	var pool: Array = impact_pool.get(entry.kind,[])
	if pool.size() < FREE_PER_KIND:
		pool.append(entry)
		impact_pool[entry.kind] = pool
	else: entry.node.queue_free()

func _part(parent: Node3D, mesh: Mesh, material: Material, position: Vector3, scale_value: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.scale = scale_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _multimesh(parent: Node3D, mesh: Mesh, material: Material, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _solid_dark() -> Material:
	if materials.has("dark"): return materials.dark
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.012,0.009,0.022)
	mat.roughness = 0.34
	mat.metallic = 0.30
	materials.dark = mat
	return mat

func _ice() -> Material:
	if materials.has("ice"): return materials.ice
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42,0.79,0.98,0.76)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.16
	mat.metallic = 0.28
	mat.emission_enabled = true
	mat.emission = Color(0.12,0.36,0.55)
	materials.ice = mat
	return mat

func _glow(kind: int, burst: bool, rim: bool = false) -> ShaderMaterial:
	var key := "glow_%d_%s_%s" % [kind,str(burst),str(rim)]
	if materials.has(key): return materials[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add,depth_draw_never,cull_disabled,unshaded;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool burst = false;
uniform bool rim = false;
instance uniform float fx_age = 0.0;
varying vec3 local_position;
void vertex(){
 local_position=VERTEX;
 VERTEX.x += sin(VERTEX.z*11.0+fx_age*18.0)*abs(VERTEX.z)*0.025;
 VERTEX.y += cos(VERTEX.z*9.0+fx_age*14.0)*abs(VERTEX.z)*0.025;
}
void fragment(){
 float flicker=0.80+0.20*sin(local_position.z*22.0+local_position.y*17.0+fx_age*23.0);
 ALBEDO=tint.rgb*1.3;
 EMISSION=tint.rgb*flicker;
 ALPHA=tint.a*flicker*(burst?pow(1.0-clamp(fx_age,0.0,1.0),1.5):1.0);
 if(rim){ ALPHA*=smoothstep(0.54,0.60,length(vec2(local_position.x+0.24,local_position.y))); }
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var color: Color = COLORS[kind]
	color.a = 0.38 if kind==1 else 0.48 if kind==4 else 0.67
	mat.set_shader_parameter("tint",color)
	mat.set_shader_parameter("burst",burst)
	mat.set_shader_parameter("rim",rim)
	materials[key] = mat
	return mat

func _fire_material() -> Material:
	if materials.has("fire"): return materials.fire
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add,depth_draw_never,cull_disabled,unshaded;
instance uniform float fx_age = 0.0;
varying vec3 p;
void vertex(){
 p=VERTEX;
 float flow=sin(VERTEX.z*18.0-fx_age*27.0+VERTEX.x*11.0)*cos(VERTEX.y*21.0+fx_age*17.0);
 VERTEX.xy*=1.0+flow*0.20;
 VERTEX.x+=sin(VERTEX.z*10.0-fx_age*19.0)*max(0.0,VERTEX.z)*0.12;
}
void fragment(){
 float n=sin(p.z*21.0-fx_age*25.0+sin(p.x*14.0+p.y*23.0))*0.5+0.5;
 float hot=clamp(1.0-length(p.xy)*2.5-p.z*0.4+n*0.25,0.0,1.0);
 vec3 color=mix(vec3(0.95,0.055,0.003),vec3(1.0,0.87,0.25),hot);
 ALBEDO=color;
 EMISSION=color*(1.2+hot*1.4);
 ALPHA=0.65+n*0.25;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	materials.fire = mat
	return mat

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)

func _crescent() -> Mesh:
	if meshes.has("crescent"): return meshes.crescent
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var a := -1.45+2.90*float(i)/24.0
		var b := -1.45+2.90*float(i+1)/24.0
		var outer_a := Vector2(cos(a)*0.62-0.24,sin(a)*0.62)
		var outer_b := Vector2(cos(b)*0.62-0.24,sin(b)*0.62)
		var inner_a := Vector2(cos(a)*(0.62-sin(float(i)/24.0*PI)*0.20)-0.24,sin(a)*(0.62-sin(float(i)/24.0*PI)*0.20))
		var inner_b := Vector2(cos(b)*(0.62-sin(float(i+1)/24.0*PI)*0.20)-0.24,sin(b)*(0.62-sin(float(i+1)/24.0*PI)*0.20))
		for depth in [-0.035,0.035]:
			var p0 := Vector3(outer_a.x,outer_a.y,depth);var p1 := Vector3(outer_b.x,outer_b.y,depth)
			var p2 := Vector3(inner_a.x,inner_a.y,depth);var p3 := Vector3(inner_b.x,inner_b.y,depth)
			if depth > 0:
				_tri(st,p0,p1,p2);_tri(st,p1,p3,p2)
			else:
				_tri(st,p0,p2,p1);_tri(st,p1,p2,p3)
		for pair in [[outer_a,outer_b],[inner_b,inner_a]]:
			var p0 := Vector3(pair[0].x,pair[0].y,-0.035);var p1 := Vector3(pair[1].x,pair[1].y,-0.035)
			var p2 := Vector3(pair[0].x,pair[0].y,0.035);var p3 := Vector3(pair[1].x,pair[1].y,0.035)
			_tri(st,p0,p1,p2);_tri(st,p1,p3,p2)
	st.generate_normals();meshes.crescent=st.commit();return meshes.crescent

func _helix() -> Mesh:
	if meshes.has("helix"): return meshes.helix
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(36):
		var t0 := float(i)/36.0;var t1 := float(i+1)/36.0
		for side in range(5):
			var points: Array[Vector3] = []
			for uv: Vector2 in [Vector2(t0,side),Vector2(t1,side),Vector2(t0,side+1),Vector2(t1,side+1)]:
				var angle := uv.x*TAU*1.35;var cross_angle := uv.y*TAU/5.0
				var radius := (0.11+uv.x*0.22)+cos(cross_angle)*0.024*sin(uv.x*PI)
				points.append(Vector3(cos(angle)*radius,sin(angle)*radius,uv.x*0.95-0.24+sin(cross_angle)*0.024))
			_tri(st,points[0],points[2],points[1]);_tri(st,points[1],points[2],points[3])
	st.generate_normals();meshes.helix=st.commit();return meshes.helix

func _ribbon() -> Mesh:
	if meshes.has("ribbon"): return meshes.ribbon
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in range(2):
		for i in range(14):
			var points: Array[Vector3] = []
			for uv: Vector2 in [Vector2(i,-1),Vector2(i,1),Vector2(i+1,-1),Vector2(i+1,1)]:
				var t := uv.x/14.0
				var width := sin(t*PI)*0.12*(1.0-t)
				var curl := sin(t*8.0)*t*0.10
				points.append(Vector3(width*uv.y,curl,t*1.65) if axis==0 else Vector3(curl,width*uv.y,t*1.65))
			_tri(st,points[0],points[1],points[2]);_tri(st,points[2],points[1],points[3])
	st.generate_normals();meshes.ribbon=st.commit();return meshes.ribbon

func _flame() -> Mesh:
	if meshes.has("flame"): return meshes.flame
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(7):
		for side in range(12):
			var points: Array[Vector3] = []
			for uv: Vector2 in [Vector2(ring,side),Vector2(ring,side+1),Vector2(ring+1,side),Vector2(ring+1,side+1)]:
				var t := uv.x/7.0;var angle := uv.y*TAU/12.0
				var radius := (1.0-t)*0.23*(0.85+0.15*cos(angle*3.0+t*7.0))
				points.append(Vector3(cos(angle)*radius,sin(angle)*radius,t*1.12))
			_tri(st,points[0],points[2],points[1]);_tri(st,points[1],points[2],points[3])
	st.generate_normals();meshes.flame=st.commit();return meshes.flame

func _crystal() -> Mesh:
	if meshes.has("crystal"): return meshes.crystal
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(6):
		var a := float(i)*TAU/6.0;var b := float(i+1)*TAU/6.0
		var p0 := Vector3(cos(a)*0.14,sin(a)*0.14,0.02);var p1 := Vector3(cos(b)*0.14,sin(b)*0.14,0.02)
		_tri(st,p0,Vector3(0,0,-0.39),p1);_tri(st,p1,Vector3(0,0,0.27),p0)
	st.generate_normals();meshes.crystal=st.commit();return meshes.crystal

func _orb() -> Mesh:
	if not meshes.has("orb"):
		var mesh := SphereMesh.new();mesh.radius=1.0;mesh.height=2.0;mesh.radial_segments=18;mesh.rings=10;meshes.orb=mesh
	return meshes.orb

func _ember() -> Mesh:
	if not meshes.has("ember"):
		var mesh := SphereMesh.new();mesh.radius=0.055;mesh.height=0.11;mesh.radial_segments=5;mesh.rings=3;meshes.ember=mesh
	return meshes.ember
