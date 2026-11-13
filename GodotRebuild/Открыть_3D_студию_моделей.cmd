@echo off
setlocal
set "KDTD_STUDIO_PROJECT=%~dp0."
set "KDTD_STUDIO_GODOT=%~dp0..\Tools\Godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%KDTD_STUDIO_GODOT%" set "KDTD_STUDIO_GODOT=%~dp0..\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%KDTD_STUDIO_GODOT%" (
  echo Godot was not found in the repository Tools\Godot folder. 1>&2
  exit /b 1
)
if not exist "%KDTD_STUDIO_PROJECT%\scenes\model_studio.tscn" (
  echo The model studio scene was not found beside this launcher. 1>&2
  exit /b 1
)
"%KDTD_STUDIO_GODOT%" --path "%KDTD_STUDIO_PROJECT%" "res://scenes/model_studio.tscn"
exit /b %errorlevel%
