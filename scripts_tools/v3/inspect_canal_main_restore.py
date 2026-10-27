"""Copy one completed QA profile, compare old process cadence and real physics support."""
import ctypes, datetime, hashlib, json, os, pathlib, shutil, sys, uuid
sys.dont_write_bytecode = True
import dev
SOURCE = 'qa_canal_main_lifecycle_20261020_224952_95d86b'


def main():
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    label = 'canal-restore-inspect-' + stamp
    driver = dev.ROOT / 'artifacts/v3' / (label + '-driver')
    driver.mkdir(parents=True, exist_ok=False)
    dev.EVIDENCE = driver
    profiles = pathlib.Path(os.environ['APPDATA']) / 'LowAltitudeTwinPulseV3/profiles_v3'
    source = profiles / SOURCE
    profile = 'qa_canal_restore_inspect_' + stamp
    target = profiles / profile
    if not source.is_dir() or target.exists() or target.parent.resolve() != profiles.resolve():
        raise RuntimeError('Expected completed source QA profile or private destination is unavailable')

    def source_hashes():
        return {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in source.rglob('*') if path.is_file()}

    before = source_hashes()
    shutil.copytree(source, target)
    (target / 'qa_inspect_origin.json').write_text(json.dumps({'source_profile': SOURCE, 'source_hashes': before}), encoding='utf-8')
    process = None
    try:
        process = dev.execute(['--headless', '--script', 'res://tests_v3/candidates/canal_session/inspect_canal_main_restore.gd',
                               '--', '--qa-profile=' + profile, '--output=res://artifacts/v3/' + label], 'engine', 25)
    finally:
        after = source_hashes()
        (driver / 'source_integrity.json').write_text(json.dumps({'source_profile': SOURCE, 'copied_profile': profile,
            'before': before, 'after': after, 'source_unchanged': before == after, 'process': process}, indent=2), encoding='utf-8')
    if before != after:
        raise RuntimeError('The original source QA profile changed; inspection evidence is invalid')
    report = json.loads((dev.ROOT / 'artifacts/v3' / label / 'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output': label, 'checks': len(report['checks']), 'failures': report['failures'],
        'engine_errors': report['engine_errors'], 'process_histogram': report['process_frame_delta_histogram'],
        'physics_histogram': report['ordinary_physics_observer'].get('physics_histogram'),
        'max_consecutive_frames': report['ordinary_physics_observer'].get('max_consecutive_frames'), 'process': process}, ensure_ascii=False))
    if report['failures'] or report['engine_errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
