# The Massif — course `massif_v2` (pass 3)

## Dimensions

`SnowMountain.LENGTH = 9360 m`, `WIDTH = 1200 m` (X=-600..600), +Z downhill, +Y up. Spawn Z=8, finish gate Z=9180 (|X|<50). ~3115 m net drop from the snow under the spawn to the gate. Backing terrain Z=-200..9600 as 48 indexed 200 m chunks (8 m grid). No checkpoints or invisible walls; beyond |X|≈520 visible cornices fall away to real lower slopes and the surrounding ranges (SnowBackdrop, with collision), so leaving the course is a physical fall, not a coordinate kill.

Feature definitions use a logical distance (world Z / 1.2). The base grade (0.34), gravity, drag, carve and boost produce the time; pass 3 kept the pass-2 course and hazard seeds, so records remain comparable (`snow_records_massif_v2.json`).

## Regions (world Z)

| Region | Z | Personality and decisions |
|---|---|---|
| Summit | 0–1320 | Broad exposed plateau under serrated peaks; the whole valley opens ahead. Sparse rocks, a few wind-stunted firs. **New:** an east-side field of wind-drift rollers (X≈70..420) — optional playful kickers where a timed ollie becomes real air and the first nitro. The west ramp (X=-80) remains. |
| Cliffs | 1320–3360 | The transverse gorge (~100 m deep near Z≈1.8 km) spans X≈-215..215; its lip is wind-scoured, darker and stony long before the edge. Go around either end, or risk the narrow rock spur jump at X=120. Large boulders, outcrops on every steep wall, then the exposed buttress (Z≈2.77 km) with routes around both ends and a narrow central chute. |
| Forest | 3360–5640 | Dense snow-loaded conifers with two winding natural corridors and countless gaps; softer powder underfoot and muffled wind. Branch canopies are non-solid (snow falls as you brush them) but trunks are solid. The left-side escarpment near Z≈5.1 km demands an early traverse right or a long outside line. |
| Broken Mountain | 5640–7800 | Ridges, gullies, rolls, boulders, icy convex spines. Two deep offset cuts (≈6.55 and 7.56 km). **New:** the first cut pinches to a ~35 m gap near X=170 with a kicker on the uphill lip and a raised far rim whose downslope is a proper landing — a visible, committing shortcut versus the long west detour. Optional ramps near X=-270/+290. |
| Final Descent | 7800–9360 | Open, fast valley bowl framed by timbered flanks (|X|≈330–505) — the place to spend nitro. A ramp near X=0 and a **new** tabletop near X=-70 (Z≈8.63 km). Pennant lines funnel the last 260 m to the timber finish gate, banner and timing hut. |

## Surfaces

`SnowMountain.surface_at()` returns (powder, ice): ice on steep, convex, exposed and wind-patched ground; powder in the forest and concave hollows. Physics: ice -32% edge grip and slightly less resistance; powder more resistance/drag. The terrain shader paints the same values (bluish, smoother ice; brighter, softer powder), audio cross-fades the matching board layers and haptics sharpen on ice — what you see is what you ride and hear.

## Readability and fairness

- Lips: vertices whose ground falls >5–14 m faster than the grade within 24 m downhill (or sideways) get rock/scour colour, so gorge edges, cuts and escarpments read as dark bands from far away.
- Outcrops: ~880 faceted stone outcrops on steep walls (solid convex rocks) make cliffs look like cliffs.
- Camera: rises automatically when the ground 30–85 m ahead drops away faster than the slope.
- Shortcuts are clear of scenery on approach and landing (spur X=120, pinch gap X=170) so the gap itself is the only danger.
- Trunks are thinner than pass 2 (visible solid trunk radius 0.3 x scale) and still exactly match their colliders; canopies are non-solid.
- Rider pinned against a trunk at walking speed shuffles around it in the board's direction.

## Routes

The reference broad route (tests/mountain_test.gd ROUTE): west around the gorge and buttress, through lower forest gaps, traverse east before the escarpment, west across the broken mountain's safer shoulder, then down the bowl. Bots use it with only ordinary inputs; it is evidence of traversability, not a human-difficulty measure. Alternatives: east around the gorge; spur jump; buttress chute; forest corridor B; outside escarpment line; pinch-gap shortcut; east broken launches; summit roller line. Local fixtures prove the spur and pinch-gap jumps are clearable with a normal ollie and land cleanly with a nitro reward; not every alternative line has been ridden end-to-end by a human.

## Collision

Terrain trimesh == render mesh. Trees: per-chunk static bodies with `CylinderShape3D` trunks (radius 0.3 x s, height 4.8 x s). Boulders/outcrops: `ConvexPolygonShape3D` from the exact displaced vertices used by the visual mesh, with the instance rotation/scale. Backdrop: coarse trimesh below the course edge. Hazard positions are also kept in 200 m buckets for queries (`hazards_near`).
