"""Real cold A -> normal MAIN/Story Fact/SaveGate -> actual reheat and saved proof."""
import ctypes
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid

sys.dont_write_bytecode = True
import dev


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    label = "canal-preparation-story-" + stamp
    driver = dev.ROOT / "artifacts/v3" / (label + "-driver")
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    entry = "tests_v3/test_canal_preparation_story.gd"
    pending = [entry, "project.godot", "scripts_tools/v3/dev.py", "scripts_tools/v3/check_canal_preparation_story.py"]
    paths = set()
    while pending:
        path = pending.pop()
        if path in paths or not (dev.ROOT / path).is_file():
            continue
        paths.add(path)
        if Path(path).suffix in (".gd", ".tscn", ".tres"):
            pending.extend(re.findall(r'res://([^"\s\)]+)', (dev.ROOT / path).read_text(encoding="utf-8")))
    paths.update(path.relative_to(dev.ROOT).as_posix() for path in (dev.ROOT / "data/v3").rglob("*.json"))

    def hashes():
        return {path: hashlib.sha256((dev.ROOT / path).read_bytes()).hexdigest() for path in sorted(paths)}

    before = hashes()
    for path in paths:
        if Path(path).suffix not in (".gd", ".json", ".tscn", ".godot", ".py"):
            continue
        target = driver / "source" / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((dev.ROOT / path).read_bytes())
    process = None
    try:
        process = dev.execute(["--headless", "--script", "res://" + entry, "--",
                               "--qa-profile=qa_canal_preparation_story_" + stamp,
                               "--output=res://artifacts/v3/" + label], "engine", 45)
    finally:
        after = hashes()
        (driver / "inputs.json").write_text(json.dumps({"before": before, "after": after,
            "unchanged": before == after, "process": process,
            "scope": "Pinned actual A normal factory before fake prior Director rules; original Fact/SaveGate/proof tx, real heat Ability, actual hot save/independent original Store read. Thirty-second post-construction physics /45-second process; no whole Registry reload claim."}, indent=2), encoding="utf-8")
    result_path = dev.ROOT / "artifacts/v3" / label / "result.json"
    if not result_path.is_file():
        print(json.dumps({"output": label, "process": process, "inputs_unchanged": before == after,
                          "failure": "No completed test report; inspect isolated bounded engine log"}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(result_path.read_text(encoding="utf-8"))
    print(json.dumps({"output": label, "checks": len(report["checks"]), "failures": report["failures"],
                      "engine_errors": report["engine_errors"], "process": process,
                      "input_count": len(before), "inputs_unchanged": before == after}, ensure_ascii=False))
    if report["failures"] or report["engine_errors"] or before != after:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
