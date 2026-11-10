# Audio design — pass 3

Sound is half of SNOW's sense of speed and danger. Every sound is ORIGINAL: `tools/synth_audio.py` (Python 3 + numpy, fixed seeds) synthesizes all 32 WAVs in `audio/` (44.1 kHz, 16-bit; stereo for wind/nitro). No recordings, samples or third-party assets; the soundtrack is supplied separately by the owner. Loops are built periodically (FFT-shaped noise, integer-cycle oscillators, wrapped grains) so they are seamless, and carry a RIFF `smpl` loop chunk that Godot's importer detects (verified: `loop_mode=1`). Regenerate with `python3 tools/synth_audio.py`, then let Godot re-import.

## Layers (scripts/snow_audio.gd)

| Layer | Asset | Drive |
|---|---|---|
| Packed scrape | snow_packed | speed^0.7 x packed fraction; pitch rises with speed |
| Powder hiss | snow_powder | speed^0.7 x powder (forest, hollows) |
| Icy chatter | snow_ice | speed x ice (exposed/steep/convex) — irregular edge skipping |
| Carve rip | carve | edge engagement x speed |
| Brake skid | skid | brake or sideways slip |
| Mountain air | wind_base (stereo) | always on, exposure x gusts; forest shelter |
| Speed rush | wind_rush (stereo) | speed^1.4; pitch with speed |
| Whistle/flutter | wind_whistle (stereo) | high speed and air |
| Clothing | cloth_flutter | speed^1.6, stronger in air |
| Nitro core | nitro_loop (stereo) | while boosting; pitch climbs with boost time and speed |

Surface weights are the same `surface_at()` data the physics and terrain shader use, smoothed so transitions cross-fade. Contact layers follow the real ground contact: leaving the snow drops them to silence within ~40 ms (air rush and clothing take over); landing re-engages instantly with a 0.35 s spray boost. Loops start at random offsets and stop when silent.

## Events

| Event | Sound |
|---|---|
| Push / ollie | board scrape; tail-snap knock + spray, louder with preload |
| Landing | land_soft / land_hard: sub thump (pitch-dropping sine), board slap, snow crunch grains, binding rattle; sketchy adds a wobble scrape |
| Crash | crash_minor / moderate / severe by tier: thumps + decaying tumble impacts + board knocks + spray; tumble_0..2 on each bounce; getup brush |
| Fatal | huge low impact, debris and a long ground rumble |
| Charge | glass-bell partials (inharmonic 1, 2.76, 5.40, 8.93): small single chime, big rising triad, full-board shimmer swell |
| Nitro ignite | deep activation impact → resonant comb build (110 Hz series) with glittering partials → the sustained core: detuned 55 Hz drones + "singing ice" comb resonance + crystalline partials + pressure-wave air. Deliberately not an engine or rocket |
| Nitro release / deplete | soft power-down breath; descending resonant glide with crackle ending in a low thunk |
| Empty | a mechanism trying to start: four failing chuffs (resonant thump, ratchet click, cough, whine) losing energy, then a dry rattle |
| Pass-by | positional whoosh at trunks/boulders flashing by at speed (pitch with speed) |
| Bough | needle brush and falling snow when riding through low canopies |

12 one-shot voices with idle-first stealing; 4 positional voices; loops auto-stop when silent.

## Mix

Master: hard limiter (-0.8 dB ceiling) prevents clipping. SFX (+1 dB) glue compressor (-16 dB, 3:1). Board, MountainWind (low-pass 16 kHz → 2.3 kHz in forest shelter), Impacts (reverb: wetter/larger in cliffs and enclosed gorges, damped in forest) and Nitro (via Impacts). Music → Master (-4 dB): `scripts/music.gd` plays the owner's soundtrack from `res://assets/music/` (every .ogg/.mp3/.wav in filename order, playlist loops, continues through pause and restarts); with no files it stays silent. Agents never generate or alter music. Everything else pauses with the tree.

## Haptics (scripts/haptics.gd)

Continuous light snow texture (stronger on ice/skids), landing pulses scaled by impact, crash tiers, fatal double hit, boost kick + sustained rumble, the empty-sputter pulse rhythm matching its sound. First connected pad; stopped on pause.

## Honesty

The cloud environment has no audio device; the mix was validated numerically (Movie Maker capture through the real buses: levels, peaks, spectra — see BUILD_STATUS.md), NOT by listening. A headphones/speakers listening session on the target PC is still required to judge character, balance and loudness.
