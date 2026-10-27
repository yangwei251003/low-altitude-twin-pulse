"""Opt-in retained-space experiment; default only describes frozen inputs."""
from __future__ import annotations
import argparse
import ast
import ctypes
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import time
import uuid

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCRIPT = "res://tests_v3/candidates/canal_retained_site/test_retained_site.gd"
TOTAL_SECONDS = 270
INNER_SECONDS = 240
SEED = ROOT / "tests_v3/candidates/canal_player_service/evidence/ui_input_seed_paths.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect_inputs() -> dict[str, str]:
    seeds = json.loads(SEED.read_text(encoding="utf-8-sig"))
    seeds += ["project.godot", "scripts_tools/v3/dev.py", SEED.relative_to(ROOT).as_posix(),
              Path(__file__).relative_to(ROOT).as_posix(), SCRIPT.removeprefix("res://"),
              "scripts/v3/candidates/canal_retained_site/retained_site.gd",
              "scripts/v3/candidates/canal_retained_site/measured_playable.gd"]
    pending = list(seeds)
    found: dict[str, str] = {}
    while pending:
        relative = pending.pop()
        if relative in found:
            continue
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ROOT.resolve()) or not path.is_file():
            raise RuntimeError(f"Missing or out-of-project declared input: {relative}")
        found[relative] = sha(path)
        if path.suffix.lower() in {".gd", ".json", ".tscn", ".tres", ".gdshader", ".gdshaderinc"}:
            text = path.read_text(encoding="utf-8-sig")
            for child in re.findall(r'''["']res://([^"']+)["']''', text):
                candidate = ROOT / child
                # Runtime directory prefixes and dynamic resource patterns are
                # not files; the prior successful UI input inventory covers them.
                if candidate.is_file() and child not in found:
                    pending.append(child)
    return dict(sorted(found.items()))


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def cpu_two() -> tuple[object, int, int]:
    """Restrict this private Python launcher; created engine children inherit it."""
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.GetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.POINTER(ctypes.c_size_t)]
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    process = kernel.GetCurrentProcess()
    allowed, system = ctypes.c_size_t(), ctypes.c_size_t()
    if not kernel.GetProcessAffinityMask(process, ctypes.byref(allowed), ctypes.byref(system)):
        raise ctypes.WinError(ctypes.get_last_error())
    bits = [1 << i for i in range(allowed.value.bit_length()) if allowed.value & (1 << i)]
    selected = sum(bits[:2])
    if not selected or not kernel.SetProcessAffinityMask(process, selected):
        raise ctypes.WinError(ctypes.get_last_error())
    return kernel, allowed.value, selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Only after Root grants the exclusive 270-second engine slot")
    parser.add_argument("--skip-import", action="store_true", help="Root already imported these exact inputs")
    options = parser.parse_args()
    ast.parse(Path(__file__).read_text(encoding="utf-8"))
    before = collect_inputs()
    if not options.run:
        print(json.dumps({"prepared_only": True, "engine_started": False,
                          "outer_seconds": TOTAL_SECONDS, "inner_seconds": INNER_SECONDS,
                          "input_count": len(before), "inputs": before,
                          "scope": "headless retained candidate and minimal active second physics space; not MAIN travel/LAN/GPU performance"},
                         ensure_ascii=False, indent=2))
        return 0
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    output = HERE / "evidence" / stamp
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / "inputs_before.json", before)
    # Small source text is preserved; models/textures are referenced by SHA,
    # avoiding another copy of the entire original scene and asset pipeline.
    for relative in before:
        source = ROOT / relative
        if source.suffix.lower() not in {".gd", ".py", ".json", ".tscn", ".gdshader", ".gdshaderinc"}:
            continue
        target = output / "input_source" / (relative + ".txt")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
    spec = importlib.util.spec_from_file_location("canal_retained_guarded_dev", ROOT / "scripts_tools/v3/dev.py")
    dev = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dev)
    dev.EVIDENCE = output
    started = time.monotonic()
    affinity_kernel, old_affinity, selected_affinity = cpu_two()
    stages = []
    passed = False
    error = ""
    try:
        if not options.skip_import:
            stages.append(dev.execute_command([str(dev.GODOT), "--headless", "--path", str(ROOT),
                                               "--editor", "--import", "--quit"], "import", 20))
        remaining = TOTAL_SECONDS - (time.monotonic() - started)
        if remaining < INNER_SECONDS + 5:
            raise RuntimeError("Import left insufficient time for the complete bounded probe")
        stages.append(dev.execute_command([str(dev.GODOT), "--headless", "--path", str(ROOT),
                                           "--script", SCRIPT, "--", "--capture-output=" + output.as_posix()],
                                          "retained_site", remaining))
        report = json.loads((output / "result.json").read_text(encoding="utf-8"))
        transitions = report.get("transitions", [])
        if (not report.get("checks") or report.get("failures") != [] or report.get("engine_errors") != []
                or len(transitions) < 6 or not all(row.get("same_identity") is True for row in transitions)):
            raise RuntimeError("Retained experiment did not establish every required identity/physics check")
        passed = True
    except (SystemExit, OSError, RuntimeError, ValueError, KeyError) as failure:
        error = f"{type(failure).__name__}: {failure}"
    finally:
        affinity_kernel.SetProcessAffinityMask(affinity_kernel.GetCurrentProcess(), old_affinity)
        after = {relative: sha(ROOT / relative) for relative in before}
        changed = [relative for relative in before if before[relative] != after[relative]]
        write_json(output / "inputs_after.json", after)
        passed = passed and not changed
        summary = {"passed": passed, "error": error, "stages": stages, "changed_inputs": changed,
                   "inputs_unchanged": not changed, "input_count": len(before),
                   "elapsed_seconds": round(time.monotonic() - started, 3),
                   "outer_seconds": TOTAL_SECONDS, "inner_seconds": INNER_SECONDS,
                   "inherited_cpu_affinity_mask": selected_affinity,
                   "private_process_job": "existing dev.execute_command suspended-start owned tree guard",
                   "result": str(output / "result.json"),
                   "scope": "headless fresh retained candidate, real original work and carrying transitions; no MAIN/LAN/GPU/performance acceptance"}
        write_json(output / "summary.json", summary)
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
