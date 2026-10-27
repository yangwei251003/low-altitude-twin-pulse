from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
started=time.monotonic();path=OUT/'i2_canal_revetment_editable.blend';initial=sha(path)
print(json.dumps({'stage':'cleaned_uv_diagnosis','pid':os.getpid(),'input_sha256':initial}),flush=True)
bpy.ops.wm.open_mainfile(filepath=str(path));parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(parts)==8
proxy,rows,materials=make_proxy(parts)
try:uv=unique_uv(proxy)
except AssertionError as error:
    assert 'collapsed BakeUV triangle' in str(error)
    assert sha(path)==initial and sha(SOURCE)==SOURCE_SHA
    print(json.dumps({'status':'FAILURE_CAPTURED_NOT_FIXED','seconds':time.monotonic()-started}),flush=True)
else:
    write_json(OUT/'unexpected_uv_success.json',uv)
