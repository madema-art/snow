# Audio design — pass 5

Sound is half of SNOW's sense of speed and danger. Every sound is ORIGINAL: `tools/synth_audio.py` (Python 3 + numpy, fixed seeds) synthesizes all 43 WAVs in `audio/` (44.1 kHz, 16-bit; stereo for wind/nitro). No recordings, samples or third-party assets; the soundtrack is supplied separately by the owner. Loops are built periodically (FFT-shaped noise, integer-cycle oscillators, wrapped grains) so they are seamless, and carry a RIFF `smpl` loop chunk that Godot's importer detects (verified: `loop_mode=1`). Regenerate with `python3 tools/synth_audio.py`, then let Godot re-import.

## Layers (scripts/snow_audio.gd)

| Layer | Asset | Drive |
|---|---|---|
| Packed scrape | snow_packed | speed^0.7 x packed fraction; pitch rises with speed |
| Powder hiss | snow_powder | speed^0.7 x powder (forest, hollows) |
| Icy chatter | snow_ice | speed x ice (exposed/steep/convex) — irregular edge skipping |
| Carve rip | carve | edge engagement x speed |
| Brake skid | skid | brake or sideways slip |
| Mountain air | wind_base (stereo) | soft, dark, slowly breathing bed (30–240 Hz); exposure and gentle gusts; forest shelter |
| Speed rush | wind_rush (stereo) | smooth dark air (rolled off above ~1.5 kHz), speed² — only builds at real speed |
| Clothing | cloth_flutter | soft jacket ripple, in the air and at very high speed only |
| Nitro core | nitro_loop (stereo) | while boosting; pitch climbs with boost time and speed |

Surface weights are the same `surface_at()` data the physics and terrain shader use, smoothed so transitions cross-fade. Contact layers follow the real ground contact: leaving the snow drops them to silence within ~40 ms (air rush and clothing take over); landing re-engages instantly with a 0.35 s spray boost. Loops start at random offsets and stop when silent.

## Events

| Event | Sound |
|---|---|
| Push / ollie | board scrape; tail-snap knock + spray, louder with preload |
| Landing | land_soft / land_hard: sub thump (pitch-dropping sine), board slap, snow crunch grains, binding rattle; sketchy adds a wobble scrape |
| Crash | crash_minor / moderate / severe by tier: thumps + decaying tumble impacts + board knocks + spray; tumble_0..2 on each bounce; getup brush |
| Fatal | huge low impact, debris and a long ground rumble. On a cliff fall the rider yells all the way down (yell_fall) and the impact sound waits for the ground |
| Pain (Voice bus) | grunt_hit_0..2 on the first hit (harder falls hurt more); grunt_roll_0..4 on each bounce and roll of the tumble (never the same twice running); groan_0..1 when the body comes to rest after a moderate or worse fall |
| Plume | plume loop: an airy, rushing sheet of snow while the deep-lean plume is thrown; the skid/chatter layer rises with over-lean as the audible warning before the edge washes out |
| Charge | glass-bell partials (inharmonic 1, 2.76, 5.40, 8.93): small single chime, big rising triad, full-board shimmer swell |
| Nitro ignite | deep activation impact → resonant comb build (110 Hz series) with glittering partials → the sustained core: detuned 55 Hz drones + "singing ice" comb resonance + crystalline partials + pressure-wave air. Deliberately not an engine or rocket |
| Nitro release / deplete | soft power-down breath; descending resonant glide with crackle ending in a low thunk |
| Empty | a mechanism trying to start: four failing chuffs (resonant thump, ratchet click, cough, whine) losing energy, then a dry rattle |
| Pass-by | positional whoosh at trunks/boulders flashing by at speed (pitch with speed) |
| Bough | needle brush and falling snow when riding through low canopies |

12 one-shot voices with idle-first stealing; 4 positional voices; loops auto-stop when silent.

## The rider's voice

The pain sounds are synthesised too, with a source-filter model in `tools/synth_audio.py` (`voice()`): a glottal pulse train with pitch glide, jitter, a rough sub-harmonic and strain, plus breath noise, through three vowel formant resonators (uh / oo / ah / eh / oh / ng). No recordings of anyone. One voice plays at a time (`SnowAudio.say`): urgent sounds interrupt, rolling grunts respect a short cooldown, pitch varies ±6%. Being synthetic and unheard so far, the voice is the sound most in need of the owner's ears: if it reads as robotic or comic, it can be retuned or replaced with recorded grunts without touching the game code.

## Mix

**Playtest rule (pass 4): the music leads; sound effects never cover it; wind is never hissy or whistling.** The pass-3 mix measured the effects bed 7 dB ABOVE the music at speed (−16 vs −23 LUFS) and its wind had resonant whistles and flutter; both were wrong. Now: the whistle layer is deleted, wind is two soft dark layers, every bed gain was cut, and the music was raised and level-matched. Measured through the real mixer at ~30 m/s (`tests/movie_mix.gd`): music ≈ −19.9 LUFS, effects bed ≈ −28.6 LUFS — the music sits ~9 dB above the bed.

Master: hard limiter (-0.8 dB ceiling) prevents clipping. SFX (−4 dB) gentle glue compressor (−12 dB, 2:1, no make-up gain). Board (low-pass 7.5 kHz takes the fizz off snow hiss), MountainWind (low-pass 5 kHz → 1.6 kHz in forest shelter), Impacts (reverb: wetter/larger in cliffs and enclosed gorges, damped in forest) and Nitro (via Impacts). Music → Master at −3 dB with per-song level matching to −16 LUFS (owner masters measure −14 to −20 LUFS), dipped only −2.5 dB for about a second under crashes. Everything else pauses with the tree.

## Soundtrack (scripts/music.gd)

Owner soundtrack in `res://assets/music/`, managed by `scripts/music.gd` (SnowMusic) on the `Music` bus: every launch opens with `Alpine Shift (Take 2) (Remix).mp3` (exact name; a random song if it is missing), then a shuffle bag of every other song, then full reshuffles of all songs (opener included), never the same song twice in a row, 2.5 s equal-power crossfades. The soundtrack leads the mix: songs are level-matched to −16 LUFS (LOUDNESS table in `scripts/music.gd`, refreshed with `tools/measure_music.sh`) and play at −3 dB on the Music bus (≈ −20 LUFS), while the wind and snow bed at speed sits near −29 LUFS; landings, crashes and nitro punch through. Any .mp3/.ogg dropped into the folder is discovered automatically (editor and exported builds). Explicit pauses pause it in place; crashes, finishes, results and restarts never interrupt or restart it. No titles or controls are ever shown. With no songs the game is silent of music and works normally. Agents never add, generate or alter songs.

Implementation: two AudioStreamPlayers alternate for crossfades; discovery merges `ResourceLoader.list_directory()` with `DirAccess` listings (stripping `.import`/`.remap`), so imported, not-yet-imported (decoded with `AudioStreamMP3/OggVorbis.load_from_file`) and exported files are all found; songs are forced non-looping; the bag is refreshed from disk at every cycle so new songs join without a restart. The node always processes so finish/fatal results keep playing; the pause menu calls `set_paused()` for explicit pauses (Menu, controller disconnect, focus loss). Verified through the real mixer with Movie Maker (`tests/movie_music.gd`): opener audible at launch, silence while paused, resume at the same position, seamless crossfade, no clipping.

## Haptics (scripts/haptics.gd)

Continuous light snow texture (stronger on ice/skids), landing pulses scaled by impact, crash tiers, fatal double hit, boost kick + sustained rumble, the empty-sputter pulse rhythm matching its sound. First connected pad; stopped on pause.

## Honesty

The cloud environment has no audio device; the mix was validated numerically (Movie Maker capture through the real buses: levels, peaks, spectra — see BUILD_STATUS.md), NOT by listening. A headphones/speakers listening session on the target PC is still required to judge character, balance and loudness.
