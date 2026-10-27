"""Scheduled actual MAIN carried WAIT fresh restore, private Job / CPU2 / 60 s."""
import ctypes
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
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    folder = Path(__file__).parent / "evidence" / stamp
    folder.mkdir(parents=True, exist_ok=False)
    entry = "tests_v3/candidates/canal_session/test_canal_wait.gd"
    pending = [entry, "project.godot", "scripts_tools/v3/dev.py",
               Path(__file__).resolve().relative_to(ROOT).as_posix()]
    paths = set()
    while pending:
        path = pending.pop()
        if path in paths or not (ROOT / path).is_file():
            continue
        paths.add(path)
        if Path(path).suffix in (".gd", ".tscn", ".tres"):
            pending.extend(re.findall(r'res://([^"\s\)]+)', (ROOT / path).read_text(encoding="utf-8")))
    def hashes():
        return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted(paths)}
    before = hashes()
    for path in paths:
        if Path(path).suffix not in (".gd", ".json", ".godot", ".tscn", ".py"):
            continue
        target = folder / "source" / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / path).read_bytes())
    dev.EVIDENCE = folder
    process = None
    code = 0
    try:
        process = dev.execute(["--headless", "--script", "res://" + entry, "--",
                               "--qa-profile=qa_canal_session_" + stamp,
                               "--output=res://" + folder.relative_to(ROOT).as_posix()]+(["--wait-diagnose"] if "--diagnose" in sys.argv else []), "engine", 60)
    except SystemExit as error:
        code = int(error.code or 1)
    finally:
        after = hashes()
        (folder / "inputs.json").write_text(json.dumps({"before":before, "after":after,
            "unchanged":before == after, "process":process,
            "scope":"literal MAIN/test resource closure; large assets hash-only; isolated profile; no network"}, indent=2), encoding="utf-8")
    report_file = folder / "result.json"
    report = json.loads(report_file.read_text(encoding="utf-8")) if report_file.exists() else {"failures":["no test result"], "engine_errors":[]}
    print(json.dumps({"evidence":str(folder), "process":process, "checks":report.get("checks",0),
                      "failures":report["failures"], "engine_errors":report["engine_errors"],
                      "input_count":len(before), "inputs_unchanged":before == after}, ensure_ascii=False))
    if code or report["failures"] or report["engine_errors"] or before != after:
        raise SystemExit(code or 1)


if __name__ == "__main__":
    main()
