# Внешние инструменты: локальная библиотека исходников

Источники загружены из официальных репозиториев по поручению пользователя 12 ноября 2026 года. Каждая копия — отдельный shallow Git clone (`--depth 1`), без инициализации подмодулей. В рабочий проект Коди TD эти библиотеки автоматически не встроены. Изучение исходников и установка готового runtime-плагина — разные этапы.

## Назначение и применение к Коди TD

| Репозиторий | Назначение | Практический следующий шаг | Основная лицензия |
|---|---|---|---|
| [JoltPhysics](https://github.com/jrouwe/JoltPhysics) | Многопоточная физика твёрдых тел и коллизий на C++ | Сначала сравнить встроенный Jolt в Godot; отдельная сборка библиотеки сама по себе не подключает её к игре | MIT |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | Heightmap-ландшафт, LOD, покраска поверхностей, инстансинг растительности | Проверить совместимый с нашей версией Godot binary release в отдельной тестовой сцене; для сборки из исходников нужны godot-cpp, Python/SCons и C++ toolchain | MIT |
| [Material Maker](https://github.com/RodZill4/material-maker) | Процедурные PBR-текстуры и покраска 3D-моделей | Отдельный инструмент подготовки материалов; в игру экспортируются подготовленные текстуры. Исходный проект клона указывает Godot 4.7 | MIT, кроме отдельно обозначенных файлов |
| [Effekseer](https://github.com/effekseer/Effekseer) | Редактор и runtime выразительных эффектов частиц | Для игры требуется [EffekseerForGodot4](https://github.com/effekseer/EffekseerForGodot4), подходящие нативные библиотеки и проверка экспорта. Подмодули основного репозитория пока не загружены | MIT + лицензии включённых зависимостей |
| [godot_voxel](https://github.com/Zylann/godot_voxel) | Объёмная воксельная местность, тоннели, навесы и изменение геометрии | Альтернатива для пространств, которые нельзя выразить heightmap. Module требует специального Godot и экспортных шаблонов; GDExtension работает с официальным движком, но документирован как менее проверенный вариант | MIT + лицензии включённых зависимостей |
| [recastnavigation](https://github.com/recastnavigation/recastnavigation) | Построение navmesh, поиск пути Detour, управление толпой | Сначала использовать NavigationServer3D Godot и его встроенное построение Recast. Для врагов на фиксированной дороге не заменять маршрутную систему без измерений | Zlib |
| [meshoptimizer](https://github.com/zeux/meshoptimizer) | Упрощение, компрессия и оптимизация мешей; gltfpack | Проверить offline-оптимизацию копии GLB и качество skinning/анимаций. Godot уже содержит meshoptimizer; дополнительный runtime может оказаться избыточным | MIT |
| [FastNoise2](https://github.com/Auburn/FastNoise2) | Быстрое SIMD-вычисление графов процедурного шума на C++17 | Сравнить время генерации с FastNoiseLite, уже доступным в Godot. Это другая библиотека, не замена существующего класса одним переключателем; нужен offline-генератор или отдельный адаптер | MIT |
| [The-Forge](https://github.com/ConfettiFX/The-Forge) | Кроссплатформенный графический framework, загрузка ресурсов, примеры рендеринга | Изучать архитектуру, batching, streaming и профилирование. Это не Godot-addon; перенос игры потребует отдельного проекта движка, UI, звука и физических систем | Apache-2.0 для открытой части, отдельные условия консольных платформ |
| [ozz-animation](https://github.com/guillaumeblanc/ozz-animation) | Сжатая скелетная анимация, sampling и blending на C++17 | Измерять выгоду для больших толп; для подключения нужны конвертация данных и адаптер к Godot. Существующие Skeleton3D/AnimationPlayer/AnimationTree сохраняются | MIT + лицензии инструментальных зависимостей |

## Что подготовлено

- Локальные исходники, примеры и upstream-документация всех десяти проектов.
- Точные SHA и размеры локальных копий в [development-tools.lock.json](../development-tools.lock.json).
- Лицензионные файлы сохранены внутри каждого клона.
- Отдельные каталоги Git: исходники библиотек не увеличивают репозиторий самой игры.

Нативные плагины и библиотеки не скомпилированы, подмодули не загружены. Перед применением выбираются совместимая версия/commit, способ импорта, необходимые лицензии и проверка производительности. Наличие исходников не означает, что готовые эффекты, модели или новый ландшафт уже включены в KDTD.exe.

## Проверенные первичные источники

- [Jolt в Godot](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html): встроен начиная с Godot 4.4.
- [Установка Terrain3D](https://terrain3d.readthedocs.io/en/stable/docs/installation.html): совместимость определяется release notes выбранной версии.
- [Платформы Terrain3D](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html): Windows и Forward+ Vulkan поддерживаются.
- [Material Maker — README](https://github.com/RodZill4/material-maker/blob/master/README.md).
- [EffekseerForGodot4 — README](https://github.com/effekseer/EffekseerForGodot4).
- [Установка Voxel Tools](https://voxel-tools.readthedocs.io/en/latest/getting_the_module/): различия Module и GDExtension, экспортные шаблоны.
- [Встроенные зависимости Godot](https://github.com/godotengine/godot/blob/master/thirdparty/README.md): meshoptimizer и Recast.
- [FastNoiseLite в Godot](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html).
- [AnimationTree в Godot](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html).

Предложенный порядок экспериментов: Material Maker и offline meshoptimizer; отдельный тест Terrain3D; EffekseerForGodot4; затем профильные эксперименты Jolt/navigation/анимаций. Voxel Tools и The-Forge рассматривать по конкретным требованиям, а не одновременно подменять ими всю текущую архитектуру.
## Восстановление локальных копий

Скрипт: GodotRebuild/tools/setup_external_sources.ps1. По умолчанию копии располагаются в Documents/GitHub/External; можно передать -ExternalRoot. Ключ -CheckOnly только проверяет наличие, чистоту и SHA. Инициализация подмодулей выполняется лишь с -InitializeSubmodules. Существующие изменённые копии не перезаписываются. Скрипт не собирает C++ и не добавляет плагины в игру.

Подробная карта просмотренных API и примеров: [EXTERNAL_SOURCE_GUIDE.md](EXTERNAL_SOURCE_GUIDE.md).
