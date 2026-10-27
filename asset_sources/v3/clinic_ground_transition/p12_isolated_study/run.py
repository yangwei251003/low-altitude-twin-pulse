from pathlib import Path
import subprocess,time,json,datetime
HERE=Path(__file__).resolve().parent
tag=datetime.datetime.now().strftime('%Y%m%d_%H%M%S');start=time.time();limit=120
with (HERE/f'isolated-{tag}.stdout.log').open('wb') as out,(HERE/f'isolated-{tag}.stderr.log').open('wb') as err:
    p=subprocess.Popen(['C:/Program Files/Blender Foundation/Blender 5.2/blender.exe','--background','--threads','2','--python-exit-code','3','--python',str(HERE/'render_sample.py')],cwd=str(HERE),stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
    r={'pid':p.pid,'status':'RUNNING','threads':2,'timeout_seconds':limit,'diagnostic_only':True};path=HERE/f'isolated-{tag}.process.json';path.write_text(json.dumps(r,indent=2));print(json.dumps(r),flush=True)
    try:code=p.wait(timeout=limit)
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=err,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW,timeout=20);p.wait(timeout=20);code=124;r['timeout']=True
    r.update(status='EXITED',exit_code=code,elapsed_seconds=time.time()-start);path.write_text(json.dumps(r,indent=2));print(json.dumps(r),flush=True)
raise SystemExit(code)
