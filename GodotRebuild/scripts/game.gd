extends Node3D

const WorldArt = preload("res://scripts/world_art.gd")
const RenderBenchmark = preload("res://scripts/render_benchmark.gd")
const MagicEffects = preload("res://scripts/magic_effects.gd")
const CharacterLOD = preload("res://scripts/character_lod.gd")
const FrostUI = preload("res://scripts/ui_theme_frost.gd")
const CombatBalance = preload("res://scripts/combat_balance.gd")

class TowerCard extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.025,0.045,0.055,0.96)
		style.border_color = Color(0.58,0.68,0.71)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel",style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation",5)
		panel.add_child(column)
		var lines := for_text.split("\n")
		for i in range(lines.size()):
			var line := Label.new()
			line.text = lines[i]
			line.custom_minimum_size.x = 250
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_font_size_override("font_size",15 if i == 0 else 12)
			line.add_theme_color_override("font_color",Color(0.96,0.79,0.48) if i == 0 else Color(0.83,0.88,0.86))
			column.add_child(line)
		return panel

const HEROES := [
	{"id":"asta", "name":"Аста · анти-магический клинок", "short":"Аста", "price":70, "damage":17.0, "range":9.0, "detect_range":10.5, "aura_range":0.0, "rate":0.85, "color":Color(0.18,0.08,0.23), "description":"Быстрый ближний клинок; высший ранг поражает три цели.", "costs":[80,125,190,290]},
	{"id":"yuno", "name":"Юно · магия ветра", "short":"Юно", "price":100, "damage":28.0, "range":13.0, "detect_range":15.0, "aura_range":0.0, "rate":1.2, "color":Color(0.45,0.92,0.67), "description":"Самая большая дальность; ветер пробивает строй.", "costs":[90,140,205,310]},
	{"id":"magna", "name":"Магна · огненный шар", "short":"Магна", "price":125, "damage":45.0, "range":10.5, "detect_range":12.5, "aura_range":0.0, "rate":1.05, "color":Color(1.0,0.32,0.08), "description":"Взрывной огненный удар задевает соседних врагов.", "costs":[95,145,215,320]},
	{"id":"vanessa", "name":"Ванесса · красная нить", "short":"Ванесса", "price":115, "damage":0.0, "range":0.0, "detect_range":0.0, "aura_range":10.5, "rate":0.0, "color":Color(0.95,0.32,0.60), "description":"Выбери ауру урона или скорости атаки.", "costs":[95,145,220,330]},
	{"id":"noelle", "name":"Ноэль · магия воды", "short":"Ноэль", "price":120, "damage":18.0, "range":10.0, "detect_range":12.0, "aura_range":0.0, "rate":1.25, "color":Color(0.48,0.83,1.0), "description":"Вода замедляет, высший ранг ненадолго замораживает врага.", "costs":[95,145,215,320]},
	{"id":"charmy", "name":"Чарми · хлопковая магия", "short":"Чарми", "price":135, "damage":34.0, "range":6.0, "detect_range":7.5, "aura_range":0.0, "rate":1.35, "color":Color(0.90,0.89,0.76), "description":"Ближний хлопковый удар по группе; на V ранге снижает броню.", "costs":[85,135,200,300]}
]
const FORMS := [
	["Аста","Чёрный бык","Демон-истребитель","Чёрная форма","Анти-магический Аста"],
	["Юно","Ветер Зефира","Дух ветра","Золотая корона","Духовой шквал"],
	["Магна","Красная нить","Пылающий мяч","Огненная броня","Великий огненный шар"],
	["Ванесса","Красная нить судьбы","Нить защиты","Алая судьба","Нить судьбы: сильная аура"],
	["Ноэль","Серебряное копьё","Водная броня","Морской дракон","Валькирия: ледяной плен"],
	["Чарми","Хлопковые рукавицы","Овечий страж","Хлопковая кухня","Хлопковый таран"]
]
const CARD_HINTS := ["Быстрый ближний удар","Дальний порыв ветра","Взрывной огненный удар","Аура урона или скорости","Замедляет и замораживает","Ближний удар по площади"]
const ATTACK_SFX := ["res://Assets/Sfx/asta-slash.mp3","res://Assets/Sfx/yuno-wind.mp3","res://Assets/Sfx/magna-fire.mp3","res://Assets/Sfx/vanessa-thread.mp3","res://Assets/Sfx/noelle-ice.mp3","res://Assets/Sfx/asta-slash.mp3"]
const DEATH_SFX := {"goblin":"res://Assets/Sfx/death-goblin.mp3","orc":"res://Assets/Sfx/death-orc.mp3","uruk":"res://Assets/Sfx/death-uruk.mp3","warg":"res://Assets/Sfx/death-warg.mp3","troll":"res://Assets/Sfx/death-troll.mp3","nazgul":"res://Assets/Sfx/death-nazgul.mp3"}
const ENEMY_KINDS := ["goblin","orc","uruk","warg","troll","nazgul","boss_troll"]
const ENEMY_MODEL_SCALE := {"goblin":0.82,"orc":1.0,"uruk":1.02,"warg":1.04,"troll":1.50,"nazgul":1.08,"boss_troll":1.0}
const ENEMY_MODEL_HEIGHT := {"goblin":2.46743,"orc":2.17860,"uruk":2.23451,"warg":1.463,"troll":2.30276,"nazgul":2.29422,"boss_troll":4.79922}
const SETTINGS_PATH := "user://settings.cfg"
const ROAD_OUTER_WIDTH := 3.35
const TOWER_BASE_RADIUS := 0.72
const TOWER_BASE_CLEARANCE := 0.07
const TOWER_SELECT_RADIUS := 1.50
const ENEMY_REFERENCE_RUN_SPEED := 3.078947
const WARG_REFERENCE_RUN_SPEED := 2.357143
var arena := 0
var wave := 0
var gold := 360
var lives := 15
var game_speed := 1.0
var paused := false
var wave_running := false
var stage_ready := false
var game_over := false
var spawn_left := 0
var spawn_clock := 0.0
var world_size := 64.0
var camera_size := 54.0
var camera_target := Vector3.ZERO
var camera_zoom_goal := 54.0
var camera_zoom_anchor := Vector2.ZERO
var camera_zoom_active := false
var camera_yaw := 0.0
var camera_pitch := CAMERA_DEFAULT_PITCH
var camera_orbiting := false
var camera_orbit_mouse := Vector2.ZERO
const CAMERA_MIN_PITCH := deg_to_rad(20.0)
const CAMERA_MAX_PITCH := deg_to_rad(80.0)
const CAMERA_DEFAULT_PITCH := deg_to_rad(55.0)
var towers: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var enemy_death_visuals: Array[Dictionary] = []
var bolts: Array[Dictionary] = []
var route_points: PackedVector3Array = PackedVector3Array()
var route_lengths: PackedFloat32Array = PackedFloat32Array()
var route_length := 0.0
var build_obstacles: Array[Dictionary] = []
var selected_type := -1
var selected_tower: Dictionary = {}
var selected_enemy: Dictionary = {}
var enemy_inspect_clock := 0.0
var mouse_world := Vector3.ZERO
var build_ghost: Node3D
var ghost_range: MeshInstance3D
var ghost_material: StandardMaterial3D
var clock := 0.0
var rng := RandomNumberGenerator.new()

var camera: Camera3D
var terrain_root: Node3D
var world_art: Node3D
var tower_root: Node3D
var enemy_root: Node3D
var bolt_root: Node3D
var magic_effects: Node3D
var ui_layer: CanvasLayer
var hud_gold: Label
var hud_wave: Label
var hud_lives: Label
var hud_arena: Label
var status_label: Label
var selection_label: Label
var side_panel: PanelContainer
var side_scroll: ScrollContainer
var hud_title: Label
var music_toggle_button: Button
var hud_summary: Label
var start_button: Button
var pause_button: Button
var upgrade_button: Button
var sell_button: Button
var aura_damage_button: Button
var aura_speed_button: Button
var speed_select: OptionButton
var music_slider: HSlider
var sfx_slider: HSlider
var music_volume_text: Label
var sfx_volume_text: Label
var fullscreen_button: Button
var music_player: AudioStreamPlayer
var music_tracks: PackedStringArray = PackedStringArray()
var music_track_index := -1
var music_fallback_tracks: Dictionary = {}
var music_enabled := true
var sfx_players: Array[AudioStreamPlayer3D] = []
var sfx_stream_cache: Dictionary = {}
var sfx_voice_cursor := 0
var music_volume := 10.0
var sfx_volume := 28.0
var settings_save_timer: Timer
var card_buttons: Array[Button] = []
var panning := false
var last_mouse := Vector2.ZERO
var right_press_mouse := Vector2.ZERO
var right_dragged := false
var route_patterns: Array = []
var ambient_people: Array[Dictionary] = []
var ambient_animals: Array[Dictionary] = []
var ambient_birds: Array[Dictionary] = []
var ambient_lizards: Array[Dictionary] = []
var ambient_clock := 0.0
var menu_root: Control
var menu_paused_game := false
var tower_model_paths: Array[String] = []
var tower_model_cache: Dictionary = {}
var tower_model_failures: Array[String] = []
var enemy_model_paths: Array[String] = []
var enemy_model_cache: Dictionary = {}
var enemy_model_failures: Array[String] = []
var model_load_queue: Array[Dictionary] = []
var active_model_path := ""
var active_model_is_enemy := false
var menu_loading_label: Label
var menu_continue_button: Button
var menu_new_button: Button
var all_tower_models_ready := false
var initial_models_were_ready := false
var shutting_down := false
var last_cpu_game_logic_ms := 0.0
var last_cpu_lod_animation_ms := 0.0
var frame_limit := 60
var benchmark_mode := false
var focused_window := true
var frame_limit_select: OptionButton
var lod_refresh_clock := 0.0
var made_by_label: Label
var force_high_detail := false

func _ready() -> void:
	benchmark_mode = OS.get_cmdline_user_args().has("--render-benchmark")
	force_high_detail = OS.get_cmdline_user_args().has("--force-high-detail")
	DisplayServer.window_set_title("Коди TD · Рубеж Средиземья")
	DisplayServer.window_set_min_size(Vector2i(1000,600))
	var icon := load("res://Assets/Icons/black-bulls-emblem.png") as Texture2D
	if icon != null:
		DisplayServer.window_set_icon(icon.get_image())
	_load_settings()
	rng.randomize()
	_load_route_patterns()
	_build_scene()
	_build_hud()
	_build_main_menu()
	menu_root.hide()
	_apply_frame_limit()
	settings_save_timer = Timer.new()
	settings_save_timer.one_shot = true
	settings_save_timer.wait_time = 0.4
	settings_save_timer.timeout.connect(_save_settings)
	add_child(settings_save_timer)
	get_viewport().size_changed.connect(_update_ui_layout)
	_update_ui_layout()
	_build_arena()
	_build_music()
	_build_sfx()
	# Static geometry/material creation finishes before background texture jobs.
	# This also avoids Dummy renderer RID initialization races during headless QA.
	_start_tower_model_loading()
	_start_enemy_model_loading()
	_refresh_hud()
	_refresh_selection()
	if OS.get_cmdline_user_args().has("--render-benchmark"):
		var benchmark := RenderBenchmark.new()
		add_child(benchmark)
		benchmark.start(self)

func _exit_tree() -> void:
	shutting_down = true
	_save_settings()
	if music_player != null:
		music_player.stop()
		music_player.stream = null
	for player in sfx_players:
		player.stop()
		player.stream = null
	# Only the active request has been submitted to ResourceLoader. Queued paths
	# have no loader state to query or join and are simply discarded on shutdown.
	_release_active_model_request()
	model_load_queue.clear()
	tower_model_paths.clear()
	enemy_model_paths.clear()
	tower_model_cache.clear()
	enemy_model_cache.clear()
	sfx_stream_cache.clear()
	selected_tower = {}
	selected_enemy = {}
	bolts.clear()
	enemies.clear()
	enemy_death_visuals.clear()
	towers.clear()

func _release_active_model_request() -> void:
	if active_model_path.is_empty(): return
	var state := ResourceLoader.load_threaded_get_status(active_model_path)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS or state == ResourceLoader.THREAD_LOAD_LOADED:
		var pending_resource: Resource = ResourceLoader.load_threaded_get(active_model_path)
		pending_resource = null
	active_model_path = ""
	active_model_is_enemy = false

func _pump_model_loading() -> void:
	if shutting_down or not active_model_path.is_empty(): return
	while not model_load_queue.is_empty():
		var request: Dictionary = model_load_queue.pop_front()
		var path: String = request.path
		var is_enemy: bool = request.enemy
		var error := ResourceLoader.load_threaded_request(path,"PackedScene",false)
		if error == OK:
			active_model_path = path
			active_model_is_enemy = is_enemy
			return
		if is_enemy: enemy_model_failures.append(path)
		else: tower_model_failures.append(path)

func _poll_model_loading() -> void:
	if shutting_down: return
	if active_model_path.is_empty():
		_pump_model_loading()
		return
	var state := ResourceLoader.load_threaded_get_status(active_model_path)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	var path := active_model_path
	var is_enemy := active_model_is_enemy
	var packed: PackedScene
	if state == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	active_model_path = ""
	active_model_is_enemy = false
	if packed != null:
		if is_enemy: enemy_model_cache[path] = packed
		else: tower_model_cache[path] = packed
	else:
		if is_enemy: enemy_model_failures.append(path)
		else: tower_model_failures.append(path)
	if not is_enemy:
		all_tower_models_ready = _initial_tower_models_ready()
		initial_models_were_ready = all_tower_models_ready
		_update_model_loading_ui()
	_pump_model_loading()

func _load_route_patterns() -> void:
	var file := FileAccess.open("res://Assets/Maps/routes.json", FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array and not parsed.is_empty():
			route_patterns = parsed
	if route_patterns.is_empty():
		route_patterns = [
			[[0.04,0.22],[0.22,0.17],[0.28,0.19],[0.42,0.27],[0.48,0.36],[0.44,0.40],[0.33,0.48],[0.27,0.58],[0.30,0.63],[0.41,0.61],[0.56,0.54],[0.63,0.45],[0.60,0.41],[0.51,0.46],[0.43,0.58],[0.43,0.70],[0.48,0.78],[0.57,0.77],[0.70,0.71],[0.78,0.57],[0.77,0.70],[0.71,0.78],[0.85,0.86],[0.97,0.82]],
			[[0.78,0.08],[0.76,0.16],[0.68,0.21],[0.58,0.19],[0.49,0.14],[0.40,0.16],[0.33,0.24],[0.30,0.34],[0.34,0.43],[0.43,0.47],[0.53,0.45],[0.63,0.39],[0.72,0.35],[0.81,0.38],[0.88,0.47],[0.91,0.56],[0.88,0.65],[0.80,0.70],[0.70,0.73],[0.59,0.72],[0.49,0.67],[0.42,0.58],[0.39,0.49],[0.43,0.40],[0.52,0.34],[0.62,0.31],[0.72,0.33],[0.82,0.39],[0.94,0.47]]
		]

func _start_tower_model_loading() -> void:
	for hero in HEROES:
		_request_tower_model(hero.id,1)
	_update_model_loading_ui()

func _request_tower_model(hero_id: String, rank: int) -> void:
	if shutting_down: return
	var path := "res://Assets/Heroes/%s_L%d.glb" % [hero_id,rank]
	if tower_model_cache.has(path) or tower_model_failures.has(path) or tower_model_paths.has(path):
		return
	if not ResourceLoader.exists(path):
		tower_model_failures.append(path)
		return
	tower_model_paths.append(path)
	model_load_queue.append({"path":path,"enemy":false})
	_pump_model_loading()

func _poll_tower_model_loading() -> void:
	_poll_model_loading()

func _initial_tower_models_ready() -> bool:
	for hero in HEROES:
		var path := "res://Assets/Heroes/%s_L1.glb" % hero.id
		if not tower_model_cache.has(path):
			return false
	return true

func _start_enemy_model_loading() -> void:
	if shutting_down: return
	for kind in ENEMY_KINDS:
		var path := "res://Assets/Enemies/%s.glb" % kind
		if enemy_model_cache.has(path) or enemy_model_failures.has(path) or enemy_model_paths.has(path): continue
		if not ResourceLoader.exists(path):
			enemy_model_failures.append(path)
			continue
		enemy_model_paths.append(path)
		model_load_queue.append({"path":path,"enemy":true})
	_pump_model_loading()

func _poll_enemy_model_loading() -> void:
	if shutting_down: return
	_poll_model_loading()
	if not enemy_model_failures.is_empty() and status_label != null and not wave_running:
		status_label.text = "Ошибка загрузки модели противника: %s" % enemy_model_failures[0].get_file()

func _enemy_models_ready() -> bool:
	if not enemy_model_failures.is_empty():
		return false
	for kind in ENEMY_KINDS:
		if not enemy_model_cache.has("res://Assets/Enemies/%s.glb" % kind):
			return false
	return true

func _update_model_loading_ui() -> void:
	if menu_loading_label != null:
		var loaded_initial := 0
		for hero in HEROES:
			if tower_model_cache.has("res://Assets/Heroes/%s_L1.glb" % hero.id):
				loaded_initial += 1
		menu_loading_label.text = "Модели готовы · можно играть" if _initial_tower_models_ready() else "Загрузка героев · %d/%d" % [loaded_initial,HEROES.size()]
	if menu_continue_button != null:
		menu_continue_button.disabled = not _initial_tower_models_ready()
	if menu_new_button != null:
		menu_new_button.disabled = not _initial_tower_models_ready()
	if card_buttons.size() == HEROES.size():
		_refresh_hud()
	if selection_label != null:
		_refresh_selection()

func _build_scene() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035,0.055,0.052)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62,0.68,0.61)
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.65
	environment.ssao_intensity = 0.85
	environment.ssao_power = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color(1.0,0.86,0.69)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22,146,0)
	fill.light_color = Color(0.54,0.69,0.85)
	fill.light_energy = 0.34
	add_child(fill)
	var pivot := Node3D.new()
	pivot.name = "CameraTarget"
	add_child(pivot)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	pivot.add_child(camera)
	_update_camera()
	terrain_root = Node3D.new()
	terrain_root.name = "Arena"
	add_child(terrain_root)
	tower_root = Node3D.new()
	tower_root.name = "Towers"
	add_child(tower_root)
	enemy_root = Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)
	bolt_root = Node3D.new()
	bolt_root.name = "Projectiles"
	add_child(bolt_root)
	magic_effects = MagicEffects.new()
	magic_effects.name = "ElementalEffects"
	bolt_root.add_child(magic_effects)
	ghost_material = StandardMaterial3D.new()
	ghost_material.albedo_color = Color(0.2,0.8,0.35,0.48)
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _make_procedural_surface_material(base: Color, accent: Color, detail_scale: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 world_position;
uniform vec3 base_tint;
uniform vec3 accent_tint;
uniform float detail_scale = 0.1;
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_position.xz;
	float broad = noise2(p * detail_scale);
	float mottling = noise2(p * detail_scale * 5.7);
	float grain = noise2(p * detail_scale * 38.0);
	vec3 base = mix(base_tint * 0.73, base_tint * 1.16, broad);
	base = mix(base, accent_tint, smoothstep(0.56, 0.90, mottling) * 0.23);
	base *= 0.92 + grain * 0.12;
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 0.96;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_tint",Vector3(base.r,base.g,base.b))
	material.set_shader_parameter("accent_tint",Vector3(accent.r,accent.g,accent.b))
	material.set_shader_parameter("detail_scale",detail_scale)
	return material

func _build_arena() -> void:
	ambient_people.clear()
	ambient_animals.clear()
	ambient_birds.clear()
	ambient_lizards.clear()
	world_size = 64.0 + arena * 2.0
	build_obstacles.clear()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(world_size, world_size * 0.72)
	var ground := MeshInstance3D.new()
	ground.name = "NoiseTexturedGround"
	ground.mesh = ground_mesh
	ground.position.y = -0.18
	var ground_color: Color = [Color(0.20,0.29,0.19),Color(0.29,0.19,0.12),Color(0.34,0.39,0.37)][arena % 3]
	ground.material_override = _make_procedural_surface_material(ground_color,ground_color.lightened(0.22),0.11)
	terrain_root.add_child(ground)
	_build_route()
	world_art = WorldArt.new()
	terrain_root.add_child(world_art)
	world_art.build(world_size,arena,route_points,build_obstacles)
	world_art.apply_lighting(self)
	_build_settlement()
	_build_wildlife()
	world_art.decorate_hamlet(terrain_root.get_node_or_null("RiversideHamlet"))
	camera_size = minf(maxf(40.0, world_size * 0.74),_camera_max_size())
	camera_zoom_goal = camera_size
	camera_zoom_active = false
	camera_target = _camera_fit_center()
	_update_camera()

func _build_route() -> void:
	var pattern: Array = route_patterns[mini(arena,route_patterns.size()-1)]
	var anchors := PackedVector3Array()
	for raw_point in pattern:
		var p := Vector2(float(raw_point[0]),float(raw_point[1]))
		anchors.append(Vector3((p.x-0.5)*world_size*0.90,0.02,(p.y-0.5)*world_size*0.66))
	route_points = PackedVector3Array()
	for i in range(anchors.size()-1):
		var p0: Vector3 = anchors[maxi(0,i-1)]
		var p1: Vector3 = anchors[i]
		var p2: Vector3 = anchors[i+1]
		var p3: Vector3 = anchors[mini(anchors.size()-1,i+2)]
		for step in range(6):
			var t := float(step)/6.0
			var t2 := t*t
			var t3 := t2*t
			var point := 0.5*((2.0*p1)+(-p0+p2)*t+(2.0*p0-5.0*p1+4.0*p2-p3)*t2+(-p0+3.0*p1-3.0*p2+p3)*t3)
			route_points.append(point)
	route_points.append(anchors[anchors.size()-1])
	route_lengths = PackedFloat32Array()
	route_lengths.resize(route_points.size())
	route_length = 0.0
	for i in range(route_points.size()):
		if i > 0:
			route_length += route_points[i].distance_to(route_points[i-1])
		route_lengths[i] = route_length
	_add_road_ribbon(3.35,Color(0.16,0.13,0.09),0.00)
	_add_road_ribbon(2.85,Color(0.40,0.32,0.22),0.035)
	_add_road_ribbon(2.35,Color(0.68,0.57,0.39),0.065)
	_add_road_ribbon(2.12,[Color(0.80,0.69,0.49),Color(0.57,0.39,0.26),Color(0.66,0.72,0.70)][arena%3],0.09)

func _add_road_ribbon(width: float, color: Color, lift: float) -> void:
	if route_points.size() < 2:
		return
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var normals := PackedVector3Array()
	for i in range(route_points.size()):
		var tangent: Vector3 = (route_points[mini(i+1,route_points.size()-1)] - route_points[maxi(0,i-1)]).normalized()
		var side := Vector3(-tangent.z,0,tangent.x).normalized() * width * 0.5
		vertices.append(route_points[i]+side+Vector3.UP*lift)
		vertices.append(route_points[i]-side+Vector3.UP*lift)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if i > 0:
			var a := (i-1)*2
			# Clockwise top faces, matching Godot PlaneMesh and back-face culling.
			indices.append_array(PackedInt32Array([a,a+1,a+2,a+1,a+3,a+2]))
	# At a tight inner bend the ribbon's offset edges may exchange order. Keep
	# each individual top triangle clockwise so no bend vanishes under culling.
	for triangle in range(0,indices.size(),3):
		var a := indices[triangle]
		var b := indices[triangle+1]
		var c := indices[triangle+2]
		if (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(Vector3.UP)>0.0:
			indices[triangle+1] = c
			indices[triangle+2] = b
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0,material)
	var road := MeshInstance3D.new()
	road.mesh = mesh
	terrain_root.add_child(road)

func _build_terrain_props() -> void:
	var tree_count := 85 + arena * 3
	var rock_count := 95 + arena * 3
	if DisplayServer.get_name() == "headless":
		_build_headless_obstacle_data(tree_count,rock_count)
		return
	var tree_mesh := _make_tree_canopy_mesh()
	var tree_base: Color = Color(0.10,0.28,0.17) if arena%3 != 1 else Color(0.18,0.12,0.09)
	var tree_mat := _make_procedural_surface_material(tree_base,tree_base.lightened(0.20),0.42)
	var tree_multi := _create_multimesh(tree_mesh,tree_mat,tree_count)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.23
	trunk_mesh.height = 1.8
	trunk_mesh.radial_segments = 7
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.24,0.17,0.11) if arena%3 != 2 else Color(0.29,0.31,0.29)
	trunk_mat.roughness = 1.0
	var trunk_multi := _create_multimesh(trunk_mesh,trunk_mat,tree_count)
	var rock_mesh := _make_rock_mesh()
	var rock_base: Color = [Color(0.25,0.29,0.21),Color(0.28,0.21,0.16),Color(0.42,0.46,0.45)][arena%3]
	var rock_mat := _make_procedural_surface_material(rock_base,rock_base.lightened(0.30),1.1)
	var rock_multi := _create_multimesh(rock_mesh,rock_mat,rock_count)
	var tree_i := 0
	var rock_i := 0
	for attempt in range((tree_count+rock_count)*4):
		if tree_i >= tree_count and rock_i >= rock_count:
			break
		var p := Vector3((rng.randf()-0.5)*world_size*0.94,0,(rng.randf()-0.5)*world_size*0.65)
		if _near_route(p,9.5):
			continue
		var angle := rng.randf()*TAU
		if tree_i < tree_count and (attempt%2==0 or rock_i>=rock_count):
			var height := rng.randf_range(0.65,1.35)
			var tree_transform := Transform3D(Basis(Vector3.UP,angle).scaled(Vector3(height,height,height)),p+Vector3.UP*(1.08*height))
			tree_multi.multimesh.set_instance_transform(tree_i,tree_transform)
			trunk_multi.multimesh.set_instance_transform(tree_i,Transform3D(Basis(Vector3.UP,angle).scaled(Vector3(height*0.48,height,height*0.48)),p+Vector3.UP*(0.9*height)))
			build_obstacles.append({"position":Vector2(p.x,p.z),"radius":1.1*height})
			tree_i += 1
		elif rock_i < rock_count:
			var size := rng.randf_range(0.45,1.25)
			var rock_scale := Vector3(size*rng.randf_range(0.8,1.5),size*rng.randf_range(0.45,0.85),size)
			rock_multi.multimesh.set_instance_transform(rock_i,Transform3D(Basis(Vector3.UP,angle).scaled(rock_scale),p+Vector3.UP*(rock_scale.y*0.55)))
			build_obstacles.append({"position":Vector2(p.x,p.z),"radius":maxf(rock_scale.x,rock_scale.z)})
			rock_i += 1
	if tree_i < tree_count:
		tree_multi.multimesh.visible_instance_count = tree_i
		trunk_multi.multimesh.visible_instance_count = tree_i
	if rock_i < rock_count:
		rock_multi.multimesh.visible_instance_count = rock_i
	var shrub_mesh := SphereMesh.new()
	shrub_mesh.radial_segments = 6
	shrub_mesh.rings = 3
	var shrub_mat := _make_procedural_surface_material(Color(0.14,0.30,0.15),Color(0.28,0.43,0.20),0.72)
	var shrubs := _create_multimesh(shrub_mesh,shrub_mat,210+arena*5)
	for i in range(shrubs.multimesh.instance_count):
		var p := Vector3((rng.randf()-0.5)*world_size*0.96,0,(rng.randf()-0.5)*world_size*0.66)
		if _near_route(p,8.0):
			p.y = -1000
		var scale := rng.randf_range(0.18,0.55)
		shrubs.multimesh.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(scale,scale*0.52,scale)),p+Vector3.UP*scale*0.25))
	_build_grass_details()

func _terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color.lightened(0.035))
	surface.add_vertex(b)
	surface.set_color(color.darkened(0.045))
	surface.add_vertex(c)

func _make_tree_canopy_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := [
		{"bottom":0.12,"middle":0.70,"top":1.53,"radius":0.96,"mid_radius":0.58,"tip_radius":0.08},
		{"bottom":0.62,"middle":1.20,"top":2.04,"radius":0.79,"mid_radius":0.46,"tip_radius":0.035},
		{"bottom":1.15,"middle":1.69,"top":2.42,"radius":0.61,"mid_radius":0.34,"tip_radius":0.01}
	]
	var segments := 9
	for tier_index in range(tiers.size()):
		var tier: Dictionary = tiers[tier_index]
		var bottom_ring: Array[Vector3] = []
		var middle_ring: Array[Vector3] = []
		var tip_ring: Array[Vector3] = []
		for segment in range(segments):
			var angle := TAU*float(segment)/float(segments)+float(tier_index)*0.19
			var irregularity := 0.88+0.12*sin(float(segment)*4.7+float(tier_index)*2.3)
			var x := cos(angle)
			var z := sin(angle)
			bottom_ring.append(Vector3(x*float(tier.radius)*irregularity,float(tier.bottom)-1.2,z*float(tier.radius)*irregularity))
			middle_ring.append(Vector3(x*float(tier.mid_radius)*irregularity,float(tier.middle)-1.2,z*float(tier.mid_radius)*irregularity))
			tip_ring.append(Vector3(x*float(tier.tip_radius)*irregularity,float(tier.top)-1.2,z*float(tier.tip_radius)*irregularity))
		for segment in range(segments):
			var next := (segment+1)%segments
			var shade := 0.90+0.10*sin(float(segment)*5.1+float(tier_index)*1.7)
			var leaf_color := Color(0.60,0.84,0.62)*shade
			_terrain_triangle(surface,bottom_ring[segment],bottom_ring[next],middle_ring[next],leaf_color)
			_terrain_triangle(surface,bottom_ring[segment],middle_ring[next],middle_ring[segment],leaf_color)
			_terrain_triangle(surface,middle_ring[segment],middle_ring[next],tip_ring[next],leaf_color.lightened(0.045))
			_terrain_triangle(surface,middle_ring[segment],tip_ring[next],tip_ring[segment],leaf_color.lightened(0.045))
			_terrain_triangle(surface,bottom_ring[next],bottom_ring[segment],Vector3(0.0,float(tier.bottom)-1.2,0.0),leaf_color.darkened(0.06))
	surface.generate_normals()
	return surface.commit()

func _make_rock_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 9
	var heights := [-0.50,-0.26,0.10,0.38]
	var radii := [0.54,0.87,0.93,0.56]
	var rings: Array[Array] = []
	for ring_index in range(heights.size()):
		var ring: Array[Vector3] = []
		for segment in range(segments):
			var angle := TAU*float(segment)/float(segments)+0.12*float(ring_index)
			var angular_noise := 0.80+0.18*sin(float(segment)*4.1+float(ring_index)*2.4)+0.05*cos(float(segment)*1.9)
			var r := float(radii[ring_index])*angular_noise
			ring.append(Vector3(cos(angle)*r,float(heights[ring_index])+0.07*sin(float(segment)*3.7+float(ring_index)),sin(angle)*r))
		rings.append(ring)
	for ring_index in range(rings.size()-1):
		for segment in range(segments):
			var next := (segment+1)%segments
			var low: Array = rings[ring_index]
			var high: Array = rings[ring_index+1]
			var tone := 0.88+0.10*sin(float(segment)*3.3+float(ring_index)*1.9)
			var stone := Color(0.69,0.72,0.66)*tone
			_terrain_triangle(surface,low[segment],high[segment],high[next],stone)
			_terrain_triangle(surface,low[segment],high[next],low[next],stone.darkened(0.035))
	var top := Vector3(0.03,0.49,-0.04)
	var bottom := Vector3(-0.02,-0.52,0.02)
	for segment in range(segments):
		var next := (segment+1)%segments
		var top_ring: Array = rings[rings.size()-1]
		var bottom_ring: Array = rings[0]
		_terrain_triangle(surface,top_ring[segment],top,top_ring[next],Color(0.76,0.78,0.72))
		_terrain_triangle(surface,bottom_ring[next],bottom,bottom_ring[segment],Color(0.38,0.40,0.37))
	surface.generate_normals()
	return surface.commit()

func _build_headless_obstacle_data(tree_count: int, rock_count: int) -> void:
	var tree_i := 0
	var rock_i := 0
	for attempt in range((tree_count+rock_count)*4):
		if tree_i >= tree_count and rock_i >= rock_count:
			break
		var p := Vector3((rng.randf()-0.5)*world_size*0.94,0,(rng.randf()-0.5)*world_size*0.65)
		if _near_route(p,9.5):
			continue
		if tree_i < tree_count and (attempt%2==0 or rock_i>=rock_count):
			var height := rng.randf_range(0.65,1.35)
			build_obstacles.append({"position":Vector2(p.x,p.z),"radius":1.1*height})
			tree_i += 1
		elif rock_i < rock_count:
			var size := rng.randf_range(0.45,1.25)
			var rock_scale := Vector3(size*rng.randf_range(0.8,1.5),size*rng.randf_range(0.45,0.85),size)
			build_obstacles.append({"position":Vector2(p.x,p.z),"radius":maxf(rock_scale.x,rock_scale.z)})
			rock_i += 1

func _create_multimesh(mesh: Mesh, material: Material, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	multi.visible_instance_count = count
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multi
	visual.material_override = material
	terrain_root.add_child(visual)
	return visual

func _build_grass_details() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(7):
		var angle := TAU*float(blade)/7.0 + rng.randf_range(-0.22,0.22)
		var direction := Vector3(cos(angle),0.0,sin(angle))
		var side := Vector3(-direction.z,0.0,direction.x)
		var center := direction*rng.randf_range(0.0,0.16)
		var height := rng.randf_range(0.24,0.48)
		var width := rng.randf_range(0.024,0.043)
		var lean := direction*rng.randf_range(0.035,0.14)
		var p0 := center-side*width
		var p1 := center+side*width
		var tip := center+lean+Vector3.UP*height
		var base_color := Color(0.12,0.28,0.10).lerp(Color(0.29,0.43,0.17),rng.randf())
		for point in [p0,p1,tip,tip,p1,p0]:
			surface.set_color(base_color.lerp(Color(0.58,0.62,0.27),clampf(point.y/height,0.0,1.0)))
			surface.add_vertex(point)
	surface.generate_normals()
	var blade_mesh := surface.commit()
	var blade_material := StandardMaterial3D.new()
	blade_material.vertex_color_use_as_albedo = true
	blade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade_material.roughness = 1.0
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = blade_mesh
	var count := 1250+arena*55
	multi.instance_count = count
	for i in range(count):
		var p := Vector3((rng.randf()-0.5)*world_size*0.94,-0.16,(rng.randf()-0.5)*world_size*0.66)
		if _near_route(p,4.0):
			multi.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(0,-1000,0)))
			continue
		var scale := rng.randf_range(0.70,1.35)
		var rotation := rng.randf()*TAU
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rotation).scaled(Vector3.ONE*scale),p))
		multi.set_instance_color(i,Color(rng.randf_range(0.78,1.12),rng.randf_range(0.82,1.12),rng.randf_range(0.72,1.05),1.0))
	var grass := MultiMeshInstance3D.new()
	grass.name = "InstancedGrass"
	grass.multimesh = multi
	grass.material_override = blade_material
	terrain_root.add_child(grass)

func _terrain_material(color: Color, roughness: float = 0.92) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _terrain_box(parent: Node3D, position: Vector3, size: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation = rotation
	parent.add_child(instance)
	return instance

func _build_settlement() -> void:
	# Fit the actual buildings, pond, chores and moving actors, rather than asking
	# six arbitrary map points to have the same large empty circle around them.
	var layout := _settlement_find_layout()
	if layout.is_empty():
		push_error("No safe settlement footprint fits arena %d" % (arena+1))
		return
	var village := Node3D.new()
	village.name = "RiversideHamlet"
	village.transform = layout.transform
	world_art.reserve_settlement(layout.lots)
	terrain_root.add_child(village)
	var biome_profile: Dictionary=world_art.get("profile")
	var plaster := _terrain_material(biome_profile.house)
	var timber := _terrain_material(Color(0.22,0.13,0.075))
	var wood := _terrain_material(Color(0.36,0.23,0.12))
	var roof := _make_procedural_surface_material(Color(0.17,0.15,0.12),Color(0.31,0.23,0.16),0.55)
	var window := _terrain_material(Color(0.83,0.61,0.27),0.34)
	_build_cottage(village,Vector3(-4.4,0.0,-1.0),plaster,timber,wood,roof,window,1.0)
	_build_cottage(village,Vector3(4.2,0.0,-1.2),plaster,timber,wood,roof,window,0.78)
	var pond_mesh := CylinderMesh.new()
	pond_mesh.top_radius = 2.45
	pond_mesh.bottom_radius = 2.55
	pond_mesh.height = 0.10
	pond_mesh.radial_segments = 48
	var pond_material := _terrain_material(Color(0.08,0.24,0.27),0.30)
	pond_material.metallic = 0.12
	var pond := MeshInstance3D.new()
	pond.name = "HamletPond"
	pond.mesh = pond_mesh
	pond.material_override = pond_material
	pond.position = Vector3(0.0,-0.115,5.6)
	village.add_child(pond)
	_settlement_register_obstacle(village,Vector3(0.0,0.0,5.6),3.0)
	var shore := TorusMesh.new()
	shore.inner_radius = 2.35
	shore.outer_radius = 2.52
	shore.rings = 10
	shore.ring_segments = 40
	var shore_node := MeshInstance3D.new()
	shore_node.mesh = shore
	shore_node.material_override = _terrain_material(Color(0.33,0.30,0.18))
	shore_node.position = Vector3(0.0,-0.06,5.6)
	village.add_child(shore_node)
	_build_hamlet_garden(village,timber,wood)
	_create_ambient_villager(village,Vector3(-1.9,0.0,2.1),biome_profile.clothes,biome_profile.hat,biome_profile.chores[0],0.8)
	_create_ambient_villager(village,Vector3(6.5,0.0,3.0),(biome_profile.clothes as Color).lightened(0.06),biome_profile.hat,biome_profile.chores[1],2.4)
	_create_ambient_villager(village,Vector3(-2.1,0.0,7.6),(biome_profile.clothes as Color).darkened(0.08),biome_profile.hat,biome_profile.chores[2],4.0)
	_create_ambient_goat(village,Vector3(5.0,0.0,-2.8),0.5)
	_create_ambient_goat(village,Vector3(6.0,0.0,-3.4),2.7)
	_settlement_register_obstacle(village,Vector3(-4.4,0.0,-1.0),2.8)
	_settlement_register_obstacle(village,Vector3(4.2,0.0,-1.2),2.5)
	_settlement_register_obstacle(village,Vector3(6.35,0.0,3.4),2.5)
	_settlement_register_obstacle(village,Vector3(-1.8,0.0,-3.7),0.85)
	_settlement_register_obstacle(village,Vector3(3.0,0.0,3.7),0.95)

func _settlement_register_obstacle(village: Node3D, local_position: Vector3, radius: float) -> void:
	var world_position := village.to_global(local_position)
	build_obstacles.append({"position":Vector2(world_position.x,world_position.z),"radius":radius*village.scale.x})

func _settlement_find_layout() -> Dictionary:
	# Each lot includes the full mesh footprint and any ambient movement around it.
	var local_lots := [
		Vector3(-4.4,2.55,-1.0),Vector3(4.2,2.05,-1.2),
		Vector3(0.0,2.85,5.6),Vector3(6.35,2.75,3.4),
		Vector3(-1.8,1.1,-3.7),Vector3(-5.3,1.15,1.2),
		Vector3(5.5,1.45,-3.1),Vector3(-2.1,1.35,7.6),
		Vector3(-1.9,1.2,2.1),Vector3(3.0,1.5,3.7)]
	var candidates: Array[Dictionary] = []
	for iz in range(17):
		for ix in range(25):
			var p:=Vector3(lerpf(-world_size*0.44,world_size*0.44,float(ix)/24.0),0.0,lerpf(-world_size*0.30,world_size*0.30,float(iz)/16.0))
			var clearance := _route_clearance(p)
			if clearance>4.0: candidates.append({"center":p,"clearance":clearance})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.clearance>b.clearance)
	for settlement_scale in [1.0,0.85,0.70,0.60]:
		var best: Dictionary = {}
		var best_score := -INF
		for candidate in candidates:
			for quarter_turn in range(4):
				var rotation_basis := Basis(Vector3.UP,float(quarter_turn)*PI*0.5).scaled(Vector3.ONE*settlement_scale)
				var transform := Transform3D(rotation_basis,candidate.center)
				var valid := true
				var lots: Array[Dictionary] = []
				var penalty := 0.0
				for local_lot in local_lots:
					var p: Vector3=transform*Vector3(local_lot.x,0.0,local_lot.z)
					var radius: float=local_lot.y*settlement_scale
					if absf(p.x)+radius>world_size*0.5-0.2 or absf(p.z)+radius>world_size*0.36-0.2 or _route_clearance(p)<radius+ROAD_OUTER_WIDTH*0.5+0.35:
						valid=false
						break
					lots.append({"position":Vector2(p.x,p.z),"radius":radius})
					for obstacle in build_obstacles:
						if Vector2(p.x,p.z).distance_to(obstacle.position)<radius+float(obstacle.radius):
							var cave_obstacle: bool=obstacle.position.distance_to(Vector2(route_points[0].x,route_points[0].z))<0.1 or obstacle.position.distance_to(Vector2(route_points[-1].x,route_points[-1].z))<0.1
							if cave_obstacle: valid=false
							else: penalty+=0.15
				if valid:
					var score: float=float(candidate.clearance)-penalty
					if score>best_score:
						best_score=score
						best={"transform":transform,"lots":lots}
		if not best.is_empty(): return best
	return {}

func _build_wildlife() -> void:
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var origin := Vector3(side*world_size*0.22,5.0+float(i)*0.65,side*world_size*0.13)
		_create_ambient_bird(terrain_root,origin,float(i)*2.7,Color.WHITE)
	var made := 0
	for attempt in range(100):
		if made>=2:
			break
		var origin := Vector3(rng.randf_range(-world_size*0.42,world_size*0.42),0.01,rng.randf_range(-world_size*0.29,world_size*0.29))
		if _route_clearance(origin)<4.5:
			continue
		var clear := true
		for obstacle in build_obstacles:
			if Vector2(origin.x,origin.z).distance_to(obstacle.position)<float(obstacle.radius)+1.8:
				clear=false
				break
		if not clear:
			continue
		_create_ambient_lizard(terrain_root,origin,float(made)*3.2)
		made+=1
	# Dense routes still have usable meadow. Fall back to the same physical
	# clearance checks on a bounded grid instead of sampling only one route bend.
	if made<2:
		for iz in range(17):
			for ix in range(25):
				if made>=2: break
				var origin:=Vector3(lerpf(-world_size*0.43,world_size*0.43,float(ix)/24.0),0.01,lerpf(-world_size*0.29,world_size*0.29,float(iz)/16.0))
				if _route_clearance(origin)<3.4: continue
				var clear:=true
				for obstacle in build_obstacles:
					if Vector2(origin.x,origin.z).distance_to(obstacle.position)<float(obstacle.radius)+1.4:
						clear=false
						break
				for other in ambient_lizards:
					if origin.distance_to(other.origin)<2.0: clear=false
				if clear:
					_create_ambient_lizard(terrain_root,origin,float(made)*3.2)
					made+=1

func _route_clearance(position: Vector3) -> float:
	var closest := INF
	for i in range(1,route_points.size()):
		closest = minf(closest,_distance_to_segment(position,route_points[i-1],route_points[i]))
	return closest

func _build_cottage(parent: Node3D, position: Vector3, plaster: Material, timber: Material, wood: Material, roof: Material, window: Material, scale: float) -> void:
	var cottage := Node3D.new()
	cottage.name = "Cottage"
	cottage.position = position
	cottage.scale = Vector3.ONE*scale
	parent.add_child(cottage,true)
	_terrain_box(cottage,Vector3(0.0,1.0,0.0),Vector3(3.3,2.0,2.7),plaster)
	for x in [-1.47,1.47]:
		_terrain_box(cottage,Vector3(x,1.0,-1.38),Vector3(0.16,2.14,0.14),timber)
		_terrain_box(cottage,Vector3(x,1.0,1.38),Vector3(0.16,2.14,0.14),timber)
	for y in [0.16,1.92]:
		_terrain_box(cottage,Vector3(0.0,y,-1.39),Vector3(3.12,0.14,0.14),timber)
		_terrain_box(cottage,Vector3(0.0,y,1.39),Vector3(3.12,0.14,0.14),timber)
	_terrain_box(cottage,Vector3(-0.82,0.78,-1.38),Vector3(0.52,1.28,0.12),wood)
	_terrain_box(cottage,Vector3(0.0,0.70,-1.40),Vector3(0.64,1.36,0.12),timber)
	_terrain_box(cottage,Vector3(0.0,0.66,-1.475),Vector3(0.47,1.12,0.06),wood)
	_terrain_box(cottage,Vector3(0.82,1.20,-1.39),Vector3(0.46,0.48,0.12),timber)
	_terrain_box(cottage,Vector3(0.82,1.20,-1.47),Vector3(0.32,0.34,0.04),window)
	_terrain_box(cottage,Vector3(-1.62,1.25,0.15),Vector3(0.06,0.72,0.68),timber)
	_terrain_box(cottage,Vector3(-1.67,1.25,0.15),Vector3(0.04,0.51,0.47),window)
	for side in [-1.0,1.0]:
		_terrain_box(cottage,Vector3(side*0.83,2.46,0.0),Vector3(2.08,0.18,3.14),roof,Vector3(0.0,0.0,side*-0.43))
	for side in [-1.0,1.0]:
		_terrain_box(cottage,Vector3(side*0.76,2.49,-1.42),Vector3(2.0,0.12,0.13),timber,Vector3(0.0,0.0,side*-0.43))
	var chimney_mesh := CylinderMesh.new()
	chimney_mesh.top_radius = 0.18
	chimney_mesh.bottom_radius = 0.23
	chimney_mesh.height = 0.78
	chimney_mesh.radial_segments = 8
	var chimney := MeshInstance3D.new()
	chimney.mesh = chimney_mesh
	chimney.material_override = timber
	chimney.position = Vector3(0.92,2.96,0.56)
	cottage.add_child(chimney)
	build_obstacles.append({"position":Vector2(parent.global_position.x+position.x,parent.global_position.z+position.z),"radius":2.3*scale})

func _build_hamlet_garden(parent: Node3D, timber: Material, wood: Material) -> void:
	var biome_profile: Dictionary=world_art.get("profile")
	var frozen: bool=biome_profile.season=="winter"
	var soil := _terrain_material(Color(0.67,0.75,0.80) if frozen else Color(0.27,0.20,0.12))
	var leaf := _terrain_material(Color(0.46,0.43,0.30) if frozen else biome_profile.foliage_b)
	for row in range(3):
		var z := 2.55+float(row)*0.72
		_terrain_box(parent,Vector3(6.35,-0.075,z),Vector3(3.2,0.10,0.42),soil)
		for plant in range(7):
			var x := 5.0+float(plant)*0.45
			var stem := CylinderMesh.new()
			stem.top_radius = 0.035
			stem.bottom_radius = 0.06
			stem.height = (0.10+rng.randf()*0.08) if frozen else (0.34+rng.randf()*0.22)
			stem.radial_segments = 5
			var plant_node := MeshInstance3D.new()
			plant_node.mesh = stem
			plant_node.material_override = leaf
			plant_node.position = Vector3(x,0.16,z+rng.randf_range(-0.12,0.12))
			parent.add_child(plant_node)
	for x in [4.35,8.35]:
		_terrain_box(parent,Vector3(x,0.38,3.4),Vector3(0.12,0.76,2.9),timber)
	for z in [2.0,4.8]:
		_terrain_box(parent,Vector3(6.35,0.40,z),Vector3(4.0,0.12,0.12),wood)
	var path_stone := _terrain_material(Color(0.39,0.34,0.26))
	for step in range(9):
		var z := 0.7+float(step)*0.70
		var offset := sin(float(step)*0.48)*0.48
		_terrain_box(parent,Vector3(offset,-0.075,z),Vector3(0.52+rng.randf()*0.18,0.07,0.34+rng.randf()*0.11),path_stone,Vector3(0.0,rng.randf_range(-0.20,0.20),rng.randf_range(-0.06,0.06)))

func _create_ambient_bird(parent: Node3D, origin: Vector3, phase: float, _color: Color) -> void:
	ambient_birds.append(world_art.create_bird(parent,origin,phase))

func _create_ambient_lizard(parent: Node3D, origin: Vector3, phase: float) -> void:
	ambient_lizards.append(world_art.create_ground_animal(parent,origin,phase))

func _ambient_capsule(parent: Node3D, radius: float, height: float, material: Material, position: Vector3) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	capsule.radial_segments = 12
	capsule.rings = 5
	var instance := MeshInstance3D.new()
	instance.mesh = capsule
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance

func _ambient_sphere(parent: Node3D, radius: float, material: Material, position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius*2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.material_override = material
	instance.position = position
	instance.scale = scale
	parent.add_child(instance)
	return instance

func _create_ambient_villager(parent: Node3D, origin: Vector3, clothing_color: Color, hat_color: Color, activity: String, phase: float) -> void:
	var root := Node3D.new()
	root.name = "BackgroundVillager_"+activity
	root.position = origin
	parent.add_child(root)
	var biome_profile: Dictionary=world_art.get("profile")
	var wardrobe: String=biome_profile.wardrobe
	root.set_meta("wardrobe",wardrobe)
	root.set_meta("chore",activity)
	var clothing := _terrain_material(clothing_color)
	var skin := _terrain_material(Color(0.68,0.48,0.36))
	var hair := _terrain_material(Color(0.12,0.09,0.07))
	var hat := _terrain_material(hat_color)
	var boot := _terrain_material(Color(0.16,0.13,0.10))
	var belt := _terrain_material(Color(0.34,0.23,0.13))
	var torso := Node3D.new()
	torso.position = Vector3(0.0,0.90,0.0)
	root.add_child(torso)
	_ambient_capsule(torso,0.19,0.66,clothing,Vector3(0.0,0.25,0.0))
	_ambient_sphere(torso,0.15,skin,Vector3(0.0,0.76,0.0),Vector3(0.88,1.0,0.82))
	_ambient_sphere(torso,0.158,hair,Vector3(0.0,0.86,0.025),Vector3(1.02,0.48,0.96))
	_terrain_box(torso,Vector3(0.0,0.40,-0.145),Vector3(0.29,0.34,0.045),belt)
	if wardrobe in ["fur","headwrap"]:
		var cap:=SphereMesh.new();cap.radius=0.18;cap.height=0.32;cap.radial_segments=16;cap.rings=8
		var cap_node:=MeshInstance3D.new();cap_node.mesh=cap;cap_node.material_override=hat;cap_node.position=Vector3(0,0.90,0.02);torso.add_child(cap_node)
		var scarf:=TorusMesh.new();scarf.inner_radius=0.115;scarf.outer_radius=0.205;scarf.rings=8;scarf.ring_segments=16
		var scarf_node:=MeshInstance3D.new();scarf_node.mesh=scarf;scarf_node.material_override=hat;scarf_node.position=Vector3(0,0.64,0.01);torso.add_child(scarf_node)
		if wardrobe=="fur":
			var coat:=CylinderMesh.new();coat.top_radius=0.19;coat.bottom_radius=0.28;coat.height=0.70;coat.radial_segments=14
			var coat_node:=MeshInstance3D.new();coat_node.mesh=coat;coat_node.material_override=clothing;coat_node.position=Vector3(0,0.13,0.015);torso.add_child(coat_node)
			_ambient_sphere(torso,0.22,hat,Vector3(0,0.58,0.03),Vector3(1.30,0.30,1.0))
	elif activity in ["mow","harvest","gather"]:
		var brim := CylinderMesh.new()
		brim.top_radius=0.24;brim.bottom_radius=0.24;brim.height=0.045;brim.radial_segments=16
		var brim_node := MeshInstance3D.new();brim_node.mesh=brim;brim_node.material_override=hat;brim_node.position=Vector3(0.0,0.86,0.0);torso.add_child(brim_node)
		var crown := CylinderMesh.new();crown.top_radius=0.13;crown.bottom_radius=0.18;crown.height=0.23;crown.radial_segments=12
		var crown_node := MeshInstance3D.new();crown_node.mesh=crown;crown_node.material_override=hat;crown_node.position=Vector3(0.0,0.98,0.0);torso.add_child(crown_node)
	elif activity=="herbs":
		_terrain_box(torso,Vector3(0.0,0.18,-0.205),Vector3(0.26,0.32,0.08),hat)
	if wardrobe in ["rain_cape","ash_cape","wool"]:
		var cloak:=CylinderMesh.new();cloak.top_radius=0.14;cloak.bottom_radius=0.28;cloak.height=0.75;cloak.radial_segments=14
		var cloak_node:=MeshInstance3D.new();cloak_node.mesh=cloak;cloak_node.material_override=hat;cloak_node.position=Vector3(0,0.24,0.10);cloak_node.scale=Vector3(1.0,1.0,0.58);torso.add_child(cloak_node)
	var arms: Array[Node3D] = []
	for side in [-1.0,1.0]:
		var arm := Node3D.new()
		arm.position=Vector3(side*0.21,0.58,0.0)
		torso.add_child(arm)
		_ambient_capsule(arm,0.064,0.48,clothing,Vector3(0.0,-0.20,-0.01))
		_ambient_sphere(arm,0.064,skin,Vector3(0.0,-0.44,-0.035),Vector3.ONE)
		arms.append(arm)
	var legs: Array[Node3D] = []
	for side in [-1.0,1.0]:
		var leg := Node3D.new()
		leg.position=Vector3(side*0.095,0.59,0.0)
		root.add_child(leg)
		_ambient_capsule(leg,0.078,0.54,boot,Vector3(0.0,-0.26,-0.015))
		_terrain_box(leg,Vector3(0.0,-0.52,-0.08),Vector3(0.15,0.09,0.25),boot)
		legs.append(leg)
	if activity in ["mow","rake","shovel"]:
		var handle := CylinderMesh.new();handle.top_radius=0.025;handle.bottom_radius=0.035;handle.height=0.82;handle.radial_segments=7
		var handle_node := MeshInstance3D.new();handle_node.mesh=handle;handle_node.material_override=belt;handle_node.position=Vector3(0.0,-0.40,-0.08);handle_node.rotation.x=0.22;arms[1].add_child(handle_node)
		var tool:=_terrain_material(Color(0.32,0.35,0.34),0.45)
		_terrain_box(arms[1],Vector3(0.0,-0.80,-0.09),Vector3(0.24,0.18,0.045) if activity=="shovel" else Vector3(0.28,0.055,0.08),tool,Vector3(0.0,0.0,-0.16))
		if activity=="rake":
			for tooth in range(5): _terrain_box(arms[1],Vector3(-0.12+float(tooth)*0.06,-0.84,-0.12),Vector3(0.018,0.12,0.025),tool)
	elif activity in ["fish","ice_fish"]:
		var rod := CylinderMesh.new();rod.top_radius=0.012;rod.bottom_radius=0.022;rod.height=1.10;rod.radial_segments=6
		var rod_node := MeshInstance3D.new();rod_node.mesh=rod;rod_node.material_override=belt;rod_node.position=Vector3(0.0,-0.37,-0.10);rod_node.rotation.x=-0.48;arms[1].add_child(rod_node)
	elif activity=="firewood":
		for log_index in range(3):
			var log_mesh:=CylinderMesh.new();log_mesh.top_radius=0.065;log_mesh.bottom_radius=0.07;log_mesh.height=0.50;log_mesh.radial_segments=8
			var log_node:=MeshInstance3D.new();log_node.mesh=log_mesh;log_node.material_override=belt;log_node.position=Vector3(0.0,-0.37,-0.11-float(log_index)*0.10);log_node.rotation.z=PI*0.5;arms[0].add_child(log_node)
	elif activity in ["water","harvest","gather"]:
		var bucket:=CylinderMesh.new();bucket.top_radius=0.12;bucket.bottom_radius=0.09;bucket.height=0.22;bucket.radial_segments=12
		var bucket_node:=MeshInstance3D.new();bucket_node.mesh=bucket;bucket_node.material_override=hat;bucket_node.position=Vector3(0,-0.54,-0.04);arms[0].add_child(bucket_node)
	var walking: bool=activity in ["mow","rake","shovel","gather","water","firewood"]
	ambient_people.append({"root":root,"torso":torso,"arms":arms,"legs":legs,"origin":origin,"phase":phase,"activity":activity,"walking":walking,"radius":0.70 if walking else 0.16,"speed":1.0 if walking else 1.6})

func _create_ambient_goat(parent: Node3D, origin: Vector3, phase: float) -> void:
	var root := Node3D.new()
	root.name="BackgroundGoat"
	root.position=origin
	parent.add_child(root)
	var biome_profile: Dictionary=world_art.get("profile")
	root.set_meta("species","winter_mountain_goat" if biome_profile.season=="winter" else "domestic_goat")
	var wool := _terrain_material(Color(0.78,0.80,0.73) if biome_profile.season=="winter" else Color(0.66,0.61,0.48))
	var wool_light := _terrain_material(Color(0.86,0.86,0.78) if biome_profile.season=="winter" else Color(0.77,0.72,0.58))
	var skin := _terrain_material(Color(0.37,0.28,0.21))
	var horn := _terrain_material(Color(0.78,0.72,0.54))
	_ambient_sphere(root,0.34,wool,Vector3(0.0,0.52,0.0),Vector3(1.42,0.82,0.78))
	_ambient_sphere(root,0.19,wool_light,Vector3(0.32,0.69,-0.015),Vector3(0.84,1.04,0.82))
	_ambient_sphere(root,0.10,skin,Vector3(0.46,0.65,-0.13),Vector3(0.86,0.64,0.70))
	for side in [-1.0,1.0]:
		_ambient_sphere(root,0.11,wool_light,Vector3(0.29+side*0.08,0.78,0.0),Vector3(1.2,0.35,0.42))
		var horn_mesh := CylinderMesh.new();horn_mesh.bottom_radius=0.06;horn_mesh.top_radius=0.005;horn_mesh.height=0.18;horn_mesh.radial_segments=7
		var horn_node := MeshInstance3D.new();horn_node.mesh=horn_mesh;horn_node.material_override=horn;horn_node.position=Vector3(0.26+side*0.09,0.90,0.015);horn_node.rotation.z=side*-0.35;root.add_child(horn_node)
		_ambient_sphere(root,0.025,_terrain_material(Color(0.04,0.035,0.03)),Vector3(0.43,0.72,side*0.13),Vector3.ONE)
	var legs: Array[Node3D] = []
	for x in [-0.24,0.23]:
		for z in [-0.13,0.14]:
			var leg := Node3D.new();leg.position=Vector3(x,0.42,z);root.add_child(leg)
			_ambient_capsule(leg,0.045,0.39,skin,Vector3(0.0,-0.17,0.0));legs.append(leg)
	ambient_animals.append({"root":root,"legs":legs,"origin":origin,"phase":phase,"radius":0.48,"speed":1.05})

func _animate_background_life(delta: float) -> void:
	ambient_clock += delta
	for person in ambient_people:
		person.phase = float(person.phase)+delta*float(person.speed)
		var phase := float(person.phase)
		var activity: String = person.activity
		var origin: Vector3 = person.origin
		var root: Node3D = person.root
		var arms: Array = person.arms
		var legs: Array = person.legs
		if bool(person.get("walking",activity=="mow")):
			root.position=origin+Vector3(cos(phase)*float(person.radius),0.0,sin(phase*0.7)*0.34)
			root.rotation.y=atan2(-sin(phase),cos(phase))
			arms[0].rotation.x=sin(phase*2.0)*0.28
			arms[1].rotation.x=-0.35+sin(phase*2.0+PI)*0.34
			legs[0].rotation.x=sin(phase*2.0)*0.35
			legs[1].rotation.x=-sin(phase*2.0)*0.35
		elif activity in ["herbs","harvest"]:
			person.torso.rotation.x=0.08+maxf(0.0,sin(phase))*0.20
			arms[0].rotation.x=-0.20+sin(phase*1.4)*0.12
			arms[1].rotation.x=-0.62+sin(phase*1.8)*0.18
		else:
			person.torso.rotation.x=sin(phase*0.55)*0.035
			arms[0].rotation.x=sin(phase*0.8)*0.04
			arms[1].rotation.x=-0.62+maxf(0.0,sin(phase*0.7))*0.20
		for leg in legs:
			if not bool(person.get("walking",activity=="mow")): leg.rotation.x=sin(phase*0.65)*0.025
	for animal in ambient_animals:
		animal.phase=float(animal.phase)+delta*float(animal.speed)
		var phase := float(animal.phase)
		var root: Node3D=animal.root
		var origin: Vector3=animal.origin
		root.position=origin+Vector3(cos(phase)*float(animal.radius),0.0,sin(phase*0.72)*0.20)
		root.rotation.y=atan2(-sin(phase),cos(phase))
		var legs: Array=animal.legs
		for i in range(legs.size()): legs[i].rotation.x=sin(phase*2.0+float(i%2)*PI)*0.24
	for bird in ambient_birds:
		bird.phase=float(bird.phase)+delta*float(bird.speed)
		var phase := float(bird.phase)
		var origin: Vector3=bird.origin
		var radius := float(bird.radius)
		var root: Node3D=bird.root
		root.position=origin+Vector3(cos(phase)*radius,sin(phase*1.7)*0.32,sin(phase*0.72)*radius*0.58)
		var dx := -sin(phase)*radius
		var dz := cos(phase*0.72)*radius*0.72*0.58
		root.rotation.y=atan2(-dz,dx)
		var wings: Array=bird.wings
		var flap := sin(ambient_clock*float(bird.get("flap_rate",7.3))+phase)*float(bird.get("flap_size",0.72))
		wings[0].rotation.x=flap
		wings[1].rotation.x=-flap
	for lizard in ambient_lizards:
		lizard.phase=float(lizard.phase)+delta*float(lizard.speed)
		var phase := float(lizard.phase)
		var origin: Vector3=lizard.origin
		var root: Node3D=lizard.root
		root.position=origin+Vector3(cos(phase)*float(lizard.radius),0.0,sin(phase*0.76)*0.38)
		if lizard.get("species","")=="hare": root.position.y+=maxf(0.0,sin(phase*5.0))*0.11
		var dx := -sin(phase)*float(lizard.radius)
		var dz := cos(phase*0.76)*0.76*0.38
		root.rotation.y=atan2(-dz,dx)
		var legs: Array=lizard.legs
		for i in range(legs.size()):
			legs[i].rotation.z=sin(phase*7.0+float(i%2)*PI)*0.42
		var tail: MeshInstance3D=lizard.tail
		tail.rotation.y=sin(phase*1.7)*0.20

func _build_cave(point: Vector3, entrance: bool) -> void:
	# Mark the full footprint of the cave mouth as blocked for placement.
	build_obstacles.append({"position":Vector2(point.x,point.z),"radius":5.65})
	var gate := Node3D.new()
	gate.position = point + Vector3.UP*0.2
	var direction := (route_points[1]-route_points[0]).normalized() if entrance else (route_points[-1]-route_points[-2]).normalized()
	gate.rotation.y = atan2(direction.x,direction.z)
	terrain_root.add_child(gate)
	var arch := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.86
	torus.rings = 12
	torus.ring_segments = 20
	arch.mesh = torus
	arch.rotation.x = PI*0.5
	arch.position.y = 1.3
	arch.scale = Vector3(7.2,1.1,3.9)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = [Color(0.30,0.27,0.20),Color(0.29,0.21,0.16),Color(0.39,0.44,0.45)][arena%3]
	stone.roughness = 1.0
	arch.material_override = stone
	gate.add_child(arch)
	var darkness := MeshInstance3D.new()
	var disc := SphereMesh.new()
	disc.radial_segments = 16
	disc.rings = 8
	darkness.mesh = disc
	darkness.scale = Vector3(4.4,5.0,0.45)
	darkness.position = Vector3(0,1.65,-1.1 if entrance else 1.1)
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.025,0.022,0.018)
	dark_mat.roughness = 1.0
	darkness.material_override = dark_mat
	gate.add_child(darkness)
	for side in [-1.0,1.0]:
		var column := MeshInstance3D.new()
		var rock := CylinderMesh.new()
		rock.top_radius = 0.72
		rock.bottom_radius = 1.0
		rock.height = 2.3
		rock.radial_segments = 7
		column.mesh = rock
		column.position = Vector3(side*5.0,1.05,0)
		column.material_override = stone
		gate.add_child(column)

func _near_route(point: Vector3, margin: float) -> bool:
	for i in range(1,route_points.size()):
		if _distance_to_segment(point,route_points[i-1],route_points[i]) < margin:
			return true
	return false

func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b-a
	var t := clampf((p-a).dot(ab)/maxf(0.001,ab.length_squared()),0.0,1.0)
	return p.distance_to(a+ab*t)

func _build_hud() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root)
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = 70
	top.add_theme_stylebox_override("panel",_panel_style(Color(0.035,0.055,0.058),Color(0.60,0.45,0.22),1))
	root.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation",5)
	top.add_child(top_row)
	var title := Label.new()
	title.text = "✦  КОДИ TD"
	hud_title = title
	title.add_theme_font_size_override("font_size",19)
	title.add_theme_color_override("font_color",Color(0.91,0.74,0.43))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)
	made_by_label=Label.new()
	made_by_label.text="Made by Alex"
	made_by_label.position=Vector2(16,46)
	made_by_label.add_theme_font_size_override("font_size",10)
	made_by_label.add_theme_color_override("font_color",Color(0.66,0.68,0.64))
	made_by_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(made_by_label)
	hud_gold = _stat_label(top_row,"ЗОЛОТО")
	hud_gold.tooltip_text = "Стартовый запас кампании: 360 золота."
	hud_wave = _stat_label(top_row,"ВОЛНА")
	hud_lives = _stat_label(top_row,"РУБЕЖ")
	hud_arena = _stat_label(top_row,"АРЕНА")
	var menu_button := _button("☰ Меню",72)
	menu_button.pressed.connect(_show_main_menu)
	top_row.add_child(menu_button)
	var music_btn := _button("♫ Музыка",72)
	music_toggle_button = music_btn
	music_btn.pressed.connect(_toggle_music)
	top_row.add_child(music_btn)
	music_slider = _add_top_volume_control(top_row,"♫ МУЗЫКА",music_volume,_set_music_volume,true)
	sfx_slider = _add_top_volume_control(top_row,"✦ ЭФФЕКТЫ",sfx_volume,_set_sfx_volume,false)
	fullscreen_button = _button("⛶ Экран",76)
	fullscreen_button.tooltip_text = "Переключить полноэкранный режим · F11"
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	top_row.add_child(fullscreen_button)
	side_panel = PanelContainer.new()
	side_panel.anchor_left = 1.0
	side_panel.anchor_right = 1.0
	side_panel.anchor_bottom = 1.0
	side_panel.offset_top = 78
	side_panel.offset_right = -10
	side_panel.offset_bottom = -10
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_theme_stylebox_override("panel",FrostUI.frame_style())
	root.add_child(side_panel)
	var scroll := ScrollContainer.new()
	side_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size.x = 0
	scroll.add_child(column)
	FrostUI.section(column,"АРСЕНАЛ МАГОВ")
	for i in range(HEROES.size()):
		var hero: Dictionary = HEROES[i]
		var button := TowerCard.new()
		_style_button(button)
		button.text = "✧  %s  ·  %d ✦\n%s" % [hero.short,hero.price,CARD_HINTS[i]]
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size",13)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var reach_hint := "Аура: радиус %.1f м · усиление +30%%" % hero.aura_range if float(hero.aura_range) > 0.0 else "Урон %d · Дальность %.1f м\nАтак в секунду: %.2f" % [roundi(hero.damage),hero.range,1.0/maxf(0.01,hero.rate)]
		button.tooltip_text = "%s\n%s\n%s\nV ранг: %s\nСтоимость: %d золота" % [hero.short,reach_hint,hero.description,CombatBalance.capstone_description(i),hero.price]
		button.pressed.connect(_select_type.bind(i))
		column.add_child(button)
		card_buttons.append(button)
	var controls := HBoxContainer.new()
	start_button = _button("▶ Начать волну",-1)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(_start_wave)
	controls.add_child(start_button)
	pause_button = _button("Ⅱ Пауза",95)
	pause_button.pressed.connect(_toggle_pause)
	controls.add_child(pause_button)
	column.add_child(controls)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation",4)
	var speed_text := Label.new()
	speed_text.text = "ТЕМП ИГРЫ"
	speed_text.custom_minimum_size.x = 86
	speed_text.add_theme_font_size_override("font_size",10)
	speed_text.add_theme_color_override("font_color",Color(0.62,0.77,0.82))
	speed_row.add_child(speed_text)
	speed_select = OptionButton.new()
	speed_select.add_item("1×",1)
	speed_select.add_item("2×",2)
	speed_select.add_item("3×",3)
	speed_select.select(0)
	speed_select.custom_minimum_size = Vector2(0,30)
	speed_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_select.add_theme_font_size_override("font_size",12)
	speed_select.add_theme_color_override("font_color",Color(0.91,0.88,0.78))
	speed_select.add_theme_stylebox_override("normal",FrostUI.button_style())
	speed_select.add_theme_stylebox_override("hover",FrostUI.button_style("hover"))
	speed_select.add_theme_stylebox_override("pressed",FrostUI.button_style("pressed"))
	speed_select.get_popup().add_theme_stylebox_override("panel",FrostUI.frame_style())
	speed_select.get_popup().add_theme_color_override("font_color",Color(0.88,0.93,0.94))
	speed_select.item_selected.connect(_set_speed)
	speed_row.add_child(speed_select)
	column.add_child(speed_row)
	FrostUI.section(column,"РАЗВЕДКА И УЛУЧШЕНИЯ")
	var selection_panel := PanelContainer.new()
	selection_panel.add_theme_stylebox_override("panel",FrostUI.inset_style())
	column.add_child(selection_panel)
	selection_label = Label.new()
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.custom_minimum_size.y = 100
	selection_label.add_theme_font_size_override("font_size",13)
	selection_label.add_theme_color_override("font_color",Color(0.85,0.90,0.91))
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_panel.add_child(selection_label)
	var action_row := HBoxContainer.new()
	upgrade_button = _button("Улучшить",-1)
	upgrade_button.custom_minimum_size.y = 36
	upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_button.pressed.connect(_upgrade)
	action_row.add_child(upgrade_button)
	sell_button = _button("Продать",-1)
	sell_button.custom_minimum_size.y = 36
	sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_button.pressed.connect(_sell)
	action_row.add_child(sell_button)
	column.add_child(action_row)
	var aura_row := HBoxContainer.new()
	aura_damage_button = _button("Аура урона",-1)
	aura_damage_button.custom_minimum_size.y = 32
	aura_damage_button.toggle_mode = true
	aura_damage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aura_damage_button.pressed.connect(_set_aura.bind("damage"))
	aura_row.add_child(aura_damage_button)
	aura_speed_button = _button("Аура скорости",-1)
	aura_speed_button.custom_minimum_size.y = 32
	aura_speed_button.toggle_mode = true
	aura_speed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aura_speed_button.pressed.connect(_set_aura.bind("speed"))
	aura_row.add_child(aura_speed_button)
	column.add_child(aura_row)
	var summary := Label.new()
	hud_summary = summary
	summary.text = "15 волн · 18 арен\nЛКМ — построить/выбрать · ПКМ — отмена/камера\nКолесо — зум · Space — волна · P — пауза"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size",10)
	summary.add_theme_color_override("font_color",Color(0.60,0.72,0.77))
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(summary)
	status_label = Label.new()
	status_label.anchor_top = 1.0
	status_label.anchor_bottom = 1.0
	status_label.offset_top = -26
	status_label.offset_bottom = -4
	status_label.offset_left = 8
	status_label.add_theme_color_override("font_color",Color(0.78,0.74,0.62))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_label)

func _build_main_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.z_index = 100
	ui_layer.add_child(menu_root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.012,0.022,0.025,0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440,310)
	panel.add_theme_stylebox_override("panel",FrostUI.frame_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	panel.add_child(column)
	var title := Label.new()
	title.text = "РУБЕЖ СРЕДИЗЕМЬЯ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",25)
	title.add_theme_color_override("font_color",Color(0.94,0.76,0.43))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Чёрный клевер · орден защитников\nMade by Alex"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color",Color(0.72,0.77,0.75))
	column.add_child(subtitle)
	menu_loading_label = Label.new()
	menu_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_loading_label.add_theme_color_override("font_color",Color(0.78,0.74,0.62))
	column.add_child(menu_loading_label)
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation",12)
	column.add_child(fps_row)
	var fps_label := Label.new()
	fps_label.text = "Частота кадров"
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	frame_limit_select = OptionButton.new()
	frame_limit_select.add_theme_font_size_override("font_size",13)
	for state in ["normal","hover","pressed","disabled","focus"]:
		frame_limit_select.add_theme_stylebox_override(state,FrostUI.button_style(state))
	for value in [30,60,120,0]:
		frame_limit_select.add_item("Без ограничения" if value==0 else "%d FPS"%value,value)
	frame_limit_select.select([30,60,120,0].find(frame_limit))
	frame_limit_select.item_selected.connect(_on_frame_limit_selected)
	fps_row.add_child(frame_limit_select)
	menu_continue_button = _button("Продолжить игру",-1)
	menu_continue_button.pressed.connect(_continue_game)
	column.add_child(menu_continue_button)
	menu_new_button = _button("Начать новую кампанию",-1)
	menu_new_button.pressed.connect(_new_campaign)
	column.add_child(menu_new_button)
	var exit_button := _button("Выйти",-1)
	exit_button.pressed.connect(func(): get_tree().quit())
	column.add_child(exit_button)

func _update_ui_layout() -> void:
	if side_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var side_width := _side_panel_width()
	side_panel.offset_left = -side_width-10.0
	if hud_title != null:
		hud_title.visible = viewport_size.x >= 1240.0
	if made_by_label != null:
		made_by_label.visible=viewport_size.x>=1240.0
	if fullscreen_button != null:
		fullscreen_button.visible = viewport_size.x >= 1120.0
	if hud_summary != null:
		hud_summary.visible = viewport_size.y >= 820.0
	# The same controls remain in place at smaller logical window heights. The
	# panel does not auto-scroll away from the selected tower or aura controls.
	var compact := viewport_size.y < 800.0
	for card in card_buttons:
		card.custom_minimum_size.y = 35.0 if compact else 44.0
		card.add_theme_font_size_override("font_size",12 if compact else 13)
	if selection_label != null:
		selection_label.custom_minimum_size.y = 82.0 if compact else 100.0
		selection_label.add_theme_font_size_override("font_size",12 if compact else 13)
	if camera != null:
		camera_size = minf(camera_size,_camera_max_size())
		camera_zoom_goal = minf(camera_zoom_goal,_camera_max_size())
		_update_camera()

func _side_panel_width() -> float:
	return clampf(get_viewport().get_visible_rect().size.x*0.205,286.0,334.0)

func _show_main_menu() -> void:
	if menu_root == null:
		return
	menu_paused_game = wave_running and not paused
	if menu_paused_game:
		paused = true
		_sync_animation_speeds()
	menu_root.show()

func _continue_game() -> void:
	if not _initial_tower_models_ready():
		status_label.text = "Подожди: загружаются модели башен."
		return
	if menu_root != null:
		menu_root.hide()
	if menu_paused_game:
		paused = false
		_sync_animation_speeds()
	menu_paused_game = false
	_refresh_hud()

func _new_campaign() -> void:
	_reset_campaign()
	_continue_game()

func _stat_label(parent: Control, caption: String) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(68,48)
	panel.add_theme_stylebox_override("panel",_panel_style(Color(0.08,0.10,0.10),Color(0.42,0.34,0.21),1))
	var label := Label.new()
	label.text = "0\n"+caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",13)
	label.add_theme_color_override("font_color",Color(0.91,0.74,0.43))
	panel.add_child(label)
	parent.add_child(panel)
	return label

func _panel_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _button(text: String, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width,36)
	_style_button(button)
	return button

func _style_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size",12)
	button.add_theme_color_override("font_color",Color(0.91,0.88,0.78))
	button.add_theme_color_override("font_hover_color",Color(0.92,0.98,1.0))
	button.add_theme_color_override("font_disabled_color",Color(0.43,0.52,0.55))
	button.add_theme_color_override("font_pressed_color",Color(1.0,0.91,0.67))
	button.add_theme_stylebox_override("normal",FrostUI.button_style())
	button.add_theme_stylebox_override("hover",FrostUI.button_style("hover"))
	button.add_theme_stylebox_override("pressed",FrostUI.button_style("pressed"))
	button.add_theme_stylebox_override("disabled",FrostUI.button_style("disabled"))
	button.add_theme_stylebox_override("focus",_panel_style(Color(0.0,0.0,0.0,0.0),Color(0.83,0.73,0.45),1))

func _add_top_volume_control(parent: Control, caption: String, initial_value: float, callback: Callable, is_music: bool) -> HSlider:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 100.0
	box.add_theme_constant_override("separation",1)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size",8)
	label.add_theme_color_override("font_color",Color(0.77,0.78,0.73))
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",3)
	box.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = clampf(initial_value,0.0,100.0)
	slider.custom_minimum_size = Vector2(64,20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	row.add_child(slider)
	var percent := Label.new()
	percent.text = "%d%%" % roundi(initial_value)
	percent.custom_minimum_size.x = 32.0
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.add_theme_font_size_override("font_size",9)
	percent.add_theme_color_override("font_color",Color(0.91,0.74,0.43))
	row.add_child(percent)
	if is_music:
		music_volume_text = percent
	else:
		sfx_volume_text = percent
	parent.add_child(box)
	return slider

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	music_volume = clampf(float(config.get_value("audio","music_volume",music_volume)),0.0,100.0)
	sfx_volume = clampf(float(config.get_value("audio","sfx_volume",sfx_volume)),0.0,100.0)
	music_enabled = bool(config.get_value("audio","music_enabled",true))
	frame_limit = int(config.get_value("graphics","frame_limit",60))
	if frame_limit not in [0,30,60,120]: frame_limit=60

func _settings_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("audio","music_volume",music_volume)
	config.set_value("audio","sfx_volume",sfx_volume)
	config.set_value("audio","music_enabled",music_enabled)
	config.set_value("graphics","frame_limit",frame_limit)
	return config

func _save_settings() -> void:
	_settings_config().save(SETTINGS_PATH)

func _on_frame_limit_selected(index: int) -> void:
	frame_limit=frame_limit_select.get_item_id(index)
	_apply_frame_limit()
	_schedule_settings_save()

func _effective_frame_limit(focused: bool, menu_open: bool, game_paused: bool) -> int:
	if not focused: return 15
	if menu_open or game_paused: return mini(frame_limit,30) if frame_limit>0 else 30
	return frame_limit

func _apply_frame_limit() -> void:
	if benchmark_mode or DisplayServer.get_name()=="headless":
		Engine.max_fps=60 if benchmark_mode and OS.get_cmdline_user_args().has("--benchmark-capped") else 0
		return
	Engine.max_fps=_effective_frame_limit(focused_window,menu_root!=null and menu_root.visible,paused)

func _refresh_character_lods() -> void:
	if camera==null: return
	for tower in towers:
		CharacterLOD.update(tower.get("lod",{}),camera,force_high_detail or (not selected_tower.is_empty() and tower.node==selected_tower.node))
	for enemy in enemies:
		CharacterLOD.update(enemy.get("lod",{}),camera,force_high_detail or (not selected_enemy.is_empty() and enemy.node == selected_enemy.get("node")))
	for dead in enemy_death_visuals:
		CharacterLOD.update(dead.get("lod",{}),camera,force_high_detail)

func _schedule_settings_save() -> void:
	if settings_save_timer != null:
		settings_save_timer.start()
	else:
		_save_settings()

func _build_music() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.volume_db = _volume_to_db(music_volume)
	music_player.finished.connect(_advance_music)
	add_child(music_player)
	music_tracks = _collect_music_tracks()
	_advance_music()

func _collect_music_tracks() -> PackedStringArray:
	var bundled: Array[String] = []
	var external: Array[String] = []
	_append_resource_music("res://Assets/Music",bundled)
	var app_music_dir := OS.get_executable_path().get_base_dir().path_join("Music")
	_append_external_music(app_music_dir,external)
	_append_external_music("user://Music",external)
	bundled.sort()
	external.sort()
	var external_names := {}
	for path in external:
		external_names[path.get_file().to_lower()] = true
	var ordered := PackedStringArray()
	music_fallback_tracks.clear()
	for path in external:
		if not ordered.has(path): ordered.append(path)
	for path in bundled:
		if not external_names.has(path.get_file().to_lower()):
			ordered.append(path)
		else:
			for external_path in external:
				if external_path.get_file().to_lower() == path.get_file().to_lower():
					music_fallback_tracks[external_path] = path
	return ordered

func _append_resource_music(directory: String, tracks: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported directories contain the import/remap descriptor, not the
		# original audio file. ResourceLoader resolves that source name in PCK.
		var source_name := str(file).trim_suffix(".import").trim_suffix(".remap")
		if _is_supported_music_file(source_name):
			var path := directory.path_join(source_name)
			if ResourceLoader.exists(path) and not tracks.has(path):
				tracks.append(path)

func _append_external_music(directory: String, tracks: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		if _is_supported_music_file(file):
			tracks.append(directory.path_join(file))

func _is_supported_music_file(file_name: String) -> bool:
	return file_name.get_extension().to_lower() in ["mp3","ogg","wav"]

func _load_music_track(path: String) -> AudioStream:
	var stream: AudioStream
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		stream = ResourceLoader.load(path) as AudioStream
	else:
		if not FileAccess.file_exists(path):
			return null
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() < 16:
			return null
		match path.get_extension().to_lower():
			"mp3":
				# Reject obvious non-audio files before passing them to the decoder.
				var id3 := bytes[0] == 0x49 and bytes[1] == 0x44 and bytes[2] == 0x33
				var frame_sync := bytes[0] == 0xff and (bytes[1] & 0xe0) == 0xe0
				if not id3 and not frame_sync:
					return null
				var mp3 := AudioStreamMP3.new()
				mp3.data = bytes
				stream = mp3
			"ogg":
				if bytes.slice(0,4).get_string_from_ascii() != "OggS": return null
				stream = AudioStreamOggVorbis.load_from_buffer(bytes)
			"wav":
				if bytes.slice(0,4).get_string_from_ascii() != "RIFF": return null
				stream = AudioStreamWAV.load_from_buffer(bytes)
	return stream if stream != null and stream.get_length() > 0.01 else null

func _advance_music() -> void:
	var previous_path := music_tracks[music_track_index] if music_track_index >= 0 and music_track_index < music_tracks.size() else ""
	music_tracks = _collect_music_tracks()
	music_track_index = music_tracks.find(previous_path)
	if music_player == null or not music_enabled or music_tracks.is_empty():
		if music_player != null:
			music_player.stop()
		return
	for attempt in range(music_tracks.size()):
		music_track_index = (music_track_index+1)%music_tracks.size()
		var path := music_tracks[music_track_index]
		var stream := _load_music_track(path)
		if stream == null and music_fallback_tracks.has(path):
			stream = _load_music_track(music_fallback_tracks[path])
		if stream == null or stream.get_length() <= 0.01:
			continue
		stream = stream.duplicate() as AudioStream
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = false
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		music_player.stream = stream
		music_player.volume_db = _volume_to_db(music_volume)
		music_player.play()
		return
	music_player.stop()
	music_player.stream = null

func _build_sfx() -> void:
	for path in ATTACK_SFX:
		if ResourceLoader.exists(path):
			sfx_stream_cache[path] = load(path)
	for path in DEATH_SFX.values():
		if ResourceLoader.exists(path):
			sfx_stream_cache[path] = load(path)
	for i in range(16):
		var voice := AudioStreamPlayer3D.new()
		voice.name = "SFXVoice%d" % i
		voice.max_distance = 110.0
		voice.unit_size = 20.0
		voice.volume_db = _volume_to_db(sfx_volume)
		add_child(voice)
		sfx_players.append(voice)

func _play_sfx(path: String, world_position: Vector3) -> void:
	if sfx_volume <= 0.0 or sfx_players.is_empty():
		return
	var stream := sfx_stream_cache.get(path) as AudioStream
	if stream == null:
		return
	var voice := sfx_players[sfx_voice_cursor]
	sfx_voice_cursor = (sfx_voice_cursor+1)%sfx_players.size()
	voice.stop()
	voice.stream = stream
	voice.global_position = world_position
	voice.pitch_scale = rng.randf_range(0.96,1.04)
	voice.volume_db = _volume_to_db(sfx_volume)
	voice.play()

func _volume_to_db(value: float) -> float:
	if value <= 0.0:
		return -80.0
	return linear_to_db(pow(clampf(value/100.0,0.0,1.0),2.0))

func _set_music_volume(value: float) -> void:
	music_volume = value
	if music_volume_text != null:
		music_volume_text.text = "%d%%" % roundi(value)
	if music_player != null:
		music_player.volume_db = _volume_to_db(value)
	_schedule_settings_save()

func _set_sfx_volume(value: float) -> void:
	sfx_volume = value
	if sfx_volume_text != null:
		sfx_volume_text.text = "%d%%" % roundi(value)
	for voice in sfx_players:
		voice.volume_db = _volume_to_db(value)
	_schedule_settings_save()

func _toggle_music() -> void:
	if music_player == null:
		return
	music_enabled = not music_enabled
	if not music_enabled:
		music_player.stop()
	else:
		if music_player.stream == null:
			_advance_music()
		else:
			music_player.play()
	_schedule_settings_save()
	_refresh_hud()

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _refresh_hud() -> void:
	if hud_gold == null:
		return
	hud_gold.text = "%d\nЗОЛОТО" % gold
	hud_wave.text = "%d/15\nВОЛНА" % wave
	hud_lives.text = "%d\nРУБЕЖ" % lives
	hud_arena.text = "%d/18\nАРЕНА" % (arena+1)
	if music_toggle_button != null:
		music_toggle_button.text = "♫ Вкл" if music_enabled else "♫ Выкл"
	for i in range(card_buttons.size()):
		var model_path := "res://Assets/Heroes/%s_L1.glb" % HEROES[i].id
		card_buttons[i].disabled = gold < HEROES[i].price or not tower_model_cache.has(model_path)
		card_buttons[i].modulate = Color(1.0,0.88,0.62) if i == selected_type else Color.WHITE
	start_button.disabled = wave_running or not _initial_tower_models_ready()
	start_button.text = "Загружаются модели…" if not _initial_tower_models_ready() else "Волна идёт…" if wave_running else ("Начать кампанию заново" if game_over and arena>=17 else "Начать заново" if game_over else "Перейти на арену %d" % (arena+2) if stage_ready else "▶ Начать волну %d/15" % (wave+1))
	pause_button.disabled = not wave_running and enemies.is_empty()
	pause_button.text = "▶ Продолжить" if paused else "Ⅱ Пауза"

func _refresh_selection() -> void:
	if selection_label == null:
		return
	if not selected_enemy.is_empty() and (not enemies.has(selected_enemy) or not is_instance_valid(selected_enemy.get("node"))):
		_clear_enemy_selection()
	var has_enemy := not selected_enemy.is_empty()
	upgrade_button.visible = not has_enemy
	sell_button.visible = not has_enemy
	if has_enemy:
		upgrade_button.disabled = true
		sell_button.disabled = true
		aura_damage_button.hide()
		aura_speed_button.hide()
		selection_label.text = _enemy_inspection_text(selected_enemy)
		return
	var has_tower := not selected_tower.is_empty()
	var next_model_ready := false
	if has_tower and int(selected_tower.level) < 4:
		var next_path := "res://Assets/Heroes/%s_L%d.glb" % [HEROES[int(selected_tower.type)].id,int(selected_tower.level)+2]
		next_model_ready = tower_model_cache.has(next_path)
	upgrade_button.disabled = not has_tower or int(selected_tower.level) >= 4 or gold < int(HEROES[selected_tower.type].costs[int(selected_tower.level)]) or not next_model_ready
	sell_button.disabled = not has_tower
	var aura := has_tower and int(selected_tower.type) == 3
	aura_damage_button.visible = aura
	aura_speed_button.visible = aura
	if has_tower:
		var t: Dictionary = selected_tower
		var i: int = t.type
		var kind: Dictionary = HEROES[i]
		var next_form: String = FORMS[i][t.level+1] if int(t.level) < 4 else "максимальный ранг"
		if i == 3:
			var power := roundi(float(t.power)*100.0)
			var aura_mode := "выбери режим ниже"
			if t.aura == "damage":
				aura_mode = "УРОН +%d%%" % power
			elif t.aura == "speed":
				aura_mode = "СКОРОСТЬ +%d%%" % power
			var recipients := 0
			for other in towers:
				if int(other.type) != 3 and other.node.position.distance_to(t.node.position) <= float(t.aura_range):
					recipients += 1
			selection_label.text = "Ванесса · ранг %d/5\nАура: %s\nДальность: %.1f м · союзников: %d\n%s" % [t.level+1,aura_mode,t.aura_range,recipients,CombatBalance.capstone_description(i) if int(t.level) >= 4 else "Следующий: "+next_form]
			aura_damage_button.text = ("✓ " if t.aura == "damage" else "")+"Урон +%d%%" % power
			aura_speed_button.text = ("✓ " if t.aura == "speed" else "")+"Скорость +%d%%" % power
			aura_damage_button.tooltip_text = "Оранжевое основание и свет: увеличен урон поддерживаемых магов."
			aura_speed_button.tooltip_text = "Зелёное основание и свет: увеличена частота атак поддерживаемых магов."
		else:
			var bonuses := _aura_bonuses_for(t)
			var damage_text := _buffed_stat(float(t.damage),float(bonuses.damage_multiplier),false)
			var speed_text := _buffed_stat(1.0/maxf(0.01,float(t.rate)),float(bonuses.speed_multiplier),true)
			selection_label.text = "%s · ранг %d/5\nУрон: %s\nДальность: %.1f м · обзор: %.1f м\nСкорость: %s атак/с\n%s" % [kind.short,t.level+1,damage_text,t.range,t.detect_range,speed_text,CombatBalance.capstone_description(i) if int(t.level) >= 4 else "Следующий: "+next_form]
			if float(bonuses.armor_ignore) > 0.0:
				selection_label.text += "\nНить судьбы: −15% брони цели"
		upgrade_button.text = "Улучшить · %d ✦" % kind.costs[t.level] if t.level < 4 and next_model_ready else "Загрузка модели…" if t.level < 4 else "Максимальный ранг"
		sell_button.text = "Продать · %d ✦" % int(t.invested)
		aura_damage_button.set_pressed_no_signal(t.aura == "damage")
		aura_speed_button.set_pressed_no_signal(t.aura == "speed")
	else:
		if selected_type >= 0:
			var hero: Dictionary = HEROES[selected_type]
			selection_label.text = "%s · установка\n%s\nЗелёный — можно строить\nКрасный — дорога, препятствие или занято\nПКМ / Esc — отмена" % [hero.short,hero.description]
		else:
			selection_label.text = "Выбери мага и свободную площадку.\nЛКМ по магу — улучшения и характеристики.\nЛКМ по врагу — здоровье, броня и награда.\nНа 15-й волне — босс арены."
		upgrade_button.text = "Улучшить"
		sell_button.text = "Продать"
	if has_tower and side_scroll != null:
		side_scroll.ensure_control_visible(upgrade_button)

func _enemy_inspection_text(enemy: Dictionary) -> String:
	var armor := _effective_enemy_armor(enemy)
	var reduction := (1.0-CombatBalance.armor_multiplier(armor))*100.0
	var slow := float(enemy.get("slow",1.0)) if clock < float(enemy.get("slow_until",0.0)) else 1.0
	var state := "Движется по маршруту"
	if clock < float(enemy.get("burn_until",0.0)):
		state = "Горит · %.1f урона/с до брони" % float(enemy.get("burn_dps",0.0))
	if slow < 1.0:
		state += " · замедлен"
	if armor < float(enemy.get("armor",0.0)):
		state += " · броня ослаблена"
	return "%s\nЗдоровье: %d / %d\nБроня: %.1f · поглощает %.1f%%\nСкорость: %.1f м/с\nНаграда: %d ✦ · прорыв: −%d жизней\n%s" % [str(enemy.get("name",enemy.kind)),ceili(enemy.hp),ceili(enemy.max_hp),armor,reduction,float(enemy.speed)*slow,int(enemy.reward),int(enemy.get("life_damage",1)),state]

func _clear_enemy_selection() -> void:
	if not selected_enemy.is_empty():
		var ring: MeshInstance3D = selected_enemy.get("selection_ring") as MeshInstance3D
		if is_instance_valid(ring):
			ring.hide()
	selected_enemy = {}

func _select_enemy(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	_clear_enemy_selection()
	selected_tower = {}
	selected_type = -1
	_clear_build_ghost()
	selected_enemy = enemies[index]
	var ring: MeshInstance3D = selected_enemy.get("selection_ring") as MeshInstance3D
	if not is_instance_valid(ring):
		ring = MeshInstance3D.new()
		ring.name = "SelectedEnemyRing"
		var mesh := TorusMesh.new()
		var radius := clampf(float(selected_enemy.get("height",2.0))*0.27,0.65,1.55)
		mesh.inner_radius = radius
		mesh.outer_radius = radius+0.12
		mesh.rings = 6
		mesh.ring_segments = 48
		ring.mesh = mesh
		ring.material_override = _emissive_material(Color(1.0,0.31,0.10))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.12
		selected_enemy.node.add_child(ring)
		selected_enemy.selection_ring = ring
	ring.show()
	_sync_tower_selection_visuals()
	CharacterLOD.update(selected_enemy.get("lod",{}),camera,true)
	_refresh_selection()

func _find_enemy_at_screen(screen_point: Vector2) -> int:
	if camera == null:
		return -1
	var ray_origin := camera.project_ray_origin(screen_point)
	var ray_direction := camera.project_ray_normal(screen_point)
	var best_index := -1
	var best_distance := INF
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var height := float(enemy.get("height",2.0))
		var radius := clampf(height*0.25,0.45,1.5)
		var bounds := AABB(enemy.node.global_position+Vector3(-radius,0.05,-radius),Vector3(radius*2.0,height,radius*2.0))
		var hit = bounds.intersects_ray(ray_origin,ray_direction)
		if hit is Vector3:
			var separation := ray_origin.distance_to(hit)
			if separation < best_distance:
				best_distance = separation
				best_index = index
	return best_index

func _buffed_stat(base: float, multiplier: float, fractional: bool) -> String:
	var base_text := "%.2f" % base if fractional else str(roundi(base))
	if multiplier <= 1.001:
		return base_text
	var result := "%.2f" % (base*multiplier) if fractional else str(roundi(base*multiplier))
	return "%s (+%d%% → %s)" % [base_text,roundi((multiplier-1.0)*100.0),result]

func _select_type(index: int) -> void:
	if index < 0 or index >= HEROES.size() or not tower_model_cache.has("res://Assets/Heroes/%s_L1.glb" % HEROES[index].id):
		return
	_clear_enemy_selection()
	selected_type = index
	selected_tower = {}
	var pointer_position := _screen_to_ground(get_viewport().get_mouse_position())
	if pointer_position.x < 90000.0:
		mouse_world = pointer_position
	_sync_tower_selection_visuals()
	_create_build_ghost(index)
	_refresh_hud()
	_refresh_selection()

func _sync_tower_selection_visuals() -> void:
	for tower in towers:
		var selected: bool = not selected_tower.is_empty() and tower.node == selected_tower.get("node")
		CharacterLOD.update(tower.get("lod",{}),camera,force_high_detail or selected)
		if tower.range_mesh != null: tower.range_mesh.visible = selected
		if tower.selection_ring != null: tower.selection_ring.visible = selected
		if tower.selection_light != null: tower.selection_light.visible = selected
	_refresh_aura_indicators()

func _refresh_aura_indicators() -> void:
	for tower in towers:
		var bonuses := _aura_bonuses_for(tower)
		var damage_on := float(bonuses.damage_multiplier) > 1.001
		var speed_on := float(bonuses.speed_multiplier) > 1.001
		var damage_indicator: MeshInstance3D = tower.get("aura_damage_indicator") as MeshInstance3D
		var speed_indicator: MeshInstance3D = tower.get("aura_speed_indicator") as MeshInstance3D
		if damage_indicator != null:
			damage_indicator.visible = damage_on
		if speed_indicator != null:
			speed_indicator.visible = speed_on
		var light: OmniLight3D = tower.get("aura_light") as OmniLight3D
		if light != null:
			light.visible = damage_on or speed_on
			light.light_color = Color(1.0,0.43,0.12) if damage_on else Color(0.22,0.94,0.56)
		if int(tower.type) == 3 and tower.range_mesh != null:
			var material: StandardMaterial3D = tower.range_mesh.material_override
			material.albedo_color = Color(1.0,0.48,0.17,0.64) if tower.aura == "damage" else Color(0.25,0.94,0.60,0.64) if tower.aura == "speed" else Color(0.95,0.32,0.60,0.42)

func _find_tower_at(position: Vector3) -> int:
	var best_index := -1
	var best_distance := TOWER_SELECT_RADIUS
	var point := Vector2(position.x,position.z)
	for i in range(towers.size()):
		var tower: Dictionary = towers[i]
		var center := Vector2(tower.node.position.x,tower.node.position.z)
		var distance := point.distance_to(center)
		if distance <= best_distance:
			best_distance = distance
			best_index = i
	return best_index

func _select_tower(index: int) -> void:
	if index < 0 or index >= towers.size():
		return
	_clear_enemy_selection()
	selected_tower = towers[index]
	selected_type = -1
	_clear_build_ghost()
	_sync_tower_selection_visuals()
	_refresh_selection()

func _create_build_ghost(index: int) -> void:
	_clear_build_ghost()
	if index < 0:
		return
	var path := "res://Assets/Heroes/%s_L1.glb" % HEROES[index].id
	var packed := tower_model_cache.get(path) as PackedScene
	if packed == null:
		return
	build_ghost = Node3D.new()
	build_ghost.name = "PlacementGhost"
	var model := packed.instantiate()
	model.scale = Vector3.ONE*0.92
	build_ghost.add_child(model)
	_apply_ghost_material(model)
	ghost_range = MeshInstance3D.new()
	var ring := TorusMesh.new()
	var coverage_radius := _hero_coverage_radius(HEROES[index])
	ring.inner_radius = maxf(0.1,coverage_radius-0.1)
	ring.outer_radius = coverage_radius
	ring.ring_segments = 48
	ghost_range.mesh = ring
	ghost_range.position.y = 0.02
	ghost_range.material_override = ghost_material
	build_ghost.add_child(ghost_range)
	tower_root.add_child(build_ghost)
	_update_build_ghost()

func _apply_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = ghost_material
	for child in node.get_children():
		_apply_ghost_material(child)

func _clear_build_ghost() -> void:
	if build_ghost != null:
		build_ghost.queue_free()
	build_ghost = null
	ghost_range = null

func _update_build_ghost() -> void:
	if build_ghost == null or selected_type < 0:
		return
	build_ghost.position = Vector3(mouse_world.x,0,mouse_world.z)
	var inside_field := absf(mouse_world.x) <= world_size*0.5 and absf(mouse_world.z) <= world_size*0.36
	build_ghost.visible = inside_field
	if not inside_field:
		return
	var allowed := _valid_spot(mouse_world) and gold >= int(HEROES[selected_type].price)
	var tint := Color(0.18,0.80,0.34,0.44) if allowed else Color(0.88,0.19,0.14,0.44)
	ghost_material.albedo_color = tint
	ghost_material.emission_enabled = true
	ghost_material.emission = tint

func _set_aura(kind: String) -> void:
	if selected_tower.is_empty() or int(selected_tower.type) != 3 or kind not in ["damage","speed"]:
		return
	selected_tower.aura = kind
	_sync_tower_selection_visuals()
	_refresh_selection()
	status_label.text = "Аура выбрана: " + ("урон" if kind == "damage" else "скорость атаки")

func _place_tower(position: Vector3) -> void:
	if selected_type < 0:
		return
	var data: Dictionary = HEROES[selected_type]
	var model_path := "res://Assets/Heroes/%s_L1.glb" % data.id
	if not tower_model_cache.has(model_path):
		status_label.text = "Подожди: модель башни ещё загружается."
		return
	if gold < data.price:
		status_label.text = "Не хватает золота."
		return
	if not _valid_spot(position):
		status_label.text = "Здесь нельзя строить: выбери свободную землю вне дороги и объектов."
		return
	var tower := {"type":selected_type,"level":0,"damage":data.damage,"range":data.range,"detect_range":data.detect_range,"aura_range":data.aura_range,"rate":data.rate,"cooldown":0.3,"invested":data.price,"aura":"","power":0.30,"phase":rng.randf()*TAU,"node":Node3D.new(),"model_root":Node3D.new(),"animator":null,"idle_clip":"","attack_clip":"","range_mesh":null,"selection_ring":null,"selection_light":null,"aura_damage_indicator":null,"aura_speed_indicator":null,"aura_light":null}
	tower.node.position = Vector3(position.x,0,position.z)
	tower.node.add_child(tower.model_root)
	tower_root.add_child(tower.node)
	var range_visual := MeshInstance3D.new()
	var disk := TorusMesh.new()
	var coverage_radius := _tower_coverage_radius(tower)
	disk.inner_radius = maxf(0.1,coverage_radius-0.10)
	disk.outer_radius = coverage_radius
	disk.rings = 6
	disk.ring_segments = 64
	range_visual.mesh = disk
	range_visual.position.y = 0.03
	var range_mat := StandardMaterial3D.new()
	range_mat.albedo_color = Color(data.color.r,data.color.g,data.color.b,0.10)
	range_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	range_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_visual.material_override = range_mat
	range_visual.visible = false
	tower.node.add_child(range_visual)
	tower.range_mesh = range_visual
	var selection_ring := MeshInstance3D.new()
	var selection_mesh := TorusMesh.new()
	selection_mesh.inner_radius = 0.89
	selection_mesh.outer_radius = 1.05
	selection_mesh.ring_segments = 48
	selection_ring.mesh = selection_mesh
	selection_ring.position.y = 0.11
	var selection_material := StandardMaterial3D.new()
	selection_material.albedo_color = Color(1.0,0.72,0.22,0.92)
	selection_material.emission_enabled = true
	selection_material.emission = Color(1.0,0.43,0.08)
	selection_material.emission_energy_multiplier = 0.85
	selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ring.material_override = selection_material
	selection_ring.visible = false
	tower.node.add_child(selection_ring)
	tower.selection_ring = selection_ring
	tower.aura_damage_indicator = _create_aura_indicator(tower.node,0.74,0.83,Color(1.0,0.52,0.20))
	tower.aura_speed_indicator = _create_aura_indicator(tower.node,0.61,0.70,Color(0.30,0.94,0.60))
	var aura_light := OmniLight3D.new()
	aura_light.name = "AuraCharacterLight"
	aura_light.position.y = 1.1
	aura_light.light_energy = 0.45
	aura_light.omni_range = 2.9
	aura_light.shadow_enabled = false
	aura_light.visible = false
	tower.node.add_child(aura_light)
	tower.aura_light = aura_light
	var selection_light := OmniLight3D.new()
	selection_light.light_color = Color(1.0,0.72,0.38)
	selection_light.light_energy = 0.45
	selection_light.omni_range = 4.0
	selection_light.shadow_enabled = false
	selection_light.position.y = 1.8
	selection_light.visible = false
	tower.node.add_child(selection_light)
	tower.selection_light = selection_light
	towers.append(tower)
	_load_tower_model(tower)
	_request_tower_model(data.id,2)
	gold -= int(data.price)
	_clear_enemy_selection()
	selected_tower = tower
	selected_type = -1
	_clear_build_ghost()
	_sync_tower_selection_visuals()
	_refresh_hud()
	_refresh_selection()

func _valid_spot(position: Vector3) -> bool:
	var half_width := world_size*0.5-TOWER_BASE_RADIUS
	var half_depth := world_size*0.36-TOWER_BASE_RADIUS
	if absf(position.x) > half_width or absf(position.z) > half_depth or _near_route(position,_road_build_margin()):
		return false
	var ground_position := Vector2(position.x,position.z)
	for obstacle in build_obstacles:
		if ground_position.distance_to(obstacle.position) < float(obstacle.radius)+TOWER_BASE_RADIUS+TOWER_BASE_CLEARANCE:
			return false
	return _tower_spacing_valid(position)

func _road_build_margin() -> float:
	return ROAD_OUTER_WIDTH*0.5+TOWER_BASE_RADIUS+TOWER_BASE_CLEARANCE

func _minimum_tower_spacing() -> float:
	return TOWER_BASE_RADIUS*2.0+TOWER_BASE_CLEARANCE

func _create_aura_indicator(parent: Node3D, inner_radius: float, outer_radius: float, color: Color) -> MeshInstance3D:
	var indicator := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.ring_segments = 36
	mesh.rings = 6
	indicator.mesh = mesh
	indicator.position.y = 0.08
	var material := _emissive_material(color)
	material.albedo_color = Color(color.r,color.g,color.b,0.90)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_energy_multiplier = 0.55
	indicator.material_override = material
	indicator.visible = false
	parent.add_child(indicator)
	return indicator

func _tower_spacing_valid(position: Vector3) -> bool:
	var ground_position := Vector2(position.x,position.z)
	for other in towers:
		var other_ground := Vector2(other.node.position.x,other.node.position.z)
		if ground_position.distance_to(other_ground) < _minimum_tower_spacing():
			return false
	return true

func _hero_coverage_radius(hero: Dictionary) -> float:
	return float(hero.get("aura_range",0.0)) if float(hero.get("aura_range",0.0)) > 0.0 else float(hero.get("range",0.0))

func _tower_coverage_radius(tower: Dictionary) -> float:
	return float(tower.get("aura_range",0.0)) if int(tower.type) == 3 else float(tower.range)

func _aura_bonuses_for(tower: Dictionary) -> Dictionary:
	var bonuses := {"damage_multiplier":1.0,"speed_multiplier":1.0,"armor_ignore":0.0}
	if tower.is_empty() or int(tower.type) == 3:
		return bonuses
	var position := Vector2(tower.node.position.x,tower.node.position.z)
	for aura in towers:
		if int(aura.type) != 3 or str(aura.aura).is_empty():
			continue
		var aura_position := Vector2(aura.node.position.x,aura.node.position.z)
		if position.distance_to(aura_position) > float(aura.aura_range):
			continue
		if aura.aura == "damage":
			bonuses.damage_multiplier = maxf(bonuses.damage_multiplier,1.0+float(aura.power))
		else:
			bonuses.speed_multiplier = maxf(bonuses.speed_multiplier,1.0+float(aura.power))
		if int(aura.level) >= 4:
			bonuses.armor_ignore = 0.15
	return bonuses

func _load_tower_model(tower: Dictionary) -> void:
	for child in tower.model_root.get_children():
		tower.model_root.remove_child(child)
		child.queue_free()
	var id: String = HEROES[tower.type].id
	var path := "res://Assets/Heroes/%s_L%d.glb" % [id,tower.level+1]
	var packed := tower_model_cache.get(path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	instance.scale = Vector3.ONE * (1.10 if tower.level >= 2 else 1.0)
	tower.model_root.add_child(instance)
	tower.lod=CharacterLOD.attach(instance,path)
	CharacterLOD.update(tower.lod,camera,force_high_detail or (not selected_tower.is_empty() and tower.node==selected_tower.node))
	tower.skeleton = _find_skeleton(instance)
	tower.animator = _find_animator(instance)
	if tower.animator != null:
		var clips: PackedStringArray = tower.animator.get_animation_list()
		tower.idle_clip = _find_animation_clip(tower.animator,"Idle")
		tower.attack_clip = _find_animation_clip(tower.animator,"Attack")
		tower.ability_clip = _find_animation_clip(tower.animator,"Ability")
		if not str(tower.idle_clip).is_empty():
			tower.animator.play(tower.idle_clip)
		elif not clips.is_empty():
			tower.animator.play(clips[0])

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _find_animator(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animator(child)
		if found != null:
			return found
	return null

func _find_animation_clip(animator: AnimationPlayer, suffix: String) -> String:
	if animator == null:
		return ""
	for clip in animator.get_animation_list():
		if clip == suffix or clip.ends_with("_"+suffix):
			return clip
	return ""

func _upgrade() -> void:
	if selected_tower.is_empty() or selected_tower.level >= 4:
		return
	var t: Dictionary = selected_tower
	var kind: Dictionary = HEROES[t.type]
	var next_path := "res://Assets/Heroes/%s_L%d.glb" % [kind.id,int(t.level)+2]
	if not tower_model_cache.has(next_path):
		status_label.text = "Подожди: модель следующего ранга ещё загружается."
		return
	var price: int = kind.costs[t.level]
	if gold < price:
		return
	gold -= price
	t.invested += price
	t.level += 1
	if t.level < 4:
		_request_tower_model(kind.id,int(t.level)+2)
	if t.type == 3:
		t.aura_range += 0.65
		t.power = [0.30,0.38,0.46,0.54,0.65][t.level]
	else:
		t.damage *= 1.32
		t.range += 0.55
		t.detect_range += 0.75
		t.rate *= 0.91 if t.type == 0 else 0.94
	var disk: TorusMesh = t.range_mesh.mesh
	var coverage_radius := _tower_coverage_radius(t)
	disk.inner_radius = maxf(0.1,coverage_radius-0.10)
	disk.outer_radius = coverage_radius
	_load_tower_model(t)
	if magic_effects != null and magic_effects.has_method("impact"):
		magic_effects.impact(int(t.type),t.node.position+Vector3.UP*1.15)
	if t.animator != null and not str(t.get("ability_clip","")).is_empty():
		t.animator.play(t.ability_clip,0.08)
	_sync_tower_selection_visuals()
	_refresh_hud()
	_refresh_selection()
	status_label.text = "%s · улучшение завершено." % FORMS[t.type][t.level]

func _sell() -> void:
	if selected_tower.is_empty():
		return
	var t: Dictionary = selected_tower
	gold += int(t.invested)
	t.node.queue_free()
	towers.erase(t)
	selected_tower = {}
	_sync_tower_selection_visuals()
	_refresh_hud()
	_refresh_selection()
	status_label.text = "Маг снят с позиции · возвращено %d золота." % t.invested

func _next_arena_budget(remaining_gold: int) -> Dictionary:
	# Towers do not automatically turn into money at a map transition. A player
	# may sell them beforehand; only ten percent of the resulting purse travels.
	var remaining := maxi(0,remaining_gold)
	@warning_ignore("integer_division")
	var carryover: int = remaining/10
	var base_budget := 220
	return {"remaining":remaining,"carryover":carryover,"base":base_budget,"total":base_budget+carryover}

func _start_wave() -> void:
	if not _initial_tower_models_ready():
		status_label.text = "Подожди: загружаются модели башен."
		return
	if not _enemy_models_ready():
		status_label.text = "Подожди: загружаются объёмные модели противников."
		return
	if game_over:
		_reset_campaign()
		return
	if wave_running:
		return
	if stage_ready:
		_advance_arena()
		return
	wave += 1
	spawn_left = CombatBalance.wave_count(wave,arena)
	spawn_clock = 0.2
	wave_running = true
	paused = false
	_refresh_hud()
	_refresh_selection()
	status_label.text = "Волна %d · отражай наступление." % wave

func _advance_arena() -> void:
	if not stage_ready or wave_running or arena >= 17:
		return
	var budget := _next_arena_budget(gold)
	_clear_build_ghost()
	_clear_enemy_selection()
	selected_tower = {}
	selected_type = -1
	for tower in towers:
		tower.node.queue_free()
	for enemy in enemies:
		enemy.node.queue_free()
	magic_effects.clear_all()
	towers.clear()
	enemies.clear()
	bolts.clear()
	_clear_enemy_death_visuals()
	gold = int(budget.total)
	arena += 1
	wave = 0
	lives = 15
	stage_ready = false
	paused = false
	wave_running = false
	spawn_left = 0
	spawn_clock = 0.0
	if hud_gold != null:
		hud_gold.tooltip_text = "Бюджет арены: %d\nСтартовый запас: %d\nПеренос: %d (10%% от оставшихся %d)\nУстановленные башни не дают автоматического возврата." % [budget.total,budget.base,budget.carryover,budget.remaining]
	for child in terrain_root.get_children():
		terrain_root.remove_child(child)
		child.queue_free()
	_build_arena()
	_refresh_hud()
	_refresh_selection()
	status_label.text = "Арена %d: %d старт + %d перенос (10%% от %d). Расставь магов и запусти первую волну." % [arena+1,budget.base,budget.carryover,budget.remaining]

func _toggle_pause() -> void:
	paused = not paused
	_sync_animation_speeds()
	pause_button.text = "▶ Продолжить" if paused else "Ⅱ Пауза"
	status_label.text = "Игра на паузе." if paused else "Игра продолжается."

func _set_speed(index: int) -> void:
	game_speed = [1.0,2.0,3.0][clampi(index,0,2)]
	_sync_animation_speeds()

func _sync_animation_speeds() -> void:
	for tower in towers:
		if tower.animator != null:
			tower.animator.speed_scale = 0.0 if paused else game_speed
	for enemy in enemies:
		if enemy.animator != null:
			var slow: float = enemy.slow if clock < enemy.slow_until else 1.0
			enemy.animator.speed_scale = 0.0 if paused else _enemy_run_animation_speed(enemy,slow) if str(enemy.get("animation","Run")) == "Run" else game_speed
	for death in enemy_death_visuals:
		if death.animator != null:
			death.animator.speed_scale = 0.0 if paused else game_speed

func _process(delta: float) -> void:
	var logic_started := Time.get_ticks_usec()
	_apply_frame_limit()
	enemy_inspect_clock -= delta
	if not selected_enemy.is_empty() and enemy_inspect_clock <= 0.0:
		enemy_inspect_clock = 0.10
		_refresh_selection()
	lod_refresh_clock-=delta
	if lod_refresh_clock<=0.0:
		lod_refresh_clock=0.12
		_refresh_character_lods()
	_update_camera_zoom(delta)
	_poll_tower_model_loading()
	_poll_enemy_model_loading()
	_animate_background_life(delta)
	if not paused:
		var dt := minf(delta,0.05)*game_speed
		clock += dt
		_update_death_visuals(dt)
		magic_effects.tick(dt)
		if wave_running:
			spawn_clock -= dt
			if spawn_clock <= 0.0 and spawn_left > 0:
				_spawn_enemy()
				spawn_clock = maxf(0.38,1.02-wave*0.025)
			for enemy in enemies.duplicate():
				_update_enemy(enemy,dt)
			_update_towers(dt)
			_update_bolts(dt)
			if wave_running and spawn_left <= 0 and enemies.is_empty():
				_finish_wave()
		for tower in towers:
			if tower.animator == null:
				continue
			tower.animator.speed_scale = game_speed
			var transient_animation: bool = tower.animator.assigned_animation == tower.attack_clip or tower.animator.assigned_animation == str(tower.get("ability_clip",""))
			if transient_animation and not tower.animator.is_playing() and not str(tower.idle_clip).is_empty():
				tower.animator.play(tower.idle_clip)
	last_cpu_game_logic_ms = float(Time.get_ticks_usec()-logic_started)/1000.0
	var animation_started:=Time.get_ticks_usec()
	if not paused:
		for actors in [towers,enemies,enemy_death_visuals]:
			for actor in actors:CharacterLOD.tick(actor.get("lod",{}),delta)
	last_cpu_lod_animation_ms=float(Time.get_ticks_usec()-animation_started)/1000.0

func _campaign_strength() -> float:
	return 1.0+float(arena)*0.04

func _spawn_enemy() -> void:
	if not _enemy_models_ready() or spawn_left <= 0:
		return
	spawn_left -= 1
	var kind := CombatBalance.spawn_kind(wave,spawn_left)
	var boss := spawn_left == 0 and wave%5 == 0
	var data := _make_enemy(kind)
	data.merge(CombatBalance.enemy_stats(kind,wave,arena,boss),true)
	data.distance = 0.0
	data.phase = rng.randf()*TAU
	data.node.position = _path_at(0.0)
	data.burn_dps = 0.0
	data.burn_until = 0.0
	data.armor_shred = 0.0
	data.shred_until = 0.0
	if boss and kind != "boss_troll":
		data.node.scale *= 1.15
		data.height *= 1.15
	if boss and is_instance_valid(data.get("bar")):
		var bar_material: StandardMaterial3D = data.bar.material_override
		bar_material.albedo_color = Color(1.0,0.29,0.08)
	enemies.append(data)
	enemy_root.add_child(data.node)
	_update_enemy_health_bar(data)
	if data.animator != null:
		data.animator.speed_scale = 0.0 if paused else _enemy_run_animation_speed(data)
	if boss:
		status_label.text = "%s · %d HP · броня %d · награда %d" % [data.name,ceili(data.hp),data.armor,data.reward]

func _make_enemy(kind: String) -> Dictionary:
	var node := Node3D.new()
	var scale_factor := 1.0 + arena*0.01
	node.scale = Vector3.ONE * scale_factor
	var model_path := "res://Assets/Enemies/%s.glb" % kind
	var packed := enemy_model_cache.get(model_path) as PackedScene
	if packed == null:
		push_error("Enemy model is not loaded: " + model_path)
	var model: Node3D = packed.instantiate() as Node3D if packed != null else Node3D.new()
	model.name = "SkinnedEnemyModel"
	model.scale = Vector3.ONE * float(ENEMY_MODEL_SCALE.get(kind,1.0))
	var lod_record := CharacterLOD.attach(model,model_path)
	node.add_child(model)
	var animator := _find_animator(model)
	var initial_clip := _enemy_clip_name(kind,"Run")
	if animator != null and animator.has_animation(initial_clip):
		var run_animation := animator.get_animation(initial_clip)
		run_animation.loop_mode = Animation.LOOP_LINEAR
		animator.play(initial_clip)
		animator.speed_scale = 0.0 if paused else game_speed
	else:
		push_error("Enemy run animation is missing: " + initial_clip)
	var height := float(ENEMY_MODEL_HEIGHT.get(kind,2.2)) * float(ENEMY_MODEL_SCALE.get(kind,1.0))
	var bar := _create_enemy_health_bar(height)
	node.add_child(bar)
	return {"kind":kind,"node":node,"model":model,"lod":lod_record,"animator":animator,"bar":bar,"height":height*scale_factor,"scale":scale_factor,"hp":1.0,"max_hp":1.0,"reward":20,"speed":50.0,"distance":0.0,"phase":0.0,"boss":false,"slow":1.0,"slow_until":0.0,"hit_time":0.0,"animation":"Run","run_reference_mps":_model_run_reference(model,kind)}

func _create_enemy_health_bar(model_height: float) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	bar.name = "HealthBar"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.9,0.07)
	bar.mesh = mesh
	bar.set_meta("health_bar_local_height",model_height+0.28)
	bar.position = Vector3(0,model_height+0.28,0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.10,0.72,0.24)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bar.material_override = material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bar

func _update_enemy_health_bar(enemy: Dictionary) -> void:
	var bar: MeshInstance3D = enemy.get("bar") as MeshInstance3D
	var actor: Node3D = enemy.get("node") as Node3D
	if camera == null or not is_instance_valid(bar) or not is_instance_valid(actor) or not bar.is_inside_tree():
		return
	var fraction := clampf(float(enemy.hp)/maxf(0.001,float(enemy.max_hp)),0.0,1.0)
	bar.visible = fraction > 0.0
	# Counter the parent's heading and scale in WORLD space. Only this UI quad
	# faces the camera; the skinned model retains its route-facing orientation.
	var actor_scale := absf(actor.global_basis.get_scale().x)
	var right := camera.global_basis.x.normalized()
	var up := camera.global_basis.y.normalized()
	var toward_camera := camera.global_basis.z.normalized()
	var head_anchor := actor.to_global(Vector3(0,float(bar.get_meta("health_bar_local_height")),0))
	var left_edge := head_anchor-right*(0.45*actor_scale)
	var center := left_edge+right*(0.45*actor_scale*fraction)
	bar.global_transform = Transform3D(Basis(right*(actor_scale*maxf(0.001,fraction)),up*actor_scale,toward_camera*actor_scale),center)

func _enemy_clip_name(kind: String, clip: String) -> String:
	return "enemy_%s_%s" % [kind,clip]

func _play_enemy_animation(enemy: Dictionary, clip: String) -> void:
	var animator: AnimationPlayer = enemy.get("animator") as AnimationPlayer
	if animator == null:
		return
	var clip_name := _enemy_clip_name(str(enemy.kind),clip)
	if not animator.has_animation(clip_name):
		return
	var animation := animator.get_animation(clip_name)
	animation.loop_mode = Animation.LOOP_LINEAR if clip == "Run" or clip == "Idle" else Animation.LOOP_NONE
	animator.speed_scale = 0.0 if paused else _enemy_run_animation_speed(enemy) if clip == "Run" else game_speed
	animator.play(clip_name,0.04)
	enemy.animation = clip

func _update_death_visuals(dt: float) -> void:
	for death in enemy_death_visuals.duplicate():
		death.time_left -= dt
		if death.time_left <= 0.0:
			death.node.queue_free()
			enemy_death_visuals.erase(death)

func _clear_enemy_death_visuals() -> void:
	for death in enemy_death_visuals:
		if is_instance_valid(death.node):
			death.node.queue_free()
	enemy_death_visuals.clear()

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material

func _update_enemy(enemy: Dictionary, dt: float) -> void:
	if not enemies.has(enemy):
		return
	var burn_time := minf(dt,maxf(0.0,float(enemy.get("burn_until",0.0))-(clock-dt)))
	if burn_time > 0.0:
		_damage_enemy(enemy,float(enemy.get("burn_dps",0.0))*burn_time,0.0,false)
		if not enemies.has(enemy):
			return
	if enemy.hit_time > 0.0:
		enemy.hit_time = maxf(0.0,float(enemy.hit_time)-dt)
		if enemy.hit_time == 0.0:
			_play_enemy_animation(enemy,"Run")
	var slow: float = enemy.slow if clock < enemy.slow_until else 1.0
	enemy.distance += enemy.speed*slow*dt
	if enemy.distance >= route_length:
		lives -= int(enemy.get("life_damage",1))
		if not selected_enemy.is_empty() and selected_enemy.get("node") == enemy.node:
			_clear_enemy_selection()
			_refresh_selection()
		enemy.node.queue_free()
		enemies.erase(enemy)
		_refresh_hud()
		status_label.text = "Враг прорвался к рубежу!"
		if lives <= 0:
			wave_running = false
			game_over = true
			for remaining in enemies:
				remaining.node.queue_free()
			enemies.clear()
			_clear_enemy_selection()
			_refresh_selection()
			status_label.text = "Рубеж пал · нажми «Начать заново»."
			start_button.text = "Начать заново"
			_refresh_hud()
		return
	var p := _path_at(enemy.distance)
	enemy.node.position = p
	var tangent := _path_at(minf(route_length,enemy.distance+0.3))-p
	if tangent.length_squared() > 0.01:
		enemy.node.rotation.y = atan2(tangent.x,tangent.z)
	_update_enemy_health_bar(enemy)
	if str(enemy.get("animation","Run")) == "Run" and enemy.animator != null:
		enemy.animator.speed_scale = _enemy_run_animation_speed(enemy,slow)

func _enemy_run_animation_speed(enemy: Dictionary, slow: float = 1.0) -> float:
	var movement_speed := maxf(0.0,float(enemy.get("speed",ENEMY_REFERENCE_RUN_SPEED))*slow)
	var reference := float(enemy.get("run_reference_mps",WARG_REFERENCE_RUN_SPEED if str(enemy.get("kind","")) == "warg" else ENEMY_REFERENCE_RUN_SPEED))
	var model: Node3D = enemy.get("model") as Node3D
	var model_scale := absf(model.scale.x) if model != null else 1.0
	var actor_scale := absf(enemy.node.scale.x) if enemy.get("node") != null else 1.0
	return game_speed*movement_speed/maxf(0.001,reference*model_scale*actor_scale)

func _model_run_reference(model: Node, kind: String) -> float:
	var metadata = _find_model_metadata(model,"run_reference_mps")
	return float(metadata) if metadata != null else WARG_REFERENCE_RUN_SPEED if kind == "warg" else ENEMY_REFERENCE_RUN_SPEED

func _find_model_metadata(model: Node, key: String):
	if model.has_meta(key):
		return model.get_meta(key)
	for child in model.get_children():
		var found = _find_model_metadata(child,key)
		if found != null:
			return found
	return null

func _path_at(distance: float) -> Vector3:
	if route_points.is_empty():
		return Vector3.ZERO
	for i in range(1,route_points.size()):
		if route_lengths[i] >= distance:
			var segment := route_lengths[i]-route_lengths[i-1]
			var t := clampf((distance-route_lengths[i-1])/maxf(0.001,segment),0.0,1.0)
			return route_points[i-1].lerp(route_points[i],t)
	return route_points[-1]

func _update_towers(dt: float) -> void:
	for tower in towers:
		if tower.type == 3:
			continue
		tower.cooldown -= dt
		var shots := 3 if tower.type == 0 and tower.level >= 4 else 1
		var targets: Array[Dictionary] = []
		var scan_target: Dictionary = {}
		for enemy in enemies:
			var separation: float = tower.node.position.distance_to(enemy.node.position)
			if separation <= tower.detect_range and (scan_target.is_empty() or enemy.distance > scan_target.distance):
				scan_target = enemy
			if separation > tower.range: continue
			var insert := 0
			while insert < targets.size() and targets[insert].distance >= enemy.distance:
				insert += 1
			if insert < shots:
				targets.insert(insert,enemy)
				if targets.size() > shots: targets.pop_back()
		var aim_target: Dictionary = targets[0] if not targets.is_empty() else scan_target
		if aim_target.is_empty():
			continue
		var aim: Vector3 = aim_target.node.position-tower.node.position
		tower.node.rotation.y = atan2(aim.x,aim.z)
		if tower.cooldown > 0.0 or targets.is_empty():
			continue
		var aura_bonuses := _aura_bonuses_for(tower)
		var damage: float = tower.damage*float(aura_bonuses.damage_multiplier)
		var speed_buff: float = aura_bonuses.speed_multiplier
		var cooldown: float = tower.rate/maxf(0.1,speed_buff)
		if tower.animator != null and not str(tower.attack_clip).is_empty():
			var attack_length: float = tower.animator.get_animation(tower.attack_clip).length
			# Finish the articulated strike before a buffed tower fires again.
			tower.animator.play(tower.attack_clip,0.06,maxf(1.0,attack_length/maxf(0.15,cooldown*0.85)))
		for i in range(mini(shots,targets.size())):
			_fire_bolt(tower,targets[i],damage)
		tower.cooldown = cooldown

func _fire_bolt(tower: Dictionary, target: Dictionary, damage: float) -> void:
	var projectile: Node3D = magic_effects.acquire_flight(int(tower.type))
	projectile.position = _tower_projectile_origin(tower)
	var target_point: Vector3 = target.node.position+Vector3.UP*float(target.get("height",1.7))*0.62
	if projectile.position.distance_to(target_point) > 0.01:
		projectile.look_at(target_point,Vector3.UP)
	_play_sfx(ATTACK_SFX[tower.type],projectile.global_position)
	var aura := _aura_bonuses_for(tower)
	var armor_ignore := maxf(float(aura.armor_ignore),0.45 if tower.type == 0 and tower.level >= 4 else 0.0)
	var splash := 3.6 if tower.type == 5 and tower.level >= 4 else 2.8 if tower.type == 5 else 3.4 if tower.type == 2 and tower.level >= 4 else 2.2 if tower.type == 2 else 0.0
	bolts.append({"node":projectile,"target":target,"damage":damage,"type":tower.type,"speed":16.0 if tower.type == 5 else 20.0,"life":0.0,"slow":0.12 if tower.type == 4 and tower.level >= 4 else 0.55 if tower.type == 4 else 1.0,"freeze":tower.type == 4 and tower.level >= 4,"pierce":CombatBalance.MAX_CHAIN_HOPS if tower.type == 1 and tower.level >= 4 else 0,"hit":[],"splash":splash,"armor_ignore":armor_ignore,"burn":tower.type == 2 and tower.level >= 4,"shred":tower.type == 5 and tower.level >= 4})

func _tower_projectile_origin(tower: Dictionary) -> Vector3:
	var skeleton: Skeleton3D = tower.get("skeleton") as Skeleton3D
	if is_instance_valid(skeleton) and skeleton.is_inside_tree():
		var right_hand := skeleton.find_bone("hand.R")
		if right_hand >= 0:
			skeleton.force_update_all_bone_transforms()
			var local_hand := skeleton.get_bone_global_pose(right_hand).origin
			if int(tower.type) == 5:
				var left_hand := skeleton.find_bone("hand.L")
				if left_hand >= 0:
					local_hand = local_hand.lerp(skeleton.get_bone_global_pose(left_hand).origin,0.5)
			var world_hand := skeleton.to_global(local_hand)+skeleton.global_basis.y.normalized()*0.045
			return magic_effects.to_local(world_hand)
	# Model-free diagnostics retain the same battle timings and trajectories.
	return tower.node.position+Vector3.UP*(1.2 if int(tower.type) == 5 else 1.7)

func _emissive_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	return material

func _update_bolts(dt: float) -> void:
	for bolt in bolts.duplicate():
		var target: Dictionary = bolt.target
		if not enemies.has(target):
			_release_bolt(bolt)
			continue
		var target_point: Vector3 = target.node.position+Vector3.UP*float(target.get("height",1.7))*0.62
		var direction: Vector3 = target_point-bolt.node.position
		var step: float = bolt.speed*dt
		bolt.life += dt
		if direction.length() <= step+0.3:
			var impact_type: int = bolt.type
			bolt.node.position = target_point
			magic_effects.impact(impact_type,target_point)
			var splash_center: Vector3 = target.node.position
			_hit_with_bolt(bolt,target,1.0)
			if bolt.splash > 0.0:
				for other in enemies.duplicate():
					if other == target:
						continue
					var separation := Vector2(other.node.position.x,other.node.position.z).distance_to(Vector2(splash_center.x,splash_center.z))
					if separation <= float(bolt.splash):
						var splash_scale := lerpf(0.90,0.55,separation/float(bolt.splash)) if impact_type == 5 else 0.55
						_hit_with_bolt(bolt,other,splash_scale)
			bolt.hit.append(target)
			if bolt.pierce > 0:
				var next_target: Dictionary = {}
				var closest := 8.0
				for other in enemies:
					var separation: float = splash_center.distance_to(other.node.position)
					if not bolt.hit.has(other) and separation < closest:
						next_target = other
						closest = separation
				if not next_target.is_empty():
					bolt.target = next_target
					bolt.pierce -= 1
					bolt.damage *= CombatBalance.CHAIN_FALLOFF
					bolt.life = 0.0
				else:
					_release_bolt(bolt)
			else:
				_release_bolt(bolt)
		else:
			bolt.node.position += direction.normalized()*step
			if direction.length_squared() > 0.001:
				bolt.node.look_at(target_point,Vector3.UP)
			if bolt.life > 2.5:
				_release_bolt(bolt)

func _release_bolt(bolt: Dictionary) -> void:
	magic_effects.release_flight(bolt.node)
	bolts.erase(bolt)

func _effective_enemy_armor(enemy: Dictionary) -> float:
	return maxf(0.0,float(enemy.get("armor",0.0))-(float(enemy.get("armor_shred",0.0)) if clock < float(enemy.get("shred_until",0.0)) else 0.0))

func _damage_enemy(enemy: Dictionary, raw_damage: float, armor_ignore: float = 0.0, react: bool = true) -> float:
	if not enemies.has(enemy) or float(enemy.hp) <= 0.0:
		return 0.0
	var damage := maxf(0.0,raw_damage)*CombatBalance.armor_multiplier(_effective_enemy_armor(enemy),armor_ignore)
	var applied := minf(float(enemy.hp),damage)
	enemy.hp = maxf(0.0,float(enemy.hp)-damage)
	_update_enemy_health_bar(enemy)
	if enemy.hp <= 0.0:
		_kill_enemy(enemy)
	elif react:
		enemy.hit_time = 0.18
		_play_enemy_animation(enemy,"Hit")
	return applied

func _hit_with_bolt(bolt: Dictionary, enemy: Dictionary, multiplier: float) -> void:
	if not enemies.has(enemy):
		return
	if bool(bolt.get("shred",false)):
		enemy.armor_shred = 14.0
		enemy.shred_until = clock+3.0
	_damage_enemy(enemy,float(bolt.damage)*multiplier,float(bolt.get("armor_ignore",0.0)))
	if not enemies.has(enemy):
		return
	if int(bolt.type) == 4:
		var slow := maxf(float(bolt.slow),0.60 if bool(enemy.get("boss",false)) else 0.0)
		var previous_slow := float(enemy.slow) if clock < float(enemy.slow_until) else 1.0
		var duration := 0.7 if bolt.freeze else 1.5
		# A weaker slow cannot extend a short high-rank freeze indefinitely.
		if slow < previous_slow-0.001 or clock >= float(enemy.slow_until):
			enemy.slow = slow
			enemy.slow_until = clock+duration
		elif is_equal_approx(slow,previous_slow):
			enemy.slow_until = maxf(float(enemy.slow_until),clock+duration)
	if bool(bolt.get("burn",false)):
		# Refresh the strongest burn instead of stacking unbounded DOTs.
		enemy.burn_dps = maxf(float(enemy.get("burn_dps",0.0)) if clock < float(enemy.get("burn_until",0.0)) else 0.0,float(bolt.damage)*multiplier*0.10)
		enemy.burn_until = clock+3.0

func _kill_enemy(enemy: Dictionary) -> void:
	if not enemies.has(enemy):
		return
	if is_instance_valid(enemy.get("bar")):
		enemy.bar.visible = false
	if not selected_enemy.is_empty() and selected_enemy.get("node") == enemy.node:
		_clear_enemy_selection()
		_refresh_selection()
	gold += int(enemy.reward)
	var death_sound: String = DEATH_SFX.get(enemy.kind,DEATH_SFX.troll)
	if not death_sound.is_empty(): _play_sfx(death_sound,enemy.node.global_position)
	enemies.erase(enemy)
	var animator: AnimationPlayer = enemy.get("animator") as AnimationPlayer
	var death_length := 0.65
	if animator != null:
		var death_clip := _enemy_clip_name(str(enemy.kind),"Death")
		if animator.has_animation(death_clip):
			var animation := animator.get_animation(death_clip)
			animation.loop_mode = Animation.LOOP_NONE
			death_length = maxf(0.35,animation.length)
			animator.speed_scale = game_speed
			animator.play(death_clip)
	enemy_death_visuals.append({"node":enemy.node,"lod":enemy.get("lod",{}),"animator":animator,"time_left":death_length})
	_refresh_hud()
	status_label.text = "Враг повержен · +%d золота." % enemy.reward

func _finish_wave() -> void:
	wave_running = false
	paused = false
	for bolt in bolts.duplicate():
		_release_bolt(bolt)
	gold += CombatBalance.wave_reward(wave,arena)
	if wave >= 15:
		if arena < 17:
			stage_ready = true
			start_button.text = "Перейти на арену %d" % (arena+2)
		else:
			game_over = true
			start_button.text = "Кампания завершена"
	else:
		start_button.text = "▶ Начать волну %d/15" % (wave+1)
	_refresh_hud()
	status_label.text = "Волна отбита · награда добавлена."

func _reset_campaign() -> void:
	_clear_enemy_selection()
	_clear_build_ghost()
	for tower in towers: tower.node.queue_free()
	for enemy in enemies: enemy.node.queue_free()
	_clear_enemy_death_visuals()
	magic_effects.clear_all()
	towers.clear()
	enemies.clear()
	bolts.clear()
	selected_tower = {}
	selected_type = -1
	arena = 0
	wave = 0
	gold = 360
	if hud_gold != null:
		hud_gold.tooltip_text = "Стартовый запас кампании: 360 золота."
	lives = 15
	game_over = false
	stage_ready = false
	wave_running = false
	paused = false
	spawn_left = 0
	spawn_clock = 0.0
	for child in terrain_root.get_children():
		terrain_root.remove_child(child)
		child.queue_free()
	_build_arena()
	_refresh_hud()
	_refresh_selection()

func _update_camera() -> void:
	if camera == null:
		return
	camera.size = camera_size
	var distance := maxf(16.0,camera_size*1.15)
	var ground_distance := cos(camera_pitch)*distance
	camera.position = camera_target + Vector3(sin(camera_yaw)*ground_distance,sin(camera_pitch)*distance,cos(camera_yaw)*ground_distance)
	camera.look_at(camera_target,Vector3.UP)
	# Camera orbit/zoom is available while paused, so billboard UI must update
	# here as well as during enemy simulation.
	for enemy in enemies:
		_update_enemy_health_bar(enemy)

func _orbit_camera(relative_motion: Vector2) -> void:
	var was_fitted := camera_size >= _camera_max_size()-0.02
	camera_yaw = wrapf(camera_yaw-relative_motion.x*0.008,0.0,TAU)
	camera_pitch = clampf(camera_pitch+relative_motion.y*0.006,CAMERA_MIN_PITCH,CAMERA_MAX_PITCH)
	camera_zoom_active = false
	var new_limit := _camera_max_size()
	if was_fitted or camera_size > new_limit:
		camera_size = new_limit
		camera_target = _camera_fit_center()
	camera_zoom_goal = camera_size
	_update_camera()

func _reset_camera_view() -> void:
	camera_yaw = 0.0
	camera_pitch = CAMERA_DEFAULT_PITCH
	camera_zoom_active = false
	camera_orbiting = false
	panning = false
	camera_size = _camera_max_size()
	camera_zoom_goal = camera_size
	camera_target = _camera_fit_center()
	_update_camera()
	if selected_type >= 0:
		mouse_world = _screen_to_ground(get_viewport().get_mouse_position())
		_update_build_ghost()

func _screen_to_ground(screen_point: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var plane := Plane(Vector3.UP,0.0)
	var hit = plane.intersects_ray(origin,direction)
	return hit if hit != null else Vector3(99999,0,99999)

func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := _screen_to_ground(screen_point)
	camera_size = clampf(camera_size*factor,10.0,_camera_max_size())
	var recentered := camera_size >= _camera_max_size()-0.001
	if recentered:
		camera_target = _camera_fit_center()
	_update_camera()
	var after := _screen_to_ground(screen_point)
	if not recentered and before.x < 90000 and after.x < 90000:
		camera_target += before-after
	_update_camera()

func _request_camera_zoom(screen_point: Vector2, factor: float) -> void:
	camera_zoom_anchor = screen_point
	camera_zoom_goal = clampf((camera_zoom_goal if camera_zoom_active else camera_size)*factor,10.0,_camera_max_size())
	camera_zoom_active = true

func _update_camera_zoom(delta: float) -> void:
	if not camera_zoom_active or camera == null:
		return
	var next_size := lerpf(camera_size,camera_zoom_goal,1.0-exp(-14.0*minf(delta,0.1)))
	if absf(next_size-camera_zoom_goal) < 0.01:
		next_size = camera_zoom_goal
		camera_zoom_active = false
	_zoom_at(camera_zoom_anchor,next_size/maxf(0.01,camera_size))
	if selected_type >= 0:
		mouse_world = _screen_to_ground(camera_zoom_anchor)
		_update_build_ghost()

func _camera_max_size() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	var usable := _camera_usable_rect()
	var ground_width := world_size
	var ground_depth := world_size*0.72
	# Orthographic projection of the complete ground rectangle, at this yaw/pitch.
	var projected_width := absf(cos(camera_yaw))*ground_width+absf(sin(camera_yaw))*ground_depth
	var projected_height := sin(camera_pitch)*(absf(sin(camera_yaw))*ground_width+absf(cos(camera_yaw))*ground_depth)
	var horizontal_fit := projected_width*viewport_size.y/maxf(320.0,usable.size.x)
	var vertical_fit := projected_height*viewport_size.y/maxf(300.0,usable.size.y)
	return maxf(10.0,maxf(horizontal_fit,vertical_fit)*1.08)

func _camera_usable_rect() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	return Rect2(Vector2(8.0,78.0),Vector2(maxf(320.0,viewport_size.x-_side_panel_width()-24.0),maxf(300.0,viewport_size.y-98.0)))

func _camera_fit_center() -> Vector3:
	var viewport_size := get_viewport().get_visible_rect().size
	var optical_center := viewport_size*0.5
	var field_center := _camera_usable_rect().get_center()
	var world_per_pixel := _camera_max_size()/maxf(1.0,viewport_size.y)
	var right := Vector3(cos(camera_yaw),0.0,-sin(camera_yaw))
	var ground_up := Vector3(-sin(camera_yaw),0.0,-cos(camera_yaw))
	return right*(optical_center.x-field_center.x)*world_per_pixel+ground_up*(field_center.y-optical_center.y)*world_per_pixel/maxf(0.1,sin(camera_pitch))

func _camera_fit_center_x() -> float:
	# Compatibility for old diagnostic callers; new callers use the full vector.
	return _camera_fit_center().x

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and camera_orbiting:
		_orbit_camera(event.position-camera_orbit_mouse)
		camera_orbit_mouse = event.position
		mouse_world = _screen_to_ground(event.position)
		_update_build_ghost()
		get_viewport().set_input_as_handled()
		return
	# A button release must reach camera state even when the HUD consumes it.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		camera_orbiting = false
		get_viewport().set_input_as_handled()
		return
	# Finish a drag before the HUD can consume its release. Otherwise dragging
	# from the map onto the panel leaves the camera stuck in panning mode.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and panning:
		var was_dragged: bool = right_dragged or event.position.distance_to(right_press_mouse) > 6.0
		panning = false
		right_dragged = false
		if not was_dragged and selected_type >= 0:
			selected_type = -1
			selected_tower = {}
			_clear_build_ghost()
			_sync_tower_selection_visuals()
			_refresh_hud()
			_refresh_selection()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_toggle_fullscreen()
	elif event.keycode == KEY_HOME:
		_reset_camera_view()
	elif menu_root != null and menu_root.visible:
		if event.keycode == KEY_ESCAPE:
			_continue_game()
		else:
			return
	elif event.keycode == KEY_SPACE:
		if paused: _toggle_pause()
		elif not wave_running: _start_wave()
	elif event.keycode == KEY_P:
		_toggle_pause()
	elif event.keycode == KEY_ESCAPE:
		if selected_type >= 0:
			selected_type = -1
			selected_tower = {}
			_clear_build_ghost()
			_sync_tower_selection_visuals()
			_refresh_hud()
			_refresh_selection()
		elif not selected_enemy.is_empty():
			_clear_enemy_selection()
			_refresh_selection()
		else:
			_show_main_menu()
	else:
		return
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if menu_root != null and menu_root.visible:
		return
	if event is InputEventMouse and side_panel != null and side_panel.get_global_rect().has_point(event.position):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_orbiting = event.pressed
			camera_orbit_mouse = event.position
			if event.pressed:
				panning = false
				camera_zoom_active = false
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				panning = true
				right_dragged = false
				right_press_mouse = event.position
				last_mouse = event.position
			else:
				panning = false
				if not right_dragged and selected_type >= 0:
					selected_type = -1
					selected_tower = {}
					_clear_build_ghost()
					_sync_tower_selection_visuals()
					_refresh_hud()
					_refresh_selection()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_request_camera_zoom(event.position,0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_request_camera_zoom(event.position,1.14)
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if selected_type < 0:
				var enemy_index := _find_enemy_at_screen(event.position)
				if enemy_index >= 0:
					_select_enemy(enemy_index)
					return
			var point := _screen_to_ground(event.position)
			if point.x < 90000:
				mouse_world = point
				_update_build_ghost()
				if selected_type >= 0:
					_place_tower(point)
					return
				var tower_index := _find_tower_at(point)
				if tower_index >= 0:
					_select_tower(tower_index)
				else:
					selected_tower = {}
					_clear_enemy_selection()
					_sync_tower_selection_visuals()
					_refresh_selection()
	elif event is InputEventMouseMotion:
		if camera_orbiting:
			_orbit_camera(event.position-camera_orbit_mouse)
			camera_orbit_mouse = event.position
			mouse_world = _screen_to_ground(event.position)
			_update_build_ghost()
			get_viewport().set_input_as_handled()
		elif panning:
			if event.position.distance_to(right_press_mouse) > 6.0:
				right_dragged = true
			var before := _screen_to_ground(last_mouse)
			var after := _screen_to_ground(event.position)
			if before.x < 90000 and after.x < 90000:
				camera_zoom_active = false
				camera_target += before-after
				camera_target.x = clampf(camera_target.x,-world_size*0.48,world_size*0.48)
				camera_target.z = clampf(camera_target.z,-world_size*0.34,world_size*0.34)
				_update_camera()
			last_mouse = event.position
		else:
			mouse_world = _screen_to_ground(event.position)
			_update_build_ghost()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused_window=true
		_apply_frame_limit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused_window=false
		_apply_frame_limit()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()
		if music_player != null: music_player.stop()
		for voice in sfx_players: voice.stop()
