"""Encode a complete recorded PilotInput route at its actual wall timestamps.

No game playback, frame interpolation, time compression or audio is invented.
The output is sampled visual evidence, never a performance measurement.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--ffprobe", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Use a fresh output path; an earlier recording is preserved.")
    report = json.loads(args.report.read_text(encoding="utf-8-sig"))
    assert report["completed"] and report["source_unchanged"], "Route/source not verified"
    assert report["cleanup"]["session_released"], "Session not released"
    evidence = report["render_evidence"]
    assert evidence["display_server"] != "headless" and not evidence["failures"]
    directory = Path(evidence["capture_directory"]).resolve()
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8-sig"))
    frames = evidence["frames"]
    assert frames and len(manifest["frames"]) == len(frames)
    # Godot's manifest and full-precision final report serialize the same doubles
    # with different decimal lengths. Require identical frame identity and times
    # within one nanosecond, without rewriting either original record.
    for recorded, listed in zip(frames, manifest["frames"]):
        assert recorded.keys() == listed.keys()
        for key in recorded:
            if key in ("simulation_seconds", "wall_seconds"):
                assert abs(float(recorded[key]) - float(listed[key])) < 1e-9
            else:
                assert recorded[key] == listed[key]
    inputs = directory / "inputs.jsonl"
    assert inputs.is_file() and inputs.stat().st_size > 0
    times = [float(frame["wall_seconds"]) for frame in frames]
    assert all(b > a for a, b in zip(times, times[1:])), "Non-monotonic capture"
    assert float(frames[0]["simulation_seconds"]) <= 1.5, "Recording missed route start"
    assert float(report["elapsed_wall_seconds"]) - times[-1] <= 1.5, "Recording missed route end"
    assert max((b - a for a, b in zip(times, times[1:])), default=0) <= 2.0, "Recording has a drawable-window gap"
    assert all(frame["size"] == frames[0]["size"] for frame in frames)
    concat = ["ffconcat version 1.0"]
    for index, frame in enumerate(frames):
        name = frame["file"]
        assert Path(name).name == name and "'" not in name and "\n" not in name
        path = directory / name
        assert path.is_file() and path.stat().st_size > 0, f"Missing frame: {name}"
        duration = times[index + 1] - times[index] if index + 1 < len(times) else .25
        # The image demuxer defaults to a 1/25 second time base. Use milliseconds
        # to preserve the recorder's wall-time precision (ffmpeg-formats concat
        # 'option' directive and image2 'framerate').
        concat += [f"file '{name}'", "option framerate 1000", f"duration {duration:.6f}"]
    concat += [f"file '{frames[-1]['file']}'", "option framerate 1000"]
    listing = directory / "route.ffconcat"
    listing.write_text("\n".join(concat) + "\n", encoding="utf-8")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Even padding is required for yuv420p; original pixels are not scaled.
    expected = times[-1] - times[0] + .25
    command = [str(args.ffmpeg), "-y", "-hide_banner", "-loglevel", "warning",
               "-f", "concat", "-safe", "0", "-i", str(listing),
               "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2,fps=24",
               "-c:v", "libx264", "-preset", "fast", "-crf", "22",
               "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", "-t", f"{expected:.6f}",
               "-metadata", "comment=Automatic PilotInput route; sampled at up to 4 Hz; wall-time playback; no audio; not performance or human evidence",
               str(args.output)]
    subprocess.run(command, check=True)
    probe = json.loads(subprocess.check_output([str(args.ffprobe), "-v", "error",
        "-show_entries", "format=duration,size:stream=width,height,codec_name,codec_type",
        "-of", "json", str(args.output)], text=True, encoding="utf-8"))
    assert abs(float(probe["format"]["duration"]) - expected) < .25
    receipt = {
        "job": report["job_id"], "completed": True, "source_unchanged": True,
        "report_sha256": hashlib.sha256(args.report.read_bytes()).hexdigest(),
        "manifest_sha256": hashlib.sha256((directory / "manifest.json").read_bytes()).hexdigest(),
        "input_trace_sha256": hashlib.sha256(inputs.read_bytes()).hexdigest(),
        "video_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "sampled_frames": len(frames), "first_capture_wall_s": times[0],
        "last_capture_wall_s": times[-1], "expected_video_duration_s": expected,
        "route_elapsed_wall_s": float(report["elapsed_wall_seconds"]),
        "route_end_after_last_capture_s": float(report["elapsed_wall_seconds"]) - times[-1],
        "capture_hz_max": 4, "container_fps": 24, "interpolated": False,
        "has_audio": False, "human_playthrough": False, "performance_evidence": False,
        "probe": probe,
        "scope": "Recorded route capture interval at real wall timestamps; duplicated frames preserve timing. Initial scene setup and the measured route_end_after_last_capture_s tail are not captured; the final sampled image is held for 250ms. Completion is established by the linked route report, not an invented ending frame."
    }
    args.output.with_suffix(".json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == "__main__":
    main()
