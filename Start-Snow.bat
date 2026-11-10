@echo off
setlocal
title SNOW Launcher

set "PROJECT=%~dp0"
set "GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe"

echo =====================================
echo              SNOW
echo =====================================
echo.
echo Checking GitHub for updates...

git -C "%PROJECT%" pull --ff-only origin main

if errorlevel 1 (
    echo.
    echo Update failed. No files were forcibly overwritten.
    echo Resolve the Git issue before launching.
    pause
    exit /b 1
)

echo.
echo SNOW is up to date.
echo Launching Godot...

if not exist "%GODOT%" (
    echo Godot executable not found!
    pause
    exit /b 1
)

start "" "%GODOT%" --path "%PROJECT%" --editor

endlocal
