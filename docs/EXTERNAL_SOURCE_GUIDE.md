# Карта исходников и план экспериментов

Статическое изучение 12 ноября 2026 года. Версии исходников зафиксированы в [development-tools.lock.json](../development-tools.lock.json). База всех путей ниже — локальная папка `Documents/GitHub/External` (или каталог из `-ExternalRoot`). Это карта реально просмотренных исходников и примеров. Библиотеки не собирались, их код не запускался, модели и игровой проект не изменялись. Предлагаемые эксперименты ещё не проведены.

## 1. meshoptimizer — сначала сохранность персонажа, затем уменьшение размера

Точки входа:

- `meshoptimizer/gltf/gltfpack.cpp`: разбор CLI. Полезны `-kn` (имена узлов), `-km` (имена материалов), `-ke` (extras), `-kv` (исходные атрибуты), `-af 0` (без пересэмплирования анимаций), `-ac` (постоянные треки), `-noq` (без квантования). Они не обещают побитового сохранения модели; `-kn` также ограничивает объединение/инстансинг.
- `meshoptimizer/gltf/mesh.cpp`: `processMesh()`, `filterBones()`, `simplifyMesh()`, `simplifyAttributes()`.
- `meshoptimizer/src/meshoptimizer.h`: `meshopt_simplifyWithAttributes`, `meshopt_simplifyWithUpdate`, параметры защиты/фиксации вершин.
- `meshoptimizer/gltf/animation.cpp`: обработка интерполяции, пересэмплирование и допуски ключей.

Критическая находка: `processMesh()` для треугольных мешей вызывает `filterBones()`. Эта функция оставляет четыре наиболее сильных влияния костей на вершину, удаляет малые веса и дополнительные наборы JOINTS/WEIGHTS. Флаги сохранения имён и атрибутов не отключают этот этап. Если в исходной модели используются восемь влияний, преобразование уже меняет её skinning даже без явного упрощения геометрии.

Метрика attribute-aware simplification учитывает нормали, цвета и UV; она не измеряет ошибку деформации во всех анимационных позах. Для skinned-меша включается regularization, но это не доказательство сохранения лица, плеч, локтей и складок в движении. `-sa`, `-sp`, `-sv` нельзя без проверки применять ко всем героям.

Первый эксперимент: копия одного GLB, сначала без упрощения, с сохранением имён/материалов/extras и без пересэмплирования. До/после проверить число костей, influence count, веса, bind pose, пути узлов, материалы, морфы при их наличии и длительность клипов. Сравнить силуэт и деформации в наборе поз idle/attack со всех сторон. Затем отдельно проверить консервативные LOD. Метрики: байты, вершины/треугольники, время импорта, CPU/GPU кадра и ошибка в анимированных позах. Исходный `.blend` и близкий LOD сохранять.

Godot уже включает meshoptimizer в собственные зависимости. Сначала определить, какой этап импорта/LOD уже использует его, чтобы не повторять разрушительную оптимизацию дважды.

## 2. Terrain3D — heightmap, поверхность строительства и LOD

Точки входа:

- `Terrain3D/project/demo/src/CodeGenerated.gd`: `create_terrain()` создаёт Terrain3D, материалы и asset-слоты; импортирует 32-битную heightmap через `terrain.data.import_images([img, null, null], position, offset, scale)`. Пример берёт высоту поверхности перед размещением травы и вызывает `terrain.instancer.add_transforms()`.
- `Terrain3D/src/terrain_3d_data.h`: `import_images()`, `get_height()`, `get_normal()`, `export_image()`. Высота и координаты должны использовать тот же мировой масштаб, что и дорога/башни.
- `Terrain3D/src/terrain_3d.h` и `.cpp`: `set_mesh_lods()`, `set_mesh_size()`, `set_clipmap_target()`, `get_intersection()`. В исходнике есть явная диагностика отсутствующей камеры/clipmap target — без неё обновление LOD не работает корректно.
- `Terrain3D/src/terrain_3d_mesher.h`: организация мешей и экземпляров по уровням LOD.
- `Terrain3D/src/terrain_3d_instancer.h`: `add_transforms()`, `add_multimesh()` для растительности.
- `Terrain3D/project/demo/src/RuntimeNavigationBaker.gd`: отдельная навигационная область, отложенная обработка геометрии и ограничение частоты перепекания. Комментарий у `use_edge_connections = false` объясняет потенциальные задержки при обновлении навигации.
- `Terrain3D/project/addons/terrain_3d/terrain.gdextension`: описание нативных библиотек, которые необходимы плагину; наличие исходника не заменяет подходящий binary release.

Первый эксперимент: отдельная карта с небольшой heightmap и двумя материалами. Сначала связать попадание курсора с реальной высотой/нормалью, сохранить маску дороги и доступность травы. Башни, основания, ноги NPC и коллизии должны находиться на одной поверхности; старое пересечение луча с плоскостью Y=0 для рельефной карты недостаточно. Затем проверить близкую/далёкую камеру, LOD, границы регионов, плотность травы и shadows. Метрики: GPU кадра, draw calls, VRAM, количество видимых экземпляров, ошибки стыков/проваливания и возможность строительства в контрольных точках.

Terrain3D — heightmap-система; тоннели и нависающую геометрию разумно оформлять отдельными мешами/пещерами или оценивать Voxel Tools как иной backend. Внедрение не требует переписывать игру на другой движок, но требует адаптации геометрии дороги и world picking.

## 3. Material Maker — проверять текущие export templates

Точки входа:

- `material-maker/addons/material_maker/engine/nodes/gen_material.gd`: `get_export_profiles()`, `get_export()`, `export_material()` и сохранение PNG. Это реальный путь от material graph к текстурам/ресурсам.
- `material-maker/addons/material_maker/nodes/material.mmg`: шаблоны `Godot/Godot 4 ORM` и `Godot/Godot 4 Standard`. Они выводят текстуры и соответственно `ORMMaterial3D`/`StandardMaterial3D`; ORM упаковывает AO, roughness и metallic в каналы одной текстуры.
- `material-maker/parse_args.gd`: `export_files()` выбирает профиль и вызывает асинхронный экспорт.
- `material-maker/material_maker/windows/material_editor/export_editor.gd`: UI редактирования export-профилей.
- `material-maker/material_maker/doc/export.rst`: обзор экспорта, но упоминание SpatialMaterial в части Godot устарело относительно текущих Godot 4 шаблонов. При интеграции ориентироваться на выбранный шаблон и результат импорта.

Первый эксперимент: один воспроизводимый материал скалы и один почвы; сохранить граф и seed вместе с исходниками, экспортировать 1K/2K PBR-наборы. Проверить масштаб UV, направление normal map, линейное чтение каналов roughness/metallic/AO, sRGB для albedo и mipmaps. Для Terrain3D отдельно подготовить требуемую упаковку albedo+height и normal+roughness, как в его CodeGenerated.gd; обычный ORM-файл не считать автоматически готовым Terrain3D texture asset.

Метрики: визуальный результат при одинаковом освещении, число текстур/материалов, VRAM, время импорта и размер экспорта. Это инструмент подготовки ресурсов; его UI и весь graph runtime не нужно включать в KDTD.exe ради готовых текстур.

## 4. Effekseer — жизненный цикл эффекта и Godot bridge

Локальные точки входа:

- `Effekseer/Dev/Cpp/Effekseer/Effekseer/Effekseer.Manager.h`: `Manager::Create()`, `Play()`, `StopEffect()`, `Update()`, `Draw()`, `SetPaused()`, `SetSpeed()`, `GetTotalInstanceCount()`, `GetRestInstancesCount()`.
- `Effekseer/Dev/Cpp/Effekseer/Effekseer/Effekseer.Effect.h`: загрузка через `Effect::Create()`.
- `Effekseer/Examples/Vulkan/main.cpp`: последовательность создания renderer/manager, загрузки `.efkefc`, старта эффекта, обновления и отрисовки.
- `Effekseer/Examples/Distortion/main.cpp`, `Examples/CustomAsyncLoader/main.cpp`, `Examples/SortHandle/main.cpp`: отдельные примеры искажения, асинхронной загрузки и порядка эффектов.

Godot-адаптер не входит в один из этих десяти локальных клонов. Его исходник [EffekseerEmitter3D.h](https://github.com/effekseer/EffekseerForGodot4/blob/main/Dev/Cpp/src/EffekseerEmitter3D.h) дополнительно просмотрен удалённо: `play`, `stop`, `stop_root`, `set_paused`, `set_speed`, `set_effect`, `set_autofree`, `set_dynamic_input`, `send_trigger`. Документация `Docs/source/en/api-reference.md` описывает сигнал `finished` и transform эмиттера. Для применения нужен совместимый [EffekseerForGodot4](https://github.com/effekseer/EffekseerForGodot4) и его нативные библиотеки, а не второй самостоятельный графический цикл внутри Godot.

Первый эксперимент: один огненный снаряд и попадание в отдельной сцене. Игровая логика определяет время/место урона; эффект только отображает событие. Проверить привязку origin к анимированной руке, pause/x3 speed, остановку/повтор, освобождение или возврат эмиттера в пул, перечень встроенных зависимостей после export. После этого нагрузка 10/50/100 эффектов; отдельно измерить CPU, GPU, instance count и overdraw. Не заменять маленький снаряд большим количеством прозрачных частиц на весь экран.

## 5. Voxel Tools — бюджет потоков, блоков и коллизий

Точки входа:

- `godot_voxel/terrain/variable_lod/voxel_lod_terrain.h`: `set_generator()`, `set_mesher()`, `set_stream()`, `set_view_distance()`, `set_lod_distance()`, `set_lod_count()`, `set_collision_lod_count()` и статистика обновления.
- `godot_voxel/terrain/voxel_viewer.h`: `set_view_distance()` — источник запросов видимых блоков.
- `godot_voxel/generators/graph/voxel_generator_graph.h`: граф генерации; `generators/simple/voxel_generator_heightmap.h` — heightmap-вариант.
- `godot_voxel/meshers/transvoxel/voxel_mesher_transvoxel.h`: гладкая геометрия с переходами LOD; `meshers/blocky/voxel_mesher_blocky.h` — другой способ построения, для блочного мира.
- `godot_voxel/engine/voxel_engine_gd.h`: `VoxelEngine::get_stats()`.
- `godot_voxel/doc/source/performance.md`: ограничения поточного бюджета, main-thread time budget, размера блоков и расстояния видимости. Исторические замечания о Godot 3/OpenGL нельзя автоматически считать результатом замеров текущего Godot 4.

Первый эксперимент: маленькая объёмная пещера с фиксированной камерной траекторией. Измерить создание мешей/коллизий, очередь задач, главный поток и память; сравнить с обычной статической cave mesh. Для нашей фиксированной TD-карты стриминг бесконечного мира может дать больше сложности, чем пользы. Module-издание требует специального Godot и export templates, GDExtension — совместимого addon/binaries. Системы terrain height/road/build mask должны сохранять согласованность независимо от backend.

## 6. FastNoise2 — генерировать пакеты, учитывать детерминизм

Точки входа:

- `FastNoise2/include/FastNoise/FastNoise.h`: `FastNoise::New<T>()`, `NewFromEncodedNodeTree()`.
- `FastNoise2/include/FastNoise/Generators/Generator.h`: `GenUniformGrid2D/3D()`, `GenPositionArray2D/3D()`, `GenSingle2D/3D()`; batch-методы обрабатывают набор и возвращают min/max.
- `FastNoise2/include/FastNoise/Generators/Fractal.h`, `DomainWarp.h`, `Blends.h`: композиция генераторов.
- `FastNoise2/include/FastNoise/FastNoise_C.h`: C API, включая `fnNewFromEncodedNodeTree()`, `fnGenUniformGrid2D()` и обязательное освобождение `fnDeleteNodeRef()`; это возможная поверхность FFI, но ещё не Godot binding.
- `FastNoise2/src/CMakeLists.txt`: FastSIMD загружается отдельно через CPM; он не появился от shallow clone этого репозитория. `FASTNOISE2_STRICT_FP` по умолчанию выключен и влияет на совпадение результатов между SIMD feature sets.

Первый эксперимент: offline-генерация одинаковой heightmap 256/1024/2048 с фиксированными seed и параметрами, затем импорт в тестовый Terrain3D. Измерить batch time, память и швы между тайлами. Если требуется идентичная генерация на разных компьютерах, отдельно проверить strict FP и хэши результата на нескольких SIMD-путях. Не вызывать FFI отдельно для каждого пикселя и не пересчитывать неизменную карту каждый кадр.

FastNoiseLite уже доступен в Godot. Сравнивать нужно качество/скорость нужного графа и полную стоимость адаптера, а не только синтетический вызов функции шума.

## 7. JoltPhysics — фильтры и владение физическими объектами

Точки входа:

- `JoltPhysics/HelloWorld/HelloWorld.cpp`: allocator, регистрация типов, job system, `PhysicsSystem::Init()`, layer filters/listeners, `BodyInterface`, `CreateAndAddBody()`, `OptimizeBroadPhase()` и `PhysicsSystem::Update()`.
- В том же примере `RemoveBody()` предшествует `DestroyBody()` при освобождении. `ObjectLayerPairFilterImpl`, `BPLayerInterfaceImpl`, `ObjectVsBroadPhaseLayerFilterImpl` показывают фильтрацию до обработки контактов.
- `JoltPhysics/Samples/Tests/Character/CharacterVirtualTest.cpp` и `CharacterTest.cpp`: контроллеры движения и столкновений.

Godot уже предоставляет Jolt backend. Второй независимый PhysicsSystem рядом с физикой сцены создаст необходимость синхронизации и не ускорит draw calls/скелетную анимацию. Первый эксперимент — отдельная Godot-сцена с одинаковыми коллайдерами, tick rate и нагрузкой на встроенных backend. Измерить physics-step time, время массового spawn и число контактов; повторить проверки высоты ног и доступности строительства.

## 8. Recast/Detour — отдельно bake, отдельно поиск пути

Точки входа:

- `recastnavigation/RecastDemo/Source/Sample_SoloMesh.cpp`: rasterization → compact heightfield → regions → contours → polygon/detail meshes → `dtCreateNavMeshData()` → navmesh/query.
- `recastnavigation/RecastDemo/Source/Tool_NavMeshTester.cpp`: `findNearestPoly()`, `findPath()`, `findStraightPath()`, `moveAlongSurface()`.
- `recastnavigation/RecastDemo/Source/Tool_Crowd.cpp`: `dtCrowd::init()`, `addAgent()`, `requestMoveTarget()`, настройки размеров и avoidance.
- `recastnavigation/Detour/Include/DetourNavMeshQuery.h`, `DetourNavMeshBuilder.h`, `DetourCrowd/Include/DetourCrowd.h`: границы API.

Godot использует Recast при построении navigation mesh. Первый адаптер — существующие NavigationRegion3D/NavigationServer3D. Для врагов на извилистой дороге поиск кратчайшего пути может срезать нужные петли: предписанное продвижение по маршруту сохраняется. Начать с жителей поселения: статический navmesh и 20/100 свободных агентов; измерять bake/query/crowd time, застревание и достижение цели. Не перепекать неизменную геометрию каждый кадр.

## 9. ozz-animation — ускорение sampling не заменяет импорт и вывод поз

Точки входа:

- `ozz-animation/samples/playback/sample_playback.cc`: `SamplingJob` с отдельным контекстом/буфером local transforms и последующий `LocalToModelJob`.
- `ozz-animation/samples/blend/sample_blend.cc`: sampled-позы → `BlendingJob::Layer` → blending → model matrices.
- `ozz-animation/samples/skinning/sample_skinning.cc`: `mesh.joint_remaps` и palette из model joint × inverse bind pose.
- `ozz-animation/samples/multithread/sample_multithread.cc`: собственные controller/context/locals/matrices каждого персонажа, группировка работы вместо потока на каждого actor.
- `ozz-animation/samples/foot_ik/sample_foot_ik.cc`: анимация, raycast поверхности, цели лодыжек и IK. Контакт стоп не устраняет необходимость согласования скорости пути и длины шага.
- `ozz-animation/src/animation/offline/gltf/gltf2ozz.cc`: конвертация glTF; `src/animation/offline/tools/import2ozz_anim.cc` и `include/ozz/animation/offline/animation_optimizer.h`: optimization/build с иерархическими допусками.

Первый эксперимент — 50/200/500 одинаково анимируемых персонажей, сравнение native Godot и отдельного прототипа sampling. Измерять не только SamplingJob, но и bone mapping, передачу поз, skinning, память и итоговый кадр. Потребуются формат .ozz, привязка костей, владение буферами и правила потоков. Существующий AnimationTree нельзя заменить одним добавлением DLL. Не обрабатывать один mutable sampling context одновременно из нескольких потоков.

## 10. The-Forge — карта архитектуры рендера

Точки входа:

- `The-Forge/Examples_3/Unit_Tests/src/03_MultiThread/03_MultiThread.cpp`: `MultiThread : IApp`; `Init/Load/Update/Draw/Unload/Exit`, создание ресурсов и команд; GPU frame profiling по потокам.
- `The-Forge/Examples_3/Unit_Tests/src/21_Animations/21_Animations.cpp`: `Animations : IApp`, несколько клипов и управление анимацией.
- `The-Forge/Examples_3/Unit_Tests/src/28_Skinning/28_Skinning.cpp`: asset pipeline и GPU skinning; использует Rig/Clip/AnimatedObject/SkeletonBatcher.
- `The-Forge/Examples_3/Visibility_Buffer2/src/Visibility_Buffer.cpp`: пример отдельного графического pipeline.
- `The-Forge/Common_3/Resources/ResourceLoader/Interfaces/IResourceLoader.h`: `addResource()` с `SyncToken`, `isTokenCompleted()`, `waitForToken()`, `waitForAllResourceLoads()`. Не переносить глобальное ожидание ресурсов в середину каждого игрового кадра.
- `The-Forge/Common_3/Application/Interfaces/IProfiler.h` и `Application/Profiler/GpuProfiler.cpp`: CPU/GPU измерения; `cmdBeginGpuFrameProfile()`/`cmdEndGpuFrameProfile()` видны в примерах.
- `The-Forge/Common_3/Resources/AnimationSystem/Animation/Animation.h`: анимационный слой framework.

Первый шаг — перенять раздельные метрики CPU/GPU, ресурсные очереди и принципы batching в диагностике Godot. Полный переход на The-Forge — отдельный движковый проект; потребует восстановления scene/world layer, UI, физики, звука, игровых систем, импорта и сборки. Нельзя считать чтение/клонирование framework переходом игры на новый renderer. Для изолированного сравнения достаточно одной одинаковой сцены с повторяемой камерой, материалами и количеством персонажей.

## Единый протокол измерений

Для каждого будущего эксперимента: зафиксировать SHA, hardware/driver, renderer, разрешение, лимит кадров, одинаковую сцену, числа персонажей/эффектов и положение камеры. Отделить холодный импорт/компиляцию shaders от прогретого боя. Сравнивать frame time и его пики, CPU/GPU отдельно, VRAM/RAM, draw calls, треугольники и загрузку ресурсов. Сам процент GPU при разных FPS не доказывает улучшение или ухудшение.

Вначале сохранить контрольную копию и текущие функциональные проверки. Любая оптимизация модели проходит проверку скелета/анимаций/материалов; изменение terrain — строительство/дорога/picking/высота ног; изменение эффектов — попадание/pause/x3/освобождение; изменение навигации — сохранение маршрута. Нативный debug и release export проверяются отдельно до включения новой зависимости в основную сборку.