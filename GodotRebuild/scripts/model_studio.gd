extends Node3D

const HEROES := [
    {"id": "asta", "name": "Аста"},
    {"id": "yuno", "name": "Юно"},
    {"id": "magna", "name": "Магна"},
    {"id": "vanessa", "name": "Ванесса"},
    {"id": "noelle", "name": "Ноэль"},
    {"id": "charmy", "name": "Чарми"},
]

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var model_root: Node3D = $ModelRoot

var hero_index := 0
var level := 1
var distance := 6.0
var dragging := false
var last_mouse := Vector2.ZERO
var yaw := 0.0
var pitch := -0.10
var info_label: Label
var hero_buttons: Array[Button] = []
var level_buttons: Array[Button] = []
var active_animator: AnimationPlayer

func _ready() -> void:
    pivot.position = Vector3(0.0, 1.18, 0.0)
    _build_stage()
    _build_ui()
    _load_model()
    _update_camera()

func _build_stage() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.025, 0.038, 0.04)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.48, 0.54, 0.58)
    env.ambient_light_energy = 0.75
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    var world := WorldEnvironment.new()
    world.environment = env
    add_child(world)

    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-42, -28, 0)
    key.light_color = Color(1.0, 0.83, 0.67)
    key.light_energy = 1.25
    key.shadow_enabled = true
    add_child(key)

    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-20, 142, 0)
    fill.light_color = Color(0.45, 0.68, 0.82)
    fill.light_energy = 0.48
    add_child(fill)

    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(20.0, 20.0)
    floor.mesh = plane
    floor.position.y = -0.055
    var floor_mat := StandardMaterial3D.new()
    floor_mat.albedo_color = Color(0.075, 0.105, 0.10)
    floor_mat.roughness = 0.92
    floor.material_override = floor_mat
    add_child(floor)

    var plinth := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.78
    cylinder.bottom_radius = 0.82
    cylinder.height = 0.12
    plinth.mesh = cylinder
    plinth.position.y = 0.01
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(0.19, 0.22, 0.22)
    stone.metallic = 0.22
    stone.roughness = 0.62
    plinth.material_override = stone
    add_child(plinth)

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var panel := PanelContainer.new()
    panel.position = Vector2(18, 18)
    panel.custom_minimum_size = Vector2(410, 0)
    canvas.add_child(panel)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 8)
    panel.add_child(column)

    var title := Label.new()
    title.text = "3D-модели защитников"
    title.add_theme_font_size_override("font_size", 24)
    column.add_child(title)

    var hero_row := HBoxContainer.new()
    column.add_child(hero_row)
    for i in range(HEROES.size()):
        var button := Button.new()
        button.text = HEROES[i]["name"]
        button.pressed.connect(_select_hero.bind(i))
        hero_row.add_child(button)
        hero_buttons.append(button)

    var level_row := HBoxContainer.new()
    column.add_child(level_row)
    for tier in range(1, 6):
        var button := Button.new()
        button.text = "Ур. %d" % tier
        button.pressed.connect(_select_level.bind(tier))
        level_row.add_child(button)
        level_buttons.append(button)

    var inspect_row := HBoxContainer.new()
    column.add_child(inspect_row)
    var attack_button := Button.new()
    attack_button.text = "Показать атаку"
    attack_button.pressed.connect(_play_attack)
    inspect_row.add_child(attack_button)

    info_label = Label.new()
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_label.custom_minimum_size.y = 72
    column.add_child(info_label)

    var help := Label.new()
    help.text = "ЛКМ + движение — осмотр со всех сторон · колёсико — плавный зум к точке курсора"
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(help)

func _select_hero(index: int) -> void:
    hero_index = index
    _load_model()

func _select_level(tier: int) -> void:
    level = tier
    _load_model()

func _load_model() -> void:
    for child in model_root.get_children():
        model_root.remove_child(child)
        child.queue_free()
    var hero_id: String = HEROES[hero_index]["id"]
    active_animator = null
    var path := "res://Assets/Heroes/%s_L%d.glb" % [hero_id, level]
    if not ResourceLoader.exists(path):
        info_label.text = "%s · уровень %d\nМодель ещё не собрана: %s" % [HEROES[hero_index]["name"], level, path]
        return
    var packed := load(path) as PackedScene
    if packed == null:
        info_label.text = "Не удалось импортировать GLB: %s" % path
        return
    var instance := packed.instantiate()
    model_root.add_child(instance)
    var skeleton := _find_skeleton(instance)
    var animator := _find_animation_player(instance)
    active_animator = animator
    if animator != null:
        animator.animation_finished.connect(_on_animation_finished)
    var clip_names := PackedStringArray()
    if animator != null:
        clip_names = animator.get_animation_list()
        var idle := _clip(animator,"Idle")
        if not idle.is_empty():
            animator.play(idle)
        elif clip_names.size() > 0:
            animator.play(clip_names[0])
    var rig_text := "Скелет: %d костей" % skeleton.get_bone_count() if skeleton != null else "Скелет: отсутствует"
    var anim_text := "Клипы: " + ", ".join(clip_names) if clip_names.size() > 0 else "Клипы: не импортированы"
    info_label.text = "%s · уровень %d\n%s\n%s\nИсточник: отдельный GLB, skinned mesh + armature" % [
        HEROES[hero_index]["name"], level, rig_text, anim_text
    ]

func _play_attack() -> void:
    var attack := _clip(active_animator,"Attack")
    if not attack.is_empty():
        active_animator.play(attack)

func _on_animation_finished(animation_name: StringName) -> void:
    if str(animation_name).ends_with("_Attack") or str(animation_name)=="Attack":
        var idle := _clip(active_animator,"Idle")
        if not idle.is_empty(): active_animator.play(idle)

func _clip(animator: AnimationPlayer, suffix: String) -> String:
    if animator == null: return ""
    for candidate in animator.get_animation_list():
        if candidate==suffix or str(candidate).ends_with("_"+suffix): return str(candidate)
    return ""

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var result := _find_skeleton(child)
        if result != null:
            return result
    return null

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node
    for child in node.get_children():
        var result := _find_animation_player(child)
        if result != null:
            return result
    return null

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            dragging = event.pressed
            last_mouse = event.position
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom_at(event.position, 0.86)
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom_at(event.position, 1.16)
    elif event is InputEventMouseMotion and dragging:
        var delta: Vector2 = event.position - last_mouse
        last_mouse = event.position
        yaw -= delta.x * 0.008
        pitch = clamp(pitch - delta.y * 0.006, -0.9, 0.65)
        _update_camera()

func _zoom_at(screen_point: Vector2, factor: float) -> void:
    var before := _point_on_focus_plane(screen_point)
    distance = clamp(distance * factor, 1.65, 12.0)
    _update_camera()
    var after := _point_on_focus_plane(screen_point)
    if before != Vector3.ZERO and after != Vector3.ZERO:
        pivot.global_position += before - after
        _update_camera()

func _point_on_focus_plane(screen_point: Vector2) -> Vector3:
    var origin := camera.project_ray_origin(screen_point)
    var direction := camera.project_ray_normal(screen_point)
    if absf(direction.y) < 0.0001:
        return Vector3.ZERO
    var t := (1.18 - origin.y) / direction.y
    if t < 0.0:
        return Vector3.ZERO
    return origin + direction * t

func _update_camera() -> void:
    pivot.rotation = Vector3(pitch, yaw, 0.0)
    camera.position = Vector3(0.0, 0.35, distance)
