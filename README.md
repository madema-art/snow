# SNOW

Godot 4.7.2 snowboarding time trial, entirely in `D:\Snow`. Development pass 2 replaces the short demonstration with a 9.36 km by 1.2 km mountain, roughly 3.115 km net descent, five connected regions and a skilled-run target around five minutes. Terrain and navigation create difficulty; rider acceleration/drag were not reduced and there is no maximum-speed limiter.

## Launch

Double-click `D:\Snow\Start-Snow.bat`, or in PowerShell:

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path 'D:\Snow'
```

Editor: append `--editor`. Small developer window: append `--windowed --resolution 1280x720`. Shipped target is 3840x2160 fullscreen, VSync, a 60 FPS render cap and 60 Hz physics. Actual display refresh is controlled by Windows. There is no graphics menu or gameplay HUD.

## Xbox defaults

| Control | Action |
|---|---|
| LS horizontal | Steer/carve, permanently reserved |
| A | Push off / ollie |
| B hold | Nitro; release preserves remainder |
| LT / RT | Brake / tuck |
| X in air | Grab |
| LB / RB in air | Spin left/right |
| D-pad up/down in air | Front/back flip |
| RS, on snow AND in air | Full free camera orbit / vertical look; never rider/trick control |
| RS click | Smooth camera recenter |
| Menu | Pause/resume, permanently reserved; cancel remap capture |
| View | Instant summit restart |

Right stick has a radial deadzone and analog angular-rate response. Horizontal orbit is unlimited; vertical orbit spans -20° to 72°. A manually chosen view holds for three seconds after input stops, then gently settles behind the rider. Recenter is smooth; active input cancels settling. Camera looks ahead and pulls back with speed, with sphere collision clearance.

All actions except LS/Menu can be remapped persistently, including each camera direction, flips and recenter. Conflicts swap. Pause navigation always uses D-pad/LS, A accept, B return and Menu, independent of gameplay mappings. Old valid mappings migrate to the expanded action set. Pause/results exposes time, ten fastest completions and remapping. No prompts appear while riding.

Developer keys: A/D steer, Space push/jump, Shift boost, S brake, W tuck, G grab, Q/E spin, T/F flips, arrows free camera, C recenter, R restart, Escape pause.

## Mountain and rules

Summit → Cliffs → Forest → Broken Mountain → Final Descent form one continuous mountain. Wide terrain permits route choice; a cross-slope gorge, offset escarpments, rock buttress/chute, dense forest with winding corridors, broken ridges/gullies and optional jump spurs demand navigation. Left/right safer detours trade speed against risk. No checkpoints or invisible route walls.

Push off from rest to start the clock. Clean landed jumps/tricks earn stored nitro; board color/emission alone shows capacity. Boost adds strong acceleration without extra steering traction. Every fall wipes all speed and nitro. Recoveries take severity-dependent time while the clock runs; large actual cliff falls and severe direct impacts end attempts. Instant restart needs no confirmation. The orange valley finish stops time and saves qualifying completed runs.

Massif records use `user://snow_records_massif_v2.json`; original short-course records remain preserved separately. Controls use `user://snow_controls_v2.json`, migrating valid v1 bindings. Windows saves live under `%APPDATA%\Godot\app_userdata\SNOW\`.

Low-poly procedural visuals and original synthesized, state/region-reactive snow/edge/wind/impact/nitro sound need no external assets. Music bus remains empty. No wildlife, helicopter, opponents or health system. Actual measured results and manual gaps are in docs/BUILD_STATUS.md; route/region details in docs/MOUNTAIN.md, validation commands in docs/QA.md, and system details in docs/ARCHITECTURE.md. Read CLAUDE.md before further development.


