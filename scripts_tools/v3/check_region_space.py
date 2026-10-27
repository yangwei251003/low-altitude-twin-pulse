"""Bounded real-renderer region-ownership check; does not touch player saves."""
import ctypes
import datetime
import hashlib
import json
import sys
import uuid
from pathlib import Path

sys.dont_write_bytecode = True
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import dev


def main():
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    label = "region-space-" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    output = dev.ROOT / "artifacts/v3" / label
    driver = output.with_name(label + "-driver")
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    paths = ["scripts/v3/world/twin_region_space.gd", "tests_v3/test_region_space_presentation.gd",
             "scripts/v3/twin_test_world.gd", "scripts/v2/flight_body.gd", "scripts/v2/flight_camera.gd",
             "scripts_tools/v3/check_region_space.py", "scripts_tools/v3/dev.py", "project.godot"]
    def hashes():
        return {p: hashlib.sha256((dev.ROOT / p).read_bytes()).hexdigest() for p in paths}
    before = hashes()
    for path in paths:
        dest = driver / "inputs" / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes((dev.ROOT / path).read_bytes())
    try:
        result = dev.execute(["--rendering-method", "gl_compatibility", "--windowed",
                              "--resolution", "1280x720", "--position", "-4000,-4000",
                              "--script", "res://tests_v3/test_region_space_presentation.gd", "--",
                              "--output=res://artifacts/v3/" + label], "engine", 60)
    finally:
        after = hashes()
        (driver / "inputs.json").write_text(json.dumps({"before": before, "after": after,
            "unchanged": before == after, "scope": "eight declared runner/component sources; not full asset closure"}, indent=2), encoding="utf-8")
    report = json.loads((output / "result.json").read_text(encoding="utf-8"))
    print(json.dumps({"output": str(output), "process": result, "passed": report["passed"],
                      "checks": len(report["checks"]), "inputs_unchanged": before == after}, ensure_ascii=False))
    if not report["passed"] or before != after:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
