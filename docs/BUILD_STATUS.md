# Current build status — second development pass

Implemented directly in `D:\Snow` using Godot 4.7.2. This replaces the obsolete 74-second easy demo with a large, dangerous Massif course. Start-Snow.bat still launches the root project directly; no second project, downloads or background music were introduced.

## Implemented improvements

- **Real distance and scale:** official mountain 9360 m long x 1200 m wide, ~3115 m net vertical drop from snow under stationary spawn to finish. Spawn Z=8, finish Z=9180; backing collision terrain extends Z=-200..9600. Actual successful reference travel is about 10.03 km in 3D, including elevation and traverses.
- **Five continuous regions:** Summit 0–1320; Cliffs 1320–3360; Forest 3360–5640; Broken Mountain 5640–7800; Final Descent 7800–9360 m. Broad shoulders, curved transverse gorges, exposed buttress/chute, winding forest corridors, gullies, boulders and real snow lips/ramps provide multiple routes. No protected straight center, mandatory checkpoints, invisible barriers or X/Z death zones.
- **Contact fairness and speed:** original gravity/drag/carve/boost constants remain; no maximum-speed limiter or clock padding. Snow-only tangent momentum is preserved across innocuous internal mesh-edge contacts without restoring momentum through real hazards/walls. Rock convex hulls match actual scaled faceted visuals; trunk cylinders match visible solid trunks. Branch canopies are non-solid. Strong grazing contacts tumble; extreme direct impacts and genuinely large drops end runs. Clean normal landing tolerance is 24 m/s to support larger natural jumps; misaligned tricks remain dangerous.
- **Independent free camera:** unlimited 360 yaw, broad vertical orbit (-0.35..1.25 rad), radial 0.18 deadzone, smooth analog angular rate, on snow AND in air. RS never changes rider direction or tricks. A chosen view holds three seconds before gentle chase settling. Smooth RS-click recenter is remappable, and active manual input takes priority. Sphere sweeps check target and smoothed positions; speed lookahead/distance/FOV preserve hazard visibility.
- **Expanded controller actions:** LB/RB spins; D-pad up/down flips; RS camera; RS click recenter. All non-reserved actions remap/persist. LS steering and Menu pause remain fixed; fixed D-pad/LS/A/B UI navigation is independent. Valid v1 bindings migrate to v2 with conflict-free new actions. New-course records use their own file, preserving old short-course times separately.
- **Audio/environment:** original state-driven snow/edge/wind/impact/nitro synthesis remains; exposed gusts and smooth forest wind shelter/filtering add regional response. Music remains an empty separate bus.
- **Performance:** 49 indexed 200 m chunks, 8 m grid, 367,500 terrain triangles (~192,000 vertices), 4117 seeded trees and 960 faceted rocks, locally batched scenery with 1250 m culling. Atmospheric fog and 48 distant silhouettes emphasize scale. Compatibility rendering + 2x MSAA, one 145 m-range shadowed sun, no expensive GI/storms.

## Actual gameplay validation

All runs below use the supplied Godot executable, real generated terrain/hazard collision and fixed 60 Hz simulation. Times are actual run clock values, not wall time. Reference and cautious bots submit only normal steering/brake/tuck inputs from a normal stationary summit push-off. They never teleport, edit velocity/heading/nitro/time, remove hazards, delay finish or change physics. Built-in small local crash recovery placement still applies exactly as it does for a human.

| Test | Actual final result |
|---|---|
| A: straight downhill, no steering/brake/tuck | First rock collision at **0:53.68**, around Z=1452 m. Continued straight input repeatedly hits rocks, then suffers a real fatal gorge fall at **2:32.90**, Z=1814 m. No completion. |
| B/C: faster known-route controlled descent | **5:20.62** (320.6167 s), **10,029.73 m** 3D travel, **39.01 m/s** peak (~140 km/h), **5 recoverable falls**, successful finish. |
| More cautious input profile, same route/course/physics | **6:42.02** (402.0167 s), **10,027.61 m** travel, **27.66 m/s** peak, **4 recoverable falls**, successful finish. |
| Local terrain/shortcut fixture | 40 m/s approach retains momentum across ordinary terrain seams; a real ollie crosses the narrow gorge spur, lands without a fall and generates **0.0867 stored nitro**. Fixture starts near the gap and is explicitly separate from the whole-run proof. |
| Camera | Full yaw, pitch endpoints, active-input priority, inactivity hold, smooth recenter, airborne response/independence, deadzone drift rejection and retraction before an actual solid obstruction pass. |
| Crash/persistence rules | All nitro/velocity/speed/glow immediately clear; larger severity gives longer recovery; time continues through nonfatal recovery; actual high-speed direct tree collision and 100 m fall are fatal; remaps and records persist; finish freezes time and saves once. |

The faster reference bot knows the geography and colliders and still falls five times. It demonstrates a reachable roughly five-minute baseline with substantial speed, not a certified human skilled-run distribution. Cleaner human lines and deliberate trick/nitro/shortcut use may improve considerably; actual beginner/expert times need physical playtesting. No claim of a collision-free or physically controller-playtested whole run.

## Engine and automated checks

Executable `D:\godot\Godot_v4.7.2-stable_win64.exe`, version `4.7.2.stable.official.ed1daf0bf`.

- Headless editor import/parser: exit 0, clean final log; no missing resources or parse errors.
- Core integration suite: **40 checks passed**, zero failures. Includes input/remap migration, real airborne free camera, pause/time, nitro/rewards/glow, crashes/recovery/severity, actual impact/fall fixtures and persistence.
- Local terrain suite: **3 checks passed**, zero failures, including preserved contact momentum and clean shortcut landing/reward.
- Full mountain suite: successful straight-failure and controlled completion/time/distance/speed/finish-once checks, exit 0; final course reproduced the same 5:20.62 result. Additional focused camera suite verifies the latest active-input-over-recenter behavior, exit 0.
- Cautious whole-run profile: completed in 6:42.02; checks pass, exit 0. Lower chosen speed comes from ordinary brake/tuck input, not a different rider or modified clock.
- Rendered regional/free-camera/pause captures: real OpenGL execution, exit 0. Summit, cliffs/gorge, forest, broken terrain, finish, look-back and expanded mapping layout inspected. Snapshot positioning is separate from navigation proof. The camera capture fixture is placed on a valid broad snow shoulder, not inside a steep bank.
- Final logs are clean: pass2_import.log, pass2_core.log, terrain_test.log, mountain_test.log, mountain_cautious.log, camera_test.log and pass2_render.log in ignored `D:\Snow\work`.

Exact commands are in QA.md. All test persistence files are disposable test_*.json; production saves are not overwritten. The benchmark disables VSync/render cap only in its own process. Normal launch retains fullscreen/VSync/60 FPS cap and 60 Hz physics. Windows determines actual monitor refresh.

## Actual 4K rendering probes

NVIDIA RTX 2070 SUPER, OpenGL Compatibility. A small 1280x720 root window plus an **explicit 3840x2160 offscreen SubViewport**, 2x MSAA, actual world and shared camera. Each region warms up then samples 120 frames, with native per-viewport GPU timing, VSync/cap disabled only in this benchmark.

| Region | Whole-process mean frame ms | GPU median ms (4K viewport) | GPU p95 ms |
|---|---:|---:|---:|
| Summit | 3.03 | 1.35 | 1.84 |
| Cliffs | 3.07 | 1.37 | 1.88 |
| Forest | 3.43 | 1.55 | 2.06 |
| Broken Mountain | 2.94 | 1.31 | 1.80 |
| Final Descent | 2.93 | 1.30 | 1.80 |

The dual-view total reports 226–354 draw calls (about 113–177 for one of the identical views). Whole-process p95 is about 3.38–3.92 ms. These are **short stationary regional probes**, not a sustained five-minute moving 4K/60 certification, thermal soak or physical controller test. The old paced screenshot timing is not directly comparable. Generation is bounded but synchronous at startup and can take several seconds.

## Files changed / added

- scripts/mountain.gd: full Massif geography, scale, regions, native indexed chunks, per-chunk batches, exact trunk/rock collision, silhouettes/finish.
- scripts/rider.gd: terrain-seam momentum correction, camera-free air tricks, physical drop/direct-impact rules, glancing threshold, safe local recovery, landing tolerance and debug crash reason.
- scripts/chase_camera.gd: full independent analog orbit, pitch/idle/recenter/collision/lookahead.
- scripts/controls.gd, run_state.gd: expanded actions/migration and separate course saves.
- scripts/snow_audio.gd: regional wind exposure/filtering and dedicated bus.
- tests/mountain_test.gd, terrain_test.gd, massif_capture.gd added; prototype_test.gd expanded; capture.gd delegates to current capture script.
- CLAUDE.md, README.md and all relevant docs rewritten; MOUNTAIN.md added. Root scene, renderer settings and launcher retained. Old scripts/tests backed up in ignored work/pass1_backup. No Git repository existed and no commit was made.

## Remaining limits / next priorities

1. Physical Xbox feel, analog comfort, hardware triggers, haptics/reconnect and all remaps require hands-on sessions. Synthetic events do not certify these.
2. Human route readability/difficulty and safe/fast alternate lines are not exhaustively tested. Bots have route/collider knowledge. Coarse 8 m cliff lips, prolonged side traverses, dense tree/rock approaches and recovery near large formations need fairness review. Repeated straight input can keep colliding after get-up; active steering is required.
3. Camera orbit/collision works in automated fixtures; stress dense forests, extreme pitch, close rock walls and high-speed look-back manually.
4. Sustained actual 4K fullscreen moving play, frame-time tails, startup generation and physics under extreme collisions need profiling beyond short regional GPU probes.
5. No audio listening session was performed; synthesized sound still needs real mix/quality work. No background music.
6. Art/animation are procedural placeholders: no skeletal animation, ragdoll, tracks, spray or snow deformation. Branch canopies are non-solid. The field is finite and 60 Hz contact physics is not bit-identical replay validation/anti-cheat.
7. Preserve all locked rules: no HUD/score/injury, single rider, push-off clock, complete crash wipe, severity recovery, pause/time, saved top ten/remaps, quick restart, no wildlife/helicopter/opponents/intro/music/storms/avalanche.

## Launch

Double-click `D:\Snow\Start-Snow.bat`, or:

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path 'D:\Snow'
```

A pushes off; LS steers; RS freely looks; RS click recenters; Menu pauses; View instantly restarts. LB/RB spin and D-pad up/down flip in air. See README for all defaults and developer keys. Add --editor for editing or --windowed --resolution 1280x720 for a small developer window.

