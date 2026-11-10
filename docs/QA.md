# QA and reproducible validation — Massif v2

Engine: `D:\godot\Godot_v4.7.2-stable_win64.exe` (4.7.2.stable.official.ed1daf0bf). Sole root D:\Snow. Commands below are PowerShell; keep logs in ignored `D:\Snow\work`. Check ERROR/SCRIPT ERROR/WARNING text as well as exit codes: Godot can return 0 on parse errors.

## Engine import/parser

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'D:\Snow' --editor --import --quit 2>&1 | Tee-Object 'D:\Snow\work\pass2_import.log'
```

## Core rules / camera input / persistence

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'D:\Snow' --fixed-fps 60 --script res://tests/prototype_test.gd 2>&1 | Tee-Object 'D:\Snow\work\pass2_core.log'
```

Tests actual scene/physics, stationary clock, push-off, ollie, real airborne RS independence and camera response, deadzone drift rejection, midair pause, clean landed charge, variable boost, harder trick reward, bad landing, complete charge/momentum/glow wipe, running recovery time, reserved bindings, conflict swapping and persistence, malformed save values, legacy action migration, fixed Menu/capture/D-pad focus/accept behavior, sorted top ten, hundredths, restart, brake/carve direction, severity duration, actual direct fatal/moderate tree collisions, safe get-up and real 100 m physical fall. Persistence fixtures use separate test_*.json paths and clean up. Production records/remaps are never overwritten by the tests.

## Terrain contact and optional jump fixture

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'D:\Snow' --fixed-fps 60 --script res://tests/terrain_test.gd 2>&1 | Tee-Object 'D:\Snow\work\terrain_test.log'
```

This explicitly positions a LOCAL collision fixture near the narrow gorge spur at X=120, with 40 m/s approach speed. It checks that innocuous mesh seams do not discard speed, then presses ordinary jump input and verifies clearing the actual gap, clean landing and earned stored nitro. This local placement is not the full-course traversability proof.

## Whole course: straight versus controlled (A/B/C/D)

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'D:\Snow' --fixed-fps 60 --script res://tests/mountain_test.gd 2>&1 | Tee-Object 'D:\Snow\work\mountain_test.log'
```

The camera checks prove unlimited horizontal orbit, pitch endpoints, movement independence, inactivity hold, smooth recenter and retraction in front of an actual added solid obstruction. The fixture is removed before descent.

Test A pushes off with no steering/brake/tuck. It uses actual collisions, can recover naturally after falls, and must not finish easily; it meets rocks then a real gorge drop. The log reports every impact and final state/time/position. Test B restarts at the normal summit and uses only ordinary steering/brake/tuck actions, route knowledge and local obstacle avoidance on the real rider. It never writes position, velocity, heading, nitro or time after push-off; it never clears course hazards or delays finish. Built-in collision recovery still performs the same small local reposition as human gameplay. Test C measures the untouched actual fixed-step run clock, accumulated 3D distance, peak speed and falls. Final assertions require completion around the five-minute target, real distance/speed and record-once/time-freeze behavior. Test-only route waypoints are not in-game checkpoints.

The reference bot knows the landscape and all nearby collider positions; this is repeatable skilled route knowledge, not a human usability/playtest result. Successful bot runs may still crash. Frame-step simulation time is not wall-clock duration. Cross-hardware bit-identical contact physics is not guaranteed.

Optional cautious input profile, SAME course/physics/clock, lower selected speed through ordinary brake/tuck choices:

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'D:\Snow' --fixed-fps 60 --script res://tests/mountain_test.gd -- --cautious 2>&1 | Tee-Object 'D:\Snow\work\mountain_cautious.log'
```

Run the two profiles sequentially because they share a disposable test record filename. This comparison does not measure actual beginner/expert human populations. Tests allow 100 ms real time at exit for audio mixer cleanup after accelerated stepping.

## Rendered view / explicit 4K GPU probes

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path 'D:\Snow' --windowed --resolution 1280x720 --script res://tests/massif_capture.gd 2>&1 | Tee-Object 'D:\Snow\work\pass2_render.log'
```

Captures all five regions, gorge look, look-behind and pause/remaps in work/pass2_*.png. Snapshot positioning is a VISUAL fixture, separate from full-run proof. The benchmark creates an explicit 3840x2160 SubViewport with 2x MSAA sharing the actual world and camera, samples native per-viewport GPU timing across 120 frames after warmup, and prints CPU frame average/p95 and GPU median/p95. VSync and render cap are disabled only inside this test process; shipped settings stay fullscreen/VSync/60. Total reported draw calls include both the small root window and the explicit 4K view; do not misreport those as single-view calls. Old tests/capture.gd delegates to this updated script.

These are short stationary regional render probes, not sustained whole-course moving performance or hardware controller certification. They provide a real 4K rendering target without needing a 4K monitor. Do not compare an uncapped GPU sample directly against the earlier paced 16.45 ms stationary screenshot sample.

## Essential physical/manual tests still required

- Xbox hardware: LS steering direction/feel/inertia, triggers, full RS look-behind while riding/in air, diagonal deadzone, inactive settle and smooth recenter; haptics and reconnects. Remap all non-reserved actions, save/relaunch, cancel capture and preserve fixed D-pad/LS/A/B/Menu UI navigation.
- Human route learning: initial route readability, several ways around each gorge/buttress, low-speed tree avoidance, preserving speed across ridges, safely braking/traversing, all optional jump/chute lines. Compare beginner/learned/expert completion distributions; tune geography without flattening challenge or slowing the board.
- High-speed collision fairness at tree edges, actual rock facets, cliff lips, coarse 8 m terrain cells and uneven landing surfaces. Check low-energy brushes versus tumbling, large drops/direct impacts versus fatality, full nitro/momentum/glow wipe and safe local get-up placement. Time continues through recovery.
- Camera: dense trees/rocks, steep terrain, extreme pitch, full orbit and look-behind at speed; ensure no clipping or abrupt direction changes. Input must never alter rider/tricks. Pause midair freezes camera, audio, simulation and clock.
- Tricks and nitro: clean/misaligned spins/flips, grab reward, board-only charge, partial bursts, depletion/empty sputter and no steering gain. Finish through orange valley gate, record once, persist top ten; instant restart from every state. Absolutely no active HUD or music.
- Listen on headphones/speakers: regional exposure/forest shelter, scrape/edge/wind balance, loop seams, impacts, boost and sputter distinction. No audio listening session is implied by code validation.
- Sustained actual 3840x2160 fullscreen 60 Hz gameplay profiling: frame-time tails, forest/boost/landings/free orbit, startup generation and native physics budget. Short offscreen GPU probes do not certify a full session at stable 60 FPS.


Focused camera regression without repeating the full descent: run the mountain_test.gd command with `-- --camera-only`. This covers the latest active-input-over-recenter priority along with yaw/pitch/hold/recenter/solid obstruction checks.
