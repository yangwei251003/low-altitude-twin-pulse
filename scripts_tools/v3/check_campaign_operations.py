"""Seven real development-area operations; physical obstruction and Store reload."""
import ctypes,datetime,hashlib,json,sys,uuid
sys.dont_write_bytecode=True
import dev

def main():
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetCurrentProcess.restype=ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(),3):raise ctypes.WinError(ctypes.get_last_error())
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    label='campaign-operations-'+stamp;driver=dev.ROOT/'artifacts/v3'/(label+'-driver')
    driver.mkdir(parents=True,exist_ok=False);dev.EVIDENCE=driver
    names=['project.godot','scenes/v3/main.tscn','data/v3/regions.json','data/v3/campaign/layouts.json',
        'data/v3/campaign/physical_bindings.json','scripts/v3/twin_session.gd','scripts/v3/twin_test_world.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd','scripts/v3/campaign/twin_campaign_mechanisms.gd',
        'scripts/v3/world/twin_campaign_arena.gd','scripts/v3/core/twin_world_store.gd',
        'tests_v3/test_campaign_operations.gd','scripts_tools/v3/check_campaign_operations.py','scripts_tools/v3/dev.py']
    def hashes():return {name:hashlib.sha256((dev.ROOT/name).read_bytes()).hexdigest() for name in names}
    before=hashes();process=None
    try:
        process=dev.execute(['--headless','--script','res://tests_v3/test_campaign_operations.gd','--',
            '--qa-profile=qa_campaign_operations_'+stamp,'--output=res://artifacts/v3/'+label],'engine',110)
    finally:
        after=hashes();(driver/'inputs.json').write_text(json.dumps({'before':before,'after':after,'unchanged':before==after,
            'process':process,'scope':'declared relevant inputs; unique QA profile and QA-only in-memory catalog'},indent=2),encoding='utf-8')
    if before!=after:raise RuntimeError('Inputs changed during campaign operations check')
    report=json.loads((dev.ROOT/'artifacts/v3'/label/'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output':label,'checks':len(report['checks']),'failures':report['failures'],
        'engine_errors':report['engine_errors'],'operations':len(report['operations']),'reloads':len(report['reloads']),'process':process},ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or len(report['operations'])!=7 or len(report['reloads'])!=4:raise SystemExit(1)

if __name__=='__main__':main()
