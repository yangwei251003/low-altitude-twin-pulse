"""Offline reproducible CC0 audio preparation. Sources are SHA256-pinned in sources.json.

Uses NumPy/SciPy and the already installed imageio-ffmpeg runtime. Never downloads
while building. Original recordings remain untouched in downloads/.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import subprocess
import sys
import wave
import zipfile
import numpy as np
from scipy import signal
import imageio_ffmpeg

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'assets/v2/audio'
RATE = 48000
MANIFEST = []
SOURCES = json.loads((HERE / 'sources.json').read_text(encoding='utf8'))


def decode(name, member=None, channels=1):
    source = HERE / 'downloads' / name
    data = source.read_bytes()
    if member:
        with zipfile.ZipFile(source) as archive:
            data = archive.read(member)
    command = [imageio_ffmpeg.get_ffmpeg_exe(), '-v', 'error', '-i', 'pipe:0',
               '-ac', str(channels), '-ar', str(RATE), '-f', 'f32le', 'pipe:1']
    decoded = subprocess.run(command, input=data, capture_output=True, check=True).stdout
    return np.frombuffer(decoded, dtype='<f4').astype(np.float64).reshape(-1, channels)


def rms(audio):
    return float(np.sqrt(np.mean(np.square(audio))))


def normal(audio, target_rms=-20, ceiling=-4):
    audio = audio - audio.mean(axis=0)
    gain = min(10 ** (target_rms / 20) / max(rms(audio), 1e-12),
               10 ** (ceiling / 20) / max(float(np.max(np.abs(audio))), 1e-12))
    return audio * gain


def cyclic(audio, seconds, crossfade=.25, offset=0):
    """Equal-gain overlap of source tail/head followed by a circular period.

    Output length is exact. The overlap begins at the source tail and ends at
    the source head continuation, so neither seam is an abrupt cut.
    """
    count = round(seconds * RATE)
    overlap = min(round(crossfade * RATE), count // 3)
    start = round(offset * RATE)
    indices = (np.arange(count + overlap) + start) % len(audio)
    source = audio[indices].copy()
    weight = (0.5 - 0.5 * np.cos(np.linspace(0, math.pi, overlap)))[:, None]
    source[:overlap] = source[count:count + overlap] * (1 - weight) + source[:overlap] * weight
    return source[:count]


def filtered(audio, low=0, high=6000):
    if low:
        sos = signal.butter(2, [low, high], 'bandpass', fs=RATE, output='sos')
    else:
        sos = signal.butter(2, high, fs=RATE, output='sos')
    return signal.sosfiltfilt(sos, audio, axis=0)


def periodic_noise(seconds, seed, high=2500, low=70):
    count = round(seconds * RATE)
    random = np.random.default_rng(seed).normal(size=(count, 1))
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    spectrum = np.fft.rfft(random[:, 0])
    # Smooth spectral band limits preserve circular continuity exactly.
    spectrum *= np.exp(-(frequencies / high) ** 4) * (1 - np.exp(-(frequencies / low) ** 4))
    return np.fft.irfft(spectrum, n=count)[:, None]


def measure(path, loop):
    with wave.open(str(path), 'rb') as stream:
        channels, rate, frames = stream.getnchannels(), stream.getframerate(), stream.getnframes()
        pcm = np.frombuffer(stream.readframes(frames), dtype='<i2').astype(np.int32).reshape(-1, channels)
    peak = int(np.max(np.abs(pcm)))
    step = int(np.max(np.abs(np.diff(pcm, axis=0))))
    boundary = int(np.max(np.abs(pcm[0] - pcm[-1])))
    return {'seconds': round(frames / rate, 6), 'sample_rate': rate, 'channels': channels,
            'pcm_bits': 16, 'frames': frames, 'peak_dbfs': round(20 * math.log10(max(1, peak) / 32768), 3),
            'rms_dbfs': round(20 * math.log10(max(rms(pcm / 32768), 1e-12)), 3),
            'clipped_samples': int(np.sum(np.abs(pcm) >= 32767)),
            'dc_mean': round(float(np.mean(pcm / 32768)), 8), 'loop': loop,
            'loop_begin_frame': 0 if loop else None, 'loop_end_frame': frames if loop else None,
            'boundary_step_lsb': boundary, 'max_adjacent_step_lsb': step,
            'boundary_to_max_step': round(boundary / max(1, step), 5),
            'file_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def write(name, audio, loop, purpose, source_ids, target=-20, ceiling=-4):
    audio = normal(audio, target, ceiling)
    if not loop:
        fade = min(round(.001 * RATE), len(audio) // 4)
        audio[:fade] *= np.linspace(0, 1, fade)[:, None]
        audio[-fade:] *= np.linspace(1, 0, fade)[:, None]
    pcm = np.round(audio * 32767).astype('<i2')
    path = OUT / (name + '.wav')
    with wave.open(str(path), 'wb') as stream:
        stream.setnchannels(audio.shape[1]); stream.setsampwidth(2); stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())
    item = dict(id=name, file=path.name, purpose=purpose, source_ids=source_ids, **measure(path, loop))
    MANIFEST.append(item)
    print(f"{name}: {item['seconds']} s, RMS {item['rms_dbfs']} dBFS, peak {item['peak_dbfs']} dBFS", flush=True)


def build():
    rotor = filtered(decode('drone_flying_sheyvan_hq.mp3'), 100, 6500)
    for name, rate, start in [('low', .82, 3), ('mid', 1, 7), ('high', 1.24, 11), ('unstable', .95, 15)]:
        stretched = signal.resample_poly(rotor, 100, round(rate * 100))
        clip = cyclic(stretched, 4, .3, start)
        if name == 'unstable':
            time = np.arange(len(clip)) / RATE
            clip *= (.75 + .25 * np.sin(math.tau * 4 * time))[:, None]
        write('rotor_' + name, clip, True, 'Real small-drone rotor; smooth telemetry pitch and thrust blend', ['rotor'], -17, -6)
    wind = periodic_noise(16, 920, 2500)
    time = np.arange(len(wind)) / RATE
    wind *= (.8 + .2 * np.cos(math.tau * time / 8))[:, None]
    write('wind', wind, True, 'Broadband airspeed air rush', ['original_synthesis'], -22, -6)

    birds = normal(filtered(decode('birds-isaiah658.ogg'), 250, 10000), -18, -3)
    birds = normal(np.tanh(birds * 4), -20, -5)
    waves = normal(decode('wave_01.flac'), -22, -6)
    for region in range(1, 5):
        for night in [False, True]:
            seconds = 24
            time = np.arange(round(seconds * RATE)) / RATE
            air = normal(periodic_noise(seconds, 9000 + region, 1400 if night else 2600), -25)
            birds_clip = cyclic(birds, seconds, 1.0, region * 2.5)
            water_clip = cyclic(waves, seconds, .6, .7 * region)
            if region == 1:
                mix = .8 * birds_clip * (0 if night else 1) + .25 * water_clip + .25 * air
                sources = ['birds', 'waves', 'original_synthesis']
            elif region == 2:
                mix = .40 * birds_clip * (0 if night else 1) + .15 * water_clip + .85 * air
                sources = ['birds', 'waves', 'original_synthesis']
            elif region == 3:
                swell = (.65 + .35 * np.sin(math.tau * time / 8) ** 2)[:, None]
                mix = water_clip * swell + .4 * air
                sources = ['waves', 'original_synthesis']
            else:
                mechanical = sum(np.sin(math.tau * hz * time) * gain for hz, gain in [(90, .012), (180, .004), (270, .002)])[:, None]
                mix = mechanical * (.5 if night else 1) + .45 * air + .06 * water_clip
                sources = ['waves', 'original_synthesis']
            if night and region in [1, 2]:
                # Subtle synthetic cricket layer; no claim of an animal field recording.
                chirp = np.sin(math.tau * 3400 * time) * np.maximum(0, np.sin(math.tau * 2 * time)) ** 12
                mix += .003 * chirp[:, None]
            write(f'ambient_R{region}_{"night" if night else "day"}', cyclic(mix, seconds, .6), True,
                  'Regional day/night field-recording soundscape with circular overlap', sources, -21.5, -5)

    music = decode('sherwood.ogg', channels=2)
    # Source has isolated decode overshoots: soft limit before peak normalisation.
    music = np.tanh(music * .7)
    music = cyclic(music, 32 * 60 / 110 * 2, .06)  # 16 bars, original 110 BPM.
    # Begin at a full musical phrase, not the source's near-silent first bars.
    music = np.roll(music, -round(8 * 60 / 110 * RATE), axis=0)
    write('music_calm', music, True, 'Sherwood, a full 16-bar stereo melodic music loop at 110 BPM', ['music'], -16, -3)
    # Combat adds only a phase-matched rhythmic stem; it never clashes harmonically.
    seconds = len(music) / RATE
    time = np.arange(len(music)) / RATE
    beat = (time * 110 / 60) % 1
    kick = np.sin(math.tau * (48 * time + 1.8 * np.exp(-beat * 16))) * np.exp(-beat * 18)
    noise = periodic_noise(seconds, 6001, 5200)[:, 0]
    hats = noise * np.exp(-((time * 110 / 60 * 2) % 1) * 40) * .35
    pulse = (kick + hats)[:, None]
    write('music_tension', np.repeat(pulse, 2, axis=1), True, 'Original 110 BPM percussion stem aligned to calm music', ['original_synthesis'], -20, -4)

    # High quality physical contact and tactile UI from the Kenney packs.
    event_sources = {
        'collision': ('kenney_impact-sounds.zip', ['impactMetal_medium_000', 'impactMetal_medium_002'], 'kenney_impacts'),
        'land': ('kenney_impact-sounds.zip', ['impactSoft_medium_000', 'impactSoft_medium_001'], 'kenney_impacts'),
        'scrape': ('kenney_impact-sounds.zip', ['impactPlate_light_002', 'impactPlate_light_004'], 'kenney_impacts'),
        'ui': ('kenney_ui-audio.zip', ['click1', 'click3'], 'kenney_ui'),
    }
    for key, (archive, members, source) in event_sources.items():
        for index, member in enumerate(members):
            write(f'{key}_{index + 1}', decode(archive, f'Audio/{member}.ogg'), False,
                  'Licensed tactile ' + key + ' feedback', [source], -18 if key == 'ui' else -17, -4)
    # Clear, restrained feedback tones remain original and fully editable.
    for name, duration, f0, f1 in [('shot', .16, 980, 240), ('warning', .48, 740, 740), ('tool', .42, 420, 860), ('shield', .65, 240, 600)]:
        for variant in range(2):
            time = np.arange(round(duration * RATE)) / RATE
            phase = math.tau * (1 + variant * .025) * (f0 * time + (f1-f0) * time*time / (2*duration))
            tone = np.sin(phase) + .16 * np.sin(phase * 2)
            env = np.minimum(1, time / .012) * np.exp(-time * (20 if name == 'shot' else 4))
            if name == 'warning': env *= .55 + .45 * np.cos(math.tau * 5 * time)
            write(f'{name}_{variant + 1}', (tone * env)[:, None], False, 'Original event variation', ['original_synthesis'], -17, -5)
    for name, notes, duration in [('reward', [523.25, 659.25, 783.99], 1.2), ('complete', [392, 523.25, 659.25, 783.99], 1.8), ('failure', [440, 392, 293.66], 1.25), ('disconnect', [783.99, 587.33], .8)]:
        time = np.arange(round(duration * RATE)) / RATE
        audio = np.zeros_like(time)
        for index, frequency in enumerate(notes):
            note_time = np.maximum(0, time - index * .12)
            audio += np.sin(math.tau * frequency * note_time) * np.exp(-5 * note_time) * np.minimum(1, note_time / .01)
        write(name, audio[:, None], False, 'Original musical status cue', ['original_synthesis'], -18, -4)
    time = np.arange(round(.7 * RATE)) / RATE
    spinup = signal.chirp(time, 180, .7, 720) * np.sin(math.pi * time / .7) ** 2
    write('takeoff', spinup[:, None], False, 'Short motor arming and launch accent', ['original_synthesis'], -21, -6)
    brake = periodic_noise(.32, 1111, 3500) * np.exp(-np.arange(round(.32 * RATE))[:, None] / RATE * 15)
    write('brake', brake, False, 'Short air-brake feedback accent', ['original_synthesis'], -23, -6)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for source in SOURCES:
        path = HERE / 'downloads' / source['source_file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != source['sha256']:
            raise ValueError('Source checksum mismatch: ' + source['source_file'])
    if args.verify_only:
        previous = json.loads((OUT / 'audio_manifest.json').read_text(encoding='utf8'))
        for entry in previous['assets']:
            measured = measure(OUT / entry['file'], entry['loop'])
            if measured['file_sha256'] != entry['file_sha256']:
                raise ValueError('Output checksum mismatch: ' + entry['file'])
            MANIFEST.append({**entry, **measured})
    else:
        build()
    failures = []
    for entry in MANIFEST:
        if entry['clipped_samples'] or entry['peak_dbfs'] > -2.9:
            failures.append(entry['id'] + ': insufficient headroom')
        if entry['loop'] and entry['boundary_to_max_step'] > 1.15:
            failures.append(entry['id'] + ': abnormal loop seam')
        if entry['rms_dbfs'] < -36:
            failures.append(entry['id'] + ': near-silent source')
    result = {'schema': 2, 'origin': 'cc0_recordings_and_original_synthesis', 'third_party_samples': True,
              'generator': 'asset_sources/v2/audio/build_audio_upgrade.py',
              'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'sources': SOURCES, 'sample_rate': RATE, 'pcm_bits': 16, 'assets': MANIFEST,
              'validation': {'passed': not failures, 'failures': failures, 'human_listening': 'NOT_TESTED',
                             'loop_method': 'Cosine overlap plus circular PCM seam checks; output captured separately in evidence/.',
                             'game_output_capture': 'See evidence/current_result.json'}}
    (OUT / 'audio_manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    print(json.dumps({'files': len(MANIFEST), 'max_peak_dbfs': max(x['peak_dbfs'] for x in MANIFEST),
                      'clipped_samples': sum(x['clipped_samples'] for x in MANIFEST), 'failures': failures}))
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
