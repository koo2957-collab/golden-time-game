@echo off
chcp 65001 >nul
rem 소방 지휘관 훈련게임 실행 (Godot 4.7.2가 필요하다). GODOT 경로를 이 PC에 맞게 고친다.
set GODOT=%~dp0godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" set GODOT=C:\Users\%USERNAME%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" set GODOT=C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot 실행 파일을 찾지 못했습니다. 이 폴더 안 godot 폴더에 Godot_v4.7.2-stable_win64.exe를 넣어 주세요.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0"
