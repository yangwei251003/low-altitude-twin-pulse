"""Run the existing core/audio checks using isolated Godot user data."""
from pathlib import Path
import argparse,os,subprocess,time,json,shutil,uuid,re
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'));args=p.parse_args()
 if not args.godot:raise SystemExit('Supply --godot with your Godot 4.7.2 standard executable.')
 version=subprocess.check_output([args.godot,'--version'],text=True).strip()
 if not version.startswith('4.7.2.'):raise SystemExit('This snapshot is pinned to Godot 4.7.2; received: '+version)
 work=ROOT/'.runtime/checks'/uuid.uuid4().hex;work.mkdir(parents=True)
 env=os.environ.copy()
 for key,name in [('APPDATA','roaming'),('LOCALAPPDATA','local'),('USERPROFILE','home'),('HOME','home'),('TEMP','temp'),('TMP','temp')]:
  d=work/name;d.mkdir(exist_ok=True);env[key]=str(d)
 env['PUBLIC_CHECK_ROOT']=str(work/'roaming')
 script=work/'check-user-dir.gd'
 script.write_text('extends SceneTree\nfunc _initialize() -> void:\n\tvar expected := OS.get_environment("PUBLIC_CHECK_ROOT").replace("\\\\", "/")\n\tvar actual := OS.get_user_data_dir().replace("\\\\", "/")\n\tquit(0 if actual.begins_with(expected + "/") else 2)\n',encoding='utf-8')
 jobs=[('isolation',['--script',str(script)]),('import',['--import']),('core',['--script','res://tests_v3/test_core.gd']),('audio',['--script','res://scripts/v3/audio/test_audio.gd','--','--audio-report='+str(work/'audio.json')])]
 results=[]
 for name,options in jobs:
  log=work/(name+'.log');engine=work/(name+'-engine.log')
  command=[args.godot,'--headless','--path',str(ROOT),'--log-file',str(engine),*options]
  with log.open('w',encoding='utf-8') as output:
   child=subprocess.Popen(command,cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT);start=time.monotonic()
   while child.poll() is None:
    if time.monotonic()-start>900 or log.stat().st_size>64*1024*1024:
     child.terminate();child.wait(timeout=15);raise RuntimeError('owned check stopped at time/log bound')
    time.sleep(.2)
  text=log.read_text(encoding='utf-8',errors='replace')
  if engine.exists():text+='\n'+engine.read_text(encoding='utf-8',errors='replace')
  errors=len(re.findall(r'ERROR:|SCRIPT ERROR|Parse Error',text))
  result={'name':name,'exit_code':child.returncode,'error_markers':errors};results.append(result)
  print(json.dumps(result),flush=True)
  if child.returncode or errors:raise SystemExit('Check failed; inspect '+str(log))
 (work/'summary.json').write_text(json.dumps({'engine':version,'jobs':results,'headless_scope':'logic/import only; no visual/human/device proof'},indent=2),encoding='utf-8')
 print('Checks passed with fresh isolated user data. Logs: '+str(work))
if __name__=='__main__':main()
