"""Build the small original V3 industrial music bed, or check the full cue bank.

No downloads, engine processes, microphone, or audio-device changes. Reuses the
project's already licensed CC0 audio; the new bed is deterministic synthesis.
"""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "data/v3/audio/cues.json"
DESTINATION = ROOT / "assets/v3/audio/industrial_pulse.wav"
RATE = 48_000
BPM = 110
BARS = 8


def build() -> None:
    # All oscillators repeat across the full bed; a quiet cosine seam mask keeps
    # the final-to-first sample step below one 16-bit sample without a hard cut.
    duration = BARS * 4 * 60 / BPM
    frames = round(duration * RATE)
    pcm = array.array("h")
    roots = [55.0, 65.406391, 43.653529, 48.999429]
    for i in range(frames):
        t = i / RATE
        beat = t * BPM / 60
        chord = min(3, int(beat // 8))
        root = roots[chord]
        within_chord = beat % 8 * 60 / BPM
        chord_seconds = 8 * 60 / BPM
        chord_edge = min(1.0, within_chord / .05,
                         (chord_seconds - within_chord) / .05)
        chord_fade = .5 - .5 * math.cos(math.pi * max(0, chord_edge))
        # Low, sparse pulse and a soft fifth. This is a usable background bed,
        # deliberately below the level of mechanism and combat information.
        local = beat % 1
        envelope = math.exp(-local * 6.5)
        bass = math.sin(math.tau * root * t) * envelope * 0.085
        pad = (math.sin(math.tau * root * 2 * t)
               + .36 * math.sin(math.tau * root * 3 * t)) * .024
        tap = math.sin(math.tau * 550 * t) * math.exp(-(beat * 2 % 1) * 55) * .012
        edge = min(1.0, i / 2400, (frames - 1 - i) / 2400)
        fade = .5 - .5 * math.cos(math.pi * max(0, edge))
        left = (bass + pad + tap) * fade * chord_fade
        right = (bass + pad * .94 + tap * .78) * fade * chord_fade
        pcm.extend((round(left * 32767), round(right * 32767)))
    if sys.byteorder != "little":
        pcm.byteswap()
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(DESTINATION), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def verify() -> dict:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    paths = set()
    for cue in catalog["events"].values():
        paths.update(cue["files"])
        assert cue["cooldown_ms"] >= 0
        assert 0 <= cue["priority"] <= 9
        assert cue["range_m"] > 0
        assert cue["bus"] in ("sfx", "ui")
    for loop in catalog["loops"].values():
        paths.add(loop["file"])
        assert loop["bus"] in ("music", "rotor", "ambient")
    old_manifest = json.loads((ROOT / "assets/v2/audio/audio_manifest.json").read_text(encoding="utf-8"))
    combat_manifest = json.loads((ROOT / "assets/audio/v22_combat/manifest.json").read_text(encoding="utf-8"))
    expected = {"res://assets/v2/audio/" + a["file"]: a["file_sha256"] for a in old_manifest["assets"]}
    expected.update({"res://assets/audio/v22_combat/" + a["file"]: a["sha256"] for a in combat_manifest["files"]})
    files = []
    for resource in sorted(paths):
        assert resource.startswith("res://"), resource
        path = ROOT / resource.removeprefix("res://")
        assert path.is_file(), resource
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if resource in expected:
            assert expected[resource] == digest, f"Changed licensed input: {resource}"
        with wave.open(str(path), "rb") as wav:
            assert wav.getframerate() == RATE, resource
            assert wav.getsampwidth() == 2, resource
            assert wav.getnchannels() in (1, 2), resource
            samples = array.array("h", wav.readframes(wav.getnframes()))
            if sys.byteorder != "little":
                samples.byteswap()
            peak = max(abs(x) for x in samples)
            assert 0 < peak < 32767, resource
            files.append({"file": resource, "sha256": digest,
                          "seconds": round(wav.getnframes() / RATE, 6),
                          "channels": wav.getnchannels(), "peak_pcm": peak})
    return {"schema": 1, "static_pcm_and_source_hashes": "passed",
            "events": len(catalog["events"]), "loops": len(catalog["loops"]),
            "files": files, "godot_runtime": "not_run_by_audio_agent",
            "human_listening": "not_performed"}


def write_sources(result: dict) -> None:
    original = json.loads((ROOT / "assets/v2/audio/audio_manifest.json").read_text(encoding="utf-8"))
    by_path = {"res://assets/v2/audio/" + a["file"]: a["source_ids"] for a in original["assets"]}
    provenance = []
    for item in result["files"]:
        resource = item["file"]
        sources = by_path.get(resource)
        if sources is None:
            sources = ["kenney_impacts", "original_synthesis"] if "/v22_combat/" in resource else ["original_synthesis_v3"]
        provenance.append({"file": resource, "sha256": item["sha256"], "source_ids": sources})
    doc = {"schema": 1, "provenance_basis": "Existing local source manifests and licenses; no new downloads",
           "sources": original["sources"] + [
               {"id": "original_synthesis", "author": "Low Altitude project", "title": "Editable project procedural feedback", "license": "Original project work", "editable_source": "asset_sources/v2/audio/build_audio_upgrade.py and scripts_tools/v22_combat_audio_build.py"},
               {"id": "original_synthesis_v3", "author": "Low Altitude project", "title": "Industrial Pulse", "license": "Original project work", "editable_source": "scripts/v3/audio/build_audio_assets.py", "bpm": BPM, "bars": BARS}],
           "files": provenance,
           "original_license_records": ["assets/v2/audio/source_credits.json", "assets/audio/v22_combat/CREDITS.txt", "assets/source_audio/v22_combat/Kenney-License.txt"]}
    (ROOT / "data/v3/audio/sources.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not args.verify_only:
        build()
    result = verify()
    if not args.verify_only:
        write_sources(result)
    if args.report:
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "files"}, ensure_ascii=False))
