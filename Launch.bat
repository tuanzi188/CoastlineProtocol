@echo off
setlocal
cd /d "%~dp0"
set "GODOT="
for %%G in ("%~dp0tools\godot\Godot*_win64.exe") do if exist "%%~fG" set "GODOT=%%~fG"
if defined GODOT (
    start "Coastline Protocol" "%GODOT%" --path "%~dp0."
    exit /b 0
)
where godot >nul 2>nul
if not errorlevel 1 (
    start "Coastline Protocol" godot --path "%~dp0."
    exit /b 0
)
echo Godot 4.5 or newer is required.
echo Import project.godot with Godot, then press F6/F5 to play.
echo Official download: https://godotengine.org/download/windows/
pause
