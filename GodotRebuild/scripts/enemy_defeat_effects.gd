extends Node3D
## Presentation only. Rewards, targeting and wave completion remain in game.gd.
## Shared opaque dissolve materials and a bounded pool of instanced fragments.
const MAX_CORPSES := 48
const MAX_BURSTS := 24
const MAX_FREE_BURSTS := 8
const PARTICLES := 24
const COLORS := [Color(0.13,0.025,0.07),Color(0.67,0.91,1.0),Color(1.0,0.27,0.035),Color(0.95,0.19,0.47),Color(0.40,0.74,0.91),Color(0.94,0.90,0.73),Color(0.43,0.39,0.32),Color(0.56,0.86,1.0)]
const DISSOLVE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_tex : filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_tex : filter_linear_mipmap_anisotropic;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
uniform bool has_metallic = false;
uniform float base_roughness = 0.85;
uniform float base_metallic = 0.0;
uniform float normal_depth = 1.0;
uniform vec4 roughness_channel = vec4(0.0,1.0,0.0,0.0);
uniform vec4 metallic_channel = vec4(0.0,0.0,1.0,0.0);
instance uniform float defeat_fade = 0.0;
instance uniform float defeat_scorch = 0.0;
instance uniform float defeat_style = 6.0;
instance uniform float defeat_seed = 0.0;
varying vec3 surface_point;
float hash3(vec3 p) { return fract(sin(dot(p,vec3(12.9898,78.233,37.719)))*43758.5453); }
void vertex() { surface_point = VERTEX; }
void fragment() {
    float cell_scale = (defeat_style < 0.5 || (defeat_style > 1.5 && defeat_style < 2.5)) ? 7.0 : 26.0;
    vec3 cell = floor(surface_point*cell_scale+vec3(defeat_seed));
    float noise = hash3(cell)*0.88+hash3(floor(surface_point*47.0))*0.12;
    if (defeat_fade > noise) { discard; }
    vec4 paint = base_color;
    if (has_albedo) { paint *= texture(albedo_tex,UV); }
    ALBEDO = paint.rgb;
    ROUGHNESS = base_roughness;
    METALLIC = base_metallic;
    if (has_roughness) { ROUGHNESS *= dot(texture(roughness_tex,UV),roughness_channel); }
    if (has_metallic) { METALLIC *= dot(texture(metallic_tex,UV),metallic_channel); }
    if (has_normal) { NORMAL_MAP = texture(normal_tex,UV).rgb; NORMAL_MAP_DEPTH = normal_depth; }
    float edge = (1.0-smoothstep(0.0,0.085,noise-defeat_fade))*step(0.005,defeat_fade);
    if (defeat_style > 1.5 && defeat_style < 2.5) {
        ALBEDO = mix(ALBEDO,vec3(0.035,0.019,0.010),defeat_scorch*0.94);
        EMISSION = vec3(1.0,0.17,0.012)*edge*2.1;
        ROUGHNESS = mix(ROUGHNESS,1.0,defeat_scorch);
    } else if (defeat_style < 0.5) {
        ALBEDO *= 1.0-defeat_scorch*0.65;
        EMISSION = vec3(0.50,0.012,0.06)*edge*0.9;
    } else if (defeat_style > 6.5) {
        ALBEDO = mix(ALBEDO,vec3(0.47,0.73,0.85),defeat_scorch*0.35);
        EMISSION = vec3(0.31,0.62,0.8)*edge*0.6;
    }
}
"""
var shader: Shader
var material_cache: Dictionary = {}
var free_bursts: Array[MultiMeshInstance3D] = []
var particle_material: StandardMaterial3D
var particle_mesh: ArrayMesh
var active_bursts := 0
var serial := 0

func begin(actor: Node3D, model: Node3D, height: float, cause: Dictionary, clip_length: float, render_enabled: bool = true) -> Dictionary:
	serial += 1
	var kind := clampi(int(cause.get("kind",6)),0,6) if int(cause.get("kind",-1)) >= 0 else 6
	if kind == 4 and bool(cause.get("freeze",false)): kind = 7
	var length := maxf(0.35,clip_length)
	var fade_start := length+0.20
	var duration := fade_start+0.50
	if kind == 0:
		fade_start = length*0.50
		duration = length+0.35
	elif kind == 2:
		fade_start = length*0.75
		duration = length+0.80
	var direction: Vector3 = cause.get("direction",Vector3.ZERO)
	direction.y = 0.0
	if direction.length_squared() < 0.0001: direction = -actor.global_basis.z
	direction = direction.normalized()
	var entry := {"node":actor,"age":0.0,"time_left":duration,"duration":duration,"clip_length":length,"fade_start":fade_start,
		"style":kind,"cause_kind":int(cause.get("kind",-1)),"direction":direction,"origin":actor.global_position,
		"height":maxf(0.5,height),"meshes":[],"burst":null,"skeleton":null,"anchors":[],"seed":serial%997,
		"boss":bool(cause.get("boss",false))}
	if render_enabled and is_instance_valid(model):
		for node in model.find_children("*","MeshInstance3D",true,false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null or mesh.mesh.get_surface_count() == 0: continue
			var source := mesh.get_active_material(0)
			if not source is BaseMaterial3D: continue
			mesh.material_override = _dissolve_material(source)
			mesh.set_instance_shader_parameter("defeat_style",float(kind))
			mesh.set_instance_shader_parameter("defeat_seed",float(entry.seed))
			entry.meshes.append(mesh)
		var skeletons := model.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty():
			entry.skeleton = skeletons[0]
			entry.anchors = _anchor_bones(entry.skeleton)
		if not entry.meshes.is_empty() and active_bursts < MAX_BURSTS:
			entry.burst = _acquire_burst()
			var radius := maxf(1.5,height*1.5)
			entry.burst.custom_aabb = AABB(actor.global_position-Vector3(radius,0.3,radius),Vector3(radius*2.0,height+1.8,radius*2.0))
		_update(entry)
	return entry

func advance(entry: Dictionary, dt: float) -> void:
	entry.age = minf(float(entry.duration),float(entry.age)+maxf(0.0,dt))
	entry.time_left = maxf(0.0,float(entry.duration)-float(entry.age))
	_update(entry)

func release(entry: Dictionary) -> void:
	var burst := entry.get("burst") as MultiMeshInstance3D
	if is_instance_valid(burst):
		burst.visible = false
		active_bursts = maxi(0,active_bursts-1)
		if free_bursts.size() < MAX_FREE_BURSTS: free_bursts.append(burst)
		else: burst.queue_free()
	entry.burst = null
	entry.meshes.clear()
	entry.skeleton = null
	entry.anchors.clear()

func debug_counts() -> Dictionary:
	return {"active_bursts":active_bursts,"pooled_bursts":free_bursts.size(),"material_cache":material_cache.size(),"max_bursts":MAX_BURSTS,"max_corpses":MAX_CORPSES}

func _update(entry: Dictionary) -> void:
	if not is_instance_valid(entry.node): return
	var age: float = entry.age
	var style: int = entry.style
	var fade := smoothstep(float(entry.fade_start),float(entry.duration),age)
	var scorch := smoothstep(0.08,float(entry.clip_length)*0.85,age)
	for mesh in entry.meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter("defeat_fade",fade)
			mesh.set_instance_shader_parameter("defeat_scorch",scorch)
	# The skeleton performs the collapse. Only wind adds an external impulse;
	# no rigid whole-character pitch or shrinking replaces articulated motion.
	if style == 1:
		var t := clampf(age/0.70,0.0,1.0)
		var distance := minf(1.15,float(entry.height)*0.43)*(0.35 if entry.boss else 1.0)
		entry.node.global_position = entry.origin+entry.direction*distance*(1.0-pow(1.0-t,3.0))+Vector3.UP*(sin(t*PI)*minf(0.16,float(entry.height)*0.06))
	var burst := entry.get("burst") as MultiMeshInstance3D
	if not is_instance_valid(burst): return
	var multi := burst.multimesh
	var color: Color = COLORS[style]
	var anchor_positions: Array[Vector3] = []
	var skeleton := entry.get("skeleton") as Skeleton3D
	if is_instance_valid(skeleton):
		for bone in entry.anchors: anchor_positions.append(skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))
	if anchor_positions.is_empty(): anchor_positions.append(entry.node.global_position+Vector3.UP*float(entry.height)*lerpf(0.45,0.12,scorch))
	for i in range(PARTICLES):
		var seed := float(i)*2.399963+float(entry.seed)*0.13
		var cycle := fposmod(age*(1.5 if style == 2 else 1.0)+float(i)/PARTICLES,1.0)
		var offset := Vector3(cos(seed),0,sin(seed))*float(entry.height)*0.09
		var position: Vector3 = anchor_positions[i%anchor_positions.size()]+offset
		var size := minf(0.075,float(entry.height)*0.025)*(0.40+sin(cycle*PI)*0.60)*(1.0-fade)
		var shape := Vector3.ONE
		var emit_start := float(entry.clip_length)*0.55 if style == 6 or style == 7 else float(entry.fade_start)*0.70 if style == 0 else 0.0
		if age < emit_start: size = 0.0
		match style:
			2:
				if i%3 == 0:
					position += Vector3(sin(seed+age*2.0)*0.06,0.05,cos(seed-age)*0.06)
					shape = Vector3(0.70,5.2,0.70)
					size *= 1.4
				else:
					position += Vector3(sin(seed+age*2.0)*0.10,cycle*0.85,cos(seed-age)*0.10)
					shape = Vector3(0.35,0.6,0.35)
				color = Color(1.0,lerpf(0.58,0.10,cycle),0.02)
			1:
				position += entry.direction*cycle*0.9+Vector3(sin(seed+cycle*TAU)*0.22,sin(cycle*PI)*0.22,cos(seed+cycle*TAU)*0.22)
				shape = Vector3(0.30,0.30,2.4)
			0:
				position += Vector3(cos(seed)*cycle*0.40,-cycle*cycle*0.35,sin(seed)*cycle*0.40)
				shape = Vector3(0.8,1.6,0.45)
			4:
				position += Vector3(cos(seed)*cycle*0.30,-cycle*0.45,sin(seed)*cycle*0.30)
				shape = Vector3(0.45,0.85,0.45)
			7:
				position += Vector3(cos(seed)*cycle*0.36,-cycle*cycle*0.45,sin(seed)*cycle*0.36)
				shape = Vector3(0.40,1.7,0.60)
			_:
				position += Vector3(cos(seed)*cycle*0.25,sin(cycle*PI)*0.18,sin(seed)*cycle*0.25)
		position.y = maxf(position.y,float(entry.origin.y)+0.015)
		var basis := Basis.from_euler(Vector3(seed+age,seed*0.37,age+seed*0.6)).scaled(shape*size)
		if style == 2 and i%3 == 0:
			basis = Basis(Vector3.UP,seed).scaled(shape*size)
		multi.set_instance_transform(i,Transform3D(basis,position))
		multi.set_instance_color(i,color*(1.0-cycle*0.45))

func _anchor_bones(skeleton: Skeleton3D) -> Array[int]:
	var result: Array[int] = []
	for token in ["hips","pelvis","spine","spine02","chest","head"]:
		for i in range(skeleton.get_bone_count()):
			if skeleton.get_bone_name(i).to_lower().split(".")[0] == token:
				result.append(i)
				break
	return result

func _dissolve_material(source: BaseMaterial3D) -> ShaderMaterial:
	var key := source.get_instance_id()
	if material_cache.has(key): return material_cache[key]
	if shader == null:
		shader = Shader.new()
		shader.code = DISSOLVE_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color",source.albedo_color)
	material.set_shader_parameter("base_roughness",source.roughness)
	material.set_shader_parameter("base_metallic",source.metallic)
	material.set_shader_parameter("normal_depth",source.normal_scale)
	for pair in [["albedo",BaseMaterial3D.TEXTURE_ALBEDO],["normal",BaseMaterial3D.TEXTURE_NORMAL],["roughness",BaseMaterial3D.TEXTURE_ROUGHNESS],["metallic",BaseMaterial3D.TEXTURE_METALLIC]]:
		var texture := source.get_texture(pair[1])
		material.set_shader_parameter("has_"+pair[0],texture != null)
		if texture != null: material.set_shader_parameter(pair[0]+"_tex",texture)
	material.set_shader_parameter("roughness_channel",_channel(source.roughness_texture_channel))
	material.set_shader_parameter("metallic_channel",_channel(source.metallic_texture_channel))
	if material_cache.size() >= 32: material_cache.erase(material_cache.keys()[0])
	material_cache[key] = material
	return material

func _channel(index: int) -> Vector4:
	match index:
		BaseMaterial3D.TEXTURE_CHANNEL_RED: return Vector4(1,0,0,0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0,0,1,0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0,0,0,1)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(0.333333,0.333333,0.333333,0)
		_: return Vector4(0,1,0,0)

func _acquire_burst() -> MultiMeshInstance3D:
	active_bursts += 1
	if not free_bursts.is_empty():
		var existing: MultiMeshInstance3D = free_bursts.pop_back()
		existing.visible = true
		return existing
	if particle_mesh == null:
		particle_mesh = ArrayMesh.new()
		var points := PackedVector3Array([Vector3(0,0.8,0),Vector3(-0.6,-0.4,0.4),Vector3(0.6,-0.4,0.4),Vector3(0,-0.4,-0.7)])
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,0,3,2,0,1,3,1,2,3])
		particle_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		particle_material = StandardMaterial3D.new()
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = particle_mesh
	multi.instance_count = PARTICLES
	var node := MultiMeshInstance3D.new()
	node.name = "DefeatFragments"
	node.multimesh = multi
	node.material_override = particle_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.global_transform = Transform3D.IDENTITY
	return node
