"""Two actual MAIN GPU views; isolated profile, private bounded Windows Job."""
import ctypes
import datetime
import hashlib
import json
import sys
import uuid
sys.dont_write_bytecode=True
import dev

def main():
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetCurrentProcess.restype=ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(),3):raise ctypes.WinError(ctypes.get_last_error())
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    label='ready-assets-'+stamp
    driver=dev.ROOT/'artifacts/v3'/(label+'-driver');driver.mkdir(parents=True,exist_ok=False)
    dev.EVIDENCE=driver
    names=['project.godot','scenes/v3/main.tscn','scripts/v3/twin_session.gd','scripts/v3/twin_test_world.gd',
        'scripts/v3/art/twin_f1_thermal_stone_art.gd','scripts/v3/art/twin_central_service_apron_art.gd',
        'assets/v3/environment/f1_thermal_stone/f1_thermal_stone.glb',
        'assets/v3/environment/central_service_apron/central_service_apron.glb',
        'assets/v3/environment/central_service_apron/central_service_partition.json',
        'tests_v3/test_ready_assets_main.gd','scripts_tools/v3/check_ready_assets_main.py','scripts_tools/v3/dev.py']
    def hashes():return {name:hashlib.sha256((dev.ROOT/name).read_bytes()).hexdigest() for name in names}
    before=hashes();process=None
    try:
        process=dev.execute(['--rendering-method','gl_compatibility','--windowed','--resolution','1280x720',
            '--position','-4000,-4000','--script','res://tests_v3/test_ready_assets_main.gd','--',
            '--qa-profile=qa_ready_assets_'+stamp,'--output=res://artifacts/v3/'+label],'engine',65)
    finally:
        after=hashes()
        (driver/'inputs.json').write_text(json.dumps({'before':before,'after':after,'unchanged':before==after,
            'process':process,'scope':'declared relevant source/GLB hashes; not a full resource closure'},indent=2),encoding='utf-8')
    if before!=after:raise RuntimeError('Inputs changed during asset MAIN check')
    report=json.loads((dev.ROOT/'artifacts/v3'/label/'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output':label,'checks':len(report['checks']),'failures':report['failures'],
        'engine_errors':report['engine_errors'],'images':len(report['shots']),'process':process},ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or len(report['shots'])!=2:raise SystemExit(1)

if __name__=='__main__':main()
