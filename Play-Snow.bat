@echo off
rem ==========================================================================
rem  SNOW with a visible console: updates from GitHub, then starts the game
rem  directly (no editor). Normally use the SNOW desktop shortcut instead
rem  (launcher\Create-Shortcut.bat makes it); this is the plain fallback.
rem
rem  The whole launch is one parenthesised block: cmd reads it completely before
rem  running it, so an update that replaces this file cannot disturb it.
rem ==========================================================================
setlocal EnableExtensions
for %%I in ("%~dp0.") do set "P=%%~fI"
(
    echo Checking GitHub for SNOW updates...
    copy /y "%P%\launcher\snow_update.bat" "%TEMP%\snow_update_run.bat" >nul
    call "%TEMP%\snow_update_run.bat" "%P%"
    if exist "%P%\launcher\update_notice.txt" type "%P%\launcher\update_notice.txt"
    echo Starting SNOW...
    call "%P%\launcher\snow_run.bat" "%P%"
    if exist "%P%\launcher\run_notice.txt" (
        type "%P%\launcher\run_notice.txt"
        pause
    )
    exit /b
)
