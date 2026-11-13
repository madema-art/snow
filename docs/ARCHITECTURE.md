# Architecture — pass 8

Godot 4.7.2, GDScript, Compatibility (OpenGL 3.3) renderer, main scene `scenes/main.tscn` (one Node3D with `scripts/main.gd`). No external dependencies, plugins or downloaded assets. Everything is built at startup by small scripts (measured ~1.5–4 s generation, see BUILD_STATUS).

## Files

| File | Responsibility |
|---|---|
| scripts/main.gd | Composition root: controls, run, mountain, rider, camera, FX, audio, haptics, music, pause menu, launch title; applies the saved time of day and forwards `SnowRun.mode_changed` to the atmosphere |
| scripts/snow_tuning.gd | **All feel constants**: gravity/drag, carve, brake/tuck, surfaces, ollie/air, landing, trick rewards and fatigue, nitro, crash thresholds/recovery, camera |
| scripts/mountain.gd | `SnowMountain`: the 360-degree world. Static sampling of the baked massif + runtime detail (`height_at`, `normal_at`, `surface_at`, masks, `at_bottom`, `face_name`, `spawn_point`), tile streaming (L0 render+collision tiles with seeded trees/boulders/outcrops, merged L1/L2 blocks, far trees, horizon ring) on worker threads, hazard buckets + `hazards_near()` |
| tools/build_massif.py, world/massif_v4.bin | Offline bake of the mountain (heights + masks) and its output |
| scripts/scenery_meshes.gd | `SnowMeshes`: tiered snow-loaded conifers (+ far LOD), faceted boulders whose vertices are also their convex colliders |
| scripts/atmosphere.gd | `SnowAtmosphere`: the Day and Night looks (`MODES`, `SKY_NIGHT`) and the cross-fade between them: sky shader, sky ambient, ACES exposure, fog/aerial perspective, glow, one directional light (sun by day, moon by night) with 4-split shadows; static `night_amount` / `fx_tint` for everything else |
| scripts/rider.gd | `SnowRider`: CharacterBody physics, carving, surfaces, ollie/coyote, air tricks, landing evaluation, trick rewards/fatigue, nitro, hazards/impacts, crash + visual tumble, get-up, finish coast; emits `sound_event(kind, strength)` |
| scripts/rider_visual.gd | `SnowRiderVisual`: the rider model and its posing. Board (sidecut, camber, kick, thickness, glowing top sheet with a dark two-band graphic, base graphic), curved highbacks and strapped bindings, flexed boots, baggy pants flaring over the boots with reinforced knees, fitted jacket (shoulder yoke, piping, zip, tall collar, hood, long hem that flaps in the wind), backpack with harness, gauntlet mitts, vented helmet with wrap goggles, mirrored lens and face mask. All colours are vertex colours from the palette constants at the top of the file. Per-frame two-bone IK legs/arms; carve inclination, crouch spring, tuck, preload/pop, grabs, spin/flip poses, flail/lie/get-up, summit breathing; board glow |
| scripts/rider_mesh.gd | `SnowRiderMesh`: the small mesh builder behind the rider: tubes swept along a path with elliptical or rounded-box cross-sections, end caps, per-vertex colour callbacks, `cut()` to add rings at colour edges, smooth normals; several sweeps per mesh so each garment is one draw call |
| scripts/chase_camera.gd | `SnowCamera`: travel-relative free look, analog rate smoothing, idle settle/recenter, speed framing/FOV, drop anticipation, sprung anchor, landing nod, asymmetric sphere collision |
| scripts/snow_fx.gd | `SnowFX`: edge spray, deep-lean plume (core arc, hanging mist, sun glitter), landing bursts, fall dispersion (pooled impact bursts and clods thrown along the body's momentum, ploughed tumble trail), nitro embers, bough snow, persistent board tracks (ribbon segments) |
| scripts/snow_audio.gd | `SnowAudio`: bus graph, 10 surface/wind/nitro loops mixed from rider state, 12-voice one-shot pool with stealing, 4 positional voices (tree pass-bys, boughs), environment (exposure, forest shelter, cliff reverb) |
| scripts/music.gd | `SnowMusic`: soundtrack manager — fixed opener, shuffle bag without back-to-back repeats, crossfades, per-song level matching, pause-in-place, auto-discovery in editor/exports, silent when empty |
| scripts/haptics.gd | `SnowHaptics`: continuous snow rumble + event pulses (landing, crash tiers, nitro, empty sputter) on the first connected pad |
| scripts/controls.gd | `SnowControls`: default bindings (16 remappable actions), fixed LS steering + LS forward tuck / back brake and UI events, `complete_bindings()` upgrade of older saved mappings, validated remaps with conflict swap, persistence, v1 migration, readable names |
| scripts/run_state.gd | `SnowRun`: ready/running/finished/ended, clock, time of day (`mode`, `set_mode`, `can_change_mode`, `mode_changed`, saved in `user://snow_settings.json`), one top ten per mode, last rank |
| scripts/pause_menu.gd | `SnowPauseMenu`: the only UI; pause/results, Time of day selector (disabled while a run is timed), leaderboard of the selected mode, remapping, delayed results after finish/fatal, auto-pause on disconnect/focus loss |
| scripts/title.gd | `SnowTitle`: the wordmark that fades over the summit at launch; never blocks input, leaves on push-off or pause |
| shaders/*.gdshader | terrain (incl. distant forest stands), tree, rock, backdrop (horizon ring), sky, board track, pause frost; `noise.gdshaderinc` shared noise |
| audio/*.wav | Original synthesized sounds generated by `tools/synth_audio.py` |
| tests/*.gd | See QA.md |
| launcher/, Play-Snow.bat | Windows launch: hidden updater, headless import, runtime start, shortcut creation, repair (see launcher/README.md) |
| branding/ | Icon (`snow.ico`, PNG previews), boot splash, editable SVG sources in `branding/source/` (hidden from Godot by `.gdignore`) |
| override.cfg | Runtime-only project settings (window icon, boot splash). The editor ignores it; `project.godot` is untouched |
| tools/render_branding.js, tools/make_icon.py | Rebuild PNGs from the SVGs (Playwright) and pack the ICO (Pillow) |
| tests/launcher/ | Wine harness with stand-in `git`/`where`/Godot executables for the launcher scripts |

## Coordinates and world

+Y up; north = -Z, east = +X, south = +Z, west = -X. The summit is at the origin (`SnowMountain.summit`, spawn `spawn_point()`). Board heading 0 points south (+Z); `forward() = (sin h, 0, cos h)`; positive steer turns the board clockwise seen from above in every direction of travel. Nothing in physics, camera, audio or tests depends on a world axis.

## Terrain (massif_v4)

**Bake** (`tools/build_massif.py`, numpy, deterministic, ~40 s) writes `world/massif_v4.bin`: header (`SNOWMAP1`, sizes, extent ±16 km, height offset/scale, summit) + 1280² uint16 heights (25 m apart) + four 640² uint8 masks (valley floor, cliff, forest, cornice), zlib-compressed (Godot reads it with `decompress(..., COMPRESSION_DEFLATE)`). Steps: ridge skeleton with domain warp → aspect-dependent flanks (smooth max) → summit top (0.42 grade all round; the runtime adds a sharper ~4 m top the 25 m bake cannot hold), valley floors, surrounding ranges, foothills → relief → 32 passes of stream-power erosion → cliff bands (terracing gated by face, altitude, broad slope and gap noise) → priority-flood pit filling from the valley floors (0.07 drain grade; guarantees no closed hollow, including any a band could make) → masks. `--preview path.png` writes a shaded map. See MOUNTAIN.md.

**`SnowMountain.height_at(x, z)`** (static, thread-safe, ~5 µs) = bicubic macro (which already holds the cliff bands) + cornice lips + rollers (fade below a 0.2-0.4 grade) + small relief. Runtime detail must never be able to dig a closed hollow: anything that could (bands, deep features) belongs in the bake, before the pit fill. `normal_at`, `surface_at/surface_from` (powder/ice from slope, curvature, forest mask, patches), `tree_density`, `rock_density`, `valley_floor`, `at_bottom`, `face_name`, `region`, `forest_amount`, `cliff_amount`, `spawn_point` are all static.

**Streaming** (`SnowMountain` node): the ±16 km square is 50×50 tiles of 640 m, grouped in 10×10 blocks of 3.2 km.
- L0: 8 m grid (81² vertices + border for normals/curvature/lips), render == collision triangles (`ConcavePolygonShape3D`), skirts, per-vertex surface data and AO baked from the tile's hazards; trees (cylinder colliders) and rocks (convex hulls of their exact vertices) per tile from a fixed per-tile seed, never within 6 m of a tile edge (order-independent). The 3×3 tiles around the rider's position led by 2.5 s of velocity — in whatever direction it travels; unloaded at 3 tiles (after the block has its terrain back).
- L1 (32 m) within 3.6 km and L2 (128 m) elsewhere: each block is ONE mesh merged from its tiles' pieces, with holes where L0 tiles are shown. Pieces are cached per block.
- Trees are batched per 320 m quarter-tile (Godot picks level of detail per batch by its centre): near meshes (4 variants, shadows) to 420 m from the batch centre, one shared simple far mesh beyond. Far trees (no colliders) on tiles within ~1.5 km; beyond that the terrain shader paints dark stands from UV.x (forest density) from ~0.9 km out. A coarse horizon ring (2 km grid to ±48 km, backdrop shader) closes the world.
- All generation runs on `WorkerThreadPool` (at most 6 tasks); the main thread applies results within a 4 ms budget and plants one tile's scenery per frame. `prepare(p)` builds everything around a point synchronously (startup ~2 s on the 4-core cloud box, restarts are instant), `ensure_ready(p)` builds missing collision immediately (teleports, fixtures, or a rider outrunning the streamer). `stream_stats` counts builds, synchronous builds and the longest main-thread apply.

**Finish**: `SnowRider` calls `run.finish(face)` when the run is running, the board is on the floor, not recovering and not airborne, and `SnowMountain.at_bottom(position)` (floor mask > 0.5 and at least `FINISH_DROP` below the summit).

## Physics (60 Hz)

CharacterBody3D capsule r=0.28 h=1.3, `move_and_slide`, floor max 57°, snap 0.85 m (suspended for 0.2 s after a pop so ollies at speed leave steep snow). Ground step:

1. Steering input shaped (`|x|^1.3`) and smoothed with faster release than engage → `steer` (edge engagement).
2. Max yaw rate = min(PIVOT_RATE, CARVE_ACCEL / speed) x (1 + brake x SKID_TURN_BONUS): easy pivots at low speed, carve-limited at high speed.
3. CharacterBody clears vertical floor velocity, so the tangent velocity is reconstructed, then gravity is projected onto the slope.
4. Lateral damping (edge grip) scaled by edge engagement, ice (-32%) and braking (deliberate skid). Forward inertia untouched.
5. Resistance: rolling (+powder, -ice), quadratic drag (tuck -58%, powder +12%), brake, carve scrub. **No speed cap.**
6. Edge catch: lateral slide >17 m/s above 21 m/s without braking → fall.
7. Ollie on release; preload up to +30% pop; coyote 0.14 s.

Air: gravity, air-only drag (0.35 x riding drag), LS pre-aims the board (does not move the rider), spin/flip rates ramp up/down (LB/RB, D-pad), grab accumulates. Confirmed air after 0.09 s filters terrain micro-hops.

Contacts: snow-only contacts restore pre-contact tangent momentum to remove seam losses (pass 2). Hazard contacts: normal impact <5 m/s brushes (and at walking pace the rider shuffles around the trunk instead of being pinned); harder impacts fall; >30 m/s trees / >34 m/s rocks are fatal; steep terrain walls >16 m/s fall, >34 fatal. Apex-to-landing drop >35 m or sustained free fall >55 m is fatal.

Landing: yaw error (180s allowed, ride switch), pitch error, board-vs-travel alignment and impact; quality 0..1. Reward = (air + drop + spins + flips + grab) x combo x quality / (1 + trick fatigue + global fatigue x 0.45), capped at 0.85. Fatigue decays 1/25 s per trick, 1/7 s global.

Anti-stuck: A pushes off again below 2.2 m/s (kicking away from a trunk/boulder the rider leans on); get-up and recovery spots require a clear 7 m capsule sweep down the fall line; if `move_and_slide` makes no progress at speed on snow (a rare trimesh-crease pin) the capsule is lifted a few centimetres per tick until it rides free.

Crash: `crash()` zeros nitro, velocity, speed, boost and trick state FIRST, then starts the tumble. The tumble is its own small momentum simulation (`tumble_pos/vel/omega/basis`, never the CharacterBody): launch with `TUMBLE_MOMENTUM` of the crash velocity along the slope plus a pop (or a rebound off the hit normal); ballistic flight; snow impacts with restitution and tangential loss; rays against hazards for bounces off trunks/boulders; contact that hugs the ground with friction + ploughing drag while slope gravity keeps acting; cartwheel hops above `TUMBLE_HOP_MIN_SPEED`; angular velocity matched to rolling plus random wobble; settle onto the back and rest. Each impact emits `tumble` (sound, grunt, snow burst, clods, rumble, camera jolt); rest emits `groan`. A ground impact after a drop ≥ `TUMBLE_FATAL_DROP` turns the fall fatal. Recovery cannot enter get-up until the body rests; get-up places the body at the rest point if standable, else the nearest clear spot, else where the fall began.

Deep lean: `plume` (0..1, from edge engagement x speed) and `plume_side` drive FX/audio/haptics; `over_lean` integrates while the raw stick is beyond `DEEP_LEAN_START` at speed without braking and falls back when eased; at 1.0 the rider crashes with reason `over-lean`.

## Camera

`orbit = follow_yaw + look_yaw`. `follow_yaw` tracks the horizontal velocity direction (heading when slow/recovering) at 2.2–3.4/s on snow, 1.1/s in air (spins/flips never affect it), frozen during tumbles, 1.4/s on get-up, unconditionally behind the board at the summit. `look_yaw`/`lift` integrate a smoothed analog rate (deadzone 0.18, response ^1.35, 2.9/1.9 rad/s). Settling after 3 s idle (ramped, 1.4/s), recenter 5/s, none at the summit. View cycles three boom ranges (x0.72 / x1 / x1.5, saved in `user://snow_camera.json`). Distance 5.8→8.6 m with speed (+0.7 boost, +2.5 crashed), FOV 62→73 (+4 boost). Anchor: horizontally locked, vertically sprung. Look target: ahead along the view by 3+0.42 x speed, lowered toward the ground ahead at speed. Drop anticipation samples the analytic terrain 30/55/85 m ahead and raises pitch up to +0.32 rad. Collision: 0.35 m sphere cast anchor→desired against terrain+hazards; retract instantly, re-extend at 3.5 m/s; analytic ground clearance. Landing/crash nods are damped springs; a tiny speed vibration only above ~86 km/h.

## Rendering

Compatibility renderer, 2x MSAA, ACES tonemap, glow, fog with scatter and aerial perspective, sky shader also providing ambient. One DirectionalLight with 4 PSSM splits to 260 m. Trees: 4 variants x near (≤420 m, shadows) + far LOD (420–2600 m, no shadows) MultiMeshes per chunk; rocks/outcrops 4 variants ≤1600 m. Compatibility multiplies vertex COLOR by the MultiMesh instance colour, so MultiMeshes set white instance colours. Board tracks: alpha ribbons, distance-faded, last ~70 segments kept. Particles: CPUParticles3D (no emission-ratio support), density expressed through opacity/size.

## Rider model

Every garment is authored in the frame it is posed in, so posing only sets transforms: torso, hem: spine frame (origin pelvis, +Y up the spine, front -X, +Z toward the nose-side shoulder); limbs: origin at the upper joint, +Y along the bone, +X toward the limb's front (knee cap, inside of the elbow), placed by `place_bone()`; head: origin at the head centre, front -X; boots and bindings: per-foot frame on the board, toe -X. Segment lengths equal the IK bone lengths (THIGH, SHIN, UPPER_ARM, FOREARM), so nothing stretches. Joints are hidden by overlapping rounded ends rather than skinning. The whole rider is 21 mesh instances / 23 surfaces / ~9.6k triangles (the pass-6 capsule rider was 32 / 34 / ~19.4k). Colours live in the palette constants; the red jacket is the rider's identity and must stay readable against snow by day and moonlit slopes at night (all rider materials keep the soft rim). `tests/rider_studio.gd` renders a labelled turntable of poses and close-ups for checking changes.

## Day / Night

One blend value (`SnowAtmosphere.blend`, 0 day → 1 night, `TRANSITION` 1.4 s, animated even while paused) drives everything; nothing in physics, the course, audio or music reads it.

- **Look tables.** `MODES["day"|"night"]` hold light direction/colour/energy, ambient, exposure, contrast, saturation, fog, glow and `fx_tint`; `apply()` lerps them into the Environment. `SKY_NIGHT` holds moon size/colour, star and Milky Way brightness, aurora strength and speed. These are the knobs to tweak; see the table below.
- **Light.** The same DirectionalLight is the sun (`SUN_DIRECTION`, low and across the fall line) or the moon (`MOON_DIRECTION`, ahead-left, visible from the summit). It cannot sweep between them, so during a change it fades out, swaps side at the midpoint and fades back in. The terrain shader gets the same direction, so glints and ripples agree with the shadows and with the disc drawn in the sky.
- **Sky** (`shaders/sky.gdshader`): `sky()` mixes `day_sky()` and `night_sky()` by `night`. Night: zenith/horizon gradient, moon disc with limb darkening and halo, three star layers placed in 3D cells of the view direction (so they are fixed to the sky and never swim; each is at least ~1.3 screen pixels using `pixel_angle`, which the atmosphere updates from the camera FOV and viewport height), the Milky Way (`galaxy_pole`/`galaxy_core`, fbm with dust lanes, denser stars inside it), and the aurora: 16 stacked planes sampled along the view ray, three slowly drifting sheet lines, fine vertical rays, green → cyan → violet with height and a pink hem, dithered per pixel. Animated parts (cirrus, aurora, twinkle) are skipped in the radiance/ambient pass (`AT_CUBEMAP_PASS`), so the light probe is static per mode and the sky uses `PROCESS_MODE_INCREMENTAL`. `AT_CUBEMAP_PASS` and `SCREEN_UV` exist only inside `sky()` and are passed down as arguments.
- **Snow** (`shaders/terrain.gdshader`, uniforms `night`, `aurora_tint`): slightly lower roughness and higher specular at night, two layers of crystal glints anchored in world space (near and mid distance, faded out by 60 m / 170 m, wider and denser at night), a frost sheen and a faint aurora wash in emission on open snow. Materials that follow the time of day register in `SnowAtmosphere.lit_materials`.
- **Particles** are unshaded, so `SnowFX` multiplies each emitter's base colour by `SnowAtmosphere.fx_tint` (nitro embers excluded).
- **Rider.** Clothing materials have a soft rim so the silhouette holds against dark slopes. The nitro lamp (the only light on the rider) gains energy and range with `night_amount`, so the glow pools on the snow at night.
- **State.** `SnowRun.mode` is loaded from `user://snow_settings.json` (default `day`), applied instantly at startup, changed through `set_mode()` which refuses while `state == "running"`, and emits `mode_changed`. Records: `by_mode[mode]`; Day reads/writes `records_path`, Night the same name with `_night` before `.json`.

| To change | Edit |
|---|---|
| How bright/blue the night is | `MODES["night"]`: `light_energy`, `ambient_*`, `exposure` |
| Night haze | `MODES["night"]`: `fog_*` |
| Moon position (and with it all night shadows) | `MOON_DIRECTION` |
| Moon size, star/Milky Way brightness, aurora strength/speed | `SKY_NIGHT` |
| Aurora colours, curtain shapes, layer count | `aurora()` in `shaders/sky.gdshader` |
| Snow sparkle and gloss | the glint block at the end of `fragment()` in `shaders/terrain.gdshader` |
| Aurora tint on snow | `AURORA_SNOW_TINT` |
| Particle brightness at night | `MODES["night"]["fx_tint"]` |
| Board glow reach at night | `SnowRiderVisual` lamp energy/range lines |
| Cross-fade time | `TRANSITION` |

## Launch (Windows)

Desktop shortcut → `wscript.exe launcher/Start-Snow.vbs` (no window) → temp copy of `snow_update.bat` (`git fetch origin main`; nothing to do if `FETCH_HEAD` is already an ancestor; otherwise `git checkout -- "*.import" "*.uid"` to drop Godot's regenerated metadata, then `git merge --ff-only FETCH_HEAD`; offline or blocked never stops the launch) → `snow_run.bat` (locate Godot; if `git rev-parse HEAD` differs from `.godot/snow_imported_rev.txt` or `.godot/imported` is missing, `godot --headless --import`; then `start godot --path <project>`). Problems are written to `launcher/*_notice.txt` and shown by the VBS as one message box. Godot then shows the boot splash from `override.cfg` while the mountain generates, and `SnowTitle` fades the wordmark over the summit. Full description: launcher/README.md.

## Audio

See AUDIO_DESIGN.md. Bus graph: Master (hard limiter -0.8 dB) ← SFX (glue compressor) ← Board, MountainWind (low-pass for forest shelter), Impacts (reverb tuned by region/enclosure) ← Nitro. Music → Master (−3 dB, owner soundtrack via SnowMusic, separate from every game sound).

## Saves and UI

`SnowRun` keeps one course-specific top ten per time of day (Day `user://snow_records_massif_v4.json`, Night `user://snow_records_massif_v4_night.json`; entries `{time, face}`, plain numbers from older files still read), sorted, clamped to ten, malformed entries filtered, and the selected mode in `user://snow_settings.json`. `SnowControls` persists `user://snow_controls_v2.json` (exactly the 15 remappable actions, unique, validated; v1 migration). Pause menu UI is authored for the 3840x2160 canvas (stretch mode canvas_items).

## Performance notes

Startup: indexed height grid with border (one `height_at` per vertex), grid normals/curvature, AO baked from hazard buckets. Hazards are per-chunk static bodies with many shapes (fewer nodes). Runtime per-frame queries: camera one sphere cast; audio pass-by bucket query every 0.08 s; FX bough query; tumble one ray per tick only while crashed. See BUILD_STATUS.md for measured counts; real 4K/60 frame times must be measured on the target PC. Night adds per-pixel sky work (three star layers, Milky Way fbm, 16 aurora samples) only on visible sky pixels, and a few extra noise lookups per snow pixel; draw calls, geometry, lights and shadow passes are identical to Day.
