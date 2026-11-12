#!/bin/bash
# Exercises the Windows launcher scripts (launcher/*.bat, launcher/Start-Snow.vbs,
# Play-Snow.bat) on Linux under wine, with tiny stand-in git.exe / Godot exe /
# where.exe that log how they were called. Covers: up to date, update available,
# offline, blocked update, no git, first-launch import, re-import after an
# update, Godot missing, godot_path.txt override, a project path with spaces and
# parentheses, and that the editor is never opened.
#
#   needs: wine64, gcc-mingw-w64-x86-64      run: tests/launcher/run_launcher_tests.sh
#
# This checks the scripts' logic. It is NOT a test on real Windows: PowerShell
# (Create-Shortcut.bat), the real Git and the real Godot are not involved.
export WINEDEBUG=-all
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
S="${TMPDIR:-/tmp}/snow_launcher_test"
mkdir -p "$S/stubs"
x86_64-w64-mingw32-gcc -O1 -o "$S/stubs/git.exe" "$HERE/stub_git.c" || exit 2
x86_64-w64-mingw32-gcc -O1 -o "$S/stubs/Godot_v4.7.2-stable_win64.exe" "$HERE/stub_godot.c" || exit 2
x86_64-w64-mingw32-gcc -O1 -o "$S/stubs/where.exe" "$HERE/stub_where.c" || exit 2
wine cmd /c "ver" >/dev/null 2>&1   # creates the wine prefix on first use
C=$HOME/.wine/drive_c
PROJ="$C/Games/Snow Test (1)"
rm -rf "$C/Games" "$C/godot" "$C/stubs"; mkdir -p "$PROJ/launcher" "$PROJ/.git" "$PROJ/branding" "$C/stubs" "$C/godot"
cp "$REPO"/launcher/* "$PROJ/launcher/"; cp "$REPO/Play-Snow.bat" "$PROJ/"
# Windows checkouts have CRLF line endings (.gitattributes); reproduce that here.
sed -i 's/\r$//; s/$/\r/' "$PROJ"/launcher/*.bat "$PROJ"/launcher/*.vbs "$PROJ/Play-Snow.bat"
# Driver batch files give the scripts properly quoted arguments (wine would escape quotes passed on its own command line).
printf '@echo off\r\ncall "%%SNOW_WP%%\\launcher\\snow_update.bat" "%%SNOW_WP%%"\r\nexit /b %%errorlevel%%\r\n' > "$C/stubs/d_update.bat"
printf '@echo off\r\ncall "%%SNOW_WP%%\\launcher\\snow_run.bat" "%%SNOW_WP%%"\r\nexit /b %%errorlevel%%\r\n' > "$C/stubs/d_run.bat"
printf '@echo off\r\ncall "%%SNOW_WP%%\\Play-Snow.bat"\r\n' > "$C/stubs/d_play.bat"
export SNOW_WP="C:\\Games\\Snow Test (1)"
cp $S/stubs/git.exe $S/stubs/where.exe "$C/stubs/"
cp $S/stubs/Godot_v4.7.2-stable_win64.exe "$C/godot/"
WP='C:\Games\Snow Test (1)'
export WINEPATH='C:\stubs'
export SNOW_TEST_LOG='C:\stubs\calls.log'
export SNOW_GODOT='C:\godot\Godot_v4.7.2-stable_win64.exe'
fail=0
check() { if [ "$1" = "$2" ]; then echo "PASS: $3"; else echo "FAIL: $3 (got '$1' want '$2')"; fail=1; fi; }
has() { if grep -qF -- "$1" "$C/stubs/calls.log" 2>/dev/null; then echo "PASS: $2"; else echo "FAIL: $2"; fail=1; fi; }
hasnt() { if grep -qF -- "$1" "$C/stubs/calls.log" 2>/dev/null; then echo "FAIL: $2"; fail=1; else echo "PASS: $2"; fi; }
upd() { rm -f "$C/stubs/calls.log"; wine cmd /c 'C:\stubs\d_update.bat' >/dev/null 2>&1; echo $?; }

echo "--- updater"
rc=$(GIT_ANCESTOR_RC=0 upd); check "$rc" 0 "up to date -> exit 0"; hasnt "[merge] [--ff-only]" "up to date -> no merge attempted"
rc=$(GIT_ANCESTOR_RC=1 GIT_MERGE_RC=0 upd); check "$rc" 0 "update available -> exit 0"
has "[checkout] [--] [*.import] [*.uid]" "generated metadata restored before merging"
has "[-C] [$WP] [merge] [--ff-only] [FETCH_HEAD]" "fast-forward merge with the quoted project path (spaces and parentheses)"
rc=$(GIT_FETCH_RC=1 upd); check "$rc" 0 "offline -> exit 0 silently"; hasnt "[merge]" "offline -> nothing merged"
rc=$(GIT_ANCESTOR_RC=1 GIT_MERGE_RC=1 upd); [ "$rc" != 0 ] && echo "PASS: blocked update -> non-zero exit" || { echo "FAIL: blocked exit"; fail=1; }
[ -s "$PROJ/launcher/update_notice.txt" ] && echo "PASS: blocked update writes a notice" || { echo "FAIL: notice missing"; fail=1; }
rc=$(GIT_ANCESTOR_RC=0 upd); [ ! -e "$PROJ/launcher/update_notice.txt" ] && echo "PASS: old notice cleared on the next good run" || { echo "FAIL: stale notice"; fail=1; }
rc=$(HAVE_GIT=0 upd); [ "$rc" != 0 ] && [ -s "$PROJ/launcher/update_notice.txt" ] && echo "PASS: no git -> non-zero exit with notice" || { echo "FAIL: no git"; fail=1; }
hasnt "[reset]" "updater never resets"; hasnt "[--force]" "updater never forces"

echo "--- runner"
runner() { rm -f "$C/stubs/calls.log"; wine cmd /c 'C:\stubs\d_run.bat' >/dev/null 2>&1; rc=$?; sleep 1; echo $rc; }
rm -rf "$PROJ/.godot"
rc=$(GIT_REV=rev1 runner); check "$rc" 0 "first launch -> exit 0"
has "[--headless] [--path] [$WP] [--import]" "first launch imports assets headlessly"
has "godot [--path] [$WP]" "game started in runtime mode with the quoted path"
hasnt "--editor" "the editor is never opened"
check "$(tr -d '\r\n ' < "$PROJ/.godot/snow_imported_rev.txt")" "rev1" "imported version remembered"
rc=$(GIT_REV=rev1 runner); hasnt "[--import]" "same version -> no re-import"; has "godot [--path] [$WP]" "game started again"
rc=$(GIT_REV=rev2 runner); has "[--import]" "after an update -> re-import once"
rc=$(SNOW_GODOT='C:\nowhere\godot.exe' runner); [ "$rc" != 0 ] && echo "PASS: Godot missing -> non-zero exit" || { echo "FAIL: godot missing exit"; fail=1; }
[ -s "$PROJ/launcher/run_notice.txt" ] && echo "PASS: missing Godot writes a notice" || { echo "FAIL: run notice missing"; fail=1; }
echo 'C:\godot\Godot_v4.7.2-stable_win64.exe' > "$PROJ/launcher/godot_path.txt"
rc=$(SNOW_GODOT= runner); check "$rc" 0 "godot_path.txt override is used"
rm -f "$PROJ/launcher/godot_path.txt"

echo "--- Play-Snow.bat (visible fallback)"
rm -f "$C/stubs/calls.log"; GIT_ANCESTOR_RC=1 GIT_MERGE_RC=0 wine cmd /c 'C:\stubs\d_play.bat' >/dev/null 2>&1; sleep 1
has "[merge] [--ff-only]" "Play-Snow.bat updates"; has "godot [--path] [$WP]" "Play-Snow.bat starts the game"; hasnt "--editor" "Play-Snow.bat never opens the editor"

echo "--- Start-Snow.vbs (hidden launcher)"
rm -f "$C/stubs/calls.log"; (cd "$PROJ/launcher" && GIT_ANCESTOR_RC=1 GIT_MERGE_RC=0 timeout 60 wine cscript //nologo Start-Snow.vbs >/dev/null 2>&1); sleep 1
has "[merge] [--ff-only]" "vbs runs the updater"; has "godot [--path] [$WP]" "vbs starts the game"; hasnt "--editor" "vbs never opens the editor"
rm -f "$C/stubs/calls.log"; (cd "$PROJ/launcher" && GIT_FETCH_RC=1 timeout 60 wine cscript //nologo Start-Snow.vbs >/dev/null 2>&1); sleep 1
has "godot [--path] [$WP]" "vbs: offline still starts the game"
echo "LAUNCHER TESTS fail=$fail"
exit $fail
