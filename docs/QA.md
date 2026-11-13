# QA and reproducible validation — pass 6

Godot can exit 0 after a script error: always grep logs for `SCRIPT ERROR` / `ERROR` and `FAIL`. Keep logs and renders in the git-ignored `work/` folder. All persistence fixtures use disposable `user://test_*.json` files and delete them.

## Engine

- Windows: `D:\godot\Godot_v4.7.2-stable_win64.exe` (4.7.2.stable.official.ed1daf0bf). Replace `godot` below with that path and run from `D:\Snow` (PowerShell: `& 'D:\godot\...exe' ...`).
- Linux/cloud: official `Godot_v4.7.2-stable_linux.x86_64` from the GitHub release (same commit hash), checksum-verified with the release `SHA512-SUMS.txt`. Software rendering for screenshots: `xvfb-run` + Mesa llvmpipe (OpenGL 4.5). Audio runs on the dummy driver (no device) unless Movie Maker is used.

## 1. Import / parse (also registers global classes and imports audio)

```bash
godot --headless --path . --editor --import --quit
```

Run after pulling or after regenerating audio. Expect no `ERROR`.

## 2. Core rules / input / persistence

```bash
godot --headless --path . --fixed-fps 60 --script res://tests/prototype_test.gd
```

4K/VSync config, buses, RS deadzone, stationary start, push-off, ollie, airborne RS independence, midair pause, clean landing charge, partial boost, trick vs plain reward, bad landing, full wipe on crash, board darkening, recovery time, remap/conflict/persist/migration, fixed Menu/A/D-pad navigation, top ten, hundredths, restart, brake, carve direction, severity, real tree impacts (fatal and moderate), get-up, real 100 m fall. Expect `TESTS COMPLETE: 0 failures`.

## 3. Feel systems, Day/Night, soundtrack

```bash
godot --headless --path . --fixed-fps 60 --script res://tests/feel_test.gd
```

Pass 6: a fresh install is Day; the selector exists and is enabled at the summit; choosing Night applies and cross-fades while the game is paused; the music player and its position are untouched by the change; the choice is saved and reloaded; the selector is disabled and `set_mode` refused mid-run; the launch title is gone once riding; no CanvasLayer item is visible during a descent (no HUD); a Night finish is recorded only in the Night file and list; the mode can be changed again after the run; the menu shows the selected mode's leaderboard and title; both files reload separately; switching back restores the exact Day lighting values; branding and launcher files are in place. Pass 5: momentum tumbles (faster falls travel farther, body frozen at zero riding speed, several impacts, groan, get-up at rest), fatal tumble over the gorge lip (fixture), first-hit and rolling grunts, plume from a committed carve without tipping, over-lean fall after ~1.9 s at full lock, braking exception, left stick forward tuck / back brake / deadzone via real joypad events, restart needs a hold, View cycles camera range and persists, older saved mappings upgrade without losing remaps. Trick economy (no pay for tiny hops; harder > easier; combos; drop size; landing quality; per-trick fatigue; spam cap; fatigue recovery; reward cap), clean 180 switch, misaligned-landing fall, nitro partial/deplete/empty sputter, nitro adds no grip, crash wipe and dark board, tumble moves only the visual (body has zero speed/travel/nitro), get-up costs time and gains no ground, crash tiers, free look held relative to travel while carving, camera yaw composition, idle settle, look-back never redirects, fatal beat then results, disconnect auto-pause, record rank, binding names, soundtrack manager on the real `assets/music` files (fixed opener, every other song before repeats, full reshuffles with no back-to-back repeats over 25 cycles, crossfade, pause holds position, resume, restart never touches music, results keep playing, ducking, missing-opener fallback, no-music silence). Some steps set state directly and are labelled fixtures. Expect `FEEL TESTS failures=0`.

## 4. Local terrain / shortcut fixtures

```bash
godot --headless --path . --fixed-fps 60 --script res://tests/terrain_test.gd
```

Seam momentum at 40 m/s; gorge spur ollie (X=120) clears and lands with nitro; Broken Mountain pinch gap (X=170) clears with an ordinary ollie at ~30 m/s and lands cleanly with nitro. The rider is PLACED near each feature: these are local fixtures, not the full-course proof.

## 5. Whole course (ordinary inputs only)

```bash
godot --headless --path . --fixed-fps 60 --script res://tests/mountain_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/mountain_test.gd -- --cautious
godot --headless --path . --fixed-fps 60 --script res://tests/mountain_test.gd -- --tricks
godot --headless --path . --fixed-fps 60 --script res://tests/mountain_test.gd -- --camera-only
```

Each run first does camera checks, then **A: straight** (push-off, no steering; must not finish — meets rocks then a fatal gorge), then **B/C: controlled** (route knowledge + local hazard avoidance; only steer/brake/tuck — plus ollie/spin/grab/boost in `--tricks`; it may read state to decide but never writes position, velocity, heading, nitro or time). Reports time, 3D distance, peak speed, falls, and for `--tricks` the rewarded landings, nitro earned and boost seconds. Run profiles sequentially (shared disposable records file). Bot results are traversability evidence, not human difficulty.

## 6. Visual captures (software GL is fine)

```bash
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --windowed --resolution 1600x900 --fixed-fps 60 --rendering-driver opengl3 --script res://tests/visual_capture.gd
```

Writes `work/shots/*.png`: summit, look-back, fast summit, gorge approach/side, buttress, forest, tree close-up, escarpment, broken, pinch gap, final, finish, rider close-up/carve, nitro, pause, plus `ride_carve`/`ride_nitro`/`ride_plume`/`ride_tumble` from a real push-off (rendering paused while simulating; the nitro shot grants charge as a labelled VISUAL FIXTURE). Pass shot names as extra args (`-- summit forest`) to render a subset.

Night Mode: add `--night` to the args; every requested shot is rendered at night and saved with a `_night` suffix. Night-specific views: `sky_moon`, `sky_aurora`, `sky_up` (summit, camera tilted to the sky), `snow_close` (low camera over the glints), `slope_night`; `pause` focuses the Time of day line. Example:

```bash
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --windowed --resolution 1600x900 --fixed-fps 60 --rendering-driver opengl3 --script res://tests/visual_capture.gd -- --night summit sky_moon sky_aurora snow_close slope_night nitro forest pause
```

Software GL shows composition, colour and readability only; it says nothing about frame rate, and the finest glints/stars look different on a real GPU at 4K.

## 6b. Rider turntable (software GL is fine)

```bash
xvfb-run -a -s "-screen 0 1200x900x24" godot --path . --windowed --resolution 1200x900 --fixed-fps 60 --rendering-driver opengl3 --script res://tests/rider_studio.gd
```

VISUAL FIXTURE: the rider's physics is switched off and its state fields are set directly, so each pose (stand, ride, tuck, toe/heel carve, brake, grab, air) is held still and shot from several sides on the real summit, plus close-ups of the head and boots (`detail`). Writes `work/studio/<pose>_<view>.png`; add `-- --night` for Night and pose names to render a subset. Use it whenever the rider model or its posing changes.

## 7. Real ride recording (video + the game's actual audio mix)

```bash
xvfb-run -a -s "-screen 0 960x540x24" godot --path . --windowed --resolution 960x540 --fixed-fps 60 --rendering-driver opengl3 --write-movie work/movie/ride.avi --script res://tests/movie_ride.gd
ffmpeg -i work/movie/ride.avi -vn work/movie/ride.wav
```

Scripted ~32 s ride: summit ambience, push-off, tuck, three trick jumps (180, 180+grab), hard carves, nitro, empty sputter, brake, and a crash into ONE fixture tree with tumble and get-up. Movie Maker renders deterministically and records the real bus output, so levels, peaks and spectra can be analysed without an audio device. It is not a listening test.

## 7b. Soundtrack through the real mixer

```bash
xvfb-run -a -s "-screen 0 320x180x24" godot --path . --windowed --resolution 320x180 --fixed-fps 60 --rendering-driver opengl3 --write-movie work/movie/music.avi --script res://tests/movie_music.gd
ffmpeg -i work/movie/music.avi -vn work/movie/music.wav && python3 tools/analyze_mix.py work/movie/music.wav
```

Expect the opener at launch, silence while paused (4–7 s), resume at the same position, then a crossfade.

## 7c. Mix balance (music vs effects bed)

```bash
xvfb-run -a -s "-screen 0 160x90x24" godot --path . --windowed --resolution 160x90 --fixed-fps 60 --rendering-driver opengl3 --write-movie work/movie/mix_sfx.avi --script res://tests/movie_mix.gd -- --mute-music
xvfb-run -a -s "-screen 0 160x90x24" godot --path . --windowed --resolution 160x90 --fixed-fps 60 --rendering-driver opengl3 --write-movie work/movie/mix_music.avi --script res://tests/movie_mix.gd -- --mute-sfx
ffmpeg -nostats -ss 22 -i work/movie/mix_sfx.avi -af ebur128 -f null -     # integrated LUFS at speed
```

A real 40 s tucked descent (mountain hidden so software GL is fast), recorded once per half of the mix. Rule: at speed the effects bed must sit at least 8 dB below the music (pass 4: −28.6 vs −19.9 LUFS). When songs are added run `tools/measure_music.sh` and update the LOUDNESS table in `scripts/music.gd`.

## 8. Render cost / 4K probe

```bash
xvfb-run -a -s "-screen 0 3840x2160x24" godot --path . --resolution 3840x2160 --rendering-driver opengl3 --script res://tests/perf_probe.gd
```

Prints startup generation time and per-region draw calls, primitives and objects for the real chase view at 4K. Counts are hardware-independent; on Windows with the RTX GPU, run without xvfb (and use `tests/massif_capture.gd` for per-viewport GPU timing on an explicit 3840x2160 SubViewport). Frame times from software GL are meaningless and must not be reported as performance.

## 9. Launcher scripts (Linux, under wine)

```bash
sudo apt-get install -y wine64 gcc-mingw-w64-x86-64   # once
tests/launcher/run_launcher_tests.sh
```

Builds stand-in `git.exe`, `where.exe` and a fake Godot (they log their arguments and return scripted exit codes), copies the real `launcher/` scripts into a scratch project whose path contains spaces and parentheses, converts them to CRLF as a Windows checkout would have, and runs them with wine's `cmd`/`cscript`. Covered: up to date (no merge attempted); update available (generated metadata restored, then fast-forward, correctly quoted path); offline (silent, nothing merged); blocked update (notice written, cleared on the next good run); git missing (notice); the updater never resets or forces; first launch imports headlessly and remembers the version; same version does not re-import; a new version re-imports once; Godot missing (notice); `godot_path.txt` override; the game is always started with `--path` and never `--editor`; `Play-Snow.bat`; and the hidden `Start-Snow.vbs` end to end, online and offline. Expect `LAUNCHER TESTS fail=0`.

This checks the scripts' logic with wine's command interpreter. It does not run Windows, real Git, real Godot or PowerShell, so `Create-Shortcut.bat` (a PowerShell one-liner) is NOT covered and message-box/hidden-window behaviour is not observed.

## Manual tests still required on the target PC

- **Launch:** run `launcher\Create-Shortcut.bat`; the Desktop icon looks right at small and large sizes; double-click starts the game with no console and no editor; an update pushed to `main` arrives on the next launch; unplugged network still launches; splash and wordmark appear and do not delay push-off.
- **Night Mode:** readability of trees, rocks and drop lips at full speed in every region; that the snow glitter is stable and not noisy at 4K; aurora and Milky Way strength; moon size; rider and board glow; and sustained 60 FPS at 3840x2160 in Night (sky shader cost) as well as Day.

- **Xbox controller:** LS carve feel at 20/60/120 km/h, edge engagement, brake skid, tuck, A preload/release timing, coyote at lips, LB/RB/D-pad/X air tricks, RS free look at speed and in the air (look behind while riding forward), idle settle, RS-click recenter, haptics (snow texture, landings, crash tiers, nitro, empty sputter), disconnect → pause → reconnect → resume, remap every action, persistence across relaunch, menu navigation with D-pad/LS/A/B/Menu.
- **Listening (headphones and speakers):** surface transitions, air→landing transition, wind build-up and forest shelter, nitro ignite/sustain/deplete identity, empty sputter recognisability, crash weight, limiter behaviour, overall loudness.
- **4K/60:** sustained fullscreen runs through every region (forest especially), boosting, crashes, free orbit in dense trees; frame-time tails and startup time on the RTX 2070 SUPER.
- **Human routes:** first-time readability of the gorge/buttress/escarpment/cuts, both gorge ends, spur and pinch-gap shortcuts, summit rollers, final tabletop, recovery after poor lines, finish recognisability; beginner vs learned vs expert times.
