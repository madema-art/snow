# Audio design — pass 2

scripts/snow_audio.gd owns original seeded PCM synthesis (seed 3129, 22,050 Hz mono signed 16-bit), generated once at startup. Six reusable event voices and four continuous layers avoid per-event node creation. There are no recordings, downloads, copyrighted music or silent placeholder actions.

| Layer / event | Current response |
|---|---|
| Snow / edge | Speed-dependent filtered hiss/pitch; sharper chatter scales with edge steering and skid braking; contact layers fade off snow or in recovery |
| Mountain wind | Speed roar plus low ambient exposure, seeded spatial gust rhythm; forest region softens gain and smoothly lowers low-pass cutoff from 6000 to 2600 Hz; open alpine/broken/final terrain returns to exposed sound |
| Push / ollie / air | Short scrape/transient and takeoff whoosh, contact layers drop away in air |
| Landing / crash / fatal | Weighted low impact plus noise crack; stronger rattling/tumbling transients for falls, lower fatal tone |
| Charge | Harmonic landing reward tone, level follows earned charge |
| Boost onset / loop | Deep rising acceleration hit into modulated speed-pitched low harmonic/noise loop; releasing preserves charge and fades loop |
| Depletion / empty request | Descending flutter tail or distinct pulsed mechanical sputter/cough |

SFX trims -5 dB. A MountainWind child bus routes through a low-pass effect into SFX. Music is an independent empty reserved bus; no background music. All players pause with the world. Local board presentation is unattenuated so free camera orbit never accidentally silences it. Event vibration remains on landings/falls/empty attempts. Cleanup stops/releases streams; headless accelerated tests allow 100 ms for mixer release.

No physical listening or haptic session is claimed. Synthesis is functional prototype sound; final quality needs listening, calibrated loudness, transient dynamics and approved original snow/gear recordings. Surface physics has one snow type, no real ice zone. Region wind filtering provides environmental variation without pretending to be advanced weather or storms. Preserve the modular state/event interface and empty Music channel when improving the mix.

