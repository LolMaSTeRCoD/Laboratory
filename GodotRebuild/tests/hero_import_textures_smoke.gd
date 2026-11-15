extends SceneTree
## Verify that Godot uses the current GLB atlas, not an older extracted PNG.

func _initialize() -> void:
	call_deferred("_run")

func _mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:return node
	for child in node.get_children():
		var found:=_mesh(child)
		if found!=null:return found
	return null

func _run() -> void:
	for hero in ["asta","yuno","magna","vanessa","noelle","charmy"]:
		for rank in range(1,6):
			var path: String="res://Assets/Heroes/%s_L%d.glb"%[hero,rank]
			var bytes:=FileAccess.get_file_as_bytes(path)
			var json_length:=bytes.decode_u32(12)
			var doc: Dictionary=JSON.parse_string(bytes.slice(20,20+json_length).get_string_from_utf8())
			var texture_index: int=doc.materials[0].pbrMetallicRoughness.baseColorTexture.index
			var image_index: int=doc.textures[texture_index].source
			var view: Dictionary=doc.bufferViews[doc.images[image_index].bufferView]
			var start: int=28+json_length+int(view.get("byteOffset",0))
			var expected:=Image.new()
			if expected.load_png_from_buffer(bytes.slice(start,start+int(view.byteLength)))!=OK:
				_fail("cannot decode embedded atlas: "+path);return
			var packed:=load(path) as PackedScene
			var model:=packed.instantiate()
			var mesh:=_mesh(model)
			var material:=mesh.mesh.surface_get_material(0) as StandardMaterial3D
			if material==null or material.albedo_texture==null:
				model.free();_fail("missing imported albedo: "+path);return
			var actual:=Image.new()
			var texture_path:=material.albedo_texture.resource_path
			if actual.load_png_from_buffer(FileAccess.get_file_as_bytes(texture_path))!=OK:
				model.free();_fail("cannot read extracted atlas: "+texture_path);return
			expected.convert(Image.FORMAT_RGBA8);actual.convert(Image.FORMAT_RGBA8)
			var matches:=expected.get_size()==actual.get_size() and expected.get_data()==actual.get_data()
			model.free()
			if not matches:
				_fail("stale or mismatched imported atlas: "+path+" -> "+texture_path);return
	print("HERO_TEXTURE_IMPORT_SMOKE_OK: all 30 imported character atlases match their GLB pixels")
	quit(0)

func _fail(message: String) -> void:
	push_error("HERO_TEXTURE_IMPORT_SMOKE_FAIL: "+message)
	quit(1)
