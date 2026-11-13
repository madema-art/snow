# Current build status — development pass 8 (the 360-degree mountain)

Pass 8 rebuilds the world as a true 360-degree mountain at the owner's request: the rider starts on the summit, chooses any side with the left stick, and races to the bottom of the mountain wherever that is. It includes the pass-7 rider model (which had not been pushed yet). Developed in the cloud (software GL, no GPU, no controller, no Windows): appearance was checked in software renders only and nothing here claims real 4K/60 performance or feel.

## Pass 8 changes

**The world** (`tools/build_massif.py` → `world/massif_v4.bin`, `scripts/mountain.gd`; details in MOUNTAIN.md)
- One alpine massif ~20 km across: summit ~3,730 m at the world origin, a summit ridge with two subsidiary peaks, ten meandering aretes with spurs, bowls, eroded gullies, cliff bands broken by couloirs, cornices, rollers, forests below each face's treeline, valley floors (300–1,050 m) around the whole base, surrounding ranges and a horizon ring to 48 km. Faces have their own characters (north steep and cliffy, east forested, south open snowfields, west ravines). No main course, no preferred axis, no finish gate.
- Baked offline (deterministic numpy tool, ~40 s): ridge skeleton, aspect-dependent flanks, erosion, pit filling (no closed hollows), masks. Runtime adds cliff bands, cornice lips, rollers and relief.
- Streaming: 640 m tiles; 8 m render+collision tiles with trees and rocks on the 3×3 around the rider (in whatever direction it travels), 32 m / 128 m merged blocks beyond, far trees to ~1.9 km, painted forest stands and a horizon ring further out. Generation on worker threads; scenery planted a frame later; collision built immediately if ever needed.

**Start, finish, records** (`scripts/rider.gd`, `scripts/run_state.gd`, `scripts/pause_menu.gd`)
- Start on the summit. Before push-off the left stick turns the board on the spot (clock stopped); push-off goes the way the board points.
- The finish is the bottom: riding on a valley floor at least 1,500 m below the summit, on any side. No gate, banner or line; the old finish structures are gone.
- New records files `snow_records_massif_v4[_night].json`, each entry with the side it finished on (shown dimmed in the list). The `massif_v3` and older files are untouched.

**Direction-free physics and recovery**
- Push-off, get-up heading (down the local fall line), recovery points (uphill of the impact in any direction), and "stand-up" heights (read from the collision surface) no longer assume a downhill axis. A get-up spot must have no cliff edge just below it.
- A tumble that slides down a rock face is judged like a fall: height lost since last touching gentle ground decides whether it is fatal.
- Standing pushes chain like skating up to 5 m/s, so nobody can be trapped on a flat.

**Sky for every direction** (`scripts/atmosphere.gd`, `shaders/sky.gdshader`): sun in the south-south-west at ~32°, moon in the east-south-east, aurora owning the northern sky, the Milky Way arching south-west to north-east.

## Pass 8 validation

| Suite | Result |
|---|---|
| Import / parse | no errors |
| `prototype_test.gd` | **40/40** |
| `feel_test.gd` (+ summit start and left-stick aiming, push-off follows the board, gravity alike in all eight directions (0.61–0.82 of g·sin slope on comparable slopes), clockwise steering in every direction, valley floors on all eight sides, a ravine halfway down never counts, no finish in the air, the finishing face is recorded, older record files still read) | **104/104** |
| `terrain_test.gd` (render == collision, no seam loss at 40 m/s, streaming in every direction, bounded memory, streamer stays ahead at 42 m/s, rollers launch a rider) | **6/6** |
| `mountain_test.gd` — summit camera, four straight no-input lines (none gets down cleanly: falls, stalls or a fatal fall), and a descent in **every** sector with ordinary inputs | **all 8 sectors reach the bottom**, failures=0 |
| — N / NE / E / SE / S / SW / W / NW | 6:01 N · 5:41 NE (north valley) · 6:42 E · 6:36 SE (south) · 6:29 S (south-west) · 6:26 SW · 6:45 W · 6:11 NW (north); 8.8–10.2 km, 2.6–3.3 km down; median **6:29** |
| `--cautious` (N, E, S, W) | all 4 finish, median **7:21** |
| `--tricks` (S, SW, E, SE) | 3 of 4 finish (6:20–6:34); on SW a trick landing about 1 km down was fatal. 91 rewarded landings, 10.9 boards of nitro earned, 38 s of boost |
| Render-cost probe, 3840×2160, software GL (counts only) | 157–304 draw calls, 0.42–1.21 M primitives (east forest heaviest); startup ~3.5 s on the 4-core cloud box |

Bot notes, honestly: the bots plan a route over a 50 m grid of the real terrain and follow it with ordinary inputs; they are careful (brake for bends, slow in trees, steer away from drops) and land about a minute slower than the five-minute target a skilled human should hit with tucks, lines and nitro. Each sector finishes on its own side or the neighbouring one (the bots happen to use the north valley from NE and NW). Renders (software GL) inspected: the summit in four directions and from above, the north face and its cliff bands, the east forest, the south snowfields, the west ravine, a valley floor and the view back up, close trees, and at night the summit, the moon in the east-south-east, the aurora over the northern sky, the Milky Way, a moonlit slope and the nitro glow.

**Known issues:** in dense forest the chase camera can sit inside a tree's canopy (canopies are not solid to the camera, as before); bot times are above five minutes; streaming work on the main thread peaked at ~16 ms in one frame in the cloud.

## Not tested — needs the owner's PC

1. **How the mountain feels to ride**: whether every face reads well from the summit and at speed, whether the cliff bands and couloirs are fair, whether five minutes feels right on your favourite side.
2. **Performance at 4K/60**: far more terrain is visible than before (blocks, far trees, horizon). Draw-call counts are in the table; real frame times and streaming hitches on the RTX card are unmeasured.
3. **Night on the new mountain** on a real GPU (the sky was recomposed for every direction).
4. Everything still listed for passes 6 and 7 below.

# Pass 7 record (history)

Pass 7 rebuilds the rider model. Gameplay, physics, posing logic, sounds and the mountain are unchanged. Developed in the cloud (software GL, no GPU): the look was checked in software renders only.

## Pass 7 changes

**Rider model** (`scripts/rider_visual.gd`, new `scripts/rider_mesh.gd`)
- The capsule-and-sphere mannequin is replaced by sculpted, procedurally swept garments: a fitted red jacket with a charcoal shoulder yoke, cream piping, a front zip, tall collar, hood and a long hem that still flaps at speed; a backpack with lid, compression straps, shoulder harness and an orange sternum buckle; baggy charcoal pants with reinforced knees that flare into cuffs over the boots; flexed boots with sole, toe box, laces and orange dials; curved highbacks, heel cups and padded ankle/toe straps on the bindings; gauntlet mitts with thumbs; a vented helmet with wrap goggles, an amber-to-red mirrored lens, a strap with an orange tab and a dark face mask.
- Board: a dark two-band top-sheet graphic (still dark when uncharged, so the glow remains the only nitro signal) and a base graphic (cream bands, orange slash) visible in the air and in falls.
- A slow breathing idle at the summit.
- Lighter than before: 21 mesh instances, 23 surfaces, ~9.6k triangles (was 32, 34, ~19.4k).

## Pass 7 validation

| Suite | Result |
|---|---|
| Import / parse | exit 0, no errors |
| `prototype_test.gd` | **40/40** |
| `feel_test.gd` | **93/93** |
| `terrain_test.gd` | **5/5** |
| `mountain_test.gd` straight / reference | straight fatal at 1:08.7; reference **5:26.4** (identical to pass 6: the model is visual only) |
| Cautious / tricks | **6:42.0** / **5:23.5**, 17 rewarded landings (identical to pass 6) |

Renders inspected (software GL): the new `tests/rider_studio.gd` turntable (stand, ride, tuck, toe/heel carve, brake, grab, air; head and boot close-ups) by Day and Night, a before/after comparison against the pass-6 model, and in-game chase shots (summit, close, carve, nitro, plume, tumble).

**Needs the owner's eyes:** how the rider reads at 4K on the real GPU, at speed, by Day and Night; whether the colours (red jacket, charcoal yoke and pants, orange accents) are right.

# Pass 6 record (history)

Pass 6 status as merged:

Pass 6 adds two things: a **Day / Night** choice with a full Night presentation, and a **game-like launch** on Windows (Desktop shortcut with an icon, silent update, no editor). Developed in the cloud with the **official Godot 4.7.2 Linux build**. The container has **no GPU, no audio device, no controller and no Windows** (software GL, simulated input, launcher scripts run under wine with stand-in programs), so nothing here claims hardware feel, listening, real 4K/60 performance or a real-Windows launch.

## Pass 6 changes

**Day / Night** (`scripts/run_state.gd`, `scripts/pause_menu.gd`, `scripts/atmosphere.gd`)
- One new line in the pause menu, **Time of day: Day / Night**. Works at the summit before push-off and after a run ends or restarts; while the clock is running it is disabled and says "locked during a run". The world cross-fades in about 1.4 s behind the menu. Remembered in `user://snow_settings.json`; a fresh install is Day.
- Same mountain, hazards, physics and course in both. The reference bot's time is identical to pass 5 to the frame, because nothing in gameplay reads the mode.
- The soundtrack is not touched by a change (same player, same position).

**Night presentation** (`shaders/sky.gdshader`, `shaders/terrain.gdshader`, `scripts/atmosphere.gd`, `scripts/snow_fx.gd`, `scripts/rider_visual.gd`)
- Moon ahead and to the left of the fall line, visible from the summit, with a halo; it is the scene's one directional light and the light direction is the moon's direction.
- Three layers of stars fixed to the sky (a few warm and blue, gentle twinkle), the Milky Way with dust lanes, and aurora in slow layered curtains: green/cyan/turquoise with violet above and a pale pink hem.
- Snow turns silver-blue and slightly glossier, with two layers of crystal glints anchored in the snow, a frost sheen and a faint aurora wash on open slopes.
- No spotlight on the rider. Clothing has a soft rim so the silhouette reads; the nitro board glow reaches farther and pools on the snow. Snow particles are tinted to the moonlight.
- Day keeps its light, sky, fog and exposure values exactly. One shared change: the snow glint code was rewritten for both modes (two scales, dots that grow with distance so they do not shimmer at speed); by day it uses the previous colour, sharpness and density.

**Records**
- Day and Night have separate top tens. Day keeps using the existing `snow_records_massif_v3.json`, so every earlier time is still there as a Day time; Night uses `snow_records_massif_v3_night.json`. The menu shows "FASTEST DAY DESCENTS" or "FASTEST NIGHT DESCENTS" for the selected mode. No file is deleted or rewritten on upgrade.

**Launch** (`launcher/`, `Play-Snow.bat`, `override.cfg`, `branding/`)
- `launcher\Create-Shortcut.bat` puts a SNOW shortcut with the new icon on the Desktop. The shortcut runs a hidden script that updates from GitHub `main`, imports new assets without a window when the version changed, and starts the game directly in Godot's game mode.
- Update friction fixed: every path is quoted (folders with spaces/parentheses work); Godot-generated `*.import`/`*.uid` changes no longer block an update (they are restored, then regenerated by Godot); the update is fast-forward only and never discards anything else; if it cannot be applied the game still starts and one message says so; `Repair-Snow.bat` is the explicit, backed-up way out.
- Icon: moonlit peak, moon, aurora and a glowing board line (`branding/snow.ico`, 16–256 px; source `branding/source/snow_icon.svg`). Splash image and a wordmark that fades over the summit for a few seconds; neither blocks input.
- `Start-Snow.bat`, `project.godot` and the root `.gitignore` were left untouched on purpose, so a PC still on the old launcher can pull this version even if those files were edited locally.

## Pass 6 automated validation

| Suite | Result |
|---|---|
| Import / parse | exit 0, no errors |
| `prototype_test.gd` | **40/40** |
| `feel_test.gd` (now also Day/Night: default, selector, cross-fade while paused, music untouched, persistence, mid-run lock, no visible UI while riding, separate records and files, Day lighting restored, branding present) | **93/93** |
| `terrain_test.gd` | **5/5** |
| `mountain_test.gd` camera checks | 8/8 (also `--camera-only`) |
| Straight push-off, no input | Fatal gorge fall at **1:08.7** — no completion (same as pass 5) |
| Reference route | **5:26.4**, 10,055 m, 39.4 m/s peak, 3 recoverable falls (identical to pass 5) |
| Cautious profile | **6:42.0**, 28.8 m/s peak, 3 falls (identical to pass 5) |
| Tricks profile | **5:23.5**, 44.0 m/s peak, 17 rewarded landings, 2.2 boards of nitro earned, 7.3 s boosting (identical to pass 5) |
| `tests/launcher/run_launcher_tests.sh` (wine, stand-in git/Godot) | **31/31** |

Renders inspected (software GL, 1600x900): Day summit, forest and nitro; Night summit, moon, aurora, zenith, slope at speed, gorge approach, forest, Broken Mountain, finish, snow close-up, rider close-up, nitro glow, pause menu with the selector.

## Not tested — needs the owner's PC

1. **The launcher on real Windows.** The scripts were only run under wine with stand-in `git`/Godot programs. Never run for real: `Create-Shortcut.bat` (PowerShell; not runnable here at all), the hidden start from the shortcut, message boxes, real Git fast-forward and real Godot headless import, the icon as Windows draws it.
2. **Night at 4K/60.** The night sky does more work per sky pixel (stars, Milky Way, 16 aurora samples). Draw calls and geometry are the same as Day, but the frame rate on the RTX card is unmeasured. If it drops, lower the aurora layer count in `shaders/sky.gdshader` or tell me.
3. **How Night really looks.** Software rendering at 1600x900 shows colour and composition; fine glints, star sizes and bloom will differ at 4K on a real GPU. Check: is the glitter stable and not noisy, are trees/rocks/lips readable at full speed, moon size, aurora strength.
4. **Splash/wordmark timing** on a real start.
5. Everything still open from passes 4 and 5 below (feel, listening, performance).

# Pass 5 record (history)

Pass 5 implemented the owner's feature requests after playing pass 4: left stick forward/back for tuck/brake, a snow plume from deep leans, an over-lean fall, falls as exaggerated momentum physics with pain sounds and snow dispersion, and the View button cycling camera distance. Developed in the cloud with the **official Godot 4.7.2 Linux build**. The container has **no GPU, no audio device and no controller** (software GL, measured audio, simulated input), so nothing here claims hardware feel, listening or real 4K/60 performance.

## Pass 5 changes

**Left stick forward / back** (`scripts/controls.gd`, `scripts/rider.gd`)
- Forward crouches into a tuck (less drag, more speed); back brakes into a skid. Fixed like steering, 0.3 deadzone so steering alone never tucks or brakes. LT/RT still work and stay remappable.

**Deep lean, plume and over-lean** (`scripts/rider.gd`, `scripts/snow_fx.gd`)
- Leaning hard (about 75–85% stick) throws a plume out the side OPPOSITE the lean: a dense arcing core, soft mist that hangs in the air and sun glitter, sized by lean and speed, with its own rushing spray sound and light rumble.
- Past ~82% stick the board also turns up to 20% tighter, but the lean keeps deepening; after about 1.9 s at full lock at speed the edge washes out and the rider tumbles. Easing off, switching edges or braking recovers; below ~7 m/s it never happens. Warnings are physical only: the body laid over toward the snow, rising chatter, controller shudder.
- Fixed while here: edge spray was being thrown to the inside of the turn; it now goes to the outside.

**Falls are momentum physics** (`scripts/rider.gd`, constants `TUMBLE_*`)
- The fallen body keeps ~62% of its crash velocity (or rebounds off the trunk/boulder it hit), is pitched off the snow, cartwheels with repeated hops and impacts, ploughs and slides to rest; steeper ground slides longer. Measured: ~7 m from a 10 m/s fall, ~30 m in 3.4 s from 30 m/s.
- A tumble that goes over a drop of 18 m or more (gorge lip, icefall, cuts) becomes fatal — by physics, not by zone.
- Every impact: thud, a pain grunt, a burst of snow and flying clods thrown along the body's momentum, a camera jolt with a brief FOV punch, and a controller hit. Rolling ploughs a snow trail. A groan when the body stops; a yell on a long cliff fall, with the impact sound held until the ground.
- The rider gets up where the body came to rest (nearest safe spot if needed), never before it has stopped. Riding speed, velocity and nitro are still wiped the instant of the fall and stay zero throughout.

**Camera distance on View** (`scripts/chase_camera.gd`)
- View cycles close / medium / far (x0.72 / x1 / x1.5 boom, measured 4.2 / 5.8 / 8.7 m at rest); the choice is saved in `user://snow_camera.json`.
- Restart moved to **Y, held ~0.35 s** (a tap does nothing). An older saved control mapping is upgraded automatically: View becomes the camera control, the old default restart moves to Y, and every remap the player made is kept.

**New sounds** (`tools/synth_audio.py`): 12 more original sounds (43 total) — three first-hit grunts, five rolling grunts, two groans, a falling yell and the plume spray. The voice is synthesised (glottal source + vowel formants), not recorded.

**Also fixed:** particles that had not been emitted yet were drawn full-size and black at their emitter (visible as a dark disc once the larger mist was added); the particle material now keeps particle scale, which also makes size-over-life apply.

## Pass 5 automated validation

| Suite | Result |
|---|---|
| Import / parse | exit 0, no errors |
| `prototype_test.gd` | **40/40** |
| `feel_test.gd` (now also: momentum tumbles, fatal tumble over the gorge lip, grunts, plume, over-lean, braking exception, left stick forward/back, restart hold, camera range + persistence, mapping upgrade) | **76/76** |
| `terrain_test.gd` | **5/5** |
| `mountain_test.gd` camera checks | 8/8 (also `--camera-only`) |
| Straight push-off, no input | Fatal gorge fall at **1:08.7** — no completion |
| Reference route | **5:26.4**, 10,055 m travel, 39.4 m/s peak, 3 recoverable falls |
| Cautious profile | **6:42.0**, 28.8 m/s peak, 3 falls |
| Tricks profile | **5:23.5**, 44.0 m/s peak, 17 rewarded landings, 2.2 boards of nitro earned, 7.3 s boosting |

Bots press only ordinary inputs (and, like a careful rider, never hold full lock). Renders inspected (software GL): deep-lean plume, a fall in mid-throw and at rest, pause menu with the new control row.

## Still needs the owner's PC

1. **Feel of the new controls**: stick forward/back thresholds, how long full lean can be held, how far tumbles carry.
2. **Listen**: the synthesised grunts/groans/yell are the least certain sounds in the game — tell me if they read as painful, comic or robotic. Also the plume spray level.
3. **Look**: plume size/density at 4K, tumble exaggeration, camera close/medium/far distances.
4. Everything listed under pass 4 below (music lead, wind, new mountain) if not yet checked.

# Pass 4 record (history)

Pass 4 answered the owner's first hands-on playtest of pass 3: *"fun but needs a lot of polish; the sound effects cover up the music; the wind sound is just obnoxious; the mountain needs a lot of work, but it was still the right concept."*

## Pass 4 changes

**Mix: the music leads** (`scripts/snow_audio.gd`, `scripts/music.gd`)
- Measured the complaint first: in pass 3 the effects bed at speed was **7 dB louder than the music** (−16.1 vs −23.0 LUFS).
- Every continuous bed (snow, carve, skid, wind, clothing) was cut hard, the SFX bus lowered and its compressor make-up gain removed, a 7.5 kHz low-pass takes the fizz off the snow hiss.
- Music bus raised from −8 to −3 dB; songs are level-matched to −16 LUFS (they range −14 to −20), so quiet masters no longer disappear; ducking reduced to a brief −2.5 dB under crashes only.
- **Measured result at ~30 m/s: music −19.9 LUFS, effects bed −29.1 LUFS — the music now sits ~9 dB ABOVE the bed.** Landings, crashes, nitro and the sputter still punch through.

**Wind: rebuilt** (`tools/synth_audio.py`)
- The whistle/flutter layer (resonant tones at 1.1 and 1.8 kHz with fast flutter) is deleted outright.
- Wind is now two soft, dark layers: a slowly breathing low bed and a smooth speed rush rolled off above ~1.5 kHz that only builds at real speed (speed²). Gusts are gentler, the wind bus is low-passed at 5 kHz (1.6 kHz in forest), clothing flutter is faint and mostly in the air.

**The mountain: `massif_v3`** (`scripts/mountain.gd`, details in MOUNTAIN.md)
- A true summit peak with the ground falling away behind and off both shoulders.
- Pitches and benches (grade ≈0.24–0.44) instead of one constant ramp; same average grade and ~5 minute target.
- Two winding natural drainage gullies (banked like half-pipes) that pass the gorge ends, become the forest's creek-bed corridors and merge into the finish valley; the west creek ends in an icefall over the escarpment.
- Rolling drift/moraine relief everywhere, strongest in the Broken Mountain.
- Trees in natural thickets, glades and a real treeline (6,780 trees, was 4,580); boulders in gardens with a few big erratics (823 boulders + 884 cliff outcrops) that always leave a rideable gap.
- The sun now rakes across the slope: rolls, banks, ripples and the surrounding ranges are modelled by light and long shadows instead of flat white. Distant ranges re-shaded (snowfields over dark rock, no stripes). Finish funnel kept clear.
- Spur gap rebuilt with the kicker at the lip, a lower far rim and a steep landing.
- New records file `snow_records_massif_v3.json`; older files untouched.

**No more getting stuck** (`scripts/rider.gd`) — found by riding the new terrain with the bots:
- A pushes off again whenever the rider is nearly stopped, kicking away from a trunk or boulder they are leaning on.
- Get-up/recovery spots must have a clear 7 m path downhill (no standing up boxed in).
- A rare physics freeze (board pinned on a terrain crease while still "moving") now self-corrects.

## Pass 4 automated validation

| Suite | Result |
|---|---|
| Import / parse | exit 0, no errors |
| `prototype_test.gd` | **40/40** |
| `feel_test.gd` (now also: standing push, v3 records, song level-matching, playtest mix rules) | **52/52** |
| `terrain_test.gd` | **5/5** — spur gap clears and earns 0.19 nitro; pinch gap clears and earns 0.21 |
| `mountain_test.gd` camera checks | 8/8 (also `--camera-only`) |
| Straight push-off, no input | Fatal gorge fall at **1:08.7** — no completion |
| Reference route | **5:28.7**, 10,033 m travel, 39.4 m/s peak, 4 recoverable falls |
| Cautious profile | **6:36.7**, 28.8 m/s peak, 2 falls |
| Tricks profile | **5:30.2**, 43.7 m/s peak, 18 rewarded landings, 2.2 boards of nitro earned, 7.2 s boosting |

Bots press only ordinary inputs and know the route; they prove the course is rideable, not how it feels.

## Pass 4 measurements

- **Mix** (`tests/movie_mix.gd`, real mixer via Movie Maker, 40 s descent recorded once per half): music-only −19.9 LUFS at speed; effects-only −29.1 LUFS at speed; before this pass −23.0 and −16.1.
- **Render cost at 3840x2160** (`tests/perf_probe.gd`, counts only — software-GL frame times are meaningless):

| View | Draw calls | Primitives |
|---|---:|---:|
| Summit | 454 | 543,620 |
| Cliffs | 439 | 511,502 |
| Forest | 456 | 1,220,439 |
| Broken Mountain | 431 | 357,688 |
| Final Descent | 381 | 495,471 |
| Finish | 345 | 242,614 |

  About the same as pass 3 (more trees, offset by a shorter detailed-tree range of 320 m). Startup generation 4.5 s on the cloud CPU (was 3.2 s).
- **Renders inspected** (software GL, 1600x900): summit peak, fast summit, gorge approach, buttress, forest, escarpment, broken mountain, pinch gap, final bowl, finish.

## Still needs the owner's PC

1. **Listen again**: is the music now clearly on top, is the wind pleasant, are impacts/nitro still satisfying at the lower effects level? (Measured, not heard.)
2. **Ride the new mountain**: summit ridge, gullies as banked lines, benches, the icefall creek, both gap jumps; does it now feel like a place?
3. Xbox feel of the standing push (A when stopped) and everything listed for pass 3.
4. Real 4K/60 frame rate, especially the denser forest.

# Pass 3 record (history)

Everything below describes pass 3 as delivered; where pass 4 changed a number, the pass-4 section above wins.

## What changed in pass 3

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

**Audio** (`tools/synth_audio.py`, `audio/`, `scripts/snow_audio.gd`, `scripts/haptics.gd`): 32 original synthesized sounds; surface-aware board layers, three wind layers plus clothing, landing/crash/tumble tiers, the nitro voice (ignite → resonant build → "singing ice" sustain → deplete) and the empty sputter; positional pass-by whooshes; exposure/forest-shelter/cliff-reverb environment; limiter and glue compression. **Soundtrack:** `scripts/music.gd` manages the owner's seven songs (merged from `main` during this pass): fixed opener `Alpine Shift (Take 2) (Remix).mp3`, shuffle bag of the others, full reshuffles with no back-to-back repeats, 2.5 s crossfades, Music bus at −8 dB with ducking under crashes/nitro, pause-in-place on explicit pauses, uninterrupted through crashes/finishes/restarts, automatic discovery of new .mp3/.ogg files, graceful fallbacks. The previous no-music rule is superseded. Controller haptics for snow texture, landings, crash tiers, nitro and sputter.

**UI / controls**: restyled frosted pause/results screen (time, top ten with the new entry highlighted, readable remap names), auto-pause on controller disconnect and window focus loss, results delayed briefly after a finish/fatal crash. Same 15 remappable actions; control and record files unchanged.

## Pass 3 automated validation (cloud, Godot 4.7.2 Linux, 60 Hz fixed step)

| Suite | Result |
|---|---|
| Import / parse | exit 0, no errors |
| `prototype_test.gd` (core rules, input, persistence) | **40/40 passed** |
| `feel_test.gd` (new pass-3 systems + soundtrack manager) | **48/48 passed** |
| `terrain_test.gd` (local fixtures) | **5/5 passed**: seam momentum; spur ollie clears and earns **0.18** nitro; Broken Mountain pinch gap clears with an ordinary ollie at ~30 m/s and earns **0.22** nitro |
| `mountain_test.gd` camera checks | 8/8 passed (also `--camera-only`) |
| A: straight push-off, no input | Rock falls, then **fatal gorge fall at 1:19.57**, Z≈1803 m — no completion |
| B/C: controlled reference route | **5:24.52** (324.52 s), 9,992 m 3D travel, 38.8 m/s peak (~140 km/h), 4 recoverable falls, finish recorded once |
| Cautious profile | **6:45.55**, 28.2 m/s peak, 4 falls |
| Tricks profile (ollies/spins/grabs + spending nitro, same route) | **5:20.05**, 43.4 m/s peak, **17** rewarded landings, **2.18** boards of nitro earned, **7.1 s** boosting |

Bots use only ordinary inputs (they read state to decide) and never write position, velocity, heading, nitro or time. They know the route, so they demonstrate traversability and a ~5-minute baseline, not human difficulty. Pass-2 equivalents for comparison: 5:20.62 controlled, 6:42.02 cautious, straight fatal at 2:32.90.

## Rendering evidence (software GL — appearance only)

Captured with `tests/visual_capture.gd` at 1600x900 and `tests/movie_ride.gd` (Movie Maker, 960x540) and inspected: summit vista, look-back, gorge approach (dark scoured band and visible far wall), gorge side view, buttress, forest and tree close-up, escarpment, Broken Mountain pinch gap (kicker reads as scoured stone), final bowl, finish gate, rider close-up, carving with spray and tracks, nitro glow/embers, pause menu, and a real ride with airs, carves, boost and sputter. Renders are not committed (git-ignored `work/`); regenerate with QA.md §6–7.

## Pass 3 render cost probe (4K, counts only)

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

## Pass 3 audio measurement (not a listening test)

Movie Maker capture of the real bus output during a scripted 31 s ride (summit, push-off, three trick jumps, carves, nitro, empty sputter, brake, crash with tumble and get-up), analysed with `tools/analyze_mix.py`. First capture: no clipped samples, peak −5.6 dBFS, −26.8 dB RMS, so the SFX bus was raised 4 dB. Final capture: **no clipped samples, peak −1.6 dBFS, −23.0 dB RMS**; quiet summit ambience (≈ −42 dB RMS); board hiss (2–8 kHz) drops ≈ 8 dB within 0.1 s of leaving the snow; landings add ≈ 15 dB of sub-150 Hz energy; the crash, empty-nitro sputter and nitro ignition stand clearly above the riding bed. The soundtrack was not yet installed during the ride captures. A separate soundtrack capture (`tests/movie_music.gd`) through the real mixer showed the opener at launch (≈ −27 dB RMS with summit ambience), digital silence while paused, resume at the same position (3.99 s → 4.00 s), a seamless crossfade to the next song and no clipping. Track loudness measured −14 to −20 LUFS (ffmpeg EBU R128) against −18.4 LUFS for the gameplay mix. Loop seams were checked numerically. Nobody has listened to the mix yet.

## Requires hands-on testing on the target PC

1. Xbox controller feel: carve/edge response at 20/60/120 km/h, brake skid, tuck, preload timing, air tricks, RS free look while riding/in air, idle settle and recenter, haptics strength, disconnect/reconnect, remapping on hardware.
2. Listening on headphones and speakers: layer balance, air→landing transition, nitro identity, sputter recognisability, crash weight, loudness.
3. Sustained fullscreen 4K/60 on the RTX 2070 SUPER, especially forest, boosting and free orbit in dense trees; startup time.
4. Human route readability and fairness: first-time hazard reading, both gorge ends, spur and pinch-gap shortcuts, summit rollers, final tabletop, recovery after poor lines; beginner vs expert times.

## Known limitations

- Procedural art and animation (no skeletal mesh, no ragdoll; tumble is a scripted rigid body tumble with limb flail). Tracks are ribbons, not deformation.
- CPU particles (Compatibility) express spray density through opacity/size rather than emission rate.
- Bot results are not human results; fixed 60 Hz does not guarantee bit-identical contact physics across hardware.
- Pass 3 kept `snow_records_massif_v2.json`; pass 4 reshaped the mountain and moved to `snow_records_massif_v3.json` (older files are kept untouched).

## Launch

See the pass 6 section at the top and launcher/README.md.
