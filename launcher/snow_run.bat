@echo off
rem ==========================================================================
rem  Starts SNOW as a game: no editor, no Play button.
rem
rem    usage: snow_run.bat ["<project folder>"]      (default: this file's parent)
rem    exit 0 = game started
rem    exit 2 = Godot was not found (reason in launcher\run_notice.txt)
rem
rem  Godot is looked for, in order, in:
rem    1. the SNOW_GODOT environment variable
rem    2. the first line of launcher\godot_path.txt   (create it to override)
rem    3. D:\godot\Godot_v4.7.2-stable_win64.exe
rem    4. any Godot_v4.7.2*win64.exe in launcher\ or in a "godot" folder beside SNOW
rem ==========================================================================
setlocal EnableExtensions
set "P=%~1"
if "%P%"=="" for %%I in ("%~dp0..") do set "P=%%~fI"
set "NOTICE=%P%\launcher\run_notice.txt"
if exist "%NOTICE%" del "%NOTICE%"

set "GODOT_EXE="
if defined SNOW_GODOT if exist "%SNOW_GODOT%" set "GODOT_EXE=%SNOW_GODOT%"
if not defined GODOT_EXE if exist "%P%\launcher\godot_path.txt" (
    for /f "usebackq delims=" %%G in ("%P%\launcher\godot_path.txt") do if not defined GODOT_EXE if exist "%%~G" set "GODOT_EXE=%%~G"
)
if not defined GODOT_EXE if exist "D:\godot\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=D:\godot\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_EXE for %%G in ("%P%\launcher\Godot_v4.7.2*win64.exe" "%P%\..\godot\Godot_v4.7.2*win64.exe") do if not defined GODOT_EXE if exist "%%~fG" set "GODOT_EXE=%%~fG"
if not defined GODOT_EXE goto :no_godot

rem Godot must (re)import assets once after a fresh download or an update,
rem otherwise new sounds, songs and images would be missing. This is quick and
rem shows no window. The last imported version is remembered in .godot\.
set "REV=unknown"
for /f "delims=" %%R in ('git -C "%P%" rev-parse HEAD 2^>nul') do set "REV=%%R"
set "DONE="
if exist "%P%\.godot\snow_imported_rev.txt" set /p DONE=<"%P%\.godot\snow_imported_rev.txt"
set "NEED_IMPORT="
if not exist "%P%\.godot\imported" set "NEED_IMPORT=1"
if not "%REV%"=="%DONE%" set "NEED_IMPORT=1"
if defined NEED_IMPORT (
    "%GODOT_EXE%" --headless --path "%P%" --import > "%P%\launcher\import.log" 2>&1
    if exist "%P%\.godot" > "%P%\.godot\snow_imported_rev.txt" echo %REV%
)

start "SNOW" "%GODOT_EXE%" --path "%P%"
exit /b 0

:no_godot
> "%NOTICE%" echo SNOW could not find Godot 4.7.2.
>> "%NOTICE%" echo Expected: D:\godot\Godot_v4.7.2-stable_win64.exe
>> "%NOTICE%" echo To use another location, put its full path on the first line of launcher\godot_path.txt
exit /b 2
