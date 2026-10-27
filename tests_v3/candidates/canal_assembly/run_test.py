"""Explicitly scheduled fresh real-I2 Assembly test; CPU2/private job/240s."""
import ctypes
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts_tools/v3'))
import dev


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--lifecycle', action='store_true', help='short actual no-close owner destruction only')
    mode.add_argument('--restore', action='store_true', help='actual completed safe-point reconstruction only')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    label = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    folder = Path(__file__).resolve().parent / 'evidence' / label
    folder.mkdir(parents=True, exist_ok=False)
    filename = 'test_canal_assembly_restore.gd' if args.restore else ('test_canal_assembly_lifecycle.gd' if args.lifecycle else 'test_canal_assembly.gd')
    entry = 'tests_v3/candidates/canal_assembly/' + filename
    timeout = 60 if args.lifecycle or args.restore else 240
    pending = [entry, 'project.godot', 'scripts_tools/v3/dev.py',
               Path(__file__).resolve().relative_to(ROOT).as_posix()]
    paths = set()
    while pending:
        path = pending.pop()
        if path in paths or not (ROOT / path).is_file():
            continue
        paths.add(path)
        if Path(path).suffix in ('.gd', '.tscn', '.tres'):
            text = (ROOT / path).read_text(encoding='utf-8')
            pending.extend(re.findall(r'res://([^"\s\)]+)', text))
    # Actual source/config resource closure; imported GLBs remain hash-only.
    def hashes():
        return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted(paths)}
    before = hashes()
    for path in paths:
        if Path(path).suffix not in ('.gd', '.json', '.godot', '.tscn', '.py'):
            continue
        target = folder / 'source' / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / path).read_bytes())
    dev.EVIDENCE = folder
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://' + entry,
                               '--', '--output=res://' + folder.relative_to(ROOT).as_posix()], 'engine', timeout)
    finally:
        after = hashes()
        (folder / 'inputs.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after, 'process': process,
            'scope': 'literal res resource closure from actual test; large assets hash-only; no inherited playable or repository'}, indent=2), encoding='utf-8')
    report = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'evidence': str(folder), 'process': process, 'checks': report['checks'],
                      'failures': report['failures'], 'engine_errors': report['engine_errors'],
                      'input_count': len(before), 'inputs_unchanged': before == after}, ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or before != after:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
