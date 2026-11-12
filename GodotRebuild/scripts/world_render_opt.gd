extends RefCounted
## Exact geometry batching and camera-near spatial subdivision. No simplification,
## texture replacement, shadow removal or gameplay/placement state is involved.

const RENDER_PROPERTIES := ["layers","cast_shadow","gi_mode","transparency","lod_bias",
	"ignore_occlusion_culling","extra_cull_margin","visibility_range_begin","visibility_range_end",
	"visibility_range_begin_margin","visibility_range_end_margin","visibility_range_fade_mode",
	"gi_lightmap_scale","gi_lightmap_texel_scale"]
static var spatial_chunks_enabled: bool=not OS.get_cmdline_user_args().has("--disable-spatial-chunks")

static func use_near_chunks(near_requested: bool) -> bool:
	# Opt-in diagnostic A/B: identical authored geometry, materials and chunk
	# preparation, with only the active representation changed. Default is on.
	return near_requested and spatial_chunks_enabled

static func _render_state(node: GeometryInstance3D) -> Array:
	var state: Array=[]
	for property in RENDER_PROPERTIES: state.append(node.get(property))
	return state

static func _copy_render_state(source: GeometryInstance3D, target: GeometryInstance3D) -> void:
	for property in RENDER_PROPERTIES: target.set(property,source.get(property))

static func _gather_static(node: Node, excluded: Array[Node], output: Array[MeshInstance3D]) -> void:
	if node in excluded or node.get_meta("render_opt_dynamic",false): return
	if node is MeshInstance3D and node.mesh!=null and node.skin==null and node.material_overlay==null and node.visible:
		var valid: bool=node.mesh.get_surface_count()==1 and (node.mesh is PrimitiveMesh or node.mesh is ArrayMesh)
		for surface in range(node.mesh.get_surface_count()):
			if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: valid=false
		if valid: output.append(node)
	for child in node.get_children(): _gather_static(child,excluded,output)

static func _append_exact(st: SurfaceTool, mesh: Mesh, surface: int, transform: Transform3D) -> void:
	var arrays:=mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
	var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
	var uv2: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var normal_basis:=transform.basis.inverse().transposed()
	var count:=indices.size() if not indices.is_empty() else vertices.size()
	for corner in range(count):
		var source_corner:=corner
		if transform.basis.determinant()<0.0:
			# Reflection changes the original instance's cull orientation. Bake it
			# into the winding while preserving the original world-space triangle.
			if corner%3==1: source_corner=corner+1
			elif corner%3==2: source_corner=corner-1
		var i:=indices[source_corner] if not indices.is_empty() else source_corner
		st.set_normal((normal_basis*normals[i]).normalized() if i<normals.size() else Vector3.UP)
		var tangent:=Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2]) if i*4+3<tangents.size() else Vector3.RIGHT
		var handedness:=tangents[i*4+3] if i*4+3<tangents.size() else 1.0
		st.set_tangent(Plane((transform.basis*tangent).normalized(),handedness*signf(transform.basis.determinant())))
		st.set_uv(uv[i] if i<uv.size() else Vector2.ZERO)
		st.set_uv2(uv2[i] if i<uv2.size() else Vector2.ZERO)
		st.set_color(colors[i] if i<colors.size() else Color.WHITE)
		st.add_vertex(transform*vertices[i])

static func merge_static_subtree(root: Node3D, excluded: Array[Node]=[]) -> Dictionary:
	var nodes: Array[MeshInstance3D]=[]
	_gather_static(root,excluded,nodes)
	var batches: Dictionary={}
	var root_inverse:=root.global_transform.affine_inverse()
	for node in nodes:
		for surface in range(node.mesh.get_surface_count()):
			var material: Material=node.material_override
			if material==null: material=node.get_surface_override_material(surface)
			if material==null: material=node.mesh.surface_get_material(surface)
			var material_id:=material.get_instance_id() if material!=null else 0
			var key:=str(material_id)+":"+str(_render_state(node))
			if not batches.has(key): batches[key]={"nodes":[],"surfaces":[],"material":material,"source":node}
			batches[key].nodes.append(node)
			batches[key].surfaces.append(surface)
	var merged_sources: Dictionary={}
	var merged_surfaces:=0
	var output_surfaces:=0
	for batch in batches.values():
		if batch.nodes.size()<2: continue
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(batch.nodes.size()):
			var node: MeshInstance3D=batch.nodes[i]
			_append_exact(st,node.mesh,int(batch.surfaces[i]),root_inverse*node.global_transform)
			merged_sources[node.get_instance_id()]=node
		st.index()
		var combined:=MeshInstance3D.new()
		combined.name="ExactStaticGeometry"
		combined.mesh=st.commit()
		combined.material_override=batch.material
		_copy_render_state(batch.source,combined)
		combined.set_meta("exact_source_surfaces",batch.nodes.size())
		root.add_child(combined,true)
		merged_surfaces+=batch.nodes.size()
		output_surfaces+=1
	# The gather step admits complete single-surface meshes only; no unbatched
	# material surface can be lost. Keep container nodes when they own children.
	for node in merged_sources.values():
		if node.get_child_count()==0:
			node.get_parent().remove_child(node)
			node.free()
		else:
			node.mesh=null
	return {"source_surfaces":merged_surfaces,"output_surfaces":output_surfaces,"saved_surface_submissions":merged_surfaces-output_surfaces}

static func build_spatial_chunks(source: MultiMeshInstance3D, cell_size: float=12.0) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D]=[]
	var cells: Dictionary={}
	var stored: Array=source.get_meta("instance_transforms",[])
	var stored_colors: Array=source.get_meta("instance_colors",[])
	for i in range(source.multimesh.instance_count):
		var transform: Transform3D=stored[i] if i<stored.size() else source.multimesh.get_instance_transform(i)
		if transform.origin.y < -900.0: continue # Reserved settlement geometry is intentionally buried.
		var cell:=Vector2i(floori(transform.origin.x/cell_size),floori(transform.origin.z/cell_size))
		if not cells.has(cell): cells[cell]=[]
		cells[cell].append(i)
	for cell: Vector2i in cells:
		var origin:=Vector3((float(cell.x)+0.5)*cell_size,0,(float(cell.y)+0.5)*cell_size)
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.use_colors=source.multimesh.use_colors
		multi.use_custom_data=source.multimesh.use_custom_data
		multi.mesh=source.multimesh.mesh
		multi.instance_count=cells[cell].size()
		var bounds:=AABB()
		var has_bounds:=false
		var ids: Array[int]=[]
		var local_transforms: Array[Transform3D]=[]
		var local_colors: Array[Color]=[]
		for j in range(cells[cell].size()):
			var i: int=cells[cell][j]
			var transform: Transform3D=stored[i] if i<stored.size() else source.multimesh.get_instance_transform(i)
			transform.origin-=origin
			multi.set_instance_transform(j,transform)
			if multi.use_colors:
				var color: Color=stored_colors[i] if i<stored_colors.size() else source.multimesh.get_instance_color(i)
				multi.set_instance_color(j,color)
				local_colors.append(color)
			if multi.use_custom_data: multi.set_instance_custom_data(j,source.multimesh.get_instance_custom_data(i))
			var box: AABB=transform*multi.mesh.get_aabb()
			bounds=bounds.merge(box) if has_bounds else box
			has_bounds=true
			ids.append(i)
			local_transforms.append(transform)
		multi.custom_aabb=bounds.grow(0.25)
		var chunk:=MultiMeshInstance3D.new()
		chunk.name="NearSpatialChunk_%d_%d"%[cell.x,cell.y]
		chunk.position=origin
		chunk.multimesh=multi
		chunk.material_override=source.material_override
		_copy_render_state(source,chunk)
		chunk.custom_aabb=multi.custom_aabb
		chunk.set_meta("source_indices",ids)
		chunk.set_meta("instance_transforms",local_transforms)
		chunk.set_meta("instance_colors",local_colors)
		chunk.set_meta("render_representation","near_chunk")
		chunk.visible=false
		source.add_child(chunk)
		result.append(chunk)
	return result

static func triangle_count(mesh: Mesh) -> int:
	var total:=0
	for surface in range(mesh.get_surface_count()):
		var arrays:=mesh.surface_get_arrays(surface)
		var indices: Variant=arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		total+=int(indices.size()/3) if indices!=null and not indices.is_empty() else int(vertices.size()/3)
	return total

static func inventory(root: Node, active_only: bool=true) -> Dictionary:
	var result: Dictionary={"surface_submissions":0,"triangles":0,"instances":0,"mesh_nodes":0}
	if root is GeometryInstance3D and (not active_only or root.is_visible_in_tree()):
		var mesh: Mesh
		var instances:=1
		if root is MeshInstance3D: mesh=root.mesh
		elif root is MultiMeshInstance3D and root.multimesh!=null:
			mesh=root.multimesh.mesh
			instances=root.multimesh.visible_instance_count if root.multimesh.visible_instance_count>=0 else root.multimesh.instance_count
		if mesh!=null and instances>0:
			result.surface_submissions+=mesh.get_surface_count()
			result.triangles+=triangle_count(mesh)*instances
			result.instances+=instances
			result.mesh_nodes+=1
	for child in root.get_children():
		var child_count:=inventory(child,active_only)
		for key in result: result[key]+=int(child_count[key])
	return result
