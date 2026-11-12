@echo off
rem ==========================================================================
rem  SNOW updater. Brings the local copy up to date with GitHub "main".
rem
rem  Never run in place: Start-Snow.vbs / Play-Snow.bat copy this file to %TEMP%
rem  and run the copy, so an update that replaces this file cannot disturb it.
rem
rem    usage: snow_update.bat "<project folder, no trailing backslash>"
rem    exit 0  = up to date, updated, or offline (nothing to report)
rem    exit 20 = could not update; the reason is in launcher\update_notice.txt
rem
rem  Safety rules:
rem   - only ever fast-forwards; local commits are never rewritten or discarded
rem   - files Godot regenerates on its own (*.import, *.uid) are put back to the
rem     committed version first, because they are the usual reason a pull is
rem     refused; nothing else you changed is touched
rem   - if something else blocks the update, it is skipped and the game still
rem     starts; launcher\Repair-Snow.bat can fix it with a backup
rem ==========================================================================
setlocal EnableExtensions
set "P=%~1"
if "%P%"=="" exit /b 20
set "LOG=%P%\launcher\update.log"
set "NOTICE=%P%\launcher\update_notice.txt"
if exist "%NOTICE%" del "%NOTICE%"
> "%LOG%" echo SNOW update check %DATE% %TIME%

where git >nul 2>nul
if errorlevel 1 goto :no_git
if not exist "%P%\.git" goto :no_repo

git -C "%P%" fetch --quiet origin main >> "%LOG%" 2>&1
if errorlevel 1 goto :offline

rem Already contains everything on GitHub? Then there is nothing to do.
git -C "%P%" merge-base --is-ancestor FETCH_HEAD HEAD >> "%LOG%" 2>&1
if not errorlevel 1 goto :current

rem Put Godot's regenerated metadata back so it cannot block the update.
git -C "%P%" checkout -- "*.import" "*.uid" >> "%LOG%" 2>&1

git -C "%P%" merge --ff-only FETCH_HEAD >> "%LOG%" 2>&1
if errorlevel 1 goto :blocked
>> "%LOG%" echo Updated to the latest version.
exit /b 0

:current
>> "%LOG%" echo Already up to date.
exit /b 0

:offline
>> "%LOG%" echo Could not reach GitHub; starting the installed version.
exit /b 0

:no_git
> "%NOTICE%" echo Git was not found, so SNOW could not check for updates.
exit /b 20

:no_repo
> "%NOTICE%" echo This SNOW folder is not a Git checkout, so it cannot update itself.
exit /b 20

:blocked
> "%NOTICE%" echo SNOW could not update because files in the SNOW folder were changed on this PC.
>> "%NOTICE%" echo Nothing was overwritten. To update, run launcher\Repair-Snow.bat (it backs up your changes first).
>> "%NOTICE%" echo Details: launcher\update.log
exit /b 20
