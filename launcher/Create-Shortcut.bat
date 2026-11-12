@echo off
rem ==========================================================================
rem  Creates (or refreshes) the SNOW shortcut on your Desktop, with the SNOW
rem  icon. Double-click this once. Run it again any time the SNOW folder moves
rem  or the icon changes.
rem
rem  The shortcut starts launcher\Start-Snow.vbs, which updates quietly from
rem  GitHub and launches the game directly (no editor, no console window).
rem ==========================================================================
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "SNOW_DIR=%%~fI"
set "SNOW_VBS=%SNOW_DIR%\launcher\Start-Snow.vbs"
set "SNOW_ICO=%SNOW_DIR%\branding\snow.ico"

if not exist "%SNOW_VBS%" (
    echo Could not find "%SNOW_VBS%".
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$w = New-Object -ComObject WScript.Shell; $desktop = [Environment]::GetFolderPath('Desktop'); $s = $w.CreateShortcut((Join-Path $desktop 'SNOW.lnk')); $s.TargetPath = (Join-Path $env:SystemRoot 'System32\wscript.exe'); $s.Arguments = [char]34 + $env:SNOW_VBS + [char]34; $s.WorkingDirectory = $env:SNOW_DIR; $s.IconLocation = $env:SNOW_ICO + ',0'; $s.Description = 'SNOW'; $s.WindowStyle = 1; $s.Save(); Write-Host ('Created ' + (Join-Path $desktop 'SNOW.lnk'))"
if errorlevel 1 (
    echo.
    echo The shortcut could not be created automatically.
    echo You can make it by hand: right-click the Desktop, New, Shortcut, and use
    echo   wscript.exe "%SNOW_VBS%"
    echo then set its icon to "%SNOW_ICO%".
    pause
    exit /b 1
)

echo.
echo Done. Double-click the SNOW icon on your Desktop to play.
echo.
pause
