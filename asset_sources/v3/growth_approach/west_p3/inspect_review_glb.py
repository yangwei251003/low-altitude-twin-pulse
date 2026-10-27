"""Standard-library binary readback of this directory's basic-material review GLB.
Run with Python from any cwd; no Blender, GPU, import, or source asset mutation.
"""
from pathlib import Path
import struct,json,hashlib,math
BASE=Path(__file__).resolve().parent
P=BASE/'west_p3_review.glb';raw=P.read_bytes()
magic,version,total=struct.unpack_from('<4sII',raw)
assert magic==b'glTF' and version==2 and total==len(raw)
offset=12;doc=None;blob=None
while offset<len(raw):
    n,kind=struct.unpack_from('<II',raw,offset);offset+=8
    part=raw[offset:offset+n];offset+=n
    if kind==0x4e4f534a:doc=json.loads(part)
    if kind==0x004e4942:blob=part
def ident():return [[float(i==j) for j in range(4)] for i in range(4)]
def mul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def matrix(n):
    if 'matrix' in n:return [[n['matrix'][c*4+r] for c in range(4)] for r in range(4)]
    x,y,z,w=n.get('rotation',[0,0,0,1]);s=n.get('scale',[1,1,1]);t=n.get('translation',[0,0,0])
    m=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),t[0]],
       [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),t[1]],
       [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),t[2]], [0,0,0,1]]
    for i in range(3):
        for j in range(3):m[i][j]*=s[j]
    return m
def accessor(idx):
    a=doc['accessors'][idx];v=doc['bufferViews'][a['bufferView']]
    typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
    count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    size=struct.calcsize('<'+typ*count);stride=v.get('byteStride',size)
    start=v.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from('<'+typ*count,blob,start+i*stride) for i in range(a['count'])]
points=[];nodes=[];triangle_data=[];mesh_count=0;triangles=0;primitives=0
def walk(idx,parent):
    global mesh_count,triangles,primitives
    n=doc['nodes'][idx];m=mul(parent,matrix(n))
    nodes.append({'name':n.get('name',''),'origin':[m[i][3] for i in range(3)],'matrix':m,'mesh':n.get('mesh')})
    if 'mesh' in n:
        mesh_count+=1
        for p in doc['meshes'][n['mesh']]['primitives']:
            assert p.get('mode',4)==4
            primitives+=1
            vs=accessor(p['attributes']['POSITION'])
            indices=[int(a[0]) for a in accessor(p['indices'])] if 'indices' in p else list(range(len(vs)))
            triangles+=len(indices)//3
            actual=[[sum(m[i][j]*v[j] for j in range(3))+m[i][3] for i in range(3)] for v in vs]
            points.extend(actual)
            for k in range(0,len(indices),3):
                tri=[actual[indices[k+j]] for j in range(3)]
                triangle_data.append((tri,min(v[0] for v in tri),max(v[0] for v in tri),min(v[2] for v in tri),max(v[2] for v in tri)))
    for c in n.get('children',[]):walk(c,m)
for root in doc['scenes'][doc.get('scene',0)]['nodes']:walk(root,ident())
minimum=[min(p[i] for p in points) for i in range(3)];maximum=[max(p[i] for p in points) for i in range(3)]
report=json.loads((BASE/'geometry_report.json').read_text(encoding='utf8'))
anchors=report['anchors_godot_local'];checks=[]
def check(name,ok):checks.append({'name':name,'passed':bool(ok)})
check('only_six_expected_visible_meshes',mesh_count==6)
check('same_source_triangle_count',triangles==report['geometry']['triangles'])
check('only_four_basic_materials',len(doc.get('materials',[]))==4)
check('exact_source_bounds',max(abs(a-b) for a,b in zip(minimum+maximum,sum(report['local_bounds'],[])))<2e-5)
for name,pos in anchors.items():
    found=[n for n in nodes if n['name']==name]
    check('anchor_'+name,len(found)==1 and max(abs(found[0]['origin'][i]-pos[i]) for i in range(3))<2e-5)
check('root_identity',next(n for n in nodes if n['name']=='GrowthApproachWest')['matrix']==ident())
def down(x,z):
    answer=None
    for tri,x0,x1,z0,z1 in triangle_data:
        if x<x0-1e-7 or x>x1+1e-7 or z<z0-1e-7 or z>z1+1e-7:continue
        a,b,c=tri
        den=(b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2])
        if abs(den)<1e-10:continue
        u=((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/den
        v=((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/den
        if min(u,v,1-u-v)<-1e-6:continue
        y=u*a[1]+v*b[1]+(1-u-v)*c[1]
        if answer is None or y>answer:answer=y
    return answer
central=[{'x':p['x'],'z':p['z'],'expected':p['expected'],'actual':down(p['x'],p['z'])} for p in report['central_samples']]
check('actual_glb_central_205_carrying_samples',all(p['actual'] is not None and abs(p['actual']-p['expected'])<.0002 for p in central))
interfaces=[]
for item in report['checks']:
    if item['name'].startswith('west_measured_join_'):
        z=item['z'];z=z*.999999 if abs(z)>=1.5 else z
        interfaces.append({'label':item['name'],'x':.000001,'z':z,'expected':item['expected'],'actual':down(.000001,z)})
for label,x,y,w in [('formal_lip',3.5,5.25,1.5),('lower_nose',3.749999,5.2,1.49)]:
    for i in range(31):
        z=-w+.00001+(2*w-.00002)*i/30
        interfaces.append({'label':label,'x':x,'z':z,'expected':y,'actual':down(x,z)})
check('actual_glb_west5_lip31_nose31',all(p['actual'] is not None and abs(p['actual']-p['expected'])<.0002 for p in interfaces))
out={'glb_sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'source_blend_sha256':report['blend_sha256'],
     'status':'basic_material_source_review_only_not_game_acceptance','godot_coordinate_origin':[0,0,0],'world_placement':[-14.5,0,25],
     'bounds':[minimum,maximum],'mesh_count':mesh_count,'triangles':triangles,'draw_primitives':primitives,'material_names':[m.get('name') for m in doc['materials']],
     'nodes':nodes,'central_samples':central,'interface_samples':interfaces,'checks':checks,'failures':[c for c in checks if not c['passed']]}
(BASE/'review_glb_readback.json').write_text(json.dumps(out,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in out.items() if k not in ('nodes','checks','central_samples','interface_samples')},indent=2))
assert not out['failures']
