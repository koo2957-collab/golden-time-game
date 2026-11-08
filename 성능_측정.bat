@echo off
chcp 65001 >nul
rem 이 PC에서 게임이 실시간으로 도는지 잰다 (시뮬레이션 + 화면 fps). 결과는 창에 나오고 user://benchmark.txt에 저장된다.
set GODOT=%~dp0godot\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=C:\Users\%USERNAME%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
"%GODOT%" --path "%~dp0" -s res://tests/benchmark.gd
pause
