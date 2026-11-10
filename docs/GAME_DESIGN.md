# Game design — pass 3

**One snowboarder. One enormous mountain. One objective: reach the bottom as fast as possible.**

SNOW puts the player alone on the summit of the Massif. There are no runs, signs, lifts, opponents or helicopters — just a mountain that was never designed for snowboarding. Pushing off starts the clock; gravity does the rest. The clock only stops when the game is paused or the rider crosses the valley finish.

## Pillars

1. **The board is the joy.** Gravity-driven acceleration, a carve whose turning is limited by how much lateral acceleration an edge can hold, real inertia, a brake that skids, a tuck that cuts drag, a preloaded ollie, satisfying air and weighty, honest landings. Low speed is comfortable; high speed demands earlier, committed turns but stays controllable.
2. **The mountain is the challenge.** Difficulty comes from geography: gorges, cliff bands, a rock buttress, dense forest, broken ridges and cuts. Hazards announce themselves early (scoured, darker lips; exposed stone; the camera rises near drops). Safe lines are discoverable by looking; dangerous shortcuts look dangerous. Straight down is never safe.
3. **Risk buys speed.** Landed tricks charge the board; nitro is enormous forward thrust. Any fall erases ALL speed and ALL nitro. The tension between charging the board and keeping it is the core loop.
4. **Nothing between player and mountain.** No HUD, ever. Board glow, sound, camera, spray and rumble carry every piece of feedback.
5. **Sound is half the speed.** Snow hiss under the board, wind that rises into a roar, silence-of-friction in the air, a heavy landing, a nitro voice nobody forgets, a sputter you recognise blind.

## Rules

- **Start:** one stationary rider at the summit; look around freely; A pushes off and starts the clock. No countdown or intro.
- **Riding:** LS steers/carves; LT brake-skid; RT tuck; A hold/release ollie (longer crouch, higher pop; works up to ~0.14 s after a lip); RS camera only.
- **Tricks:** in the air LB/RB spin, D-pad flips, X grab. Rewards (stored nitro) come only on a clean landing and scale with air time, the size of the drop, completed 180s, completed flips, grab time, combinations of different elements and landing quality. Tiny flat hops pay nothing. Repeating the same trick, or chaining landings back-to-back, quickly devalues them (fatigue recovers with riding time). A 180 rides away switch.
- **Landing:** judged on spin/flip completion, board-vs-travel alignment and impact into the slope. Misaligned or overly violent landings are falls.
- **Nitro:** hold B to spend; release to keep the rest; the board dims as it burns. Pure forward thrust: no extra grip. Pressing with an empty board sputters.
- **Falls:** EVERY fall instantly zeroes velocity, speed and stored nitro and darkens the board. A visual tumble plays out (presentation only), then the rider gets up where the tumble safely stopped (never past a lip or hazard, never more than a few metres). Recovery time scales with severity — minor (~1.5 s), moderate (~2.5–3.5 s), severe (up to 7 s) — and counts toward the run.
- **Fatal:** large cliff drops and gorge falls (real apex-to-ground distance), and extreme direct impacts into trees/rocks/walls end the run. The moment plays out, then results appear. Fatal runs never enter the records.
- **Finish:** a timber gate with banners and pennant lines at the valley floor. Crossing it stops the clock; the rider skids to a stop; results show the time and its top-ten rank.
- **Restart:** View (or the menu) restores summit, stillness, zero nitro, zero speed, zero time and fresh state instantly.
- **Pause:** Menu, controller disconnect, or loss of window focus mid-run. Pause freezes physics, timer, camera, audio and particles (midair too).

## Camera

The right stick is a free look that is held relative to the direction of travel, so a look over the shoulder stays put while the rider carves. Unlimited horizontal orbit, -0.35..1.25 rad pitch, radial deadzone, analog rate with smoothed acceleration. After three seconds without input it settles gently back behind the rider; RS click recenters smoothly. At the summit, before push-off, any chosen view holds indefinitely. The chase framing pulls back and widens with speed (and a little more under nitro), aims ahead toward the snow the rider will reach, rises when the ground ahead falls away faster than the slope (lips, gorges), loosens in the air without following spins/flips, holds still and widens during a tumble, and returns to the fall line on get-up. Collisions retract instantly and re-extend slowly, so forests never make it pump. Landings nod the view through a damped spring; there is no random handheld shake.

## Presentation targets

Cinematic, realistic-leaning daylight: low raking sun, blue-white shadowed snow, atmospheric depth over kilometres, serrated surrounding ranges, snow-loaded conifers, faceted stone and cliff outcrops, wind ripples and glints on snow, spray, powder bursts and persistent board tracks. Speed should feel distinct at 20, 60 and 120 km/h through FOV, framing, spray, wind layers, whistle/flutter, passing-tree whooshes and rumble — never through screen-obscuring effects.

## Exclusions (locked)

No HUD, score, minimap, prompts, health/injury, wildlife, NPCs, opponents, helicopter, intro/countdown, background music, avalanche or advanced storms, progression systems. See DECISIONS.md.
