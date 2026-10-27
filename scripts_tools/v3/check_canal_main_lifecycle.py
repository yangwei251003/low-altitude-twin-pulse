"""Actual MAIN Canal factory lifecycle; isolated QA Store, private 100-second Job."""
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
    label = 'canal-main-lifecycle-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scenes/v3/main.tscn', 'data/v3/regions.json',
             'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
             'scripts/v3/gameplay/twin_canal_session.gd', 'scripts/v3/core/twin_canal_save_gate.gd',
             'scripts/v3/core/twin_world_store.gd', 'tests_v3/test_canal_main_lifecycle.gd',
             'scripts_tools/v3/check_canal_main_lifecycle.py', 'scripts_tools/v3/dev.py']
    for folder in ['canal_assembly', 'canal_checkpoint', 'canal_transport_executor',
                   'canal_transport_physics', 'canal_service_loop', 'canal_cooling_station',
                   'canal_workbench']:
        names.extend(str(path.relative_to(dev.ROOT)).replace('\\', '/')
                     for path in (dev.ROOT / 'scripts/v3/candidates' / folder).rglob('*.gd'))
    names = sorted(set(names))

    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}

    before = hashes()
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/test_canal_main_lifecycle.gd',
                               '--', '--qa-profile=qa_canal_main_lifecycle_' + stamp,
                               '--output=res://artifacts/v3/' + label], 'engine', 100)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({
            'before': before, 'after': after, 'unchanged': before == after, 'process': process,
            'scope': 'Relevant declared inputs; unique blank QA profile only; ordinary Session factory; no user profile access.'
        }, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during the actual MAIN Canal lifecycle check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']), 'failures': report['failures'],
                      'engine_errors': report['engine_errors'], 'save_callbacks': report['save_callbacks'],
                      'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or len(report['save_callbacks']) != 1:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
