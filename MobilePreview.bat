@echo off
setlocal
cd /d "%~dp0"
set "GODOT="
for %%G in ("%~dp0tools\godot\Godot*_win64.exe") do if exist "%%~fG" set "GODOT=%%~fG"
if defined GODOT (
    start "Coastline Mobile Preview" "%GODOT%" --path "%~dp0." --resolution 1600x720 -- --mobile-preview
    exit /b 0
)
echo Import project.godot in Godot 4.5 and add --mobile-preview to user arguments.
pause
