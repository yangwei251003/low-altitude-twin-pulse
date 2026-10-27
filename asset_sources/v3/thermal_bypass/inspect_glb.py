"""Decode final raw GLB; no Godot import and no mutation of runtime files."""
from pathlib import Path
import struct,json,hashlib,math
import numpy as np
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent
path=ROOT/'assets/v3/thermal_bypass/thermal_bypass.glb'
data=path.read_bytes();magic,version,total=struct.unpack_from('<III',data,0);assert magic==0x46546c67 and version==2 and total==len(data)
off=12;doc=None;binary=None
while off<len(data):
    n,k=struct.unpack_from('<II',data,off);chunk=data[off+8:off+8+n];off+=8+n
    if k==0x4e4f534a:doc=json.loads(chunk)
    elif k==0x004e4942:binary=chunk
def accessor(i):
    a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1',5122:'<i2',5120:'i1'}[a['componentType']]
    b=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',np.dtype(dtype).itemsize*n)
    return np.ndarray((a['count'],n),dtype=dtype,buffer=binary,offset=b,strides=(stride,np.dtype(dtype).itemsize)).copy()
def local(node):
    if 'matrix'in node:return np.array(node['matrix']).reshape(4,4).T
    m=np.eye(4);x,y,z,w=node.get('rotation',[0,0,0,1]);m[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    m[:3,:3]=m[:3,:3]@np.diag(node.get('scale',[1,1,1]));m[:3,3]=node.get('translation',[0,0,0]);return m
world={};parents={}
def walk(i,p):
    world[i]=p@local(doc['nodes'][i])
    for c in doc['nodes'][i].get('children',[]):parents[c]=i;walk(c,world[i])
for i in doc['scenes'][doc.get('scene',0)]['nodes']:walk(i,np.eye(4))
checks=[]
def check(n,ok,detail=None):checks.append({'name':n,'passed':bool(ok),'detail':detail})
points=[];triangles=0;mesh_info=[];primitive_materials={}
for i,node in enumerate(doc['nodes']):
    if 'mesh'not in node:continue
    count=0;pts=[];matnames=[]
    for prim in doc['meshes'][node['mesh']]['primitives']:
        p=accessor(prim['attributes']['POSITION']);p=(world[i]@np.c_[p,np.ones(len(p))].T).T[:,:3];pts.extend(p);points.extend(p)
        ix=accessor(prim['indices']).reshape(-1);count+=len(ix)//3
        check(node['name']+'_triangles_nonzero',len(ix)>0 and len(ix)%3==0)
        check(node['name']+'_uv0', 'TEXCOORD_0'in prim['attributes'])
        check(node['name']+'_uv_only_one','TEXCOORD_1'not in prim['attributes'])
        check(node['name']+'_normal', 'NORMAL'in prim['attributes'])
        uv=accessor(prim['attributes']['TEXCOORD_0']);check(node['name']+'_uv_finite',np.isfinite(uv).all())
        matnames.append(doc['materials'][prim['material']]['name'])
    triangles+=count;pts=np.array(pts);primitive_materials[node['name']]=matnames
    mesh_info.append({'node':node['name'],'triangles':count,'bounds':{'min':pts.min(axis=0).tolist(),'max':pts.max(axis=0).tolist()},'materials':matnames})
points=np.array(points);bounds={'min':points.min(axis=0).tolist(),'max':points.max(axis=0).tolist()}
check('within_3x2x2',np.all(points.min(axis=0)>=np.array([-1.5,0,-1])-1e-5) and np.all(points.max(axis=0)<=np.array([1.5,2,1])+1e-5),bounds)
check('grounded',abs(bounds['min'][1])<1e-5)
check('triangles_le_12000',triangles<=12000,triangles)
check('six_materials',len(doc['materials'])==6)
check('six_meshes',len(doc['meshes'])==6,len(doc['meshes']))
names=[n.get('name') for n in doc['nodes']]
for n in ['ThermalBypass','FanRotor','FanBlades','StatusLens','HeatPipes','StaticHousing','StaticSteel','StaticSafety','InteractionCentre','BaseOrigin']:check('unique_'+n,names.count(n)==1)
pi=names.index('FanRotor');fi=names.index('FanBlades');ri=names.index('ThermalBypass')
check('fan_child',parents.get(fi)==pi)
check('fan_parent_root',parents.get(pi)==ri)
check('fan_identity_local_basis',np.allclose(local(doc['nodes'][pi])[:3,:3],np.eye(3),atol=1e-6))
check('root_identity',np.allclose(local(doc['nodes'][ri]),np.eye(4),atol=1e-6))
check('pipe_only_copper',primitive_materials['HeatPipes']==['TB_CopperHeat'])
check('lens_only_status',primitive_materials['StatusLens']==['TB_StatusLens'])
check('all_images_embedded',all('bufferView'in im and 'uri'not in im for im in doc['images']))
for mat in doc['materials']:
    p=mat.get('pbrMetallicRoughness',{})
    check(mat['name']+'_base', 'baseColorTexture'in p)
    check(mat['name']+'_rough_metal', 'metallicRoughnessTexture'in p)
    check(mat['name']+'_normal', 'normalTexture'in mat)
    check(mat['name']+'_uv_bind0',p.get('baseColorTexture',{}).get('texCoord',0)==0 and mat.get('normalTexture',{}).get('texCoord',0)==0)
bladepts=[]
for pr in doc['meshes'][doc['nodes'][fi]['mesh']]['primitives']:
    p=accessor(pr['attributes']['POSITION']);p=(local(doc['nodes'][fi])@np.c_[p,np.ones(len(p))].T).T[:,:3];bladepts.extend(p)
bladepts=np.array(bladepts);rad=np.linalg.norm(bladepts[:,:2],axis=1).max()
check('rotor_radial_clearance',rad<.599,{'maximum_rotor_radius':float(rad),'fixed_inner_lip_radius':.599,'clearance':.599-float(rad)})
check('guard_axial_gap',float(bladepts[:,2].max()+world[pi][2,3])<.821,{'rotor_front':float(bladepts[:,2].max()+world[pi][2,3]),'guard_back':.821})
report={'glb':str(path),'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'triangles':triangles,'bounds':bounds,'mesh_info':mesh_info,'nodes':[{'name':n.get('name'),'parent':doc['nodes'][parents[i]].get('name') if i in parents else None,'local_matrix_row_major':local(n).tolist(),'world_matrix_row_major':world[i].tolist()} for i,n in enumerate(doc['nodes'])], 'images':len(doc['images']),'materials':doc['materials'],'checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'scope':'Raw binary geometry, hierarchy, UV/material bindings only; not Godot physics/performance/human gameplay.'}
(SRC/'evidence/glb_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:report[k] for k in ['sha256','bytes','triangles','bounds','passed','failed']},ensure_ascii=False));print(json.dumps([c for c in checks if not c['passed']],ensure_ascii=False))
assert not report['failed']
