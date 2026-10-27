"""One real MAIN yard visual check; private process tree and isolated profile."""
from pathlib import Path
import datetime, hashlib, json, sys, uuid
sys.dont_write_bytecode = True
import dev


def main():
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    label = 'i2-yard-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    names = ['project.godot', 'scripts/v3/twin_test_world.gd', 'scripts/v3/twin_session.gd',
             'scripts/v3/art/twin_i2_yard_partition.gd', 'scripts/v3/art/twin_i2_yard_connector_art.gd',
             'tests_v3/test_i2_yard_connector.gd', 'scripts_tools/v3/check_i2_yard.py',
             'scripts_tools/v3/dev.py', 'assets/v3/environment/yard_connector/yard_connector_field.glb']
    def hashes():
        return {name: hashlib.sha256((dev.ROOT / name).read_bytes()).hexdigest() for name in names}
    before = hashes()
    process = None
    try:
        process = dev.execute(['--rendering-method', 'gl_compatibility', '--windowed', '--resolution',
            '1280x720', '--position', '-4000,-4000', '--script', 'res://tests_v3/test_i2_yard_connector.gd',
            '--', '--qa-profile=qa_i2_yard_' + stamp, '--output=res://artifacts/v3/' + label], 'engine', 90)
    finally:
        after = hashes()
        (driver / 'inputs.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after, 'process': process, 'scope': 'declared changed sources and GLB; not full resource closure'}, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('Inputs changed during check')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']), 'failures': report['failures'],
        'engine_errors': report['engine_errors'], 'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
