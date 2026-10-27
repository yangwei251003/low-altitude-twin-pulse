"""Read actual GLB bytes without importing Godot or trusting builder statistics."""
from pathlib import Path
import json,struct,hashlib,math

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/v3/industrial_kit'; EVID=ROOT/'artifacts/v3/art/industrial_kit'
def identity():return [[float(i==j) for j in range(4)] for i in range(4)]
def mul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def transform(n):
    if 'matrix' in n:return [[n['matrix'][j*4+i] for j in range(4)] for i in range(4)]
    x,y,z,w=n.get('rotation',[0,0,0,1]);sx,sy,sz=n.get('scale',[1,1,1]);t=n.get('translation',[0,0,0])
    m=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),t[0]],
       [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),t[1]],
       [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),t[2]],[0,0,0,1]]
    for i in range(3):
        for j,s in enumerate((sx,sy,sz)):m[i][j]*=s
    return m
def inspect(name):
    path=OUT/(name+'.glb');raw=path.read_bytes();magic,version,length=struct.unpack_from('<III',raw,0)
    assert magic==0x46546c67 and version==2 and length==len(raw)
    jsonlen,kind=struct.unpack_from('<II',raw,12);g=json.loads(raw[20:20+jsonlen])
    nodes=g['nodes'];worlds={};parents={}
    def walk(idx,parent):
        worlds[idx]=mul(parent,transform(nodes[idx]))
        for child in nodes[idx].get('children',[]):parents[child]=idx;walk(child,worlds[idx])
    for idx in g['scenes'][g.get('scene',0)]['nodes']:walk(idx,identity())
    triangles=0;primitives=0;coords=[];materials=set();mesh_nodes=[];all_uv=True
    for idx,n in enumerate(nodes):
        if 'mesh' not in n:continue
        mesh_nodes.append(n['name'])
        for p in g['meshes'][n['mesh']]['primitives']:
            primitives+=1;materials.add(p.get('material'));all_uv &= 'TEXCOORD_0' in p['attributes']
            triangles+=g['accessors'][p['indices']]['count']//3
            acc=g['accessors'][p['attributes']['POSITION']];m=worlds[idx]
            for x in [acc['min'][0],acc['max'][0]]:
                for y in [acc['min'][1],acc['max'][1]]:
                    for z in [acc['min'][2],acc['max'][2]]:
                        v=[x,y,z,1];coords.append([sum(m[i][k]*v[k] for k in range(4)) for i in range(3)])
    lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)]
    entries={n.get('name',str(i)):{'translation':n.get('translation',[0,0,0]),'rotation':n.get('rotation',[0,0,0,1]),'scale':n.get('scale',[1,1,1]),'parent':nodes[parents[i]].get('name') if i in parents else None,'children':[nodes[c].get('name') for c in n.get('children',[])]} for i,n in enumerate(nodes)}
    expected=[[-6,0,-4],[6,4,4]] if name=='coastal_work_terrace' else [[-1,0,-.8],[1,2.8,.8]]
    checks={'triangles_under_20k':triangles<=20000,'materials_under_4':len(materials)<=4,'all_primitives_uv':all_uv,'bounds_match_nominal':all(abs(a-b)<.005 for a,b in zip(lo+hi,expected[0]+expected[1])),'no_cameras':'cameras' not in g,'no_lights':'KHR_lights_punctual' not in g.get('extensions',{})}
    if name=='power_relay_cabinet':
        for key in ['StatusLamp','Terminal_A','Terminal_B','Terminal_C','SwitchPivot','SwitchHandle']:
            checks[key+'_exists']=key in entries
        checks['switch_local_axes_identity']=entries['SwitchPivot']['rotation']==[0,0,0,1] and entries['SwitchPivot']['scale']==[1,1,1]
        checks['switch_child_is_handle']=entries['SwitchHandle']['parent']=='SwitchPivot'
        checks['switch_origin']=all(abs(a-b)<.0001 for a,b in zip(entries['SwitchPivot']['translation'],[.42,1.34,.715]))
        checks['switch_handle_zero_local']=all(abs(v)<.0001 for v in entries['SwitchHandle']['translation'])
    report={'asset':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'triangles':triangles,'materials':len(materials),'primitives':primitives,'meshes':len(g.get('meshes',[])),'embedded_images':len(g.get('images',[])),'world_bounds':{'min':lo,'max':hi},'nodes':entries,'checks':checks,'all_checks_pass':all(checks.values())}
    (EVID/(name+'_glb_inspection.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='nodes'},ensure_ascii=False))
    return report['all_checks_pass']
if __name__=='__main__':
    outcomes=[inspect(p.stem) for p in sorted(OUT.glob('*.glb'))]
    raise SystemExit(0 if outcomes and all(outcomes) else 1)
