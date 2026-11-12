# Game design — pass 6

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
- **Left stick:** steers; forward crouches into a tuck (less drag, more speed); back brakes into a skid. The triggers do the same and stay remappable.
- **Deep lean and plume:** leaning hard (about 75–85% stick) throws a rooster-tail plume of snow, mist and glitter out the side opposite the lean. Past ~82% the board also turns up to 20% tighter, but the lean keeps deepening: after roughly two seconds near full lock at speed the edge washes out and the rider goes down. Easing off, switching edges or braking brings the rider back up. No meter: the body laid over toward the snow, a rising chatter and controller shudder are the warning.
- **Camera distance:** View cycles close / medium / far and the choice is remembered.
- **Riding:** A pushes off again whenever the rider is nearly stopped (flat bench, facing uphill, leaning on a tree). LS steers/carves; LT brake-skid; RT tuck; A hold/release ollie (longer crouch, higher pop; works up to ~0.14 s after a lip); RS camera only.
- **Tricks:** in the air LB/RB spin, D-pad flips, X grab. Rewards (stored nitro) come only on a clean landing and scale with air time, the size of the drop, completed 180s, completed flips, grab time, combinations of different elements and landing quality. Tiny flat hops pay nothing. Repeating the same trick, or chaining landings back-to-back, quickly devalues them (fatigue recovers with riding time). A 180 rides away switch.
- **Landing:** judged on spin/flip completion, board-vs-travel alignment and impact into the slope. Misaligned or overly violent landings are falls.
- **Nitro:** hold B to spend; release to keep the rest; the board dims as it burns. Pure forward thrust: no extra grip. Pressing with an empty board sputters.
- **Falls:** EVERY fall instantly zeroes riding velocity, speed and stored nitro and darkens the board. The fall itself is momentum physics, exaggerated so it is felt: the body is thrown with about 60% of the speed it had (or back off the trunk/boulder it hit), cartwheels, bounces, ploughs a trail and slides to rest; faster crashes travel much farther (≈7 m from 10 m/s, ≈30 m from 30 m/s), steeper ground slides longer, and a tumble that carries over a drop of 18 m or more is fatal. Every impact throws snow along the body's momentum, jolts the camera and the controller, and hurts: a grunt on the first hit, shorter grunts as it rolls, a groan when it stops, a yell on a long fall. The rider gets up where the body came to rest (or the nearest safe spot). Recovery is at least the severity time — minor (~1.5 s), moderate (~2.5–3.5 s), severe (up to 7 s) — and never starts before the tumble has stopped; all of it counts toward the run.
- **Fatal:** large cliff drops and gorge falls (real apex-to-ground distance), and extreme direct impacts into trees/rocks/walls end the run. The moment plays out, then results appear. Fatal runs never enter the records.
- **Finish:** a timber gate with banners and pennant lines at the valley floor. Crossing it stops the clock; the rider skids to a stop; results show the time and its top-ten rank.
- **Restart:** hold Y for about a third of a second (or use the menu); it restores summit, stillness, zero nitro, zero speed, zero time and fresh state instantly.
- **Time of day:** Day or Night, chosen on one line of the pause menu. Changeable at the summit before push-off and again after a run ends or is restarted; locked while the clock is running (the line says so and cannot be changed). The world cross-fades in about a second and a half behind the menu, the soundtrack carries on untouched, the choice is remembered, and a fresh install is Day. Geometry, hazards, physics, routes and controls are identical; only the light changes. Each mode has its own top ten and the menu shows the list for the selected mode.
- **Pause:** Menu, controller disconnect, or loss of window focus mid-run. Pause freezes physics, timer, camera, audio and particles (midair too).

## Camera

The right stick is a free look that is held relative to the direction of travel, so a look over the shoulder stays put while the rider carves. Unlimited horizontal orbit, -0.35..1.25 rad pitch, radial deadzone, analog rate with smoothed acceleration. After three seconds without input it settles gently back behind the rider; RS click recenters smoothly. At the summit, before push-off, any chosen view holds indefinitely. The chase framing pulls back and widens with speed (and a little more under nitro), aims ahead toward the snow the rider will reach, rises when the ground ahead falls away faster than the slope (lips, gorges), loosens in the air without following spins/flips, holds still and widens during a tumble, and returns to the fall line on get-up. Collisions retract instantly and re-extend slowly, so forests never make it pump. Landings nod the view through a damped spring; there is no random handheld shake.

## Presentation targets

**Day.** Cinematic, realistic-leaning daylight: low raking sun, blue-white shadowed snow, atmospheric depth over kilometres, serrated surrounding ranges, snow-loaded conifers, faceted stone and cliff outcrops, wind ripples and glints on snow, spray, powder bursts and persistent board tracks.

**Night.** The same mountain on a clear night at altitude. A bright moon ahead and to the left of the fall line is the one real light, and its direction matches the disc in the sky, so shadows fall the right way. Above it: a dense field of stars in three sizes with a few warm and blue ones, the Milky Way with dust lanes arching over the valley, and aurora in slow layered curtains — green, cyan and turquoise first, violet above and a pale pink hem, never neon. Snow is silver-blue, a little glossier than by day, with two layers of crystal glints that are fixed to the snow (they sparkle as the view moves, they do not flicker in place) and a faint aurora wash on open slopes. Ridges and peaks read as moonlit faces against black shadow sides. Visibility comes from moonlight, sky light and the snow itself; there is no headlamp, spotlight or screen-space brightening around the rider. Hazards must stay readable at speed: trunks and rock are dark shapes on bright snow, and drop lips keep their scoured dark edge. The rider's clothes pick up a soft rim so the silhouette separates from the slope. The nitro board glow is the one warm thing in the scene and lights a wider pool of snow than by day.

**Both.** Speed should feel distinct at 20, 60 and 120 km/h through FOV, framing, spray, wind layers, passing-tree whooshes and rumble — never through screen-obscuring effects.

**Launch.** Starting the game shows a dark splash with the SNOW mark while the mountain is built, then the summit with the wordmark fading over it for a few seconds. It never blocks input: pushing off, pausing or simply waiting removes it. No intro, no countdown.

## Exclusions (locked)

No HUD, score, minimap, prompts, health/injury, wildlife, NPCs, opponents, helicopter, intro/countdown, generated music (the owner's soundtrack in `assets/music/` plays; no music UI), avalanche or advanced storms, progression systems. See DECISIONS.md.
