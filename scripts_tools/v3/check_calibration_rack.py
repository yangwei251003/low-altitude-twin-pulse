"""Serial import / real-work camera check. Invoke one stage per engine lease."""
from pathlib import Path
import argparse, ctypes, datetime, hashlib, json, shutil, sys, uuid
sys.dont_write_bytecode = True
import dev

ROOT = dev.ROOT
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['import', 'probe', 'checkpoint'])
    args = parser.parse_args()
    # Child processes inherit this private driver's two logical processors.
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    label = ('canal-player-checkpoint-' if args.stage=='checkpoint' else 'calibration-rack-'+args.stage+'-')+stamp
    out = ROOT/'artifacts/v3/art'/label
    out.mkdir(parents=True)
    dev.EVIDENCE = out
    paths = [ROOT/p for p in [
        'project.godot', 'scripts_tools/v3/check_calibration_rack.py',
        'scripts/v3/candidates/canal_playable/canal_playable.gd',
        'scripts/v3/candidates/canal_playable/canal_playable.tscn',
        'scripts/v3/candidates/canal_playable/probe_playable.gd',
        'scripts/v3/candidates/canal_playable/probe_workbench_playable.gd',
        'scripts/v3/candidates/canal_playable/canal_observation_visibility.gd',
        'scripts/v3/candidates/canal_calibration_art/calibration_rack_art.gd',
        'assets/v3/candidates/canal_calibration_rack/calibration_rack.glb',
        'scripts/v3/twin_test_world.gd', 'scripts/v2/flight_body.gd',
        'scripts/v2/pilot_input.gd', 'scripts/v2/flight_camera.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd']]
    for folder in ['canal_workbench','canal_transport_executor','canal_transport_physics',
                   'canal_service_loop','canal_cooling_station','canal_checkpoint']:
        paths += sorted((ROOT/'scripts/v3/candidates'/folder).glob('*.gd'))
    if args.stage=='checkpoint':
        paths += [ROOT/'scripts/v3/candidates/canal_playable/probe_checkpoint_playable.gd',ROOT/'scripts/v3/core/twin_world_store.gd']
    before = {p.relative_to(ROOT).as_posix():sha(p) for p in paths}
    (out/'inputs.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    for path in paths:
        if path.suffix in {'.gd','.py','.godot','.tscn'}:
            saved = out/'input_snapshot'/path.relative_to(ROOT)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, saved)
            assert sha(saved)==before[path.relative_to(ROOT).as_posix()]
    command = ['--headless','--editor','--import','--quit'] if args.stage=='import' else [
        '--rendering-method','gl_compatibility','--windowed','--resolution','1280x720',
        '--position','-4000,-4000','--script',
        'res://scripts/v3/candidates/canal_playable/'+('probe_checkpoint_playable.gd' if args.stage=='checkpoint' else 'probe_workbench_playable.gd'),'--',
        '--capture-output='+str(out)]
    try:
        result = dev.execute(command,'engine',90 if args.stage=='import' else (270 if args.stage=='checkpoint' else 185))
    finally:
        after = {p.relative_to(ROOT).as_posix():sha(p) for p in paths}
        (out/'inputs_after.json').write_text(json.dumps({'unchanged':before==after,'files':after},indent=2),encoding='utf-8')
    print(json.dumps({'stage':args.stage,'output':str(out),'result':result,'inputs_unchanged':before==after},ensure_ascii=False))
    if before != after: raise RuntimeError('Review inputs changed during run')

if __name__=='__main__': main()
