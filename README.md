# SNOW

A HUD-free, single-rider snowboarding time trial for **Godot 4.7.2 (GDScript)**. One rider stands at the summit of the Massif — a 9.36 km x 1.2 km mountain with ~3.1 km of vertical — and the only goal is to reach the valley finish as fast as possible. Gravity, carving, terrain and nerve decide the time; a good skilled descent takes about five minutes.

Repository: <https://github.com/madema-art/snow> (main branch is what the local launcher pulls).

## Play (Windows, local)

Double-click `Start-Snow.bat`. It runs `git pull --ff-only origin main` in the project folder, then opens the project in Godot (`D:\godot\Godot_v4.7.2-stable_win64.exe`); press F5 to play. Or run the game directly:

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path 'D:\Snow'
```

Shipped target: 3840x2160 fullscreen, VSync, 60 FPS render cap, 60 Hz physics, no graphics menu. Developer window: append `--windowed --resolution 1280x720`.

## Develop anywhere (cloud / Linux)

Everything uses `res://` paths; nothing depends on `D:\`. Fetch the official engine (checksum-verify against `SHA512-SUMS.txt` from the same release):

```bash
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
```

Then follow [docs/QA.md](docs/QA.md): headless import, the four automated suites, and optional software-GL screenshots / Movie Maker captures under Xvfb.

## Xbox controls (defaults)

| Control | Action |
|---|---|
| Left stick | Steer / carve (**fixed**) |
| Right stick | Free camera: unlimited orbit, look behind/uphill/across — on snow and in the air. Never steers or spins the rider |
| RS click | Smoothly recenter the camera |
| A | Push off (starts the clock) · hold to crouch, release to ollie (longer hold = bigger pop) |
| B (hold) | Nitro; release to save the rest |
| LT / RT | Brake-skid / tuck |
| X (air) | Grab |
| LB / RB (air) | Spin left / right |
| D-pad up / down (air) | Front / back flip |
| Menu | Pause / resume (**fixed**) |
| View | Instant restart from the summit |

Every action except left-stick steering and Menu can be remapped in the pause menu; conflicts swap, mappings persist. The menu always navigates with D-pad/left stick, A, B and Menu. Unplugging the controller or losing window focus mid-run pauses the game. Keyboard (developer): A/D steer, Space push/ollie, Shift nitro, S brake, W tuck, G grab, Q/E spin, T/F flips, arrows camera, C recenter, R restart, Esc pause.

## Rules

- No HUD while riding: no clock, speed, nitro bar, score, minimap, prompts or arrows. The pause/results screen alone shows elapsed time (hundredths), the ten fastest **completed** descents and the control mapping.
- The board is the only nitro meter: dark when empty, orange as it charges, luminous near full, dimming as boost burns.
- Landed jumps and tricks build nitro: bigger air, bigger drops, harder spins/flips/grabs and combinations pay more; clean landings pay more than sketchy ones; repeating the same trick (or spamming hops) quickly stops paying.
- **Every fall instantly wipes all speed and all stored nitro.** Minor/moderate/severe falls cost more or less get-up time; the clock keeps running. Huge cliff drops, falls into gorges and extreme direct impacts end the run (never recorded). There are no health or injury systems and no death zones — only real geometry.
- Five regions — Summit, Cliffs, Forest, Broken Mountain, Final Descent — on one continuous mountain with no checkpoints or invisible walls. Riding straight down meets rocks and then a fatal gorge. Several routes and optional shortcut jumps exist; see [docs/MOUNTAIN.md](docs/MOUNTAIN.md).

## Saves

Course records: `user://snow_records_massif_v2.json` (pass-3 changes keep the same course and timing basis). Controls: `user://snow_controls_v2.json`. On Windows: `%APPDATA%\Godot\app_userdata\SNOW\`. Tests only use disposable `test_*` files.

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

All art, animation and sound effects are original and procedural/synthesized in this repository (no downloaded assets). 

## Soundtrack

Owner soundtrack in `res://assets/music/`, managed by `scripts/music.gd` (SnowMusic) on the `Music` bus: every launch opens with `Alpine Shift (Take 2) (Remix).mp3` (exact name; a random song if it is missing), then a shuffle bag of every other song, then full reshuffles of all songs (opener included), never the same song twice in a row, 2.5 s equal-power crossfades, gentle ducking under crashes and nitro ignition. Any .mp3/.ogg dropped into the folder is discovered automatically (editor and exported builds). Explicit pauses pause it in place; crashes, finishes, results and restarts never interrupt or restart it. No titles or controls are ever shown. With no songs the game is silent of music and works normally. To add music, commit `.mp3`/`.ogg` files to `assets/music/`; no playlist editing is needed.
