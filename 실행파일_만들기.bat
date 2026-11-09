@echo off
chcp 65001 >nul
rem 배포용 exe 만들기. 처음 한 번은 Godot 편집기에서 '편집기 > 내보내기 템플릿 관리 > 다운로드 및 설치'가 필요하다.
set GODOT=%~dp0godot\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=C:\Users\%USERNAME%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
if not exist "%~dp0build" mkdir "%~dp0build"
"%GODOT%" --headless --path "%~dp0" --export-release "Windows Desktop" "%~dp0build\FireCommander.exe"
echo 완료되면 build 폴더의 FireCommander.exe 하나만 교육용 PC에 복사하면 된다.
pause
