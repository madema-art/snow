# SNOW — shared Codex / Claude context (development pass 2)

Work only in `D:\Snow`, the sole project root, with `D:\godot\Godot_v4.7.2-stable_win64.exe` (Godot 4.7.2). Read README and docs/GAME_DESIGN.md, ARCHITECTURE.md, MOUNTAIN.md, BUILD_STATUS.md and QA.md before editing. The original short-prototype requirements are superseded by the second-pass full mountain requirement.

## Locked design

- The current mountain targets approximately FIVE MINUTES for a good skilled descent; beginners should need longer, and experts may improve substantially through routes/tricks/nitro. Do not return to the 60–90 second target. Never pad the clock, delay finish, reduce acceleration or impose a speed cap to manufacture completion time.
- Current course `massif_v2`: 9.36 km long, 1.2 km wide; summit to finish about 3.115 km net vertical drop. Five contiguous regions: Summit, Cliffs, Forest, Broken Mountain, Final Descent. Multiple natural routes, real ravines, cliffs/buttresses, forest corridors, gullies and optional jump lines. No checkpoints or invisible route walls. Going straight must encounter real hazards, not finish safely. Fatality must come from physical impact/fall, never an X/Z death zone.
- One rider starts stationary; explicit push-off starts time. No NPCs, wildlife, helicopter, opponents, splash, countdown, cinematic, injury/health, scoring, music, avalanche or advanced storm system.
- Absolutely no active HUD: no clock, charge meter, speed, points, warnings, popups, minimap or instructions. Pause/results alone shows hundredth elapsed time, top ten completed times, mappings and resume/restart/quit.
- LEFT STICK always steers, Menu always pauses/resumes. RIGHT STICK is independent free camera on snow AND in air; it must never steer, spin or flip the rider. Camera has continuous 360 orbit, pitch -0.35 to 1.25 rad, radial deadzone, analog rate, 3-second inactivity delay then gentle chase settling, collision sphere, speed lookahead and smooth explicit recenter (default RS click). No active-input auto-follow fight.
- Defaults: A push/ollie; B nitro; LT brake; RT tuck; X grab; LB/RB air spin; D-pad up/down air flips; RS free camera; RS click recenter; View restart. All actions except LS steering/Menu remap and persist. UI uses independent fixed D-pad/LS, A accept, B return, Menu cancel capture. New actions must not silently destroy existing remaps.
- Preserve gravity/edge carving/inertia/brake/tuck/ollie feel and powerful variable-length boost. No hard maximum speed. Landed clean jumps/tricks earn charge, harder tricks more; physical board dark/orange/bright glow is the ONLY capacity indicator. Boost/charge/depletion/empty sputter have sounds.
- EVERY fall immediately clears ALL velocity, speed and stored nitro and darkens board. Severity scales get-up delay. Nonfatal recovery counts toward time, paused time does not. Fatal direct impacts and large cliff drops end attempts without records. Restart clears all transient state. No injury system.
- 3840x2160 fullscreen, VSync, 60 render FPS cap, 60 Hz physics, no graphics menu. Windows owns actual refresh. Optimize native meshes/collision/batching; no downloads required.

## Implementation and persistence

See docs/ARCHITECTURE.md for file responsibilities. Main scene composes modular mountain, rider/visual, run, controls, camera, pause and synthesized audio. Terrain is indexed 8 m grids in 200 m chunks; rendered and collision triangles are identical. Seeded regional scenery is batched per chunk. Rock convex colliders use their actual faceted visual vertices; cylindrical trunks match visible trunks. Continuous CharacterBody movement sweeps test contacts at speed. Branch canopies are intentionally non-solid.

Course records: `user://snow_records_massif_v2.json`; old short-course records remain untouched and are not compared against this mountain. Controls: `user://snow_controls_v2.json`; valid v1 remaps migrate, with conflict-free new camera/flip actions. User save root on Windows is `%APPDATA%\Godot\app_userdata\SNOW\`. Tests use disposable separate files. Audio has SFX, region-filtered MountainWind and empty Music buses. No listening/hardware claim from code tests.

## Validation and next priorities

Run the commands in docs/QA.md: engine import/parser, core integration suite, straight/controlled mountain navigation suite, optional cautious profile and explicit 4K offscreen render/GPU measurements. Inspect logs for errors even on exit 0. Full controlled navigation may only submit normal inputs; never teleport, edit velocity/heading, fabricate nitro, modify the clock or clear hazards in that test. Test-only camera/impact fixtures and visual snapshot positioning must be distinguished from the full-run proof.

Keep BUILD_STATUS.md accurate. Physical Xbox feel/reconnects/haptics, manual alternate-route/jump-shortcut fairness, high-speed collision/camera edge cases, actual audio listening and sustained full-run 4K profiling remain manual priorities. Art, animation and audio are procedural placeholders; no ragdoll, tracks or snow deformation. Fixed seeds/60 Hz do not guarantee bit-identical cross-hardware contact physics. No Git repository was initialized; do not claim a commit. The pre-pass scripts/tests are backed up under ignored work/pass1_backup; never run the old starter as another project.


