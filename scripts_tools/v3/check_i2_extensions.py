"""Actual MAIN extension/flight check; serial engine, isolated profile and job."""
from pathlib import Path
import ctypes, datetime, hashlib, json, shutil, sys, uuid
sys.dont_write_bytecode=True
import dev

def main():
    root=dev.ROOT
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetCurrentProcess.restype=ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(),3): raise ctypes.WinError(ctypes.get_last_error())
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    label='i2-production-'+stamp
    driver=root/'artifacts/v3'/(label+'-driver'); driver.mkdir(parents=True)
    dev.EVIDENCE=driver
    files=[root/p for p in ['project.godot','tests_v3/test_i2_production_extensions.gd','scripts_tools/v3/check_i2_extensions.py','scripts_tools/v3/dev.py','scripts/v3/candidates/canal_transport_physics/transport_pilot.gd','assets/v3/environment/inspection_pit/inspection_pit.glb','assets/v3/environment/i2_revetment_closure/revetment_closure.glb']]
    for folder,extensions in [('scripts/v3',{'.gd'}),('scripts/v2',{'.gd'}),('data/v3',{'.json'}),('scenes/v3',{'.tscn'})]:
        files.extend(p for p in (root/folder).rglob('*') if p.suffix in extensions and '/candidates/' not in p.as_posix())
    # MAIN loads this separate package-capture driver only with
    # --qa-capture-output, which this test never supplies. Its parallel edits
    # therefore do not describe a dependency of this input/flight run.
    files=sorted(set(files)-{root/'scripts/v3/qa/twin_packaged_capture.gd'})
    def snapshot(): return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    before=snapshot(); (driver/'inputs.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    # Preserve runtime bytes before execution, even if a later run changes them.
    for path in files:
        if path.suffix=='.glb': continue
        dest=driver/'input_snapshot'/path.relative_to(root); dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(path,dest)
    try:
        result=dev.execute(['--rendering-method','gl_compatibility','--windowed','--resolution','1280x720','--position','-4000,-4000','--script','res://tests_v3/test_i2_production_extensions.gd','--','--qa-profile=qa_i2_extensions_'+stamp,'--output=res://artifacts/v3/'+label],'engine',155)
    finally:
        after=snapshot(); (driver/'inputs_after.json').write_text(json.dumps({'unchanged':before==after,'files':after},indent=2),encoding='utf-8')
    print(json.dumps({'output':str(root/'artifacts/v3'/label),'result':result,'inputs_unchanged':before==after},ensure_ascii=False))
    if before!=after: raise RuntimeError('Inputs changed during MAIN check')

if __name__=='__main__': main()
