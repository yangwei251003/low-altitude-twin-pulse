"""Real production Session exit/save proposal and moving cargo; owned 40s Job."""
import ctypes
import datetime
import hashlib
import json
import sys
import uuid

sys.dont_write_bytecode = True
import dev


def main():
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    label = 'session-exit-save-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scenes/v3/main.tscn', 'data/v3/regions.json',
             'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
             'scripts/v3/twin_network.gd', 'scripts/v3/twin_interface.gd',
             'scripts/v2/flight_body.gd', 'scripts/v2/pilot_input.gd',
             'scripts/v3/core/twin_world_store.gd', 'scripts/v3/core/twin_canal_save_gate.gd',
             'scripts/v3/core/twin_consensus.gd', 'scripts/v3/gameplay/twin_opening_story.gd',
             'scripts/v3/gameplay/twin_thermal_cargo_session.gd',
             'scripts/v3/gameplay/twin_thermal_cargo_participant.gd',
             'scripts/v3/world/twin_region_catalog.gd', 'scripts/v3/world/twin_region_space.gd',
             'tests_v3/test_session_exit_save.gd', 'scripts_tools/v3/check_session_exit_save.py',
             'scripts_tools/v3/dev.py']
    for folder, pattern in [('scripts/v3/gameplay/canal', '*.gd'),
                            ('scripts/v3/campaign', '*.gd'), ('data/v3/campaign', '*.json'),
                            ('scripts/v3/gameplay/actions', '*.gd')]:
        names.extend(str(path.relative_to(dev.ROOT)).replace('\\', '/')
                     for path in (dev.ROOT / folder).rglob(pattern)
                     if not path.name.startswith('test_'))
    names = sorted(set(names))

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/test_session_exit_save.gd', '--',
                               '--qa-profile=qa_session_exit_save_' + stamp,
                               '--output=res://artifacts/v3/' + label], 'engine', 40)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({
            'before': before, 'after': after, 'unchanged': before == after, 'process': process,
            'scope': 'Declared actual production MAIN/canonical sources. One unique QA; final process exit counted by subclass only. Real Store fault/readback and ordinary physics SaveGate. 30s inner/40s private owned Job; no user profile or network access.'
        }, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during actual Session exit/save check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'complete': report['complete'],
                      'checks': len(report['checks']), 'failures': report['failures'],
                      'engine_errors': report['engine_errors'], 'process': process}, ensure_ascii=False))
    if not report['complete'] or report['failures'] or report['engine_errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
