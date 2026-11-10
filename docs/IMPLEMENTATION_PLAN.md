# Development roadmap — after pass 2

## Implemented

The original short playable scaffold has become the Massif: a 9.36 km x 1.2 km mountain, ~3.115 km net vertical drop, five connected regions, real offset gorges/buttress/chutes/forest/gullies and optional ramps. The full route now targets about five minutes through distance and navigation; no speed cap or clock padding. A straight-line attempt meets real rocks and a gorge fall. Known-route input-only navigation completes. Local seam momentum handling and matching solid colliders improve fairness. Full independent 360/vertical/airborne RS camera, remappable smooth recenter, separate bumpers/D-pad tricks and migrating controls are implemented. Existing no-HUD/timer/pause/nitro/board-glow/crash/restart/records rules remain. Regional wind improves environmental sound; no music.

## Highest priorities

1. Physical Xbox play sessions: carving/analog feel at speed, free camera hold/settle/recenter, airborne look-back, all remaps including triggers/camera/flips, reconnect/haptics and fixed UI navigation. Synthetic events do not certify hardware feel.
2. Human route difficulty: compare first-time, learned safe routes and expert shortcuts. Measure real completion distributions; bot route knowledge is a repeatable baseline only. Tune telegraphing, forest density, slow-speed recovery, ridge traverses and landing tolerances without removing geographical difficulty.
3. Explore/verify both sides of each gorge and all optional chutes/jump lines. The broad full route and one local spur jump have automated proofs, not every conceivable shortcut. Refine individual 8 m cliff lips if contact proves unfair.
4. Camera stress: dense trees, close rock walls, low/high pitch, look-behind at speed, long inactive hold and smooth recenter. Keep camera independent from ALL rider movement/tricks.
5. Sustained moving real 4K/60 profiling and frame-time tails, startup generation, physics at forest density and high-speed collisions. Short explicit offscreen 4K GPU probes are preliminary. Preserve batching/native collision and no settings menu.
6. Listen/mix on headphones/speakers, refine original environmental layers and haptics, maintain empty Music bus. Then improve low-poly landmarks, snow-covered tree shapes, skeletal ride/get-up animation, spray/tracks and terrain art.

## Future

Terrain/collision LOD or streaming for wider exploration, replay/course versioning and stronger persistence hardening, richer approved art and animation. Do not add wildlife, helicopter, opponents, injury/health, HUD, checkpoint forcing, background music, avalanche or advanced storms in this build.

## Regression gate

Run QA.md commands: engine import/parser, core rules/remap/pause tests, local seam/ollie fixture, input-only straight and controlled full descent, optional cautious profile, and rendered regional/free-camera/4K GPU probes. Inspect logs/images. State exactly what is automated versus physically played; keep CLAUDE.md, MOUNTAIN.md, ARCHITECTURE.md and BUILD_STATUS.md accurate.

