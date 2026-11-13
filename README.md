# Коди TD — Made by Alex

Трёхмерная Tower Defense на Godot. Основной игровой проект находится в
`GodotRebuild/project.godot`; последняя подготовленная Windows-сборка — **0.6.0**.

На текущем компьютере основная рабочая папка — **`E:\Laboratory`**.
Запуск: `E:\Laboratory\KDTD.exe`. Исходная папка `G:\Cady` сохранена для
проверки владельцем; дальнейшая разработка и сборки выполняются из Laboratory.

## Получить проект

Нужны Git и [Git LFS](https://git-lfs.com/). Репозиторий приватный; сначала
авторизуйтесь в GitHub CLI (`gh auth login` и `gh auth setup-git`) либо используйте
GitHub Desktop с доступом к этому репозиторию.

```powershell
git lfs install
git clone https://github.com/LolMaSTeRCoD/Laboratory.git
cd Laboratory
git lfs pull
```

Используйте клонирование с Git LFS: обычный Download ZIP может содержать только
указатели вместо больших моделей и текстур.

## Структура

| Папка | Содержимое |
|---|---|
| `GodotRebuild/` | Действующая игра, сцены, GDScript, ресурсы, тесты и сборщик |
| `GodotRebuild/Assets/` | Полные игровые GLB, LOD, текстуры, звук и сведения об источниках |
| `Source/HeroPipeline/` | Редактируемые Blender-файлы, MakeHuman, исходные данные и референсы башен |
| `Source/EnemyPipeline/` | Редактируемые модели противников |
| `Source/*.cs` | Исходники ранних версий, сохранённые для истории проекта |
| `Assets/`, `Reference/` | Исходные изображения и дополнительные референсы |
| `Music/` | Пользовательский музыкальный плейлист |
| `docs/` | Инструкции по переносу и внешним инструментам |

Крупные бинарные ресурсы и `.blend` хранятся через Git LFS. Сохраняются `.import`,
`.uid`, исходные OBJ/MakeHuman и подготовленные LOD — они нужны для открытия и
воспроизведения проекта. Кэши `.godot`, промежуточные `Builds`, локальные `Archive`
и установленные программы `Tools` не входят в историю Git и остаются локально.
Готовая игра размещается в GitHub Releases.

## Открыть и собрать

Контрольная локальная среда проекта: **Godot 4.7.2**, **Blender 5.2.3**,
PowerShell 7 и Node.js для отдельной проверки упрощения моделей.
Официальные инструменты устанавливаются отдельно из
[Godot](https://godotengine.org/download/windows/) и
[Blender](https://www.blender.org/download/). Для экспорта нужны Windows export
templates той же версии, что и Godot.

Откройте `GodotRebuild/project.godot` в Godot. Первый импорт создаст локальный
кэш; игровые модели и материалы уже присутствуют в репозитории.

```powershell
# Готовые модели: импорт, проверки, сборка и проверка упакованной игры.
pwsh -File .\GodotRebuild\build_KDTD.ps1 -ReuseModels

# Полная регенерация Blender-моделей и те же проверки.
pwsh -File .\GodotRebuild\build_KDTD.ps1
```

Пути определяются относительно репозитория. Если инструменты находятся вне
локальной `Tools`, укажите `-GodotPath`, `-BlenderPath`, `-BlenderPythonPath` и
при необходимости `-TemplatePath`, либо соответствующие переменные
`KDTD_GODOT`, `KDTD_BLENDER`, `KDTD_BLENDER_PYTHON`, `KDTD_EXPORT_TEMPLATES`.
Имя итогового файла всегда **KDTD.exe**, в корне локального проекта.

## Проверки и текущее состояние

Сборщик выполняет проверки моделей, размещения, интерфейса, боя, аур, экономики,
камеры, кампании, экспорта и ресурсов внутри готовой сборки. Отдельные сценарии
находятся в `GodotRebuild/tests/`.

Подробности и известные ограничения:
[KDTD_STATUS.md](GodotRebuild/KDTD_STATUS.md),
[COMBAT_UPDATE.md](GodotRebuild/COMBAT_UPDATE.md),
[CHARACTER_PIPELINE.md](GodotRebuild/CHARACTER_PIPELINE.md).
Наличие скелета и прохождение технических проверок само по себе не подтверждает
требуемое художественное сходство персонажей — этот пункт остаётся отдельным
критерием качества.

Управление и пользовательская инструкция: [README.txt](README.txt).

## Дополнительные инструменты разработки

По запросу подготовлены исходники десяти внешних проектов: JoltPhysics,
Terrain3D, Material Maker, Effekseer, Voxel Tools, Recast, meshoptimizer,
FastNoise2, The-Forge и ozz-animation. Они находятся в отдельных локальных
репозиториях; точные версии закреплены в `development-tools.lock.json`.

```powershell
pwsh -File .\GodotRebuild\tools\setup_external_sources.ps1
```

Назначение, совместимость, лицензии и план применения:
[EXTERNAL_TOOLS.md](docs/EXTERNAL_TOOLS.md). Это библиотека исходников для
разработки; нативные плагины ещё не скомпилированы и не включены в игру.

## Материалы и права

Сведения об источниках и лицензиях находятся рядом с ресурсами: `ASSET_CREDITS.md`,
`ATTRIBUTIONS.txt`, `sources.json` и лицензии MakeHuman в `Source`. Они сохраняются
вместе с файлами. Перенос в приватный репозиторий не меняет прав на сторонние
изображения, музыку и персонажей; общая новая лицензия всему содержимому не
назначается.
