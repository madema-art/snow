# The Massif — course `massif_v4` (the 360-degree mountain)

SNOW is one real mountain. The rider starts stationary on its summit, the highest point of the world, and can go down **any** side. There is no main course, no preferred direction, no finish line and no route to follow: the run ends on whichever valley floor the rider reaches at the bottom. Times from the earlier linear courses (`massif_v2`, `massif_v3`) are not comparable, so this course has its own records; the older files stay on disk untouched.

Compass: **north = -Z, east = +X, south = +Z, west = -X**. Azimuths are measured from north, clockwise.

## Scale

| | |
|---|---|
| Summit | ~3,730 m, at the world origin: a ~4 m top that falls away at a steady 0.42 grade in every direction, so the faces below are visible from the start |
| Valley floors | 300–1,050 m depending on the side (south lowest, north highest) |
| Net drop | ~2,700–3,400 m |
| Summit to valley floor | ~9–10.5 km in a straight line on every side; real lines ~9.5–11 km |
| Baked world | ±16 km square (1280 × 1280 height samples, 25 m apart) |
| Horizon ring | distant ranges out to ±48 km (render only) |

A skilled descent should take about five minutes; the test bots, riding carefully with no nitro, take 5:41–6:45 depending on the side (BUILD_STATUS.md). Different faces and lines take different times, and that is part of the game.

## How the mountain is made

**Baked large scale** (`tools/build_massif.py` → `world/massif_v4.bin`, deterministic):

1. **Ridge skeleton.** A summit ridge joins the main summit to two subsidiary peaks (north-west ~3,390 m, south-east ~3,300 m). Ten aretes run from the peaks out to the valleys, each with side spurs. The skeleton is measured in a domain-warped space, so ridges meander instead of running straight.
2. **Flanks by aspect.** Every point takes the highest of the flanks falling away from the skeleton (a smooth maximum, so valleys get rounded bottoms). How a flank falls depends on which way it faces: north-facing slopes are short and steep, south-facing ones long and open, east and west in between. This is what gives the faces their different characters and the ridges their asymmetric profiles.
3. **Summit dome**, valley floors that fall gently away from the base (each side at its own elevation), and the surrounding ranges beyond them. The ranges' front wanders by kilometres and foothills stand on the floors, so the valleys are not a ring.
4. **Rock relief and stream-power erosion** (32 passes of flow accumulation, gently smoothed so gully walls stay rideable): dendritic gullies and spurs on every face.
5. **Cliff bands**: where a face is meant to be cliffy (strongest north, north-west and west, by altitude) *and* is already steep (judged over ~100 m), the slope is gathered into rock risers (steep rock faces up to ~75 m tall, every 140 m of height) with benches between that follow the contours and keep about a third of the slope, so they ride rather than stall. Bands break into segments with wide gaps, and fade where the gullies run: those are the couloirs.
6. **Pit filling** (priority flood from the valley floors) runs AFTER the bands: no closed hollow anywhere on the mountain, guaranteed. Filled flats (frozen tarns) keep a 0.07 grade, so a stopped rider can always glide or skate out.
7. **Masks**: valley floor (where a descent can end), cliff (where bands were carved: rock colour, rocks), forest (below each face's treeline, thinned on steep ground and on the floors), cornices (the lee lip of high crests).

**Runtime detail** (`SnowMountain.height_at`, same function for rendering, collision, physics, camera, audio, tumbles and tests):

- **Cornice lips** on the lee of high crests.
- **Wind-drift rollers** on open, moderately steep snow (30–50 m across, up to ~3.6 m): natural kickers for a fast rider. They fade on gentle ground so they never dig pockets.
- **Small relief** (±0.6–2.6 m).

## The faces

| Side | Character |
|---|---|
| **North** | The steepest, iciest face: dense cliff bands under the summit ridge, narrow couloirs between them, a high glacial valley floor (~1,000 m). Fast for experts who know the line, fatal for anyone who rides straight. |
| **North-east** | Hanging snowfields between the north and north-east aretes; broken cliff bands; a long ridge to follow. |
| **East** | The longest, gentlest-flanked side: big forested slopes below ~2,200 m, rocks and technical tree lines, a forest river valley (~600 m). |
| **South-east** | Rolling spurs off the south-east peak, glades and scattered stands. |
| **South** | Broad open snowfields from the summit dome, the most rollers to launch off, the lowest and widest valley (~300–400 m). The most forgiving start. |
| **South-west** | A big open bowl between the south and south-west aretes, meadow basins below. |
| **West** | Deep ravines between massive ridgelines, cornices on the crests, cliff bands on the ravine walls. |
| **North-west** | Rock spires and the long serrated north-west arete from the second peak; you can follow it, or drop into the bowls either side. |

Every side has at least one way down that a careful rider can find; many straight lines do not (riding straight from the summit meets cliffs, rocks, trees or gullies on every face). `tests/mountain_test.gd -- --map` draws the cliff cells, valley floors, forest and a planned line for each of the eight sectors into `work/route_map.png`.

## Starting, finishing

- **Start:** the summit dome is gentle enough to roll off in any direction. Before pushing off, the left stick turns the board on the spot (the clock does not run); the right stick looks around. A (push) starts the clock and sends the board the way it points.
- **Finish:** the descent is complete the moment the rider is **riding** (grounded, not recovering, not in the air) on a **valley floor** (the baked floor mask) at least **1,500 m below the summit**. Valley floors are low, gentle ground beyond the mountain's base on every side — never the bottom of a ravine on the flanks and never the air above a valley. The side the run finished on (North, South-west, …) is saved with the time and shown, dimmed, in the records list.

## Fairness rules

- No checkpoints, invisible walls, coordinate death zones or speed caps. Fatality only from real impacts and falls (drop heights, tumbling over a drop of 18 m or more, hard impacts).
- No closed hollows on the mountain; pushes chain like skating up to 5 m/s, so nobody can be trapped on a flat.
- Boulders never touch or pinch (there is always a rideable gap); trees and rocks are placed per tile from fixed seeds, so the forest you learned is the forest you meet.
- The mountain never changes between attempts: learn it, find your line.
