"""Five development MAIN areas, one GPU view each, original Store readback."""
import argparse,ctypes,datetime,hashlib,json,os,shutil,sys,uuid
from pathlib import Path
sys.dont_write_bytecode=True
import dev

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--reload-profile',choices=['qa_campaign_worlds_20261020_213720_bd77fa'])
    args=parser.parse_args()
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetCurrentProcess.restype=ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(),3):raise ctypes.WinError(ctypes.get_last_error())
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    profile='qa_campaign_worlds_'+stamp
    label='campaign-worlds-'+stamp;driver=dev.ROOT/'artifacts/v3'/(label+'-driver')
    driver.mkdir(parents=True,exist_ok=False);dev.EVIDENCE=driver
    names=['project.godot','scenes/v3/main.tscn','data/v3/regions.json','data/v3/campaign/layouts.json',
        'data/v3/campaign/physical_bindings.json','data/v3/campaign/bosses.json','scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd','scripts/v3/campaign/twin_campaign_layout.gd',
        'scripts/v3/campaign/twin_campaign_mechanisms.gd','scripts/v3/world/twin_campaign_arena.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd','scripts/v3/core/twin_world_store.gd',
        'tests_v3/test_campaign_worlds.gd','scripts_tools/v3/check_campaign_worlds.py','scripts_tools/v3/dev.py']
    def hashes():return {name:hashlib.sha256((dev.ROOT/name).read_bytes()).hexdigest() for name in names}
    source_profile=None;source_before={};evidence=None
    def source_hashes():
        return {str(p.relative_to(source_profile)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_profile.rglob('*') if p.is_file()} if source_profile else {}
    if args.reload_profile:
        profiles=(Path(os.environ['APPDATA'])/'LowAltitudeTwinPulseV3/profiles_v3').resolve()
        source_profile=(profiles/args.reload_profile).resolve()
        target=(profiles/profile).resolve()
        assert source_profile.parent==profiles and source_profile.name==args.reload_profile and source_profile.is_dir()
        assert target.parent==profiles and not target.exists()
        source_before=source_hashes()
        shutil.copytree(source_profile,target)
        evidence=dev.ROOT/'artifacts/v3/campaign-worlds-20261020_213720_bd77fa/result.json'
        assert evidence.is_file()
        names.append(str(evidence.relative_to(dev.ROOT)))
    before=hashes();process=None
    try:
        options=['--headless'] if args.reload_profile else ['--rendering-method','gl_compatibility','--windowed','--resolution','1280x720','--position','-4000,-4000']
        command=options+['--script','res://tests_v3/test_campaign_worlds.gd','--','--qa-profile='+profile,'--output=res://artifacts/v3/'+label]
        if evidence:command.append('--reload-evidence=res://'+str(evidence.relative_to(dev.ROOT)).replace('\\','/'))
        process=dev.execute(command,'engine',40 if args.reload_profile else 95)
    finally:
        after=hashes();(driver/'inputs.json').write_text(json.dumps({'before':before,'after':after,'unchanged':before==after,
            'process':process,'read_only_source_profile':str(source_profile) if source_profile else None,
            'source_profile_before':source_before,'source_profile_after':source_hashes(),'source_profile_unchanged':source_before==source_hashes(),
            'scope':'declared sources/data only; catalog edits in test memory only; reload diagnosis uses a new QA copy'},indent=2),encoding='utf-8')
    if before!=after:raise RuntimeError('Inputs changed during campaign area construction check')
    if source_before!=source_hashes():raise RuntimeError('Read-only source QA profile changed during diagnostic')
    report=json.loads((dev.ROOT/'artifacts/v3'/label/'result.json').read_text(encoding='utf-8'))
    print(json.dumps({'output':label,'checks':len(report['checks']),'failures':report['failures'],
        'engine_errors':report['engine_errors'],'images':len(report['shots']),'process':process},ensure_ascii=False))
    if report['failures'] or report['engine_errors'] or len(report['shots'])!=(0 if args.reload_profile else 5):raise SystemExit(1)

if __name__=='__main__':main()
