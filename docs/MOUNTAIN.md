# The Massif — course `massif_v3` (pass 4)

Pass 4 reshaped the mountain itself after the first hands-on playtest ("the mountain needs a lot of work, but it's the right concept"). The hazards and regions of `massif_v2` are still where they were; what changed is everything between them. Because times are no longer comparable, records moved to `user://snow_records_massif_v3.json`; the v2 file is left untouched.

## Dimensions

`SnowMountain.LENGTH = 9360 m`, `WIDTH = 1200 m` (X=-600..600), +Z downhill, +Y up. Spawn Z=8, finish gate Z=9180 (|X|<50). ~3.11 km net drop. Backing terrain Z=-200..9600 as 48 indexed 200 m chunks (8 m grid), render triangles == collision triangles. Beyond |X|≈520 cornices fall to real lower slopes and the surrounding ranges (SnowBackdrop, with collision). No checkpoints, invisible walls or coordinate death zones. Feature definitions use a logical distance (world Z / 1.2).

## Shape of the mountain (new in v3)

- **A true summit.** The rider starts 12 m below the top of a peak. The ground falls away behind the start and off both shoulders of the summit ridge (convex for the first ~1 km, blending into the broad bowl below), so the first seconds are a ridge crest with the whole valley ahead.
- **Pitches and benches.** The grade is no longer one constant 0.34 ramp: it swings between about 0.24 and 0.44 (steep off the top), and the benches curve across the face. The average grade — and therefore the ~5 minute target — is unchanged; no speed cap, no padding.
- **Two natural drainages** (`west_line()` / `east_line()`), banked snow gullies 5–10 m deep that wind down the whole mountain and can be carved like a natural half-pipe:
  - On the open upper faces they pass either end of the gorge, so the terrain itself suggests the safe shoulders.
  - Through the forest they ARE the two tree-free corridors, as creek beds.
  - The **west** creek pours over the forest escarpment (a ~85 m icefall: fatal). The **east** creek passes the end of the escarpment safely.
  - In the Broken Mountain the east drainage dies out among the ridges; the west shoulder continues past the second cut.
  - Both converge into the valley floor at the finish.
- **Rolling relief.** Seeded simplex noise adds wind drifts and moraine rollers (±2–4 m over 60–115 m), strongest in the Broken Mountain: things to pump, pop off and read.
- **Scenery in natural patterns.** Trees follow a continuous altitude-and-clump density: nothing on the summit, wind-stunted krummholz from ~0.4 km, scattered stands through the cliffs, thickets and open glades in the forest, sparse survivors in the broken ground, timbered valley flanks. Boulders gather into gardens and moraines with a few house-sized erratics — and never touch or pinch, so there is always a rideable gap (no traps).

## Regions (world Z)

| Region | Z | Personality and decisions |
|---|---|---|
| Summit | 0–1320 | Peak and summit ridge, steep first pitch, then the face opens. East-side wind-drift rollers (X≈70..420) for early air and first nitro; the two gullies begin either side of the ridge. |
| Cliffs | 1320–3360 | A bench, then the transverse gorge (~100 m deep, X≈-215..215) with a dark, scoured lip. Around either end (the gullies lead there) or the narrow spur gap at X=120 — kicker at the lip, lower far rim and a steep landing. Rock gardens, outcrops on every wall, then the buttress with routes around both ends. |
| Forest | 3360–5640 | Thickets and glades, two creek-bed corridors, softer powder, muffled wind. West creek = icefall over the escarpment near Z≈5.1 km; east creek passes it. |
| Broken Mountain | 5640–7800 | Diagonal ridges, strongest rollers, boulder moraines, two deep offset cuts (≈6.55 and 7.56 km). The first cut pinches to a ~35 m gap at X=170 (kicker, raised far rim, landing). |
| Final Descent | 7800–9360 | Open valley bowl between timbered flanks; the drainages merge into a broad trough; ramp at X=0 and tabletop at X=-70; pennant lines and the timber finish gate. |

## Surfaces

`SnowMountain.surface_at()` returns (powder, ice): ice on steep, convex, exposed and wind-patched ground; powder in the forest and concave hollows (gully floors). Physics: ice -32% edge grip, slightly less resistance; powder more resistance/drag. The terrain shader, board audio and haptics use the same values.

## Readability and fairness

- The low sun now rakes ACROSS the fall line: every roll, bank, gully and ripple is modelled by light and long shadows instead of flat white.
- Lips whose ground falls 5–14 m faster than the grade within 24 m are scoured dark; the camera rises when the ground ahead drops away.
- Shortcut approaches and landings are clear of scenery; both gap jumps are proven clearable with an ordinary ollie (local fixtures).
- Falling near an edge is dangerous on purpose: a tumble carries real momentum, and one that goes over the gorge lip, the icefall or a cut is fatal.
- Getting stuck is designed out: A pushes off again whenever the rider is nearly stopped (kicking away from a trunk/boulder if leaning on one); get-up spots need a clear 7 m slide downhill; boulders keep rideable gaps; a rare trimesh-crease freeze self-corrects.
- Trunk radius 0.3 x scale (collider == visible trunk); canopies are non-solid.

## Routes

Reference broad route (tests/mountain_test.gd ROUTE): west gully past the gorge and buttress, lower forest gaps, traverse east before the escarpment, west across the broken mountain's shoulder, down the bowl. Alternatives: east gully and east gorge end; spur jump; buttress chute; east creek through the whole forest; outside escarpment line; pinch-gap shortcut; summit rollers; final tabletop. Bots only press ordinary inputs and prove traversability, not human difficulty.

## Collision

Terrain trimesh == render mesh. Trees: per-chunk static bodies, `CylinderShape3D` trunks (radius 0.3 x s, height 4.8 x s). Boulders/outcrops: `ConvexPolygonShape3D` from the exact displaced vertices of the visual mesh. Backdrop: coarse trimesh under the course edge. Hazards are bucketed per 200 m for queries (`hazards_near`).
