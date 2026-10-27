"""Serial GLB import and actual excavated-pit camera/flight check."""
from pathlib import Path
import argparse, ctypes, datetime, hashlib, json, sys, uuid
sys.dont_write_bytecode = True
import dev

ROOT = dev.ROOT

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['import', 'probe'])
    args = parser.parse_args()
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    label = 'inspection-pit-art-'+args.stage+'-'+stamp
    out = ROOT/'artifacts/v3'/label
    driver = ROOT/'artifacts/v3'/(label+'-driver')
    driver.mkdir(parents=True)
    dev.EVIDENCE = driver
    paths = [ROOT/'project.godot', Path(__file__).resolve(),
             ROOT/'scripts/v3/twin_test_world.gd',
             ROOT/'tests_v3/candidates/inspection_pit/probe_inspection_pit.gd',
             ROOT/'scripts/v3/candidates/canal_transport_physics/transport_pilot.gd',
             ROOT/'assets/v3/candidates/inspection_pit/inspection_pit.glb']
    for folder in ['scripts/v2','scripts/v3/art','scripts/v3/candidates/inspection_pit']:
        paths.extend(sorted((ROOT/folder).glob('*.gd')))
    def snapshot():
        return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    before = snapshot()
    (driver/'inputs.json').write_text(json.dumps(before, indent=2), encoding='utf-8')
    command = ['--headless','--editor','--import','--quit'] if args.stage=='import' else [
        '--rendering-method','gl_compatibility','--windowed','--resolution','1280x720',
        '--position','-4000,-4000','--script',
        'res://tests_v3/candidates/inspection_pit/probe_inspection_pit.gd','--',
        '--pit-output=res://artifacts/v3/'+label,'--with-art-and-flight']
    try:
        result = dev.execute(command, 'engine', 90 if args.stage=='import' else 195)
    finally:
        after = snapshot()
        (driver/'inputs_after.json').write_text(json.dumps({'unchanged':before==after,'files':after},indent=2),encoding='utf-8')
    print(json.dumps({'stage':args.stage,'output':str(out),'driver':str(driver),'result':result,'inputs_unchanged':before==after},ensure_ascii=False))
    if before!=after: raise RuntimeError('Review inputs changed during run')

if __name__=='__main__': main()
