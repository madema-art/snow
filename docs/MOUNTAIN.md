# The Massif — course v2

## Physical dimensions

`SnowMountain.LENGTH = 9360 m`, `WIDTH = 1200 m`, X=-600..600; +Z downhill, +Y up. Spawn is Z=8; the finish gate is Z=9180. The main playable longitudinal difference is 9172 m, with ~3115 m net vertical drop from snow under spawn to the valley gate. Backing terrain includes a summit margin and runout from Z=-200..9600: 49 native indexed 200 m collision/render chunks, 8 m spacing, 367,500 triangles, ~192,000 vertices. No route checkpoints or invisible walls exist. Crossing outer terrain edges exposes real lower snow slopes and eventual physical falls, not coordinate kills.

The base grade is 0.34 with large-scale rolls, cross-slope undulation and exposed shoulders. Maximum speed is not capped. Runtime rider gravity (20 m/s²), drag (0.0075), carve and boost constants remain from pass 1. The much larger distance, vertical relief, traverses and geographic risks create the longer run.

## Connected regions

| Region / approximate Z | Geography and route decisions |
|---|---|
| Summit, 0–1320 m | Exposed open alpine snow, sparse small trees/rocks, large distant peaks; approachable acceleration and time to see the terrain ahead |
| Cliffs, 1320–3360 m | ~100 m deep transverse gorge near 1.8 km, exposed 58 m buttress near 2.77 km, large faceted rocks, narrow notch/chute and optional ramp. Broad snow routes around either gorge end; small rock spur near X=120 creates a narrow risky jump opportunity |
| Forest, 3360–5640 m | Dense variable snow-covered forest with two winding natural corridors; scattered gaps also allow free navigation. A deep left-side escarpment near 5.10 km favors traversing toward the right, or a longer outside bypass |
| Broken Mountain, 5640–7800 m | 12 m ridges, rolls and gullies; deep offset cuts near 6.58 and 7.56 km, optional ramps around X=-270/+290, boulders and sparse trees. West and east detours differ; carrying momentum through the ridges matters |
| Final Descent, 7800–9360 m | Open fast valley bowl with scattered hazards and a final ramp; room to spend earned nitro. Orange pennants, twin towers, alternating snow-level finish tiles and a world-space finish sign identify the gate |

Region transitions blend through broad terrain masks; there are no level transitions, gates that require a route order, teleporters or mandatory checkpoints. Gorge banks curve across the slope rather than being straight artificial barriers. All snow/rock-like terrain triangles have matching collision.

## Routes and difficulty

The center line is not protected from hazards. Straight input reaches a large physical fall in the first transverse gorge. A known broad route goes west around that gorge and the rock buttress, follows lower forest gaps, traverses east before the forest escarpment, then west toward the broken mountain's safer snow shoulder before entering the final bowl. These are geographical choices, not in-game waypoints.

Several alternative snow shoulders go around gorge ends; the X=120 spur offers a short gap that rewards a well-timed ollie instead of a slow detour. The buttress has a narrow central chute. East broken-mountain routes offer more direct launches but demand a later difficult traverse or a very exposed outside line. Jump lines/shortcuts have not all been manually completed; the continuous broad reference route has an automated whole-run proof.

The test bot's reference path is in tests/mountain_test.gd. It knows geographical waypoints and visible hazard positions and only presses steering/brake/tuck inputs. It never edits rider position, velocity, heading, nitro or elapsed time during the run. Thus it represents repeatable route knowledge, not a model of a first-time human. The measured distance is 3D travel, including elevation, not just map Z length. More cautious braking loses momentum and should take longer; physical beginner/expert distributions still require human playtesting.

## Collision and fairness

Trunks use matching cylindrical shapes at their visible radii/heights. Branch canopies are non-solid. Rocks use convex hulls baked from the same scaled faceted vertices as their visuals. CharacterBody movement is swept against static collision at fixed 60 Hz. Glancing normal impacts below 5 m/s do not automatically trigger a fall; harder contacts tumble, and direct normal impact >30 m/s on trees or >34 m/s on rocks is fatal. Strong hits into steep terrain rock faces also count as physical impacts.

No X/Z coordinate is an instant-death zone. Airborne apex/drop tracking causes fatality after a real >55 m falling displacement with sustained downward velocity, or a >35 m drop ending on a surface. Fall geometry is fully collidable, including gorge bottoms and walls. Bad landings and edge catches remain recoverable when below fatal thresholds. Every crash instantly zeros ALL charge/velocity/speed and darkens the board. Nonfatal recovery takes 1.2–7 s; safe local placement avoids nearby colliders and rejects steep surfaces or vertical warps >5 m. The run timer continues. This is pose-based recovery, not ragdoll physics.

## Rendering budget and limitations

Terrain is generated once; the indexed grid evaluates each vertex once. Scenery is seeded per 200 m chunk and batched into local MultiMeshes with a 1250 m visibility range, instead of a mountain-wide batch that cannot cull locally. Final course generation creates 4117 collidable trees and 960 convex rocks. Forty-eight distant silhouettes, atmospheric fog and snow grain supply scale without downloaded assets. One 145 m-range shadowed sun, Compatibility renderer, 2x MSAA and a small non-shadow board lamp remain the baseline.

The 8 m terrain grid is intentionally coarse; refine individual difficult lips/chutes if human playtesting reveals unfair contact. Procedural shapes are stylized rather than final art; no snow deformation, tracks, skeletal ride animation or ragdoll. Route exploration is constrained by physical terrain extent, not invisible barriers. Wider exploration/LOD streaming can be developed later. See BUILD_STATUS.md for actual timings and QA.md for tests, rather than assuming every conceivable shortcut is certified.


## Pass-2 contact correction and final course expansion

Local tests found the native controller could lose almost all speed on a harmless mesh seam. The rider now retains its computed tangential candidate velocity after valid snow-only contact, subtracting artificial contact pressure first, and never restores through a real hazard or steep wall. Analytical surface checks distinguish an internal-edge normal from a genuine rock face. Swept collision still determines position and all crash/landing checks still apply. Clean normal landing tolerance is now 24 m/s to permit the mountain's bigger natural jumps; misaligned trick landings and genuinely large drops remain dangerous. A local real-physics fixture proves the narrow gorge spur can be ollied and landed cleanly with a real charge reward.

After improving contact momentum, the course was physically expanded again: longitudinal geography is scaled 1.2 times, with base grade unchanged and summit raised to 3300 m. This reaches the five-minute target through more travel, not lost speed. The region table above uses actual world distances; analytical feature definitions and test waypoint constants use a logical distance divided by DISTANCE_SCALE=1.2. Scenery masks and audio region masks use that same scale. The initial open view, cliff approaches and forest transitions are therefore farther apart, while actual acceleration, drag and unlimited speed remain intact.

