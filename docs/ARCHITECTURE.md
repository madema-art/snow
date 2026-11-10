# Architecture — development pass 2

Project root `D:\Snow`, Godot 4.7.2, main scene `scenes/main.tscn`. No external dependencies or second project. Terrain and native assets are built once by small GDScripts.

| File | Responsibility |
|---|---|
| scripts/main.gd | Compose controls, run, mountain, rider, camera, audio, pause; wire restart to camera reset |
| scripts/mountain.gd | Massif course v2, analytical height/normal/region functions, indexed render/collision chunks, per-chunk seeded tree/rock batches, matching colliders, finish, fog and silhouettes |
| scripts/snow.gdshader | World-space snow grain/mottling/ridges without downloaded textures |
| scripts/rider.gd | Swept CharacterBody motion, gravity, edge grip, brake/tuck/ollie, independent aerial tricks, landed rewards/nitro, impacts/apex/drop rules, local safe recovery and restart |
| scripts/rider_visual.gd | Procedural rider/board, normal conformance, lean/crouch/grab/get-up poses and charge-only board emission/light |
| scripts/chase_camera.gd | Independent absolute-yaw 360 orbit, pitch, analog response, idle/recenter state, speed lookahead/FOV/distance and sphere sweeps before/after smoothing |
| scripts/controls.gd | Xbox/default developer actions, permanent LS steering, explicit fixed UI events, validated conflict swaps and v1→v2 remap migration |
| scripts/run_state.gd | Ready/running/finished/ended, push-off clock, paused guard, course-specific top ten persistence and hundredth formatting |
| scripts/pause_menu.gd | Always-processing hidden CanvasLayer; pause/results, fixed focus navigation, saved remap capture and resume/restart/quit |
| scripts/snow_audio.gd | Original seeded PCM buffers, wind/snow/edge/boost loops, pooled event voices, regional filtered/gusted wind, SFX/MountainWind/Music buses, rumble |

## Mountain

See MOUNTAIN.md for exact geography/routes. Run length 9.36 km, width 1.2 km, net summit-to-finish drop ~3.115 km. Spawn Z=8, finish Z=9180 with |X|<50 on grounded non-recovering contact. Render/collision backing extends Z=-200..9600, X=-600..600, at 8 m spacing in 49 indexed 200 m chunks (~367,500 triangles). Every rendered terrain triangle has collision. Five naturally blended regions; several real transverse cuts, buttress/chute, forest corridors, broken ridges and optional ramps. No checkpoint enforcement and no coordinate death zones. Fixed seeds: scenery 74021 + chunkStart*13, backdrop 840, audio 3129. Trees and rocks are batched locally for culling; all hazards retain real native colliders.

## Physics and collision

+Z downhill, +Y up; initial camera screen-right is world -X, so positive steering reduces heading. Gravity 20 m/s², ollie 8.8 m/s, edge grip 5.2, turn rate 1.28, quadratic drag 0.0075, boost 24 m/s², nitro burn 0.25/s remain unchanged. No speed limiter was introduced. Physics is fixed 60 Hz; acceleration uses delta and damping uses exponential rates. Floor tangent Y is reconstructed because CharacterBody clears floor vertical velocity; normal gravity projection accelerates downhill. Edge damping changes sideways motion while retaining forward inertia. Brake dissipates energy; tuck reduces quadratic drag.

The 1.3 m capsule (r=0.28) uses move_and_slide sweeps, actual floor normals, 57° floor threshold and 0.85 m floor snap. Matching trunk cylinders and baked faceted rock convex hulls replace oversized capsules. Canopies are non-solid. Incidental normal contacts <5 m/s may brush past; stronger ones crash. Fatal normal impacts: tree >30 m/s, rock >34 m/s; terrain faces steeper than a floor can crash above 16 m/s normal impact and are fatal above 34. No X/Z boundary kills. Apex tracking detects real >55 m sustained airborne drops (and downward velocity), or >35 m drops on landing. Bad trick alignment/normal landing impact >24 m/s and extreme edge sliding remain recoverable crash triggers.

Air tricks use ONLY remappable bumpers for yaw and D-pad up/down for flips; RS has no rider/trick references. Clean 180/switch/full yaw landing tolerance 0.85 rad, pitch tolerance 0.7 rad. Clean jumps plus completed rotations/grabs earn charge only at landing; reversing net rotation cannot farm completed tricks. Variable boost bursts use stored charge and do not alter edge grip. Board color/emission is the only charge display.

ALL falls immediately set nitro, velocity, speed and boosting to zero and update board emission. Recovery length clamp(1.2+severity*0.12,1.2,7) s counts toward run time; world travel stops. Local recovery probes reject hazard overlap, steep candidate snow or vertical changes >5 m; they return to safe nearby snow, not past a gorge. Fatal attempts never enter records. Pose animation is a prototype, not ragdoll. last_crash_reason is debug/test metadata only, never HUD.

## Camera and controls

Camera stores absolute yaw, independent of heading. Input.get_vector applies radial deadzone 0.18; magnitude^1.35 gives precision near center and fast large-input response. Horizontal rate 2.65 rad/s has no limit or snap; pitch rate 1.8 rad/s clamps orbit elevation to -0.35..1.25 rad. Yaw affects only the camera. Manual input resets a 3 s inactivity grace period and cancels recenter. After grace, gentle shortest-angle settling follows heading. Explicit recenter (default RS click) uses faster smooth settling, never a hard transform reset. Only restarting hard-resets the camera. Speed increases follow distance and FOV and adds forward lookahead. A cached 0.45 m sphere query checks the desired and smoothed camera positions against real terrain/hazards; near plane is 0.12 m, far clip 6500 m.

Defaults: fixed LS steer, fixed Menu pause; A push/ollie, B boost, LT brake, RT tuck, X grab, LB/RB yaw, D-pad up/down flips, RS camera, RS click recenter, View restart. All non-reserved actions remap via conflict swaps. Keyboard: README. Fixed UI D-pad/LS/A/B does not inherit gameplay mapping. Expanded mappings fit the same minimal pause layout, with explicit focus neighbors.

## Run and saves

Only explicit push-off starts elapsed simulation time. Recovery counts; scene load and camera movement do not. Tree pause freezes world, camera, sound and time, even in midair. Finish saves once and opens the same pause/results interface with Resume disabled. Hundredths are rounded for display; underlying clock resolution is 1/60 s, times serialized to milliseconds.

New official-course records: user://snow_records_massif_v2.json; original user://snow_records_v1.json is retained unchanged and is not mixed with new course records. Expanded controls: user://snow_controls_v2.json; valid old v1 mappings migrate, retaining old actions and finding conflict-free free buttons for new actions. Malformed/corrupt files fall back/filter safely. Paths resolve under %APPDATA%\Godot\app_userdata\SNOW on Windows. Automated fixtures use test_* files and clean them up. There is no anti-cheat or cross-hardware bit-identical replay proof.

## Performance and remaining limits

Indexed terrain computes each vertex once; bounded generation happens at startup, not during descent. Local MultiMeshes and 1250 m visibility range prevent drawing the entire forest. Final generated count: 4117 trees, 960 rocks, 48 distant silhouettes. Compatibility rendering, 2x MSAA, one 145 m shadowed sun, no expensive GI/storms, non-shadow board lamp. Audio uses original precomputed buffers and six event players. Camera queries are reused; collision recovery queries allocate only on crash.

The test benchmark creates an explicit 3840x2160 SubViewport and samples native GPU timer values with VSync/cap disabled only inside the benchmark. A small visible root window also renders, so total call counts include two views. These are short stationary regional probes, not sustained moving gameplay certification. See BUILD_STATUS.md for numbers.

Procedural low-poly art/poses and synthesized audio remain placeholders. No tracks, spray, deformation, skeletal animation or ragdoll. Coarse 8 m cliff lips and optional shortcuts need manual fairness checks. Physical Xbox feel/reconnects/haptics, sustained 4K frame-time tails, audio listening and all alternate routes still require human playtesting. Do not infer these from synthetic input or successful bot navigation.


## Terrain-seam correction

Valid snow-only contacts now preserve the computed tangent candidate velocity after native contact resolution, with the artificial downward contact-pressure term removed before projection. This prevents internal triangle edges from deleting momentum. The restoration is excluded for solid hazard contacts and genuine steep walls; analytical surface normals disambiguate an internal-edge normal from a real rock face. Sweeps still determine position, and bad landing/drop checks still run. Clean normal landing tolerance is 24 m/s, while misaligned rotations and large physical drops retain consequences. The local terrain test verifies preserved approach speed, a real gap-crossing ollie, clean landing and charge payout. Longitudinal features/regions use logical distance divided by DISTANCE_SCALE=1.2; physical length and base grade, not fake timing, produce the final run duration.

