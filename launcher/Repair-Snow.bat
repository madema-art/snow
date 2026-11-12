@echo off
rem ==========================================================================
rem  Use this only if SNOW says it could not update.
rem
rem  It makes the SNOW folder match the latest version on GitHub WITHOUT losing
rem  anything: every change made on this PC is first saved in a Git stash, and
rem  any local commits are kept on a backup branch. Your records, controls and
rem  settings are not in this folder and are never touched.
rem ==========================================================================
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "P=%%~fI"
echo.
echo  This will update "%P%" to the latest SNOW from GitHub.
echo  Changes made to files in that folder on this PC are backed up first
echo  (git stash / a backup branch), then replaced by the GitHub version.
echo.
set "ANSWER="
set /p ANSWER= Type YES to continue: 
if /i not "%ANSWER%"=="YES" (
    echo Nothing was changed.
    pause
    exit /b 0
)
where git >nul 2>nul
if errorlevel 1 (
    echo Git was not found.
    pause
    exit /b 1
)
git -C "%P%" fetch origin main
if errorlevel 1 (
    echo Could not reach GitHub. Nothing was changed.
    pause
    exit /b 1
)
git -C "%P%" stash push --include-untracked -m "SNOW repair backup"
git -C "%P%" branch -f snow-local-backup HEAD
git -C "%P%" reset --hard FETCH_HEAD
if errorlevel 1 (
    echo The repair did not complete. Nothing was deleted; see the messages above.
    pause
    exit /b 1
)
echo.
echo  SNOW is now on the latest version.
echo  Your earlier local state is kept: "git stash list" and branch "snow-local-backup".
echo.
pause
