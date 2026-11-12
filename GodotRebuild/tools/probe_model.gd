extends SceneTree

func _initialize() -> void:
    call_deferred("_probe")

func _probe() -> void:
    for kind in ["goblin","orc","uruk","troll","nazgul","warg"]:
        var packed := load("res://Assets/Enemies/%s.glb" % kind) as PackedScene
        if packed == null:
            printerr("PROBE_ERROR: enemy GLB was not imported as PackedScene: ", kind)
            quit(2)
            return
        var instance := packed.instantiate()
        root.add_child(instance)
        await process_frame
        var skeleton := _find_type(instance, "Skeleton3D") as Skeleton3D
        var player := _find_type(instance, "AnimationPlayer") as AnimationPlayer
        var skinned_meshes := _count_skinned_meshes(instance)
        if skeleton == null or player == null or skeleton.get_bone_count() < 15 or skinned_meshes < 1:
            printerr("PROBE_ERROR: incomplete rig for ",kind," bones=",skeleton.get_bone_count() if skeleton != null else -1," meshes=",skinned_meshes)
            quit(3)
            return
        var actual_clips := {}
        for wanted_clip in ["Idle","Run","Hit","Death"]:
            var actual_clip := ""
            for clip in player.get_animation_list():
                if clip.ends_with("_"+wanted_clip): actual_clip = clip
            if actual_clip.is_empty():
                printerr("PROBE_ERROR: missing clip ",wanted_clip," for ",kind," available=",player.get_animation_list())
                quit(4)
                return
            actual_clips[wanted_clip] = actual_clip
        for clip_name in actual_clips.values():
            var anim := player.get_animation(clip_name)
            if anim.get_track_count() < 5:
                printerr("PROBE_ERROR: skeletal clip has too few tracks: ",kind," ",clip_name," tracks=",anim.get_track_count())
                quit(5)
                return
        var model_mesh := _find_mesh(instance) as MeshInstance3D
        if model_mesh != null:
            print("MODEL_AABB: ",kind," ",model_mesh.get_aabb())
        print("MODEL_ROOT: ",kind," ",instance.get_class()," children=",instance.get_child_count()," clips=",player.get_animation_list())
        print("ENEMY_GLB_OK: ",kind," bones=",skeleton.get_bone_count()," skinned_meshes=",skinned_meshes," clips=",player.get_animation_list())
        instance.queue_free()
    quit()

func _find_type(node: Node, type_name: String) -> Node:
    if node.get_class() == type_name:
        return node
    for child in node.get_children():
        var result := _find_type(child, type_name)
        if result != null:
            return result
    return null

func _count_skinned_meshes(node: Node) -> int:
    var count := 1 if node is MeshInstance3D and node.skin != null else 0
    for child in node.get_children():
        count += _count_skinned_meshes(child)
    return count

func _find_mesh(node: Node) -> Node:
    if node is MeshInstance3D: return node
    for child in node.get_children():
        var found := _find_mesh(child)
        if found != null: return found
    return null
