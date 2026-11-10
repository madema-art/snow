# Game design — Massif pass 2

SNOW is one rider attempting a dangerous, enormous mountain time trial. The current skilled-descent target is about five minutes; reaching the bottom should require route knowledge and active steering/braking. Beginners should take longer and experts should improve through faster risky lines and earned nitro. Never manufacture time through speed caps, delayed finish or altered clocks.

The actual course is 9.36 km long and 1.2 km wide with about 3.115 km net vertical change. Five blended geographical regions — Summit, Cliffs, Forest, Broken Mountain, Final Descent — form one world. Broad snow shoulders, deep transverse ravines, a buttress/chute, dense winding forest corridors, gullies, ridges, boulders and optional jump lines make geographical route selection necessary. Going straight encounters a physical gorge fall. There is no protected straight lane, invisible route wall or mandatory checkpoint. MOUNTAIN.md records locations and route tradeoffs.

The rider starts stationary; A push-off starts time, not camera motion. Gravity/carving/inertia, brake/skid, tuck, ollie and high-speed boost are preserved. Successful landed spins/flips/grabs and simple jumps create stored nitro, with harder maneuvers paying more. The snowboard alone changes dark→orange→bright; no capacity UI. Boost adds strong forward acceleration without extra steering, lasts variable bursts, has distinctive sounds and sputters when empty.

Every fall immediately wipes ALL nitro and velocity. Severity determines recovery delay/pose; time continues through nonfatal falls. Fatality comes from real large falls or extreme direct collisions, not coordinate thresholds. No injuries, health or score. Trunk and faceted rock colliders match visible solid geometry, and terrain/render topology is shared. Instant restart resets everything without confirmation.

Left stick always steers. Right stick ONLY controls the free camera, on snow and in air: full 360 yaw, broad pitch, analog deadzone/rate, smooth control, 3-second hold before gentle chase settling, explicit smooth RS-click recenter, speed lookahead and sphere collision. Bumpers handle aerial yaw, D-pad up/down handles flips; all non-reserved actions are remappable/persisted. Menu always pauses/resumes; fixed UI navigation remains independent of gameplay mappings.

Absolutely no HUD or popups/instructions while riding. Pause/results alone shows hundredth elapsed time, top ten completed runs, remaps and resume/restart/quit. Pause freezes simulation, camera, sound and time, including midair. A clear orange valley finish stops time and writes a course-specific qualifying record once. Old short-course records remain preserved separately.

Target 3840x2160 fullscreen, VSync, 60 render FPS cap and 60 Hz physics; no settings menu. Windows determines monitor refresh. Native indexed chunks, local MultiMeshes, simple geometry and atmospheric depth prioritize scale/readability. Procedural synthesized snow/edge/wind/impact/nitro audio reacts to state; forest shelters/filter wind and exposed regions gust. Separate empty Music bus. No helicopter, wildlife, NPCs, opponents, splash/countdown, music, injury, avalanche or advanced storms.

Actual validation and limits: BUILD_STATUS.md and QA.md. Bot route knowledge and synthetic controller events do not establish beginner/expert human completion distributions or physical Xbox feel. Low-poly art, pose animation, synthesized audio and optional jump fairness need further work; retain all locked design constraints during polish.


