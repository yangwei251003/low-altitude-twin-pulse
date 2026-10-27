"""Read-only diagnosis of the first rejected source UV range."""
import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import prepare as p
import bpy
bpy.ops.wm.open_mainfile(filepath=str(p.SOURCE))
_,rows,_,_=p.gather()
bad=[];coords=[]
for r in rows:
    if r['material']!='IB_BlueSteel':continue
    uv=r['uvs']['PaintPanelUV'];coords.extend(uv)
    if any(v< -1e-6 or v>1.000001 for pair in uv for v in pair):
        bad.append({'object':r['object'],'piece':r['piece'],'uv':uv})
report={'source_sha256':p.sha(p.SOURCE),'source_unchanged':p.sha(p.SOURCE)==p.SOURCE_SHA,
        'coating_uv_min':[min(q[i] for q in coords) for i in range(2)],
        'coating_uv_max':[max(q[i] for q in coords) for i in range(2)],
        'out_of_unit_triangles':len(bad),'affected_parts':sorted(set(r['object'] for r in bad)),
        'examples':bad[:12]}
p.write(p.OUT/'run-20261019_162229_e306f2/source_uv_diagnosis.json',report)
print('UV_DIAGNOSIS '+str(report),flush=True)
