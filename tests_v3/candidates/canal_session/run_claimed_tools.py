"""Serial Root-only engine entry: exact Story claimed tool synchronization probe."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts_tools/v3"))
import dev


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    source = "artifacts/v3/canal-story-20261020_231707_c3f674/result.json"
    source_sha = "dde4d072978edad1bd97b599f9c5aff5a55dc251e43829347edb61ef1f3c5bdc"
    if hashlib.sha256((ROOT / source).read_bytes()).hexdigest() != source_sha:
        raise RuntimeError("Original Story claimed evidence changed")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    label = "canal-claimed-tools-" + stamp
    driver = ROOT / "artifacts/v3" / (label + "-driver")
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    entry = "tests_v3/candidates/canal_session/probe_claimed_tools.gd"
    pending = [entry, source, "project.godot", "scripts_tools/v3/dev.py",
               "tests_v3/candidates/canal_session/run_claimed_tools.py"]
    paths = set()
    while pending:
        path = pending.pop()
        if path in paths or not (ROOT / path).is_file():
            continue
        paths.add(path)
        if Path(path).suffix in (".gd", ".tscn", ".tres"):
            pending.extend(re.findall(r'res://([^"\s\)]+)', (ROOT / path).read_text(encoding="utf-8")))
    paths.update(path.relative_to(ROOT).as_posix() for path in (ROOT / "data/v3").rglob("*.json"))

    def hashes():
        return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in sorted(paths)}

    before = hashes()
    for path in paths:
        target = driver / "source" / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / path).read_bytes())
    process = None
    try:
        process = dev.execute(["--headless", "--script", "res://" + entry, "--",
                               "--qa-profile=qa_canal_claimed_tools_" + stamp,
                               "--output=res://artifacts/v3/" + label], "engine", 25)
    finally:
        after = hashes()
        (driver / "inputs.json").write_text(json.dumps({"before": before, "after": after,
            "unchanged": before == after, "process": process, "source_sha256": source_sha,
            "scope": "Exact claimed real envelope; fresh original frozen subtree/actual empty I2; eight ordinary physical callbacks, three-second post-construction bound."}, indent=2), encoding="utf-8")
    report = json.loads((ROOT / "artifacts/v3" / label / "result.json").read_text(encoding="utf-8"))
    print(json.dumps({"output": label, "checks": len(report["checks"]), "failures": report["failures"],
                      "engine_errors": report["engine_errors"], "process": process,
                      "input_count": len(before), "inputs_unchanged": before == after}, ensure_ascii=False))
    if report["failures"] or report["engine_errors"] or before != after:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
