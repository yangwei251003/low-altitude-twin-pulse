"""F3 original MAIN mechanism/native-Ecology proof slice; 38s simulation/55s Job."""
import argparse, ctypes, datetime, hashlib, json, sys, uuid
sys.dont_write_bytecode = True
import dev


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region', choices=['F3'], default='F3', help='First bounded late-area mechanism slice; I4/F4 are not covered yet.')
    args = parser.parse_args()
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    label = 'campaign-late-main-' + args.region.lower() + '-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scenes/v3/main.tscn', 'data/v3/regions.json',
             'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
             'scripts/v3/gameplay/twin_campaign_session.gd', 'scripts/v3/gameplay/twin_opening_story.gd',
             'scripts/v3/gameplay/twin_ability_rules.gd', 'scripts/v3/core/twin_world_store.gd',
             'tests_v3/test_campaign_late_main.gd', 'scripts_tools/v3/check_campaign_late_main.py',
             'scripts_tools/v3/dev.py']
    for folder, pattern in [('scripts/v3/campaign', '*.gd'), ('scripts/v3/ecology', '*.gd'),
                            ('data/v3/campaign', '*.json'), ('data/v3/ecology', '*.json')]:
        names.extend(str(path.relative_to(dev.ROOT)).replace('\\', '/')
                     for path in (dev.ROOT / folder).rglob(pattern))
    names = sorted(set(names))

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/test_campaign_late_main.gd', '--',
                               '--region=' + args.region, '--qa-profile=qa_campaign_late_main_' + stamp,
                               '--output=res://artifacts/v3/' + label], 'engine', 55)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after, 'process': process,
            'scope': 'Declared relevant source inputs; fresh unique QA profile; explicit prior rules/current-region/actor observation fixtures; native source advance only, no user profile writes.'
        }, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during the late-area MAIN check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']), 'failures': report['failures'],
                      'engine_errors': report['engine_errors'], 'native_proof': report['native_proof'],
                      'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or not report['native_proof']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
