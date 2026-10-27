"""Unpinned ordinary I2 MAIN: ten-second headless CPU scopes, not FPS evidence."""
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
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    label = "i2-cpu-" + stamp
    driver = dev.ROOT / "artifacts/v3" / (label + "-driver")
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    entry = "tests_v3/profile_i2_cpu.gd"
    pending = [entry, "project.godot", "scripts_tools/v3/dev.py", "scripts_tools/v3/profile_i2_cpu.py"]
    paths = set()
    while pending:
        path = pending.pop()
        if path in paths or not (dev.ROOT / path).is_file():
            continue
        paths.add(path)
        if Path(path).suffix in (".gd", ".tscn", ".tres"):
            pending.extend(re.findall(r'res://([^"\s\)]+)', (dev.ROOT / path).read_text(encoding="utf-8")))
    paths.update(path.relative_to(dev.ROOT).as_posix()
                 for path in (dev.ROOT / "data/v3").rglob("*.json"))

    def hashes():
        return {path: hashlib.sha256((dev.ROOT / path).read_bytes()).hexdigest()
                for path in sorted(paths)}

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
                               "--qa-profile=qa_cpu_i2_" + stamp,
                               "--output=res://artifacts/v3/" + label], "engine", 80)
    finally:
        after = hashes()
        (driver / "inputs.json").write_text(json.dumps({
            "before": before, "after": after, "unchanged": before == after, "process": process,
            "affinity_set_by_runner": False,
            "scope": "Source MAIN/default I1 and three ordinary frames before direct QA I2 load, ten real seconds after unchanged native Canal/facility readiness. Ready wait up to50s with bootstrap status every8s; no affinity or frame/tick-rate changes. Inclusive Root-owned QA CPU scopes; headless is not rendered FPS/GPU/performance acceptance. 70s inner/80s private owned Job."
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    result = dev.ROOT / "artifacts/v3" / label / "result.json"
    if not result.is_file():
        print(json.dumps({"output": label, "process": process,
                          "inputs_unchanged": before == after,
                          "failure": "No completed profile; inspect isolated engine log"}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(result.read_text(encoding="utf-8"))
    print("I2 CPU inclusive scopes: top 5 by total microseconds")
    for row in report.get("top5", []):
        print(f"{row['label']}: total={row['total_usec']}us count={row['count']} "
              f"max={row['max_usec']}us mean={row['mean_usec']:.1f}us")
    print(json.dumps({"output": label, "sample": report.get("sample"),
                      "sample_complete": report.get("sample_complete"),
                      "failures": report["failures"], "engine_errors": report["engine_errors"],
                      "process": process, "inputs": len(before), "inputs_unchanged": before == after,
                      "affinity_set_by_runner": False}, ensure_ascii=False))
    if report["failures"] or report["engine_errors"] or not report.get("sample_complete") or before != after:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
