# Current build status — development pass 3

Pass 3 is a gameplay, camera, visual and audio overhaul of the pass-2 Massif. It was developed in a cloud container against the GitHub repository with the **official Godot 4.7.2 Linux build** (`4.7.2.stable.official.ed1daf0bf`, the same commit as the Windows executable, SHA-512 verified). The container has **no GPU, no audio device and no controller**: rendering used Mesa llvmpipe (software OpenGL 4.5) under Xvfb, audio was captured through Godot's Movie Maker, and controllers were simulated with input actions/events. Nothing below claims hardware feel, listening, or real 4K/60 performance.

## What changed

**Riding physics** (`scripts/rider.gd`, constants in `scripts/snow_tuning.gd`)
- Carve model: yaw rate limited by the lateral acceleration an edge can hold (22 m/s²) and a low-speed pivot cap (1.9 rad/s); shaped analog steering with fast edge release; edge engagement scales grip; braking deliberately breaks grip into a skid. Gravity, drag, boost and burn constants unchanged; no speed cap.
- Snow surfaces (powder/ice) from the terrain itself, subtly affecting grip/resistance, and shared with the shader, audio and haptics.
- Ollie on release with crouch preload (+30%) and 0.14 s coyote time. **Bug fix:** at speed on steep snow the ollie's world velocity still pointed down, so floor snap glued the board back (pass-2 high-speed ollies silently failed); snap is now suspended for 0.2 s after a pop.
- Air: air-only drag, LS pre-aims the board, ramped spins/flips, grabs; confirmed-air filter for terrain micro-hops.
- Landing quality (spin/flip completion, board-vs-travel alignment, impact) and a trick economy: air time, drop size, 180s, flips, grabs, combos, quality; per-trick and global fatigue; per-landing cap. Clean 180s ride switch.
- Crashes: everything is wiped first, then a visual-only tumble (bounces off trunks/rocks, settles on its back) plays; get-up happens where the tumble safely stopped or at the conservative recovery point. Severity tiers drive animation, sound and rumble. Fatal falls keep falling for presentation and results appear after a short beat.
- Riders pinned against a trunk at walking speed now shuffle around it instead of sticking.
- After the finish the rider skids to a stop (clock already frozen).

**Camera** (`scripts/chase_camera.gd`): free look held relative to travel direction (looking back stays back while carving); smoothed analog rate; 3 s idle settle (ramped), smooth RS-click recenter, summit view holds until push-off; speed framing 5.8→8.6 m and FOV 62→73° (+boost); look-ahead toward the snow ahead; automatic rise when the ground drops away ahead; loose in the air without following spins/flips; holds and widens on crashes; sprung vertical anchor; damped-spring landing nod instead of shake; asymmetric collision (instant retract, slow re-extend).

**Mountain** (`scripts/mountain.gd`, `scenery_meshes.gd`, `atmosphere.gd`, `backdrop.gd`, `shaders/`)
- New terrain shader: packed/powder/ice snow, wind-ripple (sastrugi) and bump detail normals, rock strata on steep faces, scoured lips, AO pooled around trunks/boulders, sparse sun glints.
- Tiered, drooping, snow-loaded conifers (4 variants + far LOD), noise-faceted boulders whose exact vertices are their colliders, ~880 cliff outcrops on steep walls.
- Surrounding massif: side valleys, serrated ridges, the summit falling away behind the start, a far range closing the valley; coarse collision under the course edge.
- Lighting: sky shader (haze, sun glow, cirrus), sky ambient, ACES exposure, aerial-perspective fog, glow, 4-split sun shadows to 260 m.
- Timber finish gate with banner, pennant lines and timing hut; timbered flanks in the final bowl.
- Optional jump lines: east-summit wind-drift rollers, a Broken Mountain pinch gap with kicker and landing (X=170), a final-bowl tabletop. Approaches to shortcuts kept clear of scenery.
- Visible trunk radius reduced to 0.3 x scale (from 0.5) to look like trees; colliders still match exactly.

**Rider** (`scripts/rider_visual.gd`): shaped board (sidecut, camber, kicked tips, thickness, glowing top sheet/rims), bindings with highbacks and straps, boots, baggy pants, jacket with hem and backpack, gloves, helmet and goggles. Two-bone IK legs/arms every frame; inclination from real lateral acceleration; crouch spring absorbs landings; tuck, preload, pop extension, grab reaching the toe edge, spin wind-up, flip tuck, head looking down the nose, flail/lie/get-up, board chatter on ice, jacket flutter at speed.

**FX** (`scripts/snow_fx.gd`): edge spray from the working edge, landing/crash/tumble bursts, nitro embers, snow falling from boughs you ride through, persistent board tracks for the whole run.

**Audio** (`tools/synth_audio.py`, `audio/`, `scripts/snow_audio.gd`, `scripts/haptics.gd`): 32 original synthesized sounds; surface-aware board layers, three wind layers plus clothing, landing/crash/tumble tiers, the nitro voice (ignite → resonant build → "singing ice" sustain → deplete) and the empty sputter; positional pass-by whooshes; exposure/forest-shelter/cliff-reverb environment; limiter and glue compression. **Soundtrack:** `scripts/music.gd` plays the owner's files from `res://assets/music/` (added to `main` during this pass) on the Music bus in filename order with a looping playlist, and stays silent when the folder has no audio. Controller haptics for snow texture, landings, crash tiers, nitro and sputter.

**UI / controls**: restyled frosted pause/results screen (time, top ten with the new entry highlighted, readable remap names), auto-pause on controller disconnect and window focus loss, results delayed briefly after a finish/fatal crash. Same 15 remappable actions; control and record files unchanged.

## Automated validation (cloud, Godot 4.7.2 Linux, 60 Hz fixed step)

| Suite | Result |
|---|---|
| Import / parse | exit 0, no errors |
| `prototype_test.gd` (core rules, input, persistence) | **40/40 passed** |
| `feel_test.gd` (new pass-3 systems + soundtrack player) | **37/37 passed** |
| `terrain_test.gd` (local fixtures) | **5/5 passed**: seam momentum; spur ollie clears and earns **0.18** nitro; Broken Mountain pinch gap clears with an ordinary ollie at ~30 m/s and earns **0.22** nitro |
| `mountain_test.gd` camera checks | 8/8 passed (also `--camera-only`) |
| A: straight push-off, no input | Rock falls, then **fatal gorge fall at 1:19.57**, Z≈1803 m — no completion |
| B/C: controlled reference route | **5:24.52** (324.52 s), 9,992 m 3D travel, 38.8 m/s peak (~140 km/h), 4 recoverable falls, finish recorded once |
| Cautious profile | **6:45.55**, 28.2 m/s peak, 4 falls |
| Tricks profile (ollies/spins/grabs + spending nitro, same route) | **5:20.05**, 43.4 m/s peak, **17** rewarded landings, **2.18** boards of nitro earned, **7.1 s** boosting |

Bots use only ordinary inputs (they read state to decide) and never write position, velocity, heading, nitro or time. They know the route, so they demonstrate traversability and a ~5-minute baseline, not human difficulty. Pass-2 equivalents for comparison: 5:20.62 controlled, 6:42.02 cautious, straight fatal at 2:32.90.

## Rendering evidence (software GL — appearance only)

Captured with `tests/visual_capture.gd` at 1600x900 and `tests/movie_ride.gd` (Movie Maker, 960x540) and inspected: summit vista, look-back, gorge approach (dark scoured band and visible far wall), gorge side view, buttress, forest and tree close-up, escarpment, Broken Mountain pinch gap (kicker reads as scoured stone), final bowl, finish gate, rider close-up, carving with spray and tracks, nitro glow/embers, pause menu, and a real ride with airs, carves, boost and sputter. Renders are not committed (git-ignored `work/`); regenerate with QA.md §6–7.

## Render cost probe (4K, counts only)

`tests/perf_probe.gd` at 3840x2160 (llvmpipe). Draw calls / primitives / objects are scene properties and transfer to the target GPU; the llvmpipe frame times are meaningless and are not reported.

| View | Draw calls | Primitives | Objects |
|---|---:|---:|---:|
| Summit | 465 | 575,682 | 465 |
| Cliffs | 477 | 591,228 | 477 |
| Forest | 484 | 1,197,103 | 484 |
| Broken Mountain | 470 | 457,031 | 470 |
| Final Descent | 426 | 498,910 | 426 |
| Finish | 367 | 231,145 | 367 |

Counts include all passes (4 shadow splits + main) and were taken after merging boulder and outcrop batches per chunk (≈5–10% fewer calls than before the merge). Startup generation measured **3.2 s** on the cloud CPU (pass 2 built a lighter world). Physics process ~0.6 ms per tick. Pass 2 measured 113–177 calls per view; pass 3 trades roughly 3x the draw calls and up to ~1.2 M triangles in the forest for the new scenery and shadows. The previous GPU measurement left large headroom (≈1.5 ms at 4K), but **real 4K/60 frame times must be measured on the RTX 2070 SUPER** (QA.md §8).

## Audio measurement (not a listening test)

Movie Maker capture of the real bus output during a scripted 31 s ride (summit, push-off, three trick jumps, carves, nitro, empty sputter, brake, crash with tumble and get-up), analysed with `tools/analyze_mix.py`. First capture: no clipped samples, peak −5.6 dBFS, −26.8 dB RMS, so the SFX bus was raised 4 dB. Final capture: **no clipped samples, peak −1.6 dBFS, −23.0 dB RMS**; quiet summit ambience (≈ −42 dB RMS); board hiss (2–8 kHz) drops ≈ 8 dB within 0.1 s of leaving the snow; landings add ≈ 15 dB of sub-150 Hz energy; the crash, empty-nitro sputter and nitro ignition stand clearly above the riding bed. The soundtrack folder held no audio files during these captures. Loop seams were checked numerically. Nobody has listened to the mix yet.

## Requires hands-on testing on the target PC

1. Xbox controller feel: carve/edge response at 20/60/120 km/h, brake skid, tuck, preload timing, air tricks, RS free look while riding/in air, idle settle and recenter, haptics strength, disconnect/reconnect, remapping on hardware.
2. Listening on headphones and speakers: layer balance, air→landing transition, nitro identity, sputter recognisability, crash weight, loudness.
3. Sustained fullscreen 4K/60 on the RTX 2070 SUPER, especially forest, boosting and free orbit in dense trees; startup time.
4. Human route readability and fairness: first-time hazard reading, both gorge ends, spur and pinch-gap shortcuts, summit rollers, final tabletop, recovery after poor lines; beginner vs expert times.

## Known limitations

- Procedural art and animation (no skeletal mesh, no ragdoll; tumble is a scripted rigid body tumble with limb flail). Tracks are ribbons, not deformation.
- CPU particles (Compatibility) express spray density through opacity/size rather than emission rate.
- Bot results are not human results; fixed 60 Hz does not guarantee bit-identical contact physics across hardware.
- Records keep `snow_records_massif_v2.json`: the course layout is unchanged, but rider physics changed slightly (reference bot 5:20.6 → 5:24.5), so pass-2 times are close but not strictly comparable.

## Launch

`Start-Snow.bat` (pulls `main`, opens Godot), or `& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path 'D:\Snow'`. The pass-3 work reaches the launcher once its pull request is merged into `main`.
