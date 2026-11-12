extends Node3D
## Environment layer. All gameplay remains in game.gd; obstacles are shared data.
## Uses CC0 Poly Haven scans; sources are recorded in Assets/Environment/sources.json.

const ASSETS := "res://Assets/Environment/"
const BiomeCatalog = preload("res://scripts/biome_catalog.gd")
const BiomeLife = preload("res://scripts/biome_life.gd")
const RenderOpt = preload("res://scripts/world_render_opt.gd")
const NEAR_CHUNK_CAMERA_SIZE := 24.0
var world_size := 64.0
var biome := 0
var profile: Dictionary = {}
var route := PackedVector3Array()
var obstacles: Array
var rng := RandomNumberGenerator.new()
var clock := 0.0
var smoke: Array[Dictionary] = []
var water_material: ShaderMaterial
var rock_material: StandardMaterial3D
var wood_material: ShaderMaterial
var terrain_material: ShaderMaterial
var mesh_cache: Array[ArrayMesh] = []
var checked_headless_textures: Dictionary = {}
var steam_sources: Array[Dictionary] = []
var spatial_batches: Array[Dictionary] = []
var near_chunks_active := false
var static_merge_report: Dictionary = {}

func build(size: float, arena_index: int, path: PackedVector3Array, blocked: Array) -> void:
	name = "DetailedWorldArt"
	world_size = size
	profile = BiomeCatalog.for_arena(arena_index)
	biome = int(profile.id)
	set_meta("biome",profile.key)
	set_meta("season",profile.season)
	route = path
	obstacles = blocked
	rng.seed = 260711 + arena_index * 641
	rock_material = _pbr("mossy_rock",profile.rock,0.55)
	wood_material = _wood()
	_build_terrain()
	_build_vegetation()
	_build_boulders()
	_build_tunnel(route[0],(route[1]-route[0]).normalized(),"EntranceCave")
	_build_tunnel(route[-1],(route[-2]-route[-1]).normalized(),"ExitCave")
	_upgrade_road()
	_build_weather()
	_build_biome_accents()

func apply_lighting(scene: Node3D) -> void:
	# Keep one shared lighting rig, recolored per arena rather than accumulating lights.
	var light_index := 0
	for node in scene.get_children():
		if node is WorldEnvironment:
			var env: Environment=node.environment
			env.background_color=profile.fog.darkened(0.78)
			env.ambient_light_color=profile.ambient
			env.ambient_light_energy=float(profile.ambient_energy)
			env.fog_enabled=true
			env.fog_light_color=profile.fog
			env.fog_density=float(profile.fog_density)
			env.fog_sky_affect=0.0
		elif node is DirectionalLight3D:
			if light_index==0:
				node.light_color=profile.sun
				node.light_energy=float(profile.sun_energy)
			else:
				node.light_color=(profile.ambient as Color).lightened(0.14)
				node.light_energy=0.27 if biome==BiomeCatalog.Kind.DESERT else 0.34
			light_index+=1

func _texture(filename: String) -> Texture2D:
	var path := ASSETS+filename
	if not ResourceLoader.exists(path):
		push_error("World material texture is missing: "+path)
		return null
	if DisplayServer.get_name()=="headless":
		# The dummy renderer has no GPU texture storage. Validate the imported
		# resource and, in source checkouts, decode the actual JPEG on the CPU.
		# Avoid dummy-RID uploads while threaded GLB imports load their textures.
		# A real renderer still loads the full PBR textures below.
		if not checked_headless_textures.has(path):
			var source_path := ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(source_path):
				var image := Image.load_from_file(source_path)
				if image==null or image.is_empty():
					push_error("World material texture cannot be decoded: "+path)
			checked_headless_textures[path]=true
		return null
	return load(path) as Texture2D

func _pbr(asset: String, tint: Color, scale_value: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _texture(asset+"_Diffuse.jpg")
	mat.normal_enabled = true
	mat.normal_texture = _texture(asset+"_nor_gl.jpg")
	mat.roughness_texture = _texture(asset+"_Rough.jpg")
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.albedo_color = tint
	mat.roughness = 0.94
	mat.normal_scale = 0.65
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE*scale_value
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

func _wood() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 p;
uniform vec3 bark_dark=vec3(0.115,0.065,0.032);
uniform vec3 bark_light=vec3(0.29,0.18,0.09);
void vertex(){ p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 float grain=sin(p.y*13.0+sin(p.x*37.0)*0.8+sin(p.z*22.0));
 float split=smoothstep(0.88,1.0,sin(p.x*71.0+p.z*64.0+sin(p.y*2.1)));
 ALBEDO=mix(bark_dark,bark_light,grain*0.5+0.5)*(1.0-split*0.3);
 ROUGHNESS=0.97;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if biome==BiomeCatalog.Kind.VOLCANIC:
		mat.set_shader_parameter("bark_dark",Vector3(0.025,0.021,0.018))
		mat.set_shader_parameter("bark_light",Vector3(0.105,0.085,0.07))
	return mat

func _build_terrain() -> void:
	var ground := get_parent().get_node_or_null("NoiseTexturedGround") as MeshInstance3D
	if ground == null:
		ground = MeshInstance3D.new()
		ground.name = "NoiseTexturedGround"
		get_parent().add_child(ground)
	ground.position = Vector3.ZERO
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 100
	var nz := 72
	for z in range(nz):
		for x in range(nx):
			var corners: Array[Vector3] = []
			for offset in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
				var px := (float(x+offset.x)/float(nx)-0.5)*world_size
				var pz := (float(z+offset.y)/float(nz)-0.5)*world_size*0.72
				# The playable surface stays level with placement, while the outer banks rise.
				var edge := maxf(absf(px)/(world_size*0.5),absf(pz)/(world_size*0.36))
				var banks := smoothstep(0.985,1.0,edge)*0.65
				var height := -0.18 + banks*(0.72+0.28*sin(px*0.42)*cos(pz*0.31))
				if _clearance(Vector3(px,0,pz))<4.0: height=-0.18
				corners.append(Vector3(px,height,pz))
			# Match PlaneMesh: Godot's visible top faces use clockwise winding.
			for index in [0,1,2,1,3,2]:
				st.set_uv(Vector2(corners[index].x,corners[index].z))
				st.add_vertex(corners[index])
	st.generate_normals()
	st.generate_tangents()
	ground.mesh = st.commit()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint=vec3(0.9,1.0,0.82);
uniform float meadow_grade=0.0;
uniform float worn_strength=0.52;
uniform int biome_mode=0;
uniform vec3 ground_tint=vec3(0.15,0.24,0.08);
varying vec3 p;
float hash(vec2 x){return fract(sin(dot(x,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 x){vec2 i=floor(x), f=fract(x);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 uv=p.xz*0.33;
 float patch=smoothstep(0.36,0.68,noise(p.xz*0.13));
 vec3 grass_scan=texture(meadow,uv).rgb;
 float grass_value=dot(grass_scan,vec3(0.2126,0.7152,0.0722));
 vec3 meadow_green=grass_value*vec3(0.42,0.90,0.28);
 vec3 grass=mix(grass_scan,meadow_green,meadow_grade)*tint;
 vec3 dirt=texture(soil,p.xz*0.49).rgb;
 float worn=patch*worn_strength;
 ALBEDO=mix(grass,dirt,worn)*(0.91+noise(p.xz*0.035)*0.16);
 float detail=dot(grass_scan,vec3(0.2126,0.7152,0.0722));
 if(biome_mode==2){
  float dunes=sin(p.x*2.4+p.z*0.65+noise(p.xz*0.22)*5.0)*0.5+0.5;
  ALBEDO=ground_tint*(0.80+detail*0.34+dunes*0.12);
 }else if(biome_mode==3){
  ALBEDO=mix(grass*vec3(0.90,0.73,0.44),dirt*vec3(0.80,0.68,0.40),0.46+patch*0.22);
 }else if(biome_mode==4){
  float drift=noise(p.xz*0.40);
  ALBEDO=ground_tint*(0.89+drift*0.13+detail*0.06);
 }else if(biome_mode==5){
  ALBEDO=ground_tint*(0.66+detail*0.55+noise(p.xz*0.75)*0.30);
 }
 NORMAL_MAP=mix(texture(meadow_normal,uv).rgb,texture(soil_normal,p.xz*0.49).rgb,worn);
 NORMAL_MAP_DEPTH=0.60;
 ROUGHNESS=clamp(texture(roughness_map,uv).r,0.68,1.0);
}
"""
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = shader
	terrain_material.set_shader_parameter("meadow",_texture("aerial_grass_rock_Diffuse.jpg"))
	terrain_material.set_shader_parameter("soil",_texture("brown_mud_leaves_01_Diffuse.jpg"))
	terrain_material.set_shader_parameter("meadow_normal",_texture("aerial_grass_rock_nor_gl.jpg"))
	terrain_material.set_shader_parameter("soil_normal",_texture("brown_mud_leaves_01_nor_gl.jpg"))
	terrain_material.set_shader_parameter("roughness_map",_texture("aerial_grass_rock_Rough.jpg"))
	terrain_material.set_shader_parameter("tint",Vector3(0.62,0.82,0.60) if biome!=BiomeCatalog.Kind.JUNGLE else Vector3(0.35,0.62,0.45))
	terrain_material.set_shader_parameter("biome_mode",biome)
	terrain_material.set_shader_parameter("ground_tint",_rgb(profile.ground))
	terrain_material.set_shader_parameter("meadow_grade",0.82)
	terrain_material.set_shader_parameter("worn_strength",0.18 if biome!=BiomeCatalog.Kind.JUNGLE else 0.26)
	ground.material_override = terrain_material
	ground.set_meta("biome",profile.key)

func _rgb(color: Color) -> Vector3:
	return Vector3(color.r,color.g,color.b)

func create_bird(parent: Node3D, origin: Vector3, phase: float) -> Dictionary:
	return BiomeLife.make_bird(parent,origin,phase,profile)

func create_ground_animal(parent: Node3D, origin: Vector3, phase: float) -> Dictionary:
	return BiomeLife.make_ground_animal(parent,origin,phase,profile)

func _build_weather() -> void:
	# One instanced draw, vertex-animated on the GPU. No per-particle Node/process cost.
	var kind: String=profile.weather
	var count: int={"rain":260,"snow":260,"leaves":75,"ash":120,"dust":90,"pollen":45}[kind]
	var tint: Color={"rain":Color(0.54,0.69,0.74,0.28),"snow":Color(0.91,0.96,1.0,0.80),"leaves":Color(0.72,0.31,0.04,0.85),"ash":Color(0.47,0.43,0.39,0.42),"dust":Color(0.62,0.47,0.27,0.18),"pollen":Color(0.70,0.76,0.38,0.18)}[kind]
	var geometry := SphereMesh.new()
	geometry.radius=0.027 if kind=="rain" else 0.045
	geometry.height=0.58 if kind=="rain" else 0.04
	geometry.radial_segments=5
	geometry.rings=3
	var shader:=Shader.new()
	shader.code="""
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 weather_tint : source_color;
uniform float fall_speed=0.7;
uniform float sway=0.6;
uniform float field_height=8.0;
varying float fade;
void vertex(){
 float seed=float(INSTANCE_ID)*2.39996;
 float cycle=fract(TIME*fall_speed/field_height+fract(seed));
 VERTEX.y+=(1.0-cycle)*field_height;
 VERTEX.x+=sin(TIME*0.63+seed)*sway;
 VERTEX.z+=cos(TIME*0.48+seed*0.7)*sway*0.6;
 fade=smoothstep(0.0,0.10,cycle)*(1.0-smoothstep(0.87,1.0,cycle));
}
void fragment(){ALBEDO=weather_tint.rgb;ALPHA=weather_tint.a*fade;}
"""
	var mat:=ShaderMaterial.new()
	mat.shader=shader
	mat.set_shader_parameter("weather_tint",tint)
	mat.set_shader_parameter("fall_speed",7.5 if kind=="rain" else (0.78 if kind=="snow" else 0.34))
	mat.set_shader_parameter("sway",0.15 if kind=="rain" else (1.3 if kind in ["leaves","dust"] else 0.6))
	var transforms: Array[Transform3D]=[]
	for i in range(count):
		transforms.append(Transform3D(Basis.IDENTITY,Vector3(rng.randf_range(-0.48,0.48)*world_size,0.1,rng.randf_range(-0.33,0.33)*world_size)))
	var weather:=_instances("BiomeWeather",geometry,mat,transforms)
	weather.set_meta("weather",kind)
	weather.set_meta("max_particles",count)
	weather.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weather.custom_aabb=AABB(Vector3(-world_size*0.5,-0.3,-world_size*0.36),Vector3(world_size,10.0,world_size*0.72))
	weather.multimesh.custom_aabb=weather.custom_aabb

func _build_biome_accents() -> void:
	if biome==BiomeCatalog.Kind.DESERT:
		var cactus:=SurfaceTool.new()
		cactus.begin(Mesh.PRIMITIVE_TRIANGLES)
		_branch(cactus,Vector3.ZERO,Vector3(0,1.55,0),0.19,0.12,Color(0.16,0.30,0.13))
		for side in [-1.0,1.0]:
			_branch(cactus,Vector3(0,0.65,0),Vector3(side*0.43,0.82,0.02),0.11,0.10,Color(0.20,0.33,0.13))
			_branch(cactus,Vector3(side*0.43,0.82,0.02),Vector3(side*0.46,1.26,0.02),0.10,0.07,Color(0.24,0.36,0.14))
		cactus.generate_normals()
		var cactus_mat:=StandardMaterial3D.new()
		cactus_mat.vertex_color_use_as_albedo=true
		cactus_mat.roughness=0.92
		var transforms: Array[Transform3D]=[]
		for i in range(36):
			var p:=Vector3(rng.randf_range(-0.47,0.47)*world_size,-0.13,rng.randf_range(-0.325,0.325)*world_size)
			if _clearance(p)<6.0: continue
			var scale_value:=rng.randf_range(0.6,1.15)
			transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),p))
			obstacles.append({"position":Vector2(p.x,p.z),"radius":0.6*scale_value})
		_instances("BiomeCactusGroves",cactus.commit(),cactus_mat,transforms)
	if biome==BiomeCatalog.Kind.AUTUMN:
		var litter:=SurfaceTool.new()
		litter.begin(Mesh.PRIMITIVE_TRIANGLES)
		_triangle(litter,Vector3(-0.07,0.01,0),Vector3(0,0.04,-0.13),Vector3(0.07,0.01,0),Color(0.54,0.20,0.025))
		_triangle(litter,Vector3(0.07,0.01,0),Vector3(0,0.015,0.10),Vector3(-0.07,0.01,0),Color(0.74,0.35,0.04))
		litter.generate_normals()
		var leafmat:=StandardMaterial3D.new()
		leafmat.vertex_color_use_as_albedo=true
		leafmat.cull_mode=BaseMaterial3D.CULL_DISABLED
		var transforms: Array[Transform3D]=[]
		for i in range(1100):
			var p:=Vector3(rng.randf_range(-0.47,0.47)*world_size,-0.14,rng.randf_range(-0.325,0.325)*world_size)
			if _clearance(p)<2.0: continue
			transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(0.8,1.6)),p))
		_instances("BiomeAutumnLeafLitter",litter.commit(),leafmat,transforms)
	if biome==BiomeCatalog.Kind.WINTER:
		var snow:=StandardMaterial3D.new()
		snow.albedo_color=Color(0.78,0.86,0.90)
		snow.roughness=0.88
		for family in range(3):
			var rocks:=get_node("ScannedRockClusters%d"%family) as MultiMeshInstance3D
			var transforms: Array[Transform3D]=[]
			for source: Transform3D in rocks.get_meta("instance_transforms",[]):
				var cap:=source
				cap.origin.y+=source.basis.y.length()*0.48
				cap.basis=source.basis.scaled_local(Vector3(0.89,0.15,0.89))
				transforms.append(cap)
			_instances("BiomeSnowRockCaps%d"%family,mesh_cache[family],snow,transforms)
	if biome==BiomeCatalog.Kind.VOLCANIC:
		var embers:=StandardMaterial3D.new()
		embers.albedo_color=Color(0.28,0.055,0.012)
		embers.emission_enabled=true
		embers.emission=Color(1.0,0.11,0.008)
		embers.emission_energy_multiplier=1.8
		var transforms: Array[Transform3D]=[]
		for family in range(3):
			var rocks:=get_node("ScannedRockClusters%d"%family) as MultiMeshInstance3D
			var stored: Array=rocks.get_meta("instance_transforms",[])
			for i in range(0,stored.size(),4):
				var source: Transform3D=stored[i]
				transforms.append(Transform3D(source.basis.scaled_local(Vector3(0.8,0.05,0.6)),source.origin+Vector3.UP*0.05))
		var hot_rock:=_instances("BiomeEmberFissures",mesh_cache[0],embers,transforms)
		hot_rock.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _clearance(p: Vector3) -> float:
	var value := INF
	for i in range(1,route.size()):
		var a := route[i-1]
		var ab := route[i]-a
		var t := clampf((p-a).dot(ab)/maxf(ab.length_squared(),0.001),0.0,1.0)
		value=minf(value,p.distance_to(a+ab*t))
	return value

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color = Color.WHITE) -> void:
	for p in [a,b,c]:
		st.set_color(color)
		st.set_uv(Vector2(p.x+p.z,p.y))
		st.add_vertex(p)

func _rock_mesh(seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed=seed_value
	noise.frequency=1.8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for row in range(13):
		var phi := PI*float(row)/12.0
		var ring: Array[Vector3] = []
		for j in range(25):
			var theta := TAU*float(j)/24.0
			var p := Vector3(sin(phi)*cos(theta),cos(phi),sin(phi)*sin(theta))
			var amount := 1.0+noise.get_noise_3dv(p*2.7)*0.28+noise.get_noise_3dv(p*7.0)*0.07
			p*=amount
			p.y = maxf(-0.62,p.y)*0.72
			ring.append(p)
		rows.append(ring)
	for row in range(12):
		for j in range(24):
			_triangle(st,rows[row][j],rows[row+1][j],rows[row][j+1])
			_triangle(st,rows[row][j+1],rows[row+1][j],rows[row+1][j+1])
	st.generate_normals()
	st.index()
	return st.commit()

func _instances(label: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D], colors: Array[Color] = []) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name=label
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.use_colors=not colors.is_empty()
	multi.mesh=mesh
	multi.instance_count=transforms.size()
	var local_bounds := AABB()
	var has_bounds := false
	for i in range(transforms.size()):
		multi.set_instance_transform(i,transforms[i])
		if not colors.is_empty(): multi.set_instance_color(i,colors[i])
		var instance_bounds: AABB = transforms[i]*mesh.get_aabb()
		local_bounds = local_bounds.merge(instance_bounds) if has_bounds else instance_bounds
		has_bounds = true
	# Do not depend on delayed renderer-side instance-buffer readback for culling
	# or settlement reservations. This also keeps native/headless layouts equal.
	if has_bounds:
		multi.custom_aabb = local_bounds.grow(0.25)
		node.custom_aabb = local_bounds.grow(0.25)
	node.multimesh=multi
	node.set_meta("instance_transforms",transforms.duplicate())
	node.set_meta("instance_colors",colors.duplicate())
	node.material_override=mat
	node.visibility_range_end=150.0
	add_child(node)
	return node

func _build_boulders() -> void:
	for family in range(3):
		var transforms: Array[Transform3D] = []
		var mesh := _rock_mesh(91+family*14)
		mesh_cache.append(mesh)
		for i in range(28):
			var p := Vector3(rng.randf_range(-0.47,0.47)*world_size,0.0,rng.randf_range(-0.325,0.325)*world_size)
			if _clearance(p)<5.8: continue
			# Group scree around the perimeter; retain open central meadow for building.
			if absf(p.x)<world_size*0.24 and absf(p.z)<world_size*0.16 and i%3!=0: continue
			var s := rng.randf_range(0.30,1.15)
			var shape := Vector3(s*rng.randf_range(1.0,1.7),s*rng.randf_range(0.7,1.3),s)
			transforms.append(Transform3D(Basis.from_euler(Vector3(0,rng.randf()*TAU,rng.randf_range(-0.14,0.14))).scaled(shape),p+Vector3.UP*s*0.35))
			obstacles.append({"position":Vector2(p.x,p.z),"radius":maxf(shape.x,shape.z)*0.85})
		_instances("ScannedRockClusters%d"%family,mesh,rock_material,transforms)

func _branch(st: SurfaceTool, a: Vector3, b: Vector3, bottom_radius: float, top_radius: float, color: Color) -> void:
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length()<0.1: side=axis.cross(Vector3.RIGHT).normalized()
	var tangent := axis.cross(side).normalized()
	for i in range(9):
		var t0 := TAU*float(i)/9.0
		var t1 := TAU*float(i+1)/9.0
		var v0 := side*cos(t0)+tangent*sin(t0)
		var v1 := side*cos(t1)+tangent*sin(t1)
		_triangle(st,a+v0*bottom_radius,b+v0*top_radius,b+v1*top_radius,color)
		_triangle(st,a+v0*bottom_radius,b+v1*top_radius,a+v1*bottom_radius,color)

func _tree_meshes() -> Array[ArrayMesh]:
	var bark := SurfaceTool.new()
	var leaves := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	if profile.tree in ["palm","tropical"]:
		_build_palm_mesh(bark,leaves)
		bark.generate_normals()
		leaves.generate_normals()
		return [bark.commit(),leaves.commit()]
	if profile.tree=="conifer":
		_build_conifer_mesh(bark,leaves)
		bark.generate_normals()
		leaves.generate_normals()
		return [bark.commit(),leaves.commit()]
	_branch(bark,Vector3.ZERO,Vector3(0.12,3.7,0.13),0.24,0.07,Color.WHITE)
	for i in range(11):
		var angle := float(i)*2.39
		var center := Vector3(cos(angle)*1.10,2.4+float(i%4)*0.42,sin(angle)*1.08)
		_branch(bark,Vector3(0.05,1.5+float(i%5)*0.34,0.05),center,0.085,0.022,Color.WHITE)
		if profile.tree=="charred": continue
		# Numerous real leaf surfaces create a ragged, translucent canopy silhouette.
		for j in range(42):
			var theta := rng.randf()*TAU
			var phi := acos(rng.randf_range(-1.0,1.0))
			var p := center+Vector3(sin(phi)*cos(theta),cos(phi)*0.75,sin(phi)*sin(theta))*rng.randf_range(0.24,0.94)
			var n := Vector3(cos(theta),rng.randf_range(0.2,0.8),sin(theta)).normalized()
			var side := n.cross(Vector3.UP).normalized()*rng.randf_range(0.12,0.22)
			var tip := Vector3.UP*rng.randf_range(0.13,0.31)
			var color: Color=(profile.foliage_a as Color).lerp(profile.foliage_b,rng.randf())
			_triangle(leaves,p-side,p+tip+n*0.10,p+side,color)
			_triangle(leaves,p-side,p+side,p-tip,color.darkened(0.12))
	bark.generate_normals()
	# A charred tree has real branching geometry and no fake green canopy.
	if profile.tree=="charred":
		_triangle(leaves,Vector3.ZERO,Vector3(0.001,0,0),Vector3(0,0.001,0),Color(0,0,0,0))
	leaves.generate_normals()
	return [bark.commit(),leaves.commit()]

func _build_palm_mesh(bark: SurfaceTool, leaves: SurfaceTool) -> void:
	var tall := 5.1 if profile.tree=="tropical" else 4.2
	var last := Vector3.ZERO
	for segment in range(9):
		var t:=float(segment+1)/9.0
		var next:=Vector3(sin(t*1.2)*0.37,t*tall,0.08*t*t)
		_branch(bark,last,next,lerpf(0.23,0.12,t-0.11),lerpf(0.23,0.12,t),Color.WHITE)
		last=next
	for frond in range(12):
		var angle:=float(frond)*TAU/12.0
		var dir:=Vector3(cos(angle),0,sin(angle))
		var side:=Vector3(-sin(angle),0,cos(angle))
		for step in range(10):
			var t:=float(step)/10.0
			var u:=float(step+1)/10.0
			var a:=last+dir*t*2.2+Vector3.UP*(sin(t*PI)*0.48-t*t*0.78)
			var b:=last+dir*u*2.2+Vector3.UP*(sin(u*PI)*0.48-u*u*0.78)
			var width:=sin(t*PI)*0.30+0.025
			var color: Color=(profile.foliage_a as Color).lerp(profile.foliage_b,t)
			_triangle(leaves,a,b,a+side*width-dir*0.15,color)
			_triangle(leaves,a,a-side*width-dir*0.15,b,color.darkened(0.05))
			# Separated leaflets produce a fern-like silhouette, not a solid triangle.
			if step>1:
				_triangle(leaves,b,a+side*width*1.4-dir*0.25,a+side*width*0.3,color)
				_triangle(leaves,a-side*width*0.3,a-side*width*1.4-dir*0.25,b,color)
	if profile.tree=="tropical":
		for i in range(5):
			var angle:=float(i)*TAU/5.0
			_branch(bark,Vector3(cos(angle)*0.65,0.0,sin(angle)*0.65),Vector3(0.1,0.85,0),0.11,0.08,Color.WHITE)
		# Wide banana-like understory and hanging woody lianas distinguish the
		# humid forest silhouette from the sparse, exposed oasis palms.
		for frond in range(6):
			var angle:=float(frond)*TAU/6.0
			var dir:=Vector3(cos(angle),0,sin(angle))
			var side:=Vector3(-sin(angle),0,cos(angle))
			var a:=Vector3(0.0,0.3,0.0)
			var mid:=dir*0.74+Vector3.UP*1.36
			var tip:=dir*1.50+Vector3.UP*1.12
			_triangle(leaves,a,mid-side*0.27,mid+Vector3.UP*0.07,profile.foliage_a)
			_triangle(leaves,a,mid+Vector3.UP*0.07,mid+side*0.27,profile.foliage_b)
			_triangle(leaves,mid-side*0.27,tip,mid+Vector3.UP*0.07,profile.foliage_a)
			_triangle(leaves,mid+Vector3.UP*0.07,tip,mid+side*0.27,profile.foliage_b)
		for vine in range(3):
			var start:=last+Vector3(float(vine-1)*0.46,-0.35,0.24)
			for segment in range(6):
				var a:=start+Vector3(sin(float(segment)*0.7)*0.11,-float(segment)*0.43,0)
				var b:=start+Vector3(sin(float(segment+1)*0.7)*0.11,-float(segment+1)*0.43,0)
				_branch(bark,a,b,0.025,0.022,Color.WHITE)

func _build_conifer_mesh(bark: SurfaceTool, leaves: SurfaceTool) -> void:
	_branch(bark,Vector3.ZERO,Vector3(0,4.8,0),0.22,0.025,Color.WHITE)
	for tier in range(7):
		var y:=0.95+float(tier)*0.51
		var radius:=1.6-float(tier)*0.19
		for i in range(14):
			var a:=TAU*float(i)/14.0+float(tier)*0.27
			var b:=a+TAU/14.0
			var p:=Vector3(cos(a)*radius,y,sin(a)*radius)
			var q:=Vector3(cos(b)*radius,y,sin(b)*radius)
			var tip:=Vector3(0,y+1.05,0)
			var color: Color=(profile.foliage_a as Color).lerp(profile.foliage_b,float(i%4)/4.0)
			_triangle(leaves,p,q,tip,color)
			# Snow is actual raised upper facets above darker needles.
			var snow:=Color(0.74,0.83,0.87).darkened(float(i%3)*0.035)
			_triangle(leaves,p.lerp(tip,0.20)+Vector3.UP*0.018,q.lerp(tip,0.20)+Vector3.UP*0.018,tip+Vector3.UP*0.023,snow)

func _wind_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code="""
shader_type spatial;
render_mode cull_disabled;
varying float shade;
void vertex(){
 vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float wind=sin(p.x*0.55+p.z*0.37+TIME*1.45)+sin(p.x*1.4+TIME*0.77)*0.38;
 VERTEX.x+=wind*clamp(VERTEX.y,0.0,4.0)*0.025;
 VERTEX.z+=wind*clamp(VERTEX.y,0.0,4.0)*0.015;
 shade=clamp(VERTEX.y*0.6,0.72,1.0);
}
void fragment(){ALBEDO=COLOR.rgb*shade;ROUGHNESS=0.88;BACKLIGHT=COLOR.rgb*0.17;}
"""
	var mat:=ShaderMaterial.new()
	mat.shader=shader
	return mat

func _build_vegetation() -> void:
	var tree_meshes := _tree_meshes()
	var tree_transforms: Array[Transform3D] = []
	for i in range(int(profile.trees)):
		var p := Vector3(rng.randf_range(-0.47,0.47)*world_size,0,rng.randf_range(-0.325,0.325)*world_size)
		if _clearance(p)<9.0: continue
		if absf(p.x)<world_size*0.30 and absf(p.z)<world_size*0.21: continue
		var scale_value := rng.randf_range(0.74,1.35)
		tree_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),p))
		obstacles.append({"position":Vector2(p.x,p.z),"radius":0.42*scale_value})
	var trunks:=_instances("BranchingTreeTrunks",tree_meshes[0],wood_material,tree_transforms)
	trunks.set_meta("tree_style",profile.tree)
	if profile.tree!="charred": _instances("IndividualLeafCanopies",tree_meshes[1],_wind_material(),tree_transforms)
	var grass_st:=SurfaceTool.new()
	grass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(9):
		var angle:=float(i)*2.4
		var start:=Vector3(cos(angle),0,sin(angle))*rng.randf_range(0.0,0.14)
		var side:=Vector3(-sin(angle),0,cos(angle))*rng.randf_range(0.012,0.028)
		var middle:=start+Vector3(cos(angle)*0.055,rng.randf_range(0.15,0.30),sin(angle)*0.055)
		var tip:=middle+Vector3(cos(angle)*0.075,rng.randf_range(0.10,0.20),sin(angle)*0.075)
		_triangle(grass_st,start-side,middle-side*0.65,start+side,profile.grass_a)
		_triangle(grass_st,start+side,middle-side*0.65,middle+side*0.65,(profile.grass_a as Color).lerp(profile.grass_b,0.5))
		_triangle(grass_st,middle-side*0.65,tip,middle+side*0.65,profile.grass_b)
	grass_st.generate_normals()
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var count:=int(float(4000+int(world_size)*8)*float(profile.grass))
	for i in range(count):
		var p:=Vector3(rng.randf_range(-0.485,0.485)*world_size,-0.15,rng.randf_range(-0.34,0.34)*world_size)
		if _clearance(p)<2.2: continue
		var s:=rng.randf_range(0.55,1.30)
		grass_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*s),p))
		grass_colors.append(Color(1.0,rng.randf_range(0.88,1.14),rng.randf_range(0.82,1.07)))
	var grass:=_instances("WindAnimatedMeadow",grass_st.commit(),_wind_material(),grass_transforms,grass_colors)
	grass.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if int(profile.ferns)==0: return
	var fern_st:=SurfaceTool.new()
	fern_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in range(7):
		var angle:=float(frond)*TAU/7.0
		var dir:=Vector3(cos(angle),0,sin(angle))
		var side:=Vector3(-sin(angle),0,cos(angle))
		for l in range(8):
			var t:=float(l+1)/9.0
			var p:=dir*t*0.65+Vector3.UP*sin(t*PI*0.85)*0.42
			var w:=sin(t*PI)*0.18
			for sign_value in [-1.0,1.0]:
				_triangle(fern_st,p-dir*0.035,p+side*w*sign_value-dir*0.05,p+dir*0.075,Color(0.16+t*0.05,0.31+t*0.12,0.09))
	fern_st.generate_normals()
	var fern_transforms:Array[Transform3D]=[]
	for i in range(int(profile.ferns)):
		var p:=Vector3(rng.randf_range(-0.47,0.47)*world_size,-0.14,rng.randf_range(-0.325,0.325)*world_size)
		if _clearance(p)<4.2: continue
		fern_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(0.6,1.25)),p))
	_instances("FernUndergrowth",fern_st.commit(),_wind_material(),fern_transforms)

func _upgrade_road() -> void:
	# Reuse the CC0 scan's grain, normals and roughness without its orange leaf
	# color. The compacted track remains a lighter grey-beige against the meadow.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform sampler2D dirt_scan : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer_shade=1.0;
uniform vec3 road_tint=vec3(0.36,0.315,0.255);
varying vec3 p;
void vertex(){
 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 TANGENT=vec3(1.0,0.0,0.0);
 BINORMAL=vec3(0.0,0.0,-1.0);
}
void fragment(){
 vec2 uv=vec2(p.x,-p.z)*0.48;
 vec3 scan=texture(dirt_scan,uv).rgb;
 float value=dot(scan,vec3(0.2126,0.7152,0.0722));
 float grain=0.72+0.35*sqrt(clamp(value,0.0,1.0));
 ALBEDO=road_tint*grain*layer_shade;
 NORMAL_MAP=texture(dirt_normal,uv).rgb;
 NORMAL_MAP_DEPTH=0.28;
 ROUGHNESS=clamp(texture(dirt_roughness,uv).r,0.83,1.0);
}
"""
	var dirt := ShaderMaterial.new()
	dirt.shader = shader
	dirt.set_shader_parameter("dirt_scan",_texture("brown_mud_leaves_01_Diffuse.jpg"))
	dirt.set_shader_parameter("dirt_normal",_texture("brown_mud_leaves_01_nor_gl.jpg"))
	dirt.set_shader_parameter("dirt_roughness",_texture("brown_mud_leaves_01_Rough.jpg"))
	dirt.set_shader_parameter("road_tint",_rgb(profile.road))
	for child in get_parent().get_children():
		if child is MeshInstance3D and child.name != "NoiseTexturedGround" and child.mesh is ArrayMesh and child.position==Vector3.ZERO:
			var layer := dirt.duplicate() as ShaderMaterial
			var original := child.mesh.surface_get_material(0) as StandardMaterial3D
			if original != null:
				var color: Color = original.albedo_color
				var value := color.r*0.2126+color.g*0.7152+color.b*0.0722
				layer.set_shader_parameter("layer_shade",clampf(0.60+value*0.70,0.68,1.10))
			child.material_override=layer

func _build_tunnel(point: Vector3, inward: Vector3, label: String) -> void:
	var cave:=Node3D.new()
	cave.name=label
	cave.position=Vector3(point.x,-0.18,point.z)
	cave.rotation.y=atan2(-inward.x,-inward.z)
	add_child(cave)
	obstacles.append({"position":Vector2(point.x,point.z),"radius":3.9})
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Half elliptical tunnel, with inner walls, upper arch and visibly receding interior.
	for depth in range(9):
		for arc in range(24):
			var points:Array[Vector3]=[]
			for offset in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
				var d:=float(depth+offset.y)/8.0
				var angle:=PI*float(arc+offset.x)/24.0
				var radius_scale:=1.0-d*0.21
				var ripple:=sin(angle*5.0+d*7.0)*0.06
				points.append(Vector3(cos(angle)*(2.0+ripple)*radius_scale,sin(angle)*(3.15+ripple)*radius_scale,d*5.0))
			_triangle(st,points[0],points[1],points[2],Color(1,1,1).darkened(float(depth)*0.065))
			_triangle(st,points[1],points[3],points[2],Color(1,1,1).darkened(float(depth)*0.065))
	st.generate_normals()
	var inner:=MeshInstance3D.new()
	inner.name="RecedingRockTunnel"
	inner.mesh=st.commit()
	var tunnel_mat:=rock_material.duplicate() as StandardMaterial3D
	tunnel_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	tunnel_mat.vertex_color_use_as_albedo=true
	inner.material_override=tunnel_mat
	cave.add_child(inner)
	var dark:=StandardMaterial3D.new()
	dark.albedo_color=Color(0.012,0.013,0.011)
	_box(cave,Vector3(0,1.15,5.05),Vector3(3.25,2.4,0.12),dark)
	for i in range(15):
		var angle:=PI*float(i)/14.0
		var rock:=MeshInstance3D.new()
		rock.mesh=mesh_cache[i%mesh_cache.size()]
		rock.material_override=rock_material
		rock.position=Vector3(cos(angle)*2.55,sin(angle)*3.2,0.55+rng.randf()*0.6)
		rock.scale=Vector3(rng.randf_range(0.63,1.05),rng.randf_range(0.78,1.20),rng.randf_range(0.8,1.4))
		rock.rotation=Vector3(rng.randf()*0.4,rng.randf()*TAU,rng.randf()*0.4)
		cave.add_child(rock)
	for side in [-1.0,1.0]:
		var rubble:=MeshInstance3D.new()
		rubble.mesh=mesh_cache[0]
		rubble.material_override=rock_material
		rubble.position=Vector3(side*3.1,0.28,1.1)
		rubble.scale=Vector3(1.15,0.65,1.8)
		cave.add_child(rubble)

func _box(parent: Node3D, position: Vector3, size: Vector3, material: Material, rotation: Vector3=Vector3.ZERO) -> MeshInstance3D:
	var instance:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	instance.mesh=mesh
	instance.material_override=material
	instance.position=position
	instance.rotation=rotation
	parent.add_child(instance)
	return instance

func decorate_hamlet(hamlet: Node3D) -> void:
	if hamlet==null:
		_prepare_spatial_batches()
		return
	hamlet.set_meta("biome",profile.key)
	var roof_mat:=_pbr("brown_mud_leaves_01",Color(0.53,0.43,0.32) if biome!=BiomeCatalog.Kind.WINTER else Color(0.91,0.96,1.0),2.8)
	var stone_mat:=rock_material
	for cottage in hamlet.get_children():
		if not (cottage is Node3D) or not str(cottage.name).begins_with("Cottage"): continue
		# Roof shingles, foundation, chimney and beams turn the cottage into a small scene.
		_box(cottage,Vector3(0,-0.05,0),Vector3(3.58,0.30,2.93),stone_mat)
		_box(cottage,Vector3(0.98,2.83,0.60),Vector3(0.40,1.25,0.46),stone_mat)
		_box(cottage,Vector3(0.98,3.48,0.60),Vector3(0.51,0.14,0.57),stone_mat)
		var shingle_transforms: Array[Transform3D] = []
		for side in [-1.0,1.0]:
			for row in range(5):
				for col in range(9):
					var x: float=side*(0.13+float(row)*0.37)
					# Match the actual roof slab's upper plane, then offset the
					# shingle bottom 12 mm along its normal. Global scaling would
					# flatten the rotated boxes and make them intersect in stripes.
					var roof_plane_y := 2.46+tan(0.43)*(0.83-absf(x))
					var y := roof_plane_y+(0.09+0.0275+0.012)/cos(0.43)
					var z:=-1.46+float(col)*0.36+float(row%2)*0.08
					shingle_transforms.append(Transform3D(Basis.from_euler(Vector3(0,0,side*-0.43)).scaled_local(Vector3(0.40,0.055,0.355)),Vector3(x,y,z)))
		var shingle_mesh := BoxMesh.new()
		shingle_mesh.size = Vector3.ONE
		var shingles:=_instances("InstancedRoofShingles",shingle_mesh,roof_mat,shingle_transforms)
		shingles.reparent(cottage,false)
		if biome==BiomeCatalog.Kind.WINTER:
			var snow_mat:=StandardMaterial3D.new()
			snow_mat.albedo_color=Color(0.78,0.87,0.93)
			snow_mat.roughness=0.86
			for side in [-1.0,1.0]:
				_box(cottage,Vector3(side*0.83,2.57,0),Vector3(2.06,0.045,3.13),snow_mat,Vector3(0,0,side*-0.43))
		for y in [0.25,0.65,1.05]:
			_box(cottage,Vector3(0.0,y,-1.51),Vector3(0.52,0.015,0.02),wood_material)
		_box(cottage,Vector3(0.25,0.70,-1.53),Vector3(0.05,0.10,0.05),stone_mat)
		for side in [-1.0,1.0]:
			_box(cottage,Vector3(0.82+side*0.28,1.20,-1.49),Vector3(0.20,0.48,0.06),wood_material)
		_make_smoke(cottage,Vector3(0.98,3.54,0.60))
	_build_well(hamlet,Vector3(-1.8,0,-3.7))
	_build_workyard(hamlet)
	var pond:=hamlet.get_node_or_null("HamletPond") as MeshInstance3D
	if pond!=null:
		var water_shader:=Shader.new()
		water_shader.code="""
shader_type spatial;
uniform vec3 water_tint=vec3(0.055,0.18,0.18);
uniform int water_state=0;
varying vec3 p;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;if(water_state!=1){VERTEX.y+=sin(p.x*2.1+TIME*0.8)*sin(p.z*1.5+TIME*0.6)*0.012;}}
void fragment(){
 float ripples=sin(p.x*9.0+p.z*7.0+TIME*1.7)*sin(p.x*5.0-p.z*8.0+TIME)*0.5+0.5;
 ALBEDO=water_tint+ripples*0.018;ROUGHNESS=0.23;METALLIC=0.15;SPECULAR=0.7;
 if(water_state==1){
  float cracks=pow(abs(sin(p.x*5.5+sin(p.z*3.8)*1.4)*sin(p.z*4.6+sin(p.x*2.7))),24.0);
  ALBEDO=mix(water_tint,vec3(0.72,0.86,0.93),cracks*0.75);
  ROUGHNESS=0.18+cracks*0.25;METALLIC=0.04;
 }else if(water_state==2){
  float bubbles=pow(sin(p.x*19.0+TIME*3.6)*sin(p.z*17.0-TIME*2.7)*0.5+0.5,10.0);
  ALBEDO+=bubbles*vec3(0.12,0.13,0.09);ROUGHNESS=0.33;
 }
}
"""
		water_material=ShaderMaterial.new()
		water_material.shader=water_shader
		water_material.set_shader_parameter("water_tint",_rgb(profile.water_tint))
		water_material.set_shader_parameter("water_state",1 if profile.water=="ice" else (2 if profile.water=="boiling" else 0))
		pond.material_override=water_material
		pond.set_meta("water_state",profile.water)
		if profile.water=="boiling":
			for j in range(3):
				_make_smoke(hamlet,Vector3(-0.95+float(j)*0.95,0.05,5.6),true)
		for i in range(19):
			var theta:=TAU*float(i)/19.0
			var stone:=MeshInstance3D.new()
			stone.mesh=mesh_cache[i%3]
			stone.material_override=rock_material
			stone.position=Vector3(cos(theta)*2.48,-0.04,5.6+sin(theta)*2.48)
			stone.scale=Vector3(0.22,0.16,0.30)*rng.randf_range(0.8,1.3)
			hamlet.add_child(stone)
	# All settlement reservations and seasonal geometry are now final. Keep
	# actors/animation handles intact while baking only immobile geometry.
	var before:=RenderOpt.inventory(hamlet)
	var excluded: Array[Node]=[]
	var scene:=get_parent().get_parent()
	for key in ["ambient_people","ambient_animals"]:
		for actor in scene.get(key): excluded.append(actor.root)
	for entry in smoke: excluded.append(entry.node)
	static_merge_report=RenderOpt.merge_static_subtree(hamlet,excluded)
	static_merge_report["before"]=before
	static_merge_report["after"]=RenderOpt.inventory(hamlet)
	_prepare_spatial_batches()

func _prepare_spatial_batches() -> void:
	if not spatial_batches.is_empty(): return
	for child in get_children():
		if not child is MultiMeshInstance3D: continue
		var label:=str(child.name)
		if not (label in ["BranchingTreeTrunks","IndividualLeafCanopies","WindAnimatedMeadow","FernUndergrowth","BiomeCactusGroves","BiomeAutumnLeafLitter","BiomeEmberFissures"] or label.begins_with("ScannedRockClusters") or label.begins_with("BiomeSnowRockCaps")): continue
		var chunks:=RenderOpt.build_spatial_chunks(child)
		if chunks.is_empty(): continue
		child.set_meta("render_representation","far_batch")
		spatial_batches.append({"source":child,"chunks":chunks})

func _set_near_chunks_active(near: bool) -> void:
	near=RenderOpt.use_near_chunks(near)
	if near==near_chunks_active: return
	near_chunks_active=near
	for batch in spatial_batches:
		# Keep the source Node visible so its children inherit ordinary visibility;
		# zero its draw instances instead of hiding both representations together.
		batch.source.multimesh.visible_instance_count=0 if near else -1
		for chunk in batch.chunks: chunk.visible=near

func _update_spatial_representation() -> void:
	var camera:=get_viewport().get_camera_3d()
	if camera!=null and camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		_set_near_chunks_active(camera.size<NEAR_CHUNK_CAMERA_SIZE)

func reserve_settlement(lots: Array) -> void:
	# Remove only vegetation/boulders physically replaced by the hamlet. The
	# road/cave geometry and all unrelated buildable grass remain untouched.
	var removed_positions: Dictionary = {}
	for child in get_children():
		if not (child is MultiMeshInstance3D): continue
		if not (str(child.name).begins_with("ScannedRockClusters") or str(child.name).begins_with("BiomeSnowRockCaps") or str(child.name) in ["BranchingTreeTrunks","IndividualLeafCanopies","FernUndergrowth","WindAnimatedMeadow","BiomeCactusGroves","BiomeAutumnLeafLitter","BiomeEmberFissures"]): continue
		var stored: Array = child.get_meta("instance_transforms",[])
		for i in range(child.multimesh.instance_count):
			var transform: Transform3D=stored[i] if i<stored.size() else child.multimesh.get_instance_transform(i)
			var p:=Vector2(transform.origin.x,transform.origin.z)
			var physical_radius := maxf(transform.basis.x.length(),transform.basis.z.length())
			if str(child.name) in ["BranchingTreeTrunks","IndividualLeafCanopies"]: physical_radius*=1.8
			elif str(child.name)=="WindAnimatedMeadow": physical_radius*=0.18
			for lot in lots:
				if p.distance_to(lot.position)<float(lot.radius)+physical_radius:
					transform.origin.y=-1000.0
					child.multimesh.set_instance_transform(i,transform)
					if i<stored.size(): stored[i]=transform
					removed_positions[p]=true
					break
		child.set_meta("instance_transforms",stored)
	for i in range(obstacles.size()-1,-1,-1):
		if removed_positions.has(obstacles[i].position): obstacles.remove_at(i)

func _build_well(parent: Node3D, origin: Vector3) -> void:
	var well:=Node3D.new()
	well.name="StoneWellAndBucket"
	well.position=origin
	parent.add_child(well)
	for row in range(3):
		for i in range(12):
			var theta:=TAU*(float(i)+float(row%2)*0.5)/12.0
			_box(well,Vector3(cos(theta)*0.48,float(row)*0.16+0.04,sin(theta)*0.48),Vector3(0.28,0.15,0.19),rock_material,Vector3(0,-theta,0))
	for side in [-1.0,1.0]: _box(well,Vector3(side*0.68,0.95,0),Vector3(0.12,2.0,0.14),wood_material)
	_box(well,Vector3(0,1.86,0),Vector3(1.6,0.16,0.18),wood_material)
	_box(well,Vector3(0.0,1.26,0),Vector3(0.015,1.1,0.015),wood_material)
	_box(well,Vector3(0,0.63,0),Vector3(0.23,0.25,0.22),wood_material)

func _build_workyard(parent: Node3D) -> void:
	# Cart, chopped firewood, drying herbs and a hay rack support villagers' daily chores.
	var cart:=Node3D.new()
	cart.name="FarmCart"
	cart.position=Vector3(3.0,0.12,3.7)
	cart.rotation.y=0.34
	parent.add_child(cart)
	_box(cart,Vector3(0,0.37,0),Vector3(1.15,0.12,0.85),wood_material)
	for side in [-1.0,1.0]:
		_box(cart,Vector3(side*0.55,0.63,0),Vector3(0.07,0.47,0.9),wood_material)
		_box(cart,Vector3(side*0.31,0.29,-1.0),Vector3(0.055,0.06,1.4),wood_material)
		var wheel:=MeshInstance3D.new()
		var torus:=TorusMesh.new()
		torus.inner_radius=0.22;torus.outer_radius=0.28;torus.rings=12;torus.ring_segments=16
		wheel.mesh=torus
		wheel.rotation.z=PI*0.5
		wheel.material_override=wood_material
		wheel.position=Vector3(side*0.67,0.29,0)
		cart.add_child(wheel)
		for angle in range(4):
			_box(wheel,Vector3.ZERO,Vector3(0.48,0.035,0.035),wood_material,Vector3(0,float(angle)*PI/4.0,0))
	for i in range(8):
		var log_mesh:=CylinderMesh.new()
		log_mesh.top_radius=0.09;log_mesh.bottom_radius=0.10;log_mesh.height=0.82;log_mesh.radial_segments=10
		var log_node:=MeshInstance3D.new()
		log_node.mesh=log_mesh
		log_node.material_override=wood_material
		log_node.position=Vector3(-5.7+float(i%4)*0.20,0.11+float(i/4)*0.18,1.2)
		log_node.rotation.x=PI*0.5
		parent.add_child(log_node)
	var straw:=StandardMaterial3D.new()
	straw.albedo_color=Color(0.58,0.46,0.21)
	straw.roughness=1.0
	for i in range(3):
		var pile:=MeshInstance3D.new()
		pile.mesh=mesh_cache[0]
		pile.material_override=straw
		pile.position=Vector3(6.3+float(i)*0.43,0.24,-2.0)
		pile.scale=Vector3(0.36,0.41,0.48)
		parent.add_child(pile)

func _make_smoke(parent: Node3D, origin: Vector3, steam: bool=false) -> void:
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(0.72,0.77,0.73,0.13) if steam else Color(0.48,0.47,0.43,0.14)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(5):
		var puff:=MeshInstance3D.new()
		puff.name="GeothermalSteam" if steam else "ChimneySmoke"
		puff.set_meta("render_opt_dynamic",true)
		var mesh:=SphereMesh.new()
		mesh.radius=0.13;mesh.height=0.26;mesh.radial_segments=8;mesh.rings=4
		puff.mesh=mesh;puff.material_override=material
		puff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(puff)
		smoke.append({"node":puff,"origin":origin,"phase":float(i)*0.8,"steam":steam})
		if steam: steam_sources.append({"node":puff,"origin":origin})

func _process(delta: float) -> void:
	_update_spatial_representation()
	clock+=delta
	for entry in smoke:
		var t:=fmod(clock*0.30+float(entry.phase),4.0)
		entry.node.position=entry.origin+Vector3(sin(t*1.1)*0.12+t*0.08,t*(0.48 if entry.steam else 0.37),cos(t)*0.08)
		entry.node.scale=Vector3.ONE*(0.7+t*0.46 if entry.steam else 0.5+t*0.31)
