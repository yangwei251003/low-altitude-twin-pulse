"""Original-body first-action flight and real process restart, headless only."""
import ctypes,datetime,hashlib,json,sys,uuid
sys.dont_write_bytecode=True
import dev

def main():
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetCurrentProcess.restype=ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(),3):raise ctypes.WinError(ctypes.get_last_error())
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    label='normal-flight-'+stamp;profile='qa_normal_flight_'+stamp
    driver=dev.ROOT/'artifacts/v3'/(label+'-driver');driver.mkdir(parents=True,exist_ok=False);dev.EVIDENCE=driver
    names=['project.godot','scenes/v3/main.tscn','scripts/v3/twin_session.gd','scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v2/flight_body.gd','scripts/v2/pilot_input.gd','scripts/v3/core/twin_world_store.gd',
        'tests_v3/test_normal_flight_loop.gd','scripts_tools/v3/check_normal_flight_loop.py','scripts_tools/v3/dev.py']
    def hashes():return {p:hashlib.sha256((dev.ROOT/p).read_bytes()).hexdigest() for p in names}
    before=hashes();processes=[]
    try:
        for stage,timeout in [('flight',145),('reload',35)]:
            processes.append(dev.execute(['--headless','--script','res://tests_v3/test_normal_flight_loop.gd','--',
                '--qa-profile='+profile,'--output=res://artifacts/v3/'+label,'--stage='+stage],stage,timeout))
            report=json.loads((dev.ROOT/'artifacts/v3'/label/(stage+'.json')).read_text(encoding='utf-8'))
            if report['failures'] or report['engine_errors']:raise RuntimeError(stage+' loop reported failures')
    finally:
        after=hashes();(driver/'inputs.json').write_text(json.dumps({'before':before,'after':after,'unchanged':before==after,
            'processes':processes,'profile':profile,'scope':'declared relevant files only; no graphics or human input claim'},indent=2),encoding='utf-8')
    if before!=after:raise RuntimeError('Inputs changed during normal flight check')
    print(json.dumps({'output':label,'profile':profile,'processes':processes,'scope':'headless scripted original-body first-action loop and real process restart'},ensure_ascii=False))

if __name__=='__main__':main()
