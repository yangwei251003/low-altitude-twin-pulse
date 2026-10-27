"""Single selected remaining Boss: actual MAIN/G/Ability/weapon/Damage/Store, <=65s."""
import argparse
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True, choices=["I3", "F3", "I4", "F4"])
    args = parser.parse_args()
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    label = "campaign-remaining-combat-" + args.region.lower() + "-" + stamp
    driver = dev.ROOT / "artifacts/v3" / (label + "-driver")
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    entry = "tests_v3/test_campaign_remaining_combat.gd"
    pending = [entry, "project.godot", "scripts_tools/v3/dev.py",
               "scripts_tools/v3/check_campaign_remaining_combat.py"]
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
                               "--qa-profile=qa_remaining_combat_" + args.region.lower() + "_" + stamp,
                               "--output=res://artifacts/v3/" + label,
                               "--region=" + args.region], "engine", 65)
    finally:
        after = hashes()
        (driver / "inputs.json").write_text(json.dumps({"before": before, "after": after,
            "unchanged": before == after, "process": process, "region": args.region,
            "scope": "Single region only; unique empty QA profile actual MAIN before rule fixture; original physical G/Ability/weapon/Damage/Store. QA PLAYER observation poses; thermal cargo disabled; no campaign/fresh-MAIN/LAN/graphics acceptance."}, indent=2), encoding="utf-8")
    report_path = dev.ROOT / "artifacts/v3" / label / "result.json"
    if not report_path.is_file():
        print(json.dumps({"output": label, "process": process, "inputs_unchanged": before == after,
                          "failure": "No completed bounded test report; inspect isolated engine evidence"}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(report_path.read_text(encoding="utf-8"))
    print(json.dumps({"output": label, "region": args.region, "checks": len(report["checks"]),
                      "failures": report["failures"], "engine_errors": report["engine_errors"],
                      "victory": report["victory"], "process": process,
                      "input_count": len(before), "inputs_unchanged": before == after}, ensure_ascii=False))
    if report["failures"] or report["engine_errors"] or not report["victory"] or before != after:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
