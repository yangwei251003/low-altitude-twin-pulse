"""Read the two actual GLB binaries. Never modify runtime resources."""
from pathlib import Path
import struct,json,hashlib
from collections import Counter
import numpy as np
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent
checks=[]
def check(name,ok,detail=None):checks.append(dict(name=name,passed=bool(ok),detail=detail))
def read_glb(path):
    data=path.read_bytes();magic,version,total=struct.unpack_from('<III',data,0)
    assert magic==0x46546c67 and version==2 and total==len(data)
    off=12;doc=None;binary=None
    while off<len(data):
        n,k=struct.unpack_from('<II',data,off);chunk=data[off+8:off+8+n];off+=8+n
        if k==0x4e4f534a:doc=json.loads(chunk)
        elif k==0x004e4942:binary=chunk
    def accessor(i):
        a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
        n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1',5122:'<i2',5120:'i1'}[a['componentType']]
        b=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',np.dtype(dtype).itemsize*n)
        return np.ndarray((a['count'],n),dtype=dtype,buffer=binary,offset=b,strides=(stride,np.dtype(dtype).itemsize)).copy()
    def local(node):
        if 'matrix'in node:return np.array(node['matrix']).reshape(4,4).T
        m=np.eye(4);x,y,z,w=node.get('rotation',[0,0,0,1])
        m[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
        m[:3,:3]=m[:3,:3]@np.diag(node.get('scale',[1,1,1]));m[:3,3]=node.get('translation',[0,0,0]);return m
    world={};parents={}
    def walk(i,p):
        world[i]=p@local(doc['nodes'][i])
        for c in doc['nodes'][i].get('children',[]):parents[c]=i;walk(c,world[i])
    for i in doc['scenes'][doc.get('scene',0)]['nodes']:walk(i,np.eye(4))
    groups={};allpoints=[];node_info=[]
    for i,node in enumerate(doc['nodes']):
        node_info.append({'name':node.get('name'),'parent':doc['nodes'][parents[i]].get('name') if i in parents else None,'local_matrix_row_major':local(node).tolist(),'world_matrix_row_major':world[i].tolist()})
        if 'mesh'not in node:continue
        pts=[];tris=[];mats=[]
        for j,prim in enumerate(doc['meshes'][node['mesh']]['primitives']):
            p=accessor(prim['attributes']['POSITION']);p=(world[i]@np.c_[p,np.ones(len(p))].T).T[:,:3]
            ix=accessor(prim['indices']).reshape(-1,3);pts.extend(p);tris.extend(p[ix]);mats.append(doc['materials'][prim['material']]['name'])
            prefix=path.name+':'+node['name']+':'+str(j)
            check(prefix+':triangle_mode',prim.get('mode',4)==4 and len(ix)>0)
            check(prefix+':finite_positions',np.isfinite(p).all())
            check(prefix+':UV0_only','TEXCOORD_0'in prim['attributes'] and 'TEXCOORD_1'not in prim['attributes'])
            check(prefix+':finite_UV',np.isfinite(accessor(prim['attributes']['TEXCOORD_0'])).all())
            check(prefix+':normals','NORMAL'in prim['attributes'])
        pts=np.array(pts);tris=np.array(tris);allpoints.extend(pts)
        groups[node['name']]={'points':pts,'triangles_array':tris,'triangles':len(tris),'surfaces':len(mats),'materials':mats,'bounds':{'min':pts.min(axis=0).tolist(),'max':pts.max(axis=0).tolist()}}
    allpoints=np.array(allpoints)
    check(path.name+':all_embedded',all('bufferView'in i and 'uri'not in i for i in doc['images']))
    for m in doc['materials']:
        p=m.get('pbrMetallicRoughness',{});pre=path.name+':'+m['name']
        check(pre+':base_image','baseColorTexture'in p)
        check(pre+':rough_metal_image','metallicRoughnessTexture'in p)
        check(pre+':normal_image','normalTexture'in m)
        check(pre+':bind_UV0',all(t.get('texCoord',0)==0 for t in [p.get('baseColorTexture',{}),p.get('metallicRoughnessTexture',{}),m.get('normalTexture',{})]))
        check(pre+':neutral_base_factor',np.allclose(p.get('baseColorFactor',[1,1,1,1]),[1,1,1,1]))
    return {'path':str(path),'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'nodes':node_info,'groups':groups,'triangles':sum(g['triangles']for g in groups.values()),'surfaces':sum(g['surfaces']for g in groups.values()),'bounds':{'min':allpoints.min(axis=0).tolist(),'max':allpoints.max(axis=0).tolist()},'materials':doc['materials'],'images':len(doc['images'])}
panel=read_glb(ROOT/'assets/v3/underdeck_door/panel.glb');rail=read_glb(ROOT/'assets/v3/underdeck_door/fixed_rail.glb')
def geometry_signature(tri):
    triangles=[tuple(sorted(tuple(int(v)for v in p)for p in t))for t in np.rint(tri*1000000).astype(np.int64)]
    return hashlib.sha256(repr(sorted(triangles)).encode()).hexdigest()
for current,filename in [(panel,'panel.glb'),(rail,'fixed_rail.glb')]:
    start=len(checks);old=read_glb(SRC/'evidence/rejected_material_v1'/filename);del checks[start:]
    for name,g in current['groups'].items():
        digest=geometry_signature(g['triangles_array']);previous=geometry_signature(old['groups'][name]['triangles_array'])
        g['triangle_geometry_signature_1micrometre']=digest
        check(filename+':'+name+':geometry_unchanged_since_v1',digest==previous,{'current':digest,'v1':previous,'comparison':'Unoriented full triangle multiset, coordinates quantized to 1 micrometre; includes duplicate multiplicity.'})
for asset,root,expected in [(panel,'UnderdeckDoorPanel',{'PanelBody','PanelHardware','MovingHangers'}),(rail,'UnderdeckDoorRail',{'FixedRail','StopAndGuides','StatusLens'})]:
    check(root+':groups',set(asset['groups'])==expected)
    check(root+':all_identity',all(np.allclose(n['local_matrix_row_major'],np.eye(4),atol=1e-6)for n in asset['nodes']),asset['nodes'])
    check(root+':one_root',sum(n['name']==root and n['parent']is None for n in asset['nodes'])==1)
    check(root+':direct_children',all(n['parent']==root for n in asset['nodes']if n['name']in expected))
body=panel['groups']['PanelBody'];lo=np.array(body['bounds']['min']);hi=np.array(body['bounds']['max'])
check('solid_body_exact_3.8x3.2x.30',np.allclose(lo,[-1.9,-1.6,-.15],atol=2e-6)and np.allclose(hi,[1.9,1.6,.15],atol=2e-6),body['bounds'])
for name in ['PanelHardware']:
    b=panel['groups'][name]['bounds'];check(name+':inside_slab',np.all(np.array(b['min'])>=lo-2e-6)and np.all(np.array(b['max'])<=hi+2e-6),b)
b=panel['groups']['MovingHangers']['bounds'];check('hangers_explicit_extra_top',b['min'][1]>=1.34 and b['max'][1]<=2.10 and b['max'][2]<=.15,b)
for name in ['FixedRail','StopAndGuides','StatusLens']:
    b=rail['groups'][name]['bounds'];check(name+':above_clear_opening',b['min'][1]>=1.66-2e-6,b)
check('rail_x_range',np.allclose([rail['groups']['FixedRail']['bounds']['min'][0],rail['groups']['FixedRail']['bounds']['max'][0]],[-2.05,6.25],atol=2e-6))
check('status_material_isolated',rail['groups']['StatusLens']['materials']==['UD_StatusLens'])
tri=body['triangles_array'];keys=np.round(tri,6);edges=Counter()
for t in keys:
    for a,b in [(0,1),(1,2),(2,0)]:edges[tuple(sorted((tuple(t[a]),tuple(t[b]))))]+=1
check('solid_body_welded_edges_twice',all(n==2 for n in edges.values()),{'bad_edge_count':sum(n!=2 for n in edges.values()),'unique_edges':len(edges)})
volume=float(np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])).sum()/6)
check('solid_body_positive_volume',volume>2,volume)
# Orthographic ray coverage of the genuine front and back sheet, including the
# clear opening and deliberate 0.1m side overlap. This is not a physics sweep.
def hits_at(x,y,side):
    a=tri[:,:,:2];e1=a[:,1]-a[:,0];e2=a[:,2]-a[:,0];q=np.array([x,y])-a[:,0]
    d=e1[:,0]*e2[:,1]-e1[:,1]*e2[:,0];ok=np.abs(d)>1e-12
    u=np.zeros(len(d));v=np.zeros(len(d));u[ok]=(q[ok,0]*e2[ok,1]-q[ok,1]*e2[ok,0])/d[ok];v[ok]=(e1[ok,0]*q[ok,1]-e1[ok,1]*q[ok,0])/d[ok]
    ok&=(u>=-1e-7)&(v>=-1e-7)&(u+v<=1+1e-7)
    z=tri[:,0,2]+u*(tri[:,1,2]-tri[:,0,2])+v*(tri[:,2,2]-tri[:,0,2])
    return bool(np.any(ok&(z*side>.09)))
for side in [1,-1]:
    samples=[(float(x),float(y))for x in np.linspace(-1.895,1.895,39)for y in np.linspace(-1.595,1.595,33)]
    failed=[p for p in samples if not hits_at(*p,side)]
    check('solid_sheet_ray_grid_'+str(side),not failed,{'samples':len(samples),'misses':failed})
for asset in [panel,rail]:
    for g in asset['groups'].values():g.pop('points');g.pop('triangles_array')
report={'assets':[panel,rail],'checks':checks,'passed':sum(c['passed']for c in checks),'failed':sum(not c['passed']for c in checks),'scope':'Raw GLB binary geometry, front/back solid coverage, hierarchy, UV/material and texture binding. Not Godot collision, animation, visual quality or performance approval.'}
(SRC/'evidence/glb_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':report['passed'],'failed':report['failed'],'assets':[{k:a[k]for k in ['path','sha256','bytes','triangles','surfaces','bounds']}for a in [panel,rail]]},ensure_ascii=False))
assert not report['failed'],[c for c in checks if not c['passed']]
