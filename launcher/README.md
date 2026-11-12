# Launching SNOW like a game (Windows)

## One-time setup

1. Double-click **`launcher\Create-Shortcut.bat`**.
2. A **SNOW** icon appears on your Desktop. That is the game from now on.

## What the shortcut does

`SNOW.lnk` → `wscript.exe launcher\Start-Snow.vbs`, which, with no console window:

1. **Updates quietly** from GitHub `main` (`snow_update.bat`, run from a temp copy).
2. **Imports new assets** if the version changed (`godot --headless --import`, no window).
3. **Starts the game directly** (`godot --path <SNOW folder>`): no editor, no Play button.

If there is no internet the game simply starts. If something needs attention (Git or Godot missing, an update that could not be applied) one message box says so, and the game still starts whenever it can.

## Files

| File | Purpose |
|---|---|
| `Create-Shortcut.bat` | Creates/refreshes the Desktop shortcut with the SNOW icon. Run again if the folder moves. |
| `Start-Snow.vbs` | Hidden launcher the shortcut runs. |
| `snow_update.bat` | Updater: fetch, restore Godot-generated metadata, fast-forward only. |
| `snow_run.bat` | Finds Godot, imports when needed, starts the game in runtime mode. |
| `Repair-Snow.bat` | Only if SNOW says it could not update: backs up local changes, then matches GitHub. |
| `Open-Editor.bat` | Developers: open the project in the Godot editor. |
| `..\Play-Snow.bat` | Same as the shortcut but with a visible console (fallback). |
| `..\branding\snow.ico` | The shortcut icon (source SVG in `branding\source\`). |
| `..\override.cfg` | Runtime-only project settings: window icon and boot splash. |

Written by the launcher, never committed: `update.log`, `import.log`, `update_notice.txt`, `run_notice.txt`.

## Godot location

Looked for in this order: the `SNOW_GODOT` environment variable; the first line of `launcher\godot_path.txt` (create it to point somewhere else); `D:\godot\Godot_v4.7.2-stable_win64.exe`; a `Godot_v4.7.2*win64.exe` in `launcher\` or in a `godot` folder beside the SNOW folder.

## Why updates no longer get stuck

- Godot rewrites its own metadata files (`*.import`, `*.uid`) on your PC. Those used to make `git pull` refuse to update. The updater now puts them back to the committed version before updating; Godot regenerates what it needs.
- It only ever fast-forwards. It never deletes or overwrites anything else you changed; if such a change blocks the update, the update is skipped, you are told, and `Repair-Snow.bat` fixes it after saving your changes (`git stash` + a `snow-local-backup` branch).
- The updater runs from a temp copy and the launch is read completely before it starts, so an update that replaces the launcher files cannot break a launch in progress.
- Scripts are forced to Windows line endings by `.gitattributes`.
- Your records, controls and settings live in `%APPDATA%\Godot\app_userdata\SNOW\`, outside this folder, and are never touched by updates or repairs.

## `Start-Snow.bat` (old launcher)

The original `Start-Snow.bat` in the SNOW folder is deliberately left exactly as it was in this update, so that an existing copy (possibly edited on your PC) can still pull this version without a conflict. It still opens the Godot editor. Use the Desktop shortcut instead; the old file will be retired in a later update.

## A standalone .exe?

Not in this pass, on purpose: an exported `SNOW.exe` cannot update itself from GitHub the way the source checkout does, and would need a fresh export for every change. Running the installed Godot in game mode gives the same player experience (no editor) and keeps auto-update. If you later want an exported build, the soundtrack discovery and all paths already work in exports.

## Testing the launcher

`tests/launcher/run_launcher_tests.sh` runs these scripts on Linux under wine with stand-in `git`/Godot executables (31 checks). It verifies the scripts' logic; the real thing still needs one run on Windows.
