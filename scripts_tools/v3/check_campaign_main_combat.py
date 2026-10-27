"""One F2 actual MAIN combat vertical slice; explicit QA fixtures, private Job."""
import argparse, ctypes, datetime, hashlib, json, sys, uuid
sys.dont_write_bytecode = True
import dev


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region', choices=['F2'], default='F2', help='First bounded integration slice; other Bosses are not covered yet.')
    args = parser.parse_args()
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    label = 'campaign-main-combat-' + args.region.lower() + '-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scenes/v3/main.tscn', 'data/v3/regions.json',
             'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
             'scripts/v3/gameplay/twin_campaign_session.gd', 'scripts/v3/gameplay/twin_ability_rules.gd',
             'scripts/v3/core/twin_world_store.gd', 'scripts/v3/world/twin_campaign_arena.gd',
             'scripts/v2/flight_body.gd', 'scripts/v2/damage_model.gd',
             'tests_v3/test_campaign_main_combat.gd', 'scripts_tools/v3/check_campaign_main_combat.py',
             'scripts_tools/v3/dev.py']
    for folder, pattern in [('data/v3/campaign', '*.json'), ('scripts/v3/campaign', '*.gd'),
                            ('scripts/v3/gameplay/actions', '*.gd')]:
        names.extend(str(path.relative_to(dev.ROOT)).replace('\\', '/')
                     for path in (dev.ROOT / folder).rglob(pattern))
    names = sorted(set(names))

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/test_campaign_main_combat.gd', '--',
                               '--region=' + args.region, '--qa-profile=qa_campaign_main_combat_' + stamp,
                               '--output=res://artifacts/v3/' + label], 'engine', 110)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({
            'before': before, 'after': after, 'unchanged': before == after, 'process': process,
            'scope': 'Relevant declared inputs; unique QA profile; explicit rule prefix and actor observation fixtures, no user profile access.'
        }, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during the actual MAIN combat slice')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'region': args.region, 'checks': len(report['checks']),
                      'failures': report['failures'], 'engine_errors': report['engine_errors'],
                      'victory': report['victory'], 'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or not report['victory']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
