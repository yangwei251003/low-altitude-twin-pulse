"""Read-only reopening audit for the editable T03-A .blend main-form study."""
import bpy
import hashlib
import json
from pathlib import Path

project=Path(__file__).resolve().parents[3]
source=Path(bpy.data.filepath)
revision=source.stem.rsplit('_',1)[-1]
model=bpy.data.collections['T03A_EDITABLE_MAIN_FORM']
meshes=[o for o in model.objects if o.type=='MESH']
coords=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
anchors={}
checks={}
for name,expected in {'GroundOrigin':(0,0,0),'BridgeJoin':(4.5,4.5,0),
                      'WestBlend':(-4.3,.34,0)}.items():
    matches=[o for o in model.objects if o.name==name]
    checks['unique_'+name]=len(matches)==1
    if matches:
        p=matches[0].matrix_world.translation
        actual=[float(p.x),float(p.z),float(-p.y)]
        anchors[name]=actual
        checks['position_'+name]=all(abs(a-b)<1e-5 for a,b in zip(actual,expected))
degenerate=0
triangles=0
for obj in meshes:
    obj.data.calc_loop_triangles()
    triangles+=len(obj.data.loop_triangles)
    for tri in obj.data.loop_triangles:
        a,b,c=[obj.data.vertices[i].co for i in tri.vertices]
        if (b-a).cross(c-a).length<1e-9:degenerate+=1
checks['separate_editable_stone_parts']=sum(o.get('role','')=='individually editable structural stone' for o in meshes)>=3
checks['separate_editable_root_parts']=sum(o.get('role','')=='editable broad load-bearing root' for o in meshes)>=2
checks['separate_editable_earth_parts']=any('soil' in o.get('role','') or 'interface' in o.get('role','') for o in meshes)
checks['zero_degenerate_triangles']=degenerate==0
checks['no_runtime_export_collection']='Export_ONLY' not in bpy.data.collections
checks['bridge_reference_hidden_in_saved_study']=bpy.data.collections['READ_ONLY_ROOT_ARCH_ASSEMBLY'].hide_render
bridge=project/'assets/v3/root_arch/f1_root_arch.glb'
bridge_sha=hashlib.sha256(bridge.read_bytes()).hexdigest()
checks['bridge_sha_unchanged']=bridge_sha=='a14fd39f649ddd00cf2316126349b841376334879022e6c9256b6ed323ddd581'
report={'scope':'native Blender reopen/read-only editable source audit, not Godot or visual approval',
        'blender':bpy.app.version_string,'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'editable_meshes':len(meshes),'triangles':triangles,'degenerate_triangles':degenerate,
        'anchors_godot':anchors,'bridge_reference_sha256':bridge_sha,'checks':checks,
        'passed':sum(checks.values()),'failed':sum(not x for x in checks.values())}
path=project/'artifacts/v3/art/shore_root'/('source-reopen-'+revision+'.json')
path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('SHORE_SOURCE_REOPEN '+json.dumps(report,ensure_ascii=False))
assert report['failed']==0,checks
