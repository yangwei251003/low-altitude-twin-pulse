"""Small actual MAIN Pump rig check: 20-second simulation bound, private Job."""
import ctypes, datetime, hashlib, json, sys, uuid
sys.dont_write_bytecode = True
import dev


def main():
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    label = 'pump-guardian-main-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scenes/v3/main.tscn', 'data/v3/regions.json',
             'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
             'scripts/v3/gameplay/twin_campaign_session.gd', 'scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd',
             'scripts/v3/gameplay/environment/twin_water_network.gd', 'scripts/v3/gameplay/twin_ability_rules.gd',
             'scripts/v3/gameplay/twin_opening_story.gd', 'scripts/v3/twin_network.gd',
             'scripts/v3/gameplay/twin_facility_registry.gd', 'scripts/v3/core/twin_world_store.gd',
             'scripts/v3/core/twin_canal_save_gate.gd', 'tests_v3/test_pump_guardian_main.gd',
             'scripts_tools/v3/check_pump_guardian_main.py', 'scripts_tools/v3/dev.py']

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/test_pump_guardian_main.gd', '--',
                               '--qa-profile=qa_pump_guardian_main_' + stamp,
                               '--output=res://artifacts/v3/' + label], 'engine', 40)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after, 'process': process,
            'scope': 'Relevant declared inputs; unique empty QA profile only; 20-second simulation/40-second process bound including MAIN construction and teardown.'
        }, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during Pump MAIN rig check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']), 'failures': report['failures'],
                      'engine_errors': report['engine_errors'], 'reloaded': report['reloaded'],
                      'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or not report['reloaded']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
