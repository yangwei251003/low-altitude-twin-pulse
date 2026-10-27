"""Preserve the physical exchange checkpoint and its failed predecessors."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/v3/evidence/i2-physical-exchange"
LOG = ROOT / "artifacts/v3/i2-canal-exchange-centered-20261019.log"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def result(path, prefix):
    return next(json.loads(line[len(prefix):]) for line in
                path.read_text(encoding="utf-8").splitlines() if line.startswith(prefix))


def main():
    if OUT.exists():
        raise RuntimeError("Immutable checkpoint already exists")
    report = result(LOG, "V3_I2_CANAL_EXCHANGE_RESULT ")
    run = result(LOG, "DEV_RUN_RESULT ")
    assert report["passed"] and report["checks"] == 249 and not report["engine_errors"]
    assert len(report["receipts"]) == 10 and report["pending_action"]["kind"] == "work"
    assert run["passed"] and run["remaining_owned_processes"] == 0
    sources = {path.removeprefix("res://") for path in report["input_sha256"]}
    for path, expected in report["input_sha256"].items():
        assert sha(ROOT / path.removeprefix("res://")) == expected, path
    sources.update([
        "tests_v3/candidates/canal_transport_physics/test_i2_canal_exchange.gd",
        "tests_v3/candidates/canal_transport_physics/test_cargo_custody.gd",
        "tests_v3/candidates/canal_transport_physics/test_transport_pilot.gd",
        "docs/v3/planning/I2_CANAL_PHYSICAL_EXCHANGE.md",
        "docs/v3/planning/I2_CARGO_CUSTODY.md",
        "docs/v3/planning/I2_TRANSPORT_PHYSICS_CANDIDATE.md",
        "scripts_tools/v3/dev.py",
    ])
    logs = [LOG.name, "i2-canal-exchange-first-20261019.log",
            "i2-canal-exchange-adaptive-20261019.log",
            "cargo-custody-centering-20261019.log",
            "cargo-custody-damped-20261019_211645_29e546.log",
            "transport-pilot-adaptive-20261019.log"]
    snapshots = ["canal-exchange-speed-first-run", "canal-exchange-adaptive-before-centering",
                 "cargo-centering-gain-first-run"]
    pairs = [(ROOT / path, Path("source") / path) for path in sorted(sources)]
    pairs += [(ROOT / "artifacts/v3" / name, Path("logs") / name) for name in logs]
    for name in snapshots:
        base = ROOT / "artifacts/v3" / name
        assert base.is_dir()
        pairs += [(p, Path("predecessors") / name / p.relative_to(base))
                  for p in sorted(base.rglob("*")) if p.is_file()]
    assert all(source.is_file() for source, _ in pairs)
    OUT.mkdir(parents=True)
    rows = []
    for source, relative in pairs:
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        digest = sha(source)
        assert sha(target) == digest
        rows.append({"source": source.relative_to(ROOT).as_posix(),
                     "path": relative.as_posix(), "bytes": target.stat().st_size, "sha256": digest})
    manifest = {
        "scope": "Candidate physical exchange in actual I2 terrain, not MAIN, service, save, multiplayer, graphics, performance or human play acceptance",
        "passed": True, "checks": 249, "accepted_physical_receipts": 10,
        "pending_work_not_performed": report["pending_action"],
        "run": run,
        "cargo_inertia_limitation": report["cargo_velocity_sweeps_diagnostic_only"],
        "limitation_note": "54 diagnostic cargo-own-velocity predictions would block; only first detail retained. Actual run had no collisions, but this is not full load-inertia avoidance proof. Candidate still requires correction before integration.",
        "input_sha256": report["input_sha256"], "files": rows,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(rows), "bytes": sum(r["bytes"] for r in rows),
                      "manifest_sha256": sha(OUT / "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
