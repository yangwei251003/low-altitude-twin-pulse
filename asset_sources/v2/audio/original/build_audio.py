"""Reproducible original V2 audio. Python standard library only; no downloads."""
from array import array
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "v2" / "audio"
RATE = 48000
TAU = math.tau
MANIFEST = []


def noise_table(seconds, density, seed):
    rng = random.Random(seed)
    values = [rng.uniform(-1, 1) for _ in range(round(seconds * density))]
    count = len(values)
    def sample(time):
        position = time / seconds * count
        index = int(position) % count
        fraction = position - math.floor(position)
        eased = fraction * fraction * (3 - 2 * fraction)
        return values[index] * (1 - eased) + values[(index + 1) % count] * eased
    return sample


def envelope(time, seconds, attack=.012, release=.06):
    if time <= 0 or time >= seconds:
        return 0.0
    fade_in = min(1.0, time / attack)
    fade_out = min(1.0, (seconds - time) / release)
    return math.sin(fade_in * math.pi / 2) ** 2 * math.sin(fade_out * math.pi / 2) ** 2


def smooth_periodic_pulse(time, center, width, seconds):
    distance = (time - center + seconds / 2) % seconds - seconds / 2
    return math.exp(-((distance / width) ** 2))


def measure(path, loop):
    with wave.open(str(path), "rb") as stream:
        pcm = array("h", stream.readframes(stream.getnframes()))
        if sys.byteorder != "little":
            pcm.byteswap()
        count, rate = len(pcm), stream.getframerate()
    peak = max(abs(value) for value in pcm)
    rms = math.sqrt(sum(value * value for value in pcm) / count) / 32768
    steps = [abs(pcm[index] - pcm[index - 1]) for index in range(1, count)]
    boundary = abs(pcm[0] - pcm[-1])
    return {
        "seconds": round(count / rate, 5), "sample_rate": rate, "channels": 1,
        "pcm_bits": 16, "frames": count, "peak_dbfs": round(20 * math.log10(max(1, peak) / 32768), 3),
        "rms_dbfs": round(20 * math.log10(max(rms, 1e-10)), 3),
        "clipped_samples": sum(abs(value) >= 32767 for value in pcm),
        "dc_mean": round(sum(pcm) / count / 32768, 8),
        "loop": loop, "loop_begin_frame": 0 if loop else None, "loop_end_frame": count if loop else None,
        "boundary_step_lsb": boundary, "boundary_step_dbfs": round(20 * math.log10(max(1, boundary) / 32768), 3),
        "max_adjacent_step_lsb": max(steps),
        "boundary_to_max_step": round(boundary / max(1, max(steps)), 5),
        "file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def write(name, seconds, sound, peak_db=-12, loop=False, purpose=""):
    count = round(seconds * RATE)
    samples = array("f", (sound(index / RATE) for index in range(count)))
    mean = sum(samples) / count if loop else 0
    peak = max(abs(value - mean) for value in samples)
    gain = 10 ** (peak_db / 20) / max(peak, 1e-8)
    pcm = array("h", (round((value - mean) * gain * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = OUT / (name + ".wav")
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())
    result = measure(path, loop)
    result.update({"id": name, "file": path.name, "purpose": purpose})
    MANIFEST.append(result)
    print(f"{name}: {result['seconds']}s, peak {result['peak_dbfs']} dBFS, boundary {result['boundary_step_lsb']} LSB", flush=True)


def rotor(kind, base, seed):
    seconds = 4
    air = noise_table(seconds, 600, seed)
    def sound(time):
        flutter = .80 + .12 * math.sin(TAU * 13 * time) + .08 * math.sin(TAU * 7.25 * time)
        if kind == "unstable":
            flutter *= .65 + .25 * math.sin(TAU * 3 * time) + .10 * math.sin(TAU * 5.5 * time)
        motor = math.sin(TAU * base * time) + .20 * math.sin(TAU * base * 2 * time) + .07 * math.sin(TAU * base * 3 * time)
        return motor * flutter * .8 + air(time) * .12
    write("rotor_" + kind, seconds, sound, -14, True, "Low/mid/high thrust blend or recovery instability layer; gain and pitch follow telemetry")


def environment(region, night):
    seconds = 16
    rng_seed = 901 + region * 19 + int(night)
    breeze = noise_table(seconds, [140, 210, 320, 110][region - 1], rng_seed)
    texture = noise_table(seconds, 42, rng_seed + 100)
    def sound(time):
        swell = .65 + .22 * math.sin(TAU * time / 8) + .13 * math.sin(TAU * time / 16)
        if region == 1:
            water = breeze(time) * (.28 if night else .45) * swell
            device = math.sin(TAU * (100 if night else 75) * time) * (.055 if night else .025)
            fountain = texture(time) * (.05 if night else .13)
            return water + device + fountain
        if region == 2:
            valley = breeze(time) * swell * .55 + texture(time) * .13
            pipeline = (.04 if night else .025) * (math.sin(TAU * 65 * time) + .25 * math.sin(TAU * 130 * time))
            return valley + pipeline
        if region == 3:
            surf = breeze(time) * (.25 + .65 * (.5 + .5 * math.sin(TAU * time / 8)) ** 2)
            turbine = .035 * math.sin(TAU * 62.5 * time) * (.7 + .3 * math.sin(TAU * time / 2))
            beacon = .018 * math.sin(TAU * 320 * time) * smooth_periodic_pulse(time, 10, .65, seconds) if night else 0
            return surf + turbine + beacon
        machinery = .07 * math.sin(TAU * 87.5 * time) + .023 * math.sin(TAU * 175 * time)
        clank = .025 * (math.sin(TAU * 280 * time) + .4 * math.sin(TAU * 420 * time)) * smooth_periodic_pulse(time, 6, .3, seconds)
        return breeze(time) * (.17 if night else .32) + machinery * (.55 if night else 1) + clank
    write(f"ambient_R{region}_{'night' if night else 'day'}", seconds, sound, -17, True, "Original regional ambience; no sampled wildlife, speech or external recording")


def music(tension=False):
    seconds = 32
    chords = [[130.81, 196, 293.66], [110, 164.81, 261.63], [87.31, 174.61, 261.63], [98, 196, 293.66]]
    if tension:
        chords = [[146.83, 220, 293.66], [130.81, 196, 293.66], [110, 164.81, 246.94], [130.81, 196, 261.63]]
    quantized = [[round(frequency * seconds) / seconds for frequency in chord] for chord in chords]
    def sound(time):
        value = 0
        for index, chord in enumerate(quantized):
            distance = abs((time - (index * 8 + 4) + 16) % 32 - 16)
            gain = 1 if distance <= 2 else .5 + .5 * math.cos(math.pi * (distance - 2) / 4) if distance < 6 else 0
            for note, frequency in enumerate(chord):
                value += gain * (.18 if note == 0 else .11) * (math.sin(TAU * frequency * time) + .07 * math.sin(TAU * frequency * 2 * time))
        pulse = (.72 + .28 * math.cos(TAU * time / 2)) if tension else (.95 + .05 * math.sin(TAU * time / 8))
        return value * pulse
    write("music_tension" if tension else "music_calm", seconds, sound, -18, True, "Original sustained harmonic phrase, phase-continuous 32-second loop; no sharp percussion")


def effects():
    designs = {
        "shot": (.19, 360, 125, .24, .035),
        "warning": (.55, 420, 520, .02, .15),
        "collision": (.50, 108, 54, .75, .015),
        "scrape": (.36, 190, 128, .85, .025),
        "land": (.28, 130, 75, .35, .015),
        "tool": (.48, 250, 340, .12, .05),
        "shield": (.62, 180, 330, .05, .12),
        "ui": (.12, 400, 440, .0, .012),
    }
    for ordinal, (name, (seconds, start, end, noise_gain, attack)) in enumerate(designs.items()):
        for variant in range(2):
            texture = noise_table(seconds, 850 if name == "scrape" else 480, 1550 + ordinal * 17 + variant)
            detune = 1 + variant * .027
            def sound(time, seconds=seconds, start=start, end=end, noise_gain=noise_gain, attack=attack, texture=texture, detune=detune, name=name):
                phase = TAU * detune * (start * time + .5 * (end - start) / seconds * time * time)
                tone = math.sin(phase) + .12 * math.sin(phase * 2)
                decay = math.exp(-time * (8 if name not in ("warning", "shield") else 2.0))
                return (tone * (1 - noise_gain) + texture(time) * noise_gain) * envelope(time, seconds, attack, .08) * decay
            write(f"{name}_{variant + 1}", seconds, sound, -9 if name in ("collision", "warning") else -12, False, "Original synthesized event variation")
    for name, notes, seconds in [
        ("reward", [261.63, 329.63, 392], 1.2),
        ("complete", [196, 261.63, 329.63, 392], 1.8),
        ("failure", [220, 196, 146.83], 1.25),
        ("disconnect", [392, 293.66], .8),
    ]:
        def sound(time, notes=notes, seconds=seconds):
            value = 0
            for index, frequency in enumerate(notes):
                note_time = time - index * .12
                if note_time > 0:
                    value += math.sin(TAU * frequency * note_time) * math.exp(-3 * note_time) * min(1, note_time / .018)
            return value * envelope(time, seconds, .015, .15)
        write(name, seconds, sound, -11, False, "Committed reward, completion, failure or disconnection cue")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.verify_only:
        previous = json.loads((OUT / "audio_manifest.json").read_text(encoding="utf-8"))
        for entry in previous["assets"]:
            measured = measure(OUT / entry["file"], entry["loop"])
            if measured["file_sha256"] != entry["file_sha256"]:
                raise ValueError("Audio checksum changed: " + entry["file"])
            MANIFEST.append({**entry, **measured})
    else:
        for kind, base, seed in [("low", 72, 401), ("mid", 96, 402), ("high", 124, 403), ("unstable", 84, 404)]:
            rotor(kind, base, seed)
        wind = noise_table(8, 260, 501)
        write("wind", 8, lambda time: wind(time) * (.78 + .22 * math.sin(TAU * time / 8)), -17, True, "Airspeed-dependent wind bed")
        for region in range(1, 5):
            for night in [False, True]:
                environment(region, night)
        music(False)
        music(True)
        effects()
    failures = []
    for asset in MANIFEST:
        if asset["clipped_samples"] or asset["peak_dbfs"] > -8.9:
            failures.append(asset["id"] + ": clipping/headroom")
        if asset["loop"] and asset["boundary_to_max_step"] > 1.15:
            failures.append(asset["id"] + ": abnormal loop boundary step")
    report = {
        "schema": 1, "origin": "original_project_synthesis", "third_party_samples": False,
        "generator": "asset_sources/v2/build_audio.py", "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "sample_rate": RATE, "pcm_bits": 16, "channels": 1,
        "assets": MANIFEST, "validation": {"passed": not failures, "failures": failures,
        "human_listening": "NOT_TESTED", "speaker_headphone_mix": "NOT_TESTED", "game_output_capture": "NOT_TESTED",
        "loop_method": "Periodic synthesis; boundary step compared with all in-file adjacent sample steps. This checks a numerical seam, not perceived looping or comfort."},
    }
    (OUT / "audio_manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"files": len(MANIFEST), "seconds_total": sum(item["seconds"] for item in MANIFEST),
        "max_peak_dbfs": max(item["peak_dbfs"] for item in MANIFEST), "clipped_samples": sum(item["clipped_samples"] for item in MANIFEST),
        "loop_max_boundary_ratio": max(item["boundary_to_max_step"] for item in MANIFEST if item["loop"]), "failures": failures}), flush=True)
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
