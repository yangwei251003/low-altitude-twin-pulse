# V2 audio, October 2026 upgrade

37 release WAV files, 48 kHz / 16-bit PCM. Music is stereo; other sounds are mono.
Six independently credited CC0 sources are mixed with editable original synthesis.
The original source audio is preserved under `asset_sources/v2/audio/downloads/`.
`source_credits.json` and `audio_manifest.json` contain URLs, authors, licenses,
source/output SHA256 checksums and per-file PCM measurements.

| Use | Source | License |
| --- | --- | --- |
| Real small-drone rotor | Sheyvan, [Drone Flying](https://freesound.org/people/Sheyvan/sounds/470127/) | CC0 1.0 |
| Tactile buttons | Kenney, [UI Audio](https://kenney.nl/assets/ui-audio) | CC0 1.0 |
| Metal contacts and landing | Kenney, [Impact Sounds](https://kenney.nl/assets/impact-sounds) | CC0 1.0 |
| Bird ambience | isaiah658, [Ambient Bird Sounds](https://opengameart.org/content/ambient-bird-sounds) | CC0 1.0 |
| Coastal water | jasinski, edited by qubodup, [Beach Ocean Waves](https://opengameart.org/content/beach-ocean-waves) | CC0 1.0 |
| Melodic background music | Chris Murphy (zesona), [Sherwood](https://opengameart.org/content/sherwood) | CC0 1.0 |

The drone source is the author's publicly served HQ MP3 preview; the original WAV
requires Freesound login and was not fetched. No login, paid account, microphone,
system volume adjustment or device reconfiguration was used.

Build: `python asset_sources/v2/build_audio.py`

Verify source/output checksums, PCM headroom and seams:
`python asset_sources/v2/build_audio.py --verify-only`

Recover missing pinned source downloads:
`python asset_sources/v2/audio/fetch_audio_sources.py`

Build dependencies: NumPy, SciPy, imageio-ffmpeg (already available on the build
machine). Playing the finished game needs none of these and never uses a network.
`asset_sources/v2/audio/original/` preserves the prior synthesis source and manifest.

## Playback

`GameAudioV2` retains `set_mix`, `update_flight` and `play_event`. `preview_mix()`
plays a short confirmation at the current settings. No setting is forcibly unmuted.
Four rotor layers follow actual thrust. Air rush follows airspeed. Launch, landing
and brake feedback follows telemetry edges, avoiding repeated every-frame cues.
Eight 24-second ambience loops crossfade by region and day/night. The stereo music
loops for 16 bars at 110 BPM; danger adds a matching percussion stem. Music stays
audible in the hangar and pause menu. Master uses a -1 dB hard limiter.

Imported audio loading uses `ResourceLoader.exists`, which works with PCK resource
remaps rather than requiring the editor's `.import` text marker. The parent build
must import modified WAVs before exporting a release.

## Evidence

`test_result.json`: 45 focused logical checks. `evidence/current_result.json` and
`evidence/current_mix.wav`: actual Godot audio mix on the Windows WASAPI driver,
covering menu, hover, full thrust, night, pause, loop boundary and mute. Capture
uses a temporary upstream Master fader to measure the final mix accurately.
`evidence/baseline_result.json` preserves the previous quiet mix result.

This establishes non-silent engine output and PCM headroom. It does not establish
human listening quality or prove sound emerges from a physical speaker/headphone.
