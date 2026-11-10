# Locked decisions — after pass 3

- Repository `madema-art/snow` is the source of truth; work on branches, merge via PR, never force-push `main`. `Start-Snow.bat` fast-forward pulls `main` then opens the project in Godot 4.7.2. Game code uses only `res://`/`user://`.
- Course `massif_v2` (9360 x 1200 m, ~3115 m drop, five regions, spawn Z=8, finish Z=9180) is unchanged in layout and seeds; pass 3 added optional jump features (east summit rollers, Broken Mountain pinch gap, final tabletop) that do not change the reference route's comparability, so records stay in `snow_records_massif_v2.json`. A future geometry change that affects comparability must use a new records file and keep old files.
- About FIVE MINUTES for a good skilled descent. No speed cap, clock padding, delayed finish or reduced acceleration. Gravity 20, drag 0.0075, boost 24 m/s², burn 0.25/s preserved.
- Carving model: yaw rate limited by CARVE_ACCEL / speed (22 m/s²) and PIVOT_RATE (1.9 rad/s); edge engagement scales grip; braking breaks grip into a skid. Surfaces (powder/ice) are subtle and shared by physics, shader, audio and haptics.
- Ollie on release of A with preload (+30%) and 0.14 s coyote time; floor snap suspended 0.2 s after a pop (fixes ollies at speed). Air drag in flight is 0.35 x riding drag. LS pre-aims the board in the air without moving the rider.
- Trick rewards: air time, drop size, completed 180s, flips, grabs, combos, landing quality; per-trick and global fatigue prevent farming; cap 0.85 per landing. Clean 180s ride switch.
- EVERY fall wipes ALL velocity, speed and nitro instantly. Tumbles are presentation only; get-up at the tumble rest point only if safe (≤9 m, no lip, no hazard, clear ray) — never an advantage. Recovery 1.2–7 s by severity, clock running. Fatal falls end without records; results appear after a short beat.
- Right stick is ONLY camera. Free look is held relative to travel direction; 3 s idle settle; RS click smooth recenter; summit view holds until push-off. No random camera shake.
- Trunk visual radius == collider radius (0.3 x scale, height 4.8 x scale); canopies non-solid. Rocks/outcrops collide with convex hulls of their exact visual vertices.
- No HUD, ever. Pause/results is the only UI, also opened by controller disconnect and focus loss mid-run.
- Compatibility renderer, 4K fullscreen, VSync, 60 FPS cap, 60 Hz physics, no graphics settings. MultiMesh instance colours must stay white (Compatibility multiplies vertex colour).
- All audio is original synthesis from `tools/synth_audio.py`; Music bus stays empty. Master limiter, no clipping.
- Exclusions: no wildlife, helicopter, NPCs/opponents, health/injury, score, background music, intro/countdown, avalanche, advanced storms, progression systems.
- Automated whole-course proofs use ordinary inputs only; fixtures are labelled. Cloud runs never stand in for physical Xbox feel, listening tests or real 4K/60 profiling.
