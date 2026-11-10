# Development roadmap — after pass 3

## Done in pass 3

Camera rebuilt around travel-relative free look; riding physics (carve limit, edge engagement, surfaces, preloaded ollie, coyote, air-only drag, landing quality, high-speed ollie fix, trunk shuffle); trick economy with fatigue; visual-only crash tumble and safe get-up; articulated procedural rider with IK; full environment overhaul (terrain/tree/rock/sky/backdrop shaders, conifer and boulder meshes with LOD, outcrops, surrounding ranges, sun/fog/exposure, finish area); spray/bursts/embers/bough snow/board tracks; synthesized 32-sound audio set with layered mixing, bus graph, limiter and positional pass-bys; haptics; restyled pause/results; disconnect/focus auto-pause; optional jump lines; new test suites and capture tools; documentation for cloud development.

## Next priorities (need the target PC / humans)

1. Physical Xbox session: tune `snow_tuning.gd` carve/edge/brake/ollie/camera constants from real feel; verify haptics strength and remapping on hardware.
2. Listening session: balance layer gains in `snow_audio.gd` LOOPS, event volumes and the synth recipes in `tools/synth_audio.py`; check limiter/compressor behaviour and loudness.
3. Sustained 4K/60 profiling on the RTX 2070 SUPER (`perf_probe.gd`, `massif_capture.gd`, real play): if the forest is heavy, shorten `TREE_NEAR_RANGE`, reduce shadow split distance, or simplify the near tree mesh.
4. Human route study: first-time readability of every hazard band and shortcut; collect beginner/learned/expert times; adjust telegraphing (lip scour thresholds, outcrop density) rather than slowing the board.

## Future ideas (keep the core idea; no bloat)

- Skeletal mesh rider (properly licensed or hand-built glTF) driven by the existing pose parameters.
- Snow deformation for tracks (heightmap decal) instead of ribbons; powder plumes that hang in the air.
- Terrain/collision LOD to widen the explorable area.
- Recorded or physically modelled snow/gear foley if a licensed, documented source is available.

## Regression gate

Run every command in QA.md (import, prototype, feel, terrain, mountain straight/controlled/cautious/tricks/camera-only), inspect logs and renders, and update BUILD_STATUS.md with measured — never assumed — results.
