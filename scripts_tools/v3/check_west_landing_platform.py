"""Actual MAIN visual and collision check; CPU2, isolated profile/private Job."""
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
    label = 'west-landing-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scripts/v3/world/twin_clinic_waterworks.gd',
             'scripts/v3/art/twin_west_landing_platform_art.gd',
             'scripts/v3/art/twin_terrain_visibility.gd', 'scripts/v3/twin_session.gd',
             'tests_v3/test_west_landing_platform.gd',
             'tests_v3/fixtures/west_landing_raised_water.json',
             'scripts_tools/v3/check_west_landing_platform.py', 'scripts_tools/v3/dev.py',
             'assets/v3/environment/west_landing_platform/west_landing_platform.glb',
             'scripts/v3/art/twin_clinic_lift_deck_art.gd',
             'scripts/v3/art/twin_west_service_room_art.gd',
             'assets/v3/environment/clinic_lift_deck/clinic_lift_deck.glb']

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--rendering-method', 'gl_compatibility', '--windowed',
            '--resolution', '1280x720', '--position', '-4000,-4000', '--script',
            'res://tests_v3/test_west_landing_platform.gd', '--',
            '--qa-profile=qa_west_landing_' + stamp,
            '--output=res://artifacts/v3/' + label], 'engine', 90)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after, 'process': process,
            'scope': 'declared relevant sources, historical water fixture and GLB; not full resource closure'},
            indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']),
        'failures': report['failures'], 'engine_errors': report['engine_errors'],
        'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
