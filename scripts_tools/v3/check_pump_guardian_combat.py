"""I2 actual MAIN two-phase Pump Guardian slice; 60s simulation/private 80s Job."""
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
    label = 'pump-guardian-combat-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scenes/v3/main.tscn', 'data/v3/regions.json', 'data/v3/campaign/bosses.json',
             'data/v3/campaign/i2_actions.json', 'data/v3/actions/opening_actions.json',
             'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
             'scripts/v3/gameplay/twin_campaign_session.gd', 'scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd',
             'scripts/v3/gameplay/environment/twin_water_network.gd', 'scripts/v3/gameplay/twin_ability_rules.gd',
             'scripts/v3/gameplay/twin_opening_story.gd', 'scripts/v3/twin_network.gd',
             'scripts/v3/gameplay/actions/twin_action_director.gd', 'scripts/v3/campaign/twin_campaign_encounter.gd',
             'scripts/v3/core/twin_world_store.gd', 'scripts/v3/world/twin_campaign_arena.gd',
             'tests_v3/test_pump_guardian_combat.gd', 'scripts_tools/v3/check_pump_guardian_combat.py',
             'scripts_tools/v3/dev.py']

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/test_pump_guardian_combat.gd', '--',
                               '--qa-profile=qa_pump_guardian_combat_' + stamp,
                               '--output=res://artifacts/v3/' + label], 'engine', 80)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after, 'process': process,
            'scope': 'Declared relevant inputs; unique QA profile; legal rule-prefix and actor-observation fixtures; no user profile or existing evidence writes.'
        }, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during the Pump Guardian combat check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']), 'failures': report['failures'],
                      'engine_errors': report['engine_errors'], 'victory': report['victory'],
                      'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or not report['victory']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
