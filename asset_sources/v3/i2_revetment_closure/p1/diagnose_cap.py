"""One read-only north rear-plane diagnostic; no save, no render."""
from pathlib import Path
import sys,hashlib,json,os
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from plan import SOURCE,SOURCE_SHA,build_plan
from crop import crop_mesh
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_SHA
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
spec=next(s for s in build_plan()['pieces'] if s['id']=='NorthHead_01')
try:
    crop_mesh(bpy.data.objects['ConcreteBody_4m_Closed'].data,spec['clip_planes'],spec['id'])
except AssertionError as error:
    print(json.dumps({'diagnostic':'CAP_FAILURE_RECORDED','pid':os.getpid(),'error':str(error)}),flush=True)
else:
    raise AssertionError('expected current failure was not reproduced')
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_SHA
