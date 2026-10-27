"""One-core audit of the exact diagnostic mesh exported by Blender."""
from pathlib import Path
import sys,json,hashlib,time,numpy as np
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT))
from coplanar_checks import coplanar_overlaps
arrays=OUT/'upper_cut_mesh_arrays.npz';raw=np.load(arrays)
start=time.monotonic()
result=coplanar_overlaps(raw['vertices'],[tuple(int(i) for i in t) for t in raw['triangles']],limit=25)
result.update({'elapsed_seconds':time.monotonic()-start,'mesh_arrays_sha256':hashlib.sha256(arrays.read_bytes()).hexdigest(),
    'input_blend_sha256':hashlib.sha256((OUT/'upper_cut_before_cleanup.blend').read_bytes()).hexdigest(),
    'triangles':len(raw['triangles']),'all_pass':not result['overlaps'],'status':'coplanar area audit only, not artwork approval'})
(OUT/'upper_coplanar_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result),flush=True)
