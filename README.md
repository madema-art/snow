# SNOW

A HUD-free, single-rider snowboarding time trial for **Godot 4.7.2 (GDScript)**. One rider stands on the summit of the Massif — a real, 360-degree alpine mountain about 20 km across with ~3.4 km of vertical — and the only goal is to reach the bottom as fast as possible, down **any** side. Gravity, carving, terrain, route-finding and nerve decide the time; a good skilled descent takes about five minutes.

Repository: <https://github.com/madema-art/snow> (main branch is what the local launcher pulls).

## Play (Windows, local)

**One-time setup:** double-click `launcher\Create-Shortcut.bat`. A **SNOW** icon (mountain, moon and aurora) appears on the Desktop.

**From then on:** double-click the SNOW icon. With no console window and no Godot editor it quietly updates from GitHub `main`, imports anything new, and starts the game. No internet? It just starts. Details, files and troubleshooting: [launcher/README.md](launcher/README.md).

- `Play-Snow.bat` does the same with a visible console (fallback).
- `launcher\Open-Editor.bat` opens the project in the Godot editor (development).
- `launcher\Repair-Snow.bat` is for the rare case where SNOW says an update could not be applied: it saves local changes (stash + `snow-local-backup` branch) and then matches GitHub.
- `Start-Snow.bat` is the old editor launcher, left untouched for now so existing copies update cleanly.

Godot is expected at `D:\godot\Godot_v4.7.2-stable_win64.exe`; put a different path in `launcher\godot_path.txt` if it lives elsewhere. To run by hand:

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path 'D:\Snow'
```

Shipped target: 3840x2160 fullscreen, VSync, 60 FPS render cap, 60 Hz physics, no graphics menu. Developer window: append `--windowed --resolution 1280x720`.

## Day and Night

The pause menu has one extra line: **Time of day: Day / Night**. It can be changed at the summit before pushing off and again after a run or restart; it is locked while a timed descent is in progress. The choice is remembered, and a fresh install starts in Day.

Night is the same mountain, physics and course under a full moon: stars, the Milky Way, slow aurora curtains, silver-blue moonlit snow that glitters, and a board whose nitro glow lights the snow around it. There is no headlamp or spotlight; you ride by moonlight.

Day and Night keep **separate top tens**; the menu shows the list for the selected mode.

## Develop anywhere (cloud / Linux)

Everything uses `res://` paths; nothing depends on `D:\`. Fetch the official engine (checksum-verify against `SHA512-SUMS.txt` from the same release):

```bash
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
```

Then follow [docs/QA.md](docs/QA.md): headless import, the four automated suites, and optional software-GL screenshots / Movie Maker captures under Xvfb.

## Xbox controls (defaults)

| Control | Action |
|---|---|
| Left stick | On the summit: turn the board to choose your side. Riding: steer / carve. Push **forward** to crouch into a tuck and gain speed, pull **back** to brake (**fixed**) |
| Left stick, leaned hard | Throws a plume of snow out the opposite side and turns tighter. Held at full lean too long, the edge washes out and you tumble |
| Right stick | Free camera: unlimited orbit, look behind/uphill/across — on snow and in the air. Never steers or spins the rider |
| RS click | Smoothly recenter the camera |
| A | Push off (starts the clock, and again whenever you are nearly stopped) · hold to crouch, release to ollie (longer hold = bigger pop) |
| B (hold) | Nitro; release to save the rest |
| LT / RT | Brake-skid / tuck |
| X (air) | Grab |
| LB / RB (air) | Spin left / right |
| D-pad up / down (air) | Front / back flip |
| Menu | Pause / resume (**fixed**) |
| View | Camera distance: close / medium / far (remembered) |
| Y (hold) | Restart from the summit (hold about a third of a second, so a stray tap never wipes a run) |

Every action except left-stick steering and Menu can be remapped in the pause menu; conflicts swap, mappings persist. The menu always navigates with D-pad/left stick, A, B and Menu. Unplugging the controller or losing window focus mid-run pauses the game. Keyboard (developer): A/D steer, Space push/ollie, Shift nitro, S brake, W tuck, G grab, Q/E spin, T/F flips, arrows camera, C recenter, R restart, Esc pause.

## Rules

- No HUD while riding: no clock, speed, nitro bar, score, minimap, prompts or arrows. The pause/results screen alone shows elapsed time (hundredths), the ten fastest **completed** descents for the selected time of day, the Day/Night selector and the control mapping. A wordmark fades over the summit for a few seconds at launch and is gone before or the moment you push off.
- The board is the only nitro meter: dark when empty, orange as it charges, luminous near full, dimming as boost burns.
- Landed jumps and tricks build nitro: bigger air, bigger drops, harder spins/flips/grabs and combinations pay more; clean landings pay more than sketchy ones; repeating the same trick (or spamming hops) quickly stops paying.
- Falls are momentum physics: the rider is thrown with the speed they had, bounces, rolls and slides to rest (grunting all the way), then gets up there. A tumble that carries over a real drop is fatal.
- **Every fall instantly wipes all speed and all stored nitro.** Minor/moderate/severe falls cost more or less get-up time; the clock keeps running. Huge cliff drops, falls into gorges and extreme direct impacts end the run (never recorded). There are no health or injury systems and no death zones — only real geometry.
- One mountain, every direction: steep icy cliffs and couloirs on the north, forests to the east, broad snowfields to the south, ravines and cornices to the west. No course, no checkpoints, no invisible walls, no finish line: the run ends on whichever valley floor you reach. Riding straight down meets real hazards on every side. See [docs/MOUNTAIN.md](docs/MOUNTAIN.md).

## Saves

All under `user://` (`%APPDATA%\Godot\app_userdata\SNOW\` on Windows), never touched by updates:

| File | Contents |
|---|---|
| `snow_records_massif_v4.json` | Day top ten on the 360-degree mountain (time and the side it finished on) |
| `snow_records_massif_v4_night.json` | Night top ten |
| `snow_settings.json` | Selected time of day |
| `snow_controls_v2.json` | Button mapping |
| `snow_camera.json` | Camera distance |

Older record files from the earlier linear courses (`massif_v3`, v2 and before) are kept untouched; their times are not comparable with the new mountain. Tests only use disposable `test_*` files.

## Documentation

| Doc | Contents |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Shared agent context and locked rules — read first |
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | Design pillars and rules |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Files, systems, physics/camera/audio internals |
| [docs/MOUNTAIN.md](docs/MOUNTAIN.md) | Geography, routes, shortcuts, fairness |
| [docs/AUDIO_DESIGN.md](docs/AUDIO_DESIGN.md) | Sound design, synthesis tool, mix and buses |
| [docs/QA.md](docs/QA.md) | Exact validation commands (cloud and Windows) |
| [docs/BUILD_STATUS.md](docs/BUILD_STATUS.md) | What is implemented, measured results, what still needs hands-on testing |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Locked decisions |
| [launcher/README.md](launcher/README.md) | How the Windows launch, update and shortcut work |

All art, animation, sound effects, the icon and the splash are original and procedural/synthesized in this repository (no downloaded assets). Icon and splash sources: `branding/source/*.svg` (rebuild with `node tools/render_branding.js` then `python3 tools/make_icon.py`).

## Soundtrack

Owner soundtrack in `res://assets/music/`, managed by `scripts/music.gd` (SnowMusic) on the `Music` bus: every launch opens with `Alpine Shift (Take 2) (Remix).mp3` (exact name; a random song if it is missing), then a shuffle bag of every other song, then full reshuffles of all songs (opener included), never the same song twice in a row, 2.5 s equal-power crossfades. The soundtrack leads the mix: songs are level-matched to −16 LUFS (LOUDNESS table in `scripts/music.gd`, refreshed with `tools/measure_music.sh`) and play at −3 dB on the Music bus (≈ −20 LUFS), while the wind and snow bed at speed sits near −29 LUFS; landings, crashes and nitro punch through. Any .mp3/.ogg dropped into the folder is discovered automatically (editor and exported builds). Explicit pauses pause it in place; crashes, finishes, results and restarts never interrupt or restart it. No titles or controls are ever shown. With no songs the game is silent of music and works normally. To add music, commit `.mp3`/`.ogg` files to `assets/music/`; no playlist editing is needed.
