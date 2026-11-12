extends SceneTree
## Offline compaction of imported index LODs into actual lower-vertex skinned
## meshes. Original GLBs, skeletons, weights, UVs and materials are not edited.
const OUTPUT_ROOT:="res://Assets/CharacterLOD/"
const TARGET_TRIANGLE_RATIO:=0.35
const TARGET_VERTEX_RATIO:=0.54
const MIN_NATIVE_TRIANGLE_RATIO:=0.10
var output_root:=OUTPUT_ROOT
var report: Array[Dictionary]=[]
func _initialize() -> void:call_deferred("_run")
func _find(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.skin!=null:return node
	for child in node.get_children():
		var found:=_find(child)
		if found!=null:return found
	return null
func _unique_count(indices: PackedInt32Array) -> int:
	var used: Dictionary={}
	for index in indices:used[index]=true
	return used.size()
func _decode_indices(bytes: PackedByteArray,stride: int) -> PackedInt32Array:
	var result:=PackedInt32Array()
	result.resize(bytes.size()/stride)
	for index in range(result.size()):result[index]=bytes.decode_u16(index*stride) if stride==2 else bytes.decode_u32(index*stride)
	return result
func _lod_indices(surface: Dictionary) -> PackedInt32Array:
	var raw: Array=surface.get("lods",[])
	var selected:=PackedInt32Array()
	var vertex_count:=int(surface.vertex_count)
	var stride:=2 if vertex_count<=65536 else 4
	var base_count:=int(surface.index_count)
	# LODs are ordered from detailed to coarse. Choose the least simplified
	# available level below the budget, retaining small silhouettes when possible.
	for i in range(0,raw.size(),2):
		var bytes: PackedByteArray=raw[i+1]
		var count:=bytes.size()/stride
		if count<=float(base_count)*TARGET_TRIANGLE_RATIO:
			var candidate:=_decode_indices(bytes,stride)
			if selected.is_empty():selected=candidate
			# Index reduction alone does not bound GPU skinning work. Closed,
			# seam-heavy garments can retain too many distinct vertices.
			if _unique_count(candidate)<vertex_count*TARGET_VERTEX_RATIO:return candidate
	return selected
func _fallback_indices(path: String,source: Array,old_count: int,skin: Skin,head_extrema: bool=false) -> Dictionary:
	var folder:="res://Builds/character-lod-work/"
	DirAccess.make_dir_recursive_absolute(folder)
	var stem:=path.trim_prefix("res://Assets/").get_basename().replace("/","_")
	var input_path:=folder+stem+"-input.json"
	var result_path:=folder+stem+"-output.json"
	var protected_bones:=PackedInt32Array()
	var silhouette_bones:=PackedInt32Array()
	for bind in range(skin.get_bind_count()):
		var name:=str(skin.get_bind_name(bind))
		if name in ["head","jaw"]:
			if head_extrema:silhouette_bones.append(bind)
			else:protected_bones.append(bind)
		if name in ["hand.L","hand.R"] or name.begins_with("finger"):protected_bones.append(bind)
	# Start from the full source, not the already-pruned imported LOD: deleted
	# hood/weapon silhouette cannot be recovered by simplifying that LOD again.
	# Head, hands and attached equipment remain locked; triangle count is a soft
	# target, while the compact vertex budget and quality error are hard bounds.
	var input: Dictionary={"source_vertices":old_count,"source_sha256":FileAccess.get_sha256(path),"positions":Marshalls.raw_to_base64(source[Mesh.ARRAY_VERTEX].to_byte_array()),"normals":Marshalls.raw_to_base64(source[Mesh.ARRAY_NORMAL].to_byte_array()),"uv":Marshalls.raw_to_base64(source[Mesh.ARRAY_TEX_UV].to_byte_array()),"bones":Marshalls.raw_to_base64(source[Mesh.ARRAY_BONES].to_byte_array()),"weights":Marshalls.raw_to_base64(source[Mesh.ARRAY_WEIGHTS].to_byte_array()),"indices":Marshalls.raw_to_base64(source[Mesh.ARRAY_INDEX].to_byte_array()),"protected_bones":protected_bones,"target_ratios":[.35,.30,.25,.20],"max_error":.01}
	if head_extrema:input["silhouette_bones"]=silhouette_bones;input["silhouette_bands"]=64
	var file:=FileAccess.open(input_path,FileAccess.WRITE)
	assert(file!=null,"Cannot write offline LOD input")
	file.store_string(JSON.stringify(input));file.close()
	var node:=OS.get_environment("KDTD_NODE")
	if node.is_empty():node="node"
	var output: Array=[]
	var status:=OS.execute(node,PackedStringArray([ProjectSettings.globalize_path("res://tools/compact_lod_fallback.mjs"),ProjectSettings.globalize_path(input_path),ProjectSettings.globalize_path(result_path)]),output,true)
	assert(status==0,"Offline attribute-aware LOD failed: "+str(output))
	var generated: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(result_path))
	assert(str(generated.get("source_sha256",""))==FileAccess.get_sha256(path),"LOD worker used a different source")
	var regenerated:=_decode_indices(Marshalls.base64_to_raw(str(generated.indices)),4)
	assert(regenerated.size()%3==0 and _unique_count(regenerated)<old_count*TARGET_VERTEX_RATIO,"Offline LOD did not meet the compact vertex budget")
	for index in regenerated:assert(index>=0 and index<old_count,"Offline LOD referenced an invalid source vertex")
	return {"indices":regenerated,"report":generated.selected,"locked_vertices":generated.locked_vertices,"semantic_locked_vertices":generated.semantic_locked_vertices,"silhouette_locked_vertices":generated.get("silhouette_locked_vertices",0)}
func _compact_channel(source: Variant,old_count: int,used: PackedInt32Array) -> Variant:
	if source==null:return null
	if source.size()==0:return source
	var stride: int=source.size()/old_count
	assert(stride>=1 and source.size()%old_count==0,"Invalid per-vertex channel stride")
	var compacted: Variant=source.slice(0,0)
	compacted.resize(used.size()*stride)
	for new_index in range(used.size()):
		var old_index:=used[new_index]
		for part in range(stride):compacted[new_index*stride+part]=source[old_index*stride+part]
	return compacted
func _build(path: String) -> void:
	var packed:=load(path) as PackedScene
	assert(packed!=null,"Cannot load high character: "+path)
	var model:=packed.instantiate()
	var instance:=_find(model)
	assert(instance!=null,"Missing skinned mesh: "+path)
	var high:=instance.mesh as ArrayMesh
	assert(high!=null and high.get_surface_count()==1,"Expected one atlased surface: "+path)
	var serialized: Array=high.get("_surfaces")
	var indices:=_lod_indices(serialized[0])
	assert(not indices.is_empty(),"No suitable imported index LOD: "+path)
	var source:=high.surface_get_arrays(0)
	var old_count:=high.surface_get_array_len(0)
	var fallback: Dictionary={}
	# An importer prune jump can fit the vertex budget by deleting most of a
	# hero's details. Rebuild a quality-bounded middle LOD instead of accepting
	# a <10% triangle level as the only far mesh. Dense hair protects head
	# silhouette extrema rather than locking every interior strand vertex.
	var prune_gap:=float(indices.size())/high.surface_get_array_index_len(0)<MIN_NATIVE_TRIANGLE_RATIO
	if _unique_count(indices)>=old_count*TARGET_VERTEX_RATIO or prune_gap:
		fallback=_fallback_indices(path,source,old_count,instance.skin,prune_gap)
		indices=fallback.indices
	var used:=PackedInt32Array()
	var remap: Dictionary={}
	for old_index in indices:
		if not remap.has(old_index):remap[old_index]=used.size();used.append(old_index)
	var compacted: Array=[]
	compacted.resize(Mesh.ARRAY_MAX)
	for channel in range(Mesh.ARRAY_MAX):
		if channel==Mesh.ARRAY_INDEX:continue
		compacted[channel]=_compact_channel(source[channel],old_count,used)
	var new_indices:=PackedInt32Array()
	new_indices.resize(indices.size())
	for index in range(indices.size()):new_indices[index]=int(remap[indices[index]])
	compacted[Mesh.ARRAY_INDEX]=new_indices
	var low:=ArrayMesh.new()
	low.resource_name=high.resource_name+"_CompactedLOD"
	# Keep all remaining coarser index levels on the compacted vertex buffer.
	# The simplifier is iterative, so their vertices normally form subsets of
	# this selected level. Never invent a nearest-position remap if they do not.
	var low_lods: Dictionary={}
	var raw_lods: Array=serialized[0].get("lods",[])
	var index_stride:=2 if old_count<=65536 else 4
	for lod_index in range(0,raw_lods.size(),2):
		var bytes: PackedByteArray=raw_lods[lod_index+1]
		var count:=bytes.size()/index_stride
		if count>=indices.size():continue
		var coarse:=PackedInt32Array()
		coarse.resize(count)
		var subset:=true
		for i in range(count):
			var old_index:=bytes.decode_u16(i*index_stride) if index_stride==2 else bytes.decode_u32(i*index_stride)
			if not remap.has(old_index):subset=false;break
			coarse[i]=int(remap[old_index])
		if subset:low_lods[float(raw_lods[lod_index])]=coarse
	low.add_surface_from_arrays(high.surface_get_primitive_type(0),compacted,[],low_lods,high.surface_get_format(0))
	# Material stays null in the file. The runtime assigns the SAME source
	# material resource, avoiding a second atlas/texture/material allocation.
	var skin:=instance.skin
	var bind_indices: Array[int]=[]
	var bind_names: Array[String]=[]
	for bind in range(skin.get_bind_count()):bind_indices.append(skin.get_bind_bone(bind));bind_names.append(str(skin.get_bind_name(bind)))
	low.set_meta("source_path",path)
	low.set_meta("source_sha256",FileAccess.get_sha256(path))
	low.set_meta("source_vertices",old_count)
	low.set_meta("source_indices",high.surface_get_array_index_len(0))
	low.set_meta("source_skin_bind_count",skin.get_bind_count())
	low.set_meta("source_bind_bones",bind_indices)
	low.set_meta("source_bind_names",bind_names)
	low.set_meta("source_vertex_indices",used)
	low.set_meta("pipeline","compacted-import-lod-v1")
	if not fallback.is_empty():low.set_meta("index_simplifier","meshoptimizer-index-only-attrib-v1");low.set_meta("simplifier_error",fallback.report.error)
	var output:=output_root+path.trim_prefix("res://Assets/").get_basename()+".res"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	assert(ResourceSaver.save(low,output,ResourceSaver.FLAG_COMPRESS)==OK,"Cannot save low mesh: "+output)
	var row: Dictionary={"source":path,"low":output,"high_vertices":old_count,"low_vertices":used.size(),"high_triangles":high.surface_get_array_index_len(0)/3,"low_triangles":indices.size()/3,"coarser_index_lods":low_lods.size(),"vertex_ratio":float(used.size())/old_count,"bind_count":skin.get_bind_count(),"source_sha256":FileAccess.get_sha256(path)}
	if not fallback.is_empty():row["index_simplifier"]="meshoptimizer-index-only-attrib-v1";row["simplifier_reason"]="native_prune_gap" if prune_gap else "vertex_budget";row["simplifier_error"]=fallback.report.error;row["skin_locked_vertices"]=fallback.locked_vertices;row["semantic_locked_vertices"]=fallback.semantic_locked_vertices;row["silhouette_locked_vertices"]=fallback.silhouette_locked_vertices
	report.append(row)
	print("CHARACTER_LOD_BUILT: "+JSON.stringify(row))
	model.free()
func _run() -> void:
	var override_root:=OS.get_environment("KDTD_LOD_OUTPUT_ROOT")
	if not override_root.is_empty():output_root=override_root if override_root.ends_with("/") else override_root+"/"
	var only:=OS.get_environment("KDTD_LOD_ONLY")
	var paths: Array[String]=[]
	for kind in ["goblin","orc","uruk","troll","nazgul","warg","boss_troll"]:paths.append("res://Assets/Enemies/"+kind+".glb")
	for hero in ["asta","yuno","magna","vanessa","noelle","charmy"]:
		for level in range(1,6):paths.append("res://Assets/Heroes/%s_L%d.glb"%[hero,level])
	for path in paths:
		if only.is_empty() or only==path:_build(path)
	var manifest:=FileAccess.open(output_root+"manifest.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema":1,"pipeline":"compacted-import-lod-v1","models":report},"\t"));manifest.close()
	print("CHARACTER_LODS_BUILT_OK: "+str(report.size())+" lower-vertex meshes; original geometry unchanged")
	await process_frame
	await create_timer(.2).timeout
	call_deferred("quit",0)
