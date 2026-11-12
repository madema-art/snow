@echo off
rem Developers only: opens the SNOW project in the Godot editor.
rem Players should use the SNOW desktop shortcut (see launcher\README.md).
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "P=%%~fI"
set "GODOT_EXE=D:\godot\Godot_v4.7.2-stable_win64.exe"
if defined SNOW_GODOT set "GODOT_EXE=%SNOW_GODOT%"
if exist "%P%\launcher\godot_path.txt" for /f "usebackq delims=" %%G in ("%P%\launcher\godot_path.txt") do set "GODOT_EXE=%%~G"
if not exist "%GODOT_EXE%" (
    echo Godot was not found at "%GODOT_EXE%".
    pause
    exit /b 1
)
start "" "%GODOT_EXE%" --path "%P%" --editor
