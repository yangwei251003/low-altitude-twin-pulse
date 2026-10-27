"""Actual Story atomic claim; pinned successful physical source is required."""
import argparse
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-result", required=True, help="Repository-relative successful service evidence result.json")
    parser.add_argument("--source-sha", required=True, help="Verified SHA256 supplied by the serial physical service run")
    args = parser.parse_args()
    source = Path(args.source_result)
    normalized = source.as_posix()
    if source.is_absolute() or ".." in source.parts or not normalized.startswith("tests_v3/candidates/canal_session/evidence/service_") or source.name != "result.json":
        raise ValueError("Only the explicitly pinned physical service evidence may be imported")
    payload = (dev.ROOT / source).read_bytes()
    if hashlib.sha256(payload).hexdigest() != args.source_sha:
        raise ValueError("Physical source hash mismatch")
    physical = json.loads(payload)
    if physical.get("failures") or physical.get("engine_errors") or not physical.get("snapshots", {}).get("phases", {}).get("claimed"):
        raise ValueError("Physical service source must have passed and retained actual claimed history")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    label = "canal-story-" + stamp
    driver = dev.ROOT / "artifacts/v3" / (label + "-driver")
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    entry = "tests_v3/test_canal_story_transaction.gd"
    pending = [entry, normalized, "project.godot", "scripts_tools/v3/dev.py", "scripts_tools/v3/check_canal_story_transaction.py"]
    paths = set()
    while pending:
        path = pending.pop()
        if path in paths or not (dev.ROOT / path).is_file():
            continue
        paths.add(path)
        if Path(path).suffix in (".gd", ".tscn", ".tres"):
            pending.extend(re.findall(r'res://([^"\s\)]+)', (dev.ROOT / path).read_text(encoding="utf-8")))
    # Campaign extensions are loaded from runtime data rather than all literal
    # preload paths. Snapshot the relevant real data instead of omitting it.
    paths.update(path.relative_to(dev.ROOT).as_posix() for path in (dev.ROOT / "data/v3").rglob("*.json"))

    def hashes():
        return {path: hashlib.sha256((dev.ROOT / path).read_bytes()).hexdigest() for path in sorted(paths)}

    before = hashes()
    (driver / "physical_source.json").write_bytes(payload)
    for path in paths:
        if path == normalized or Path(path).suffix not in (".gd", ".json", ".tscn", ".godot", ".py"):
            continue
        target = driver / "source" / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((dev.ROOT / path).read_bytes())
    process = None
    try:
        process = dev.execute(["--headless", "--script", "res://" + entry, "--",
                               "--qa-profile=qa_canal_story_" + stamp,
                               "--output=res://artifacts/v3/" + label,
                               "--source-result=res://" + normalized,
                               "--source-sha=" + args.source_sha], "engine", 45)
    finally:
        after = hashes()
        (driver / "inputs.json").write_text(json.dumps({"before": before, "after": after,
            "unchanged": before == after, "process": process,
            "source_result": normalized, "source_sha256": args.source_sha,
            "scope": "Pinned real idle normal factory restore BEFORE declared Director prefix; original MAIN/Story atomic claim and fresh owned Assembly, not whole-profile Registry validity; unique blank QA Store/no default user profile."}, indent=2), encoding="utf-8")
    report = json.loads((dev.ROOT / "artifacts/v3" / label / "result.json").read_text(encoding="utf-8"))
    print(json.dumps({"output": label, "checks": len(report["checks"]), "failures": report["failures"],
                      "engine_errors": report["engine_errors"], "process": process,
                      "input_count": len(before), "inputs_unchanged": before == after}, ensure_ascii=False))
    if report["failures"] or report["engine_errors"] or before != after:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
