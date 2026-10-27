"""Read actual warehouse GLB; independent surface and portal audit."""
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

asset=read_glb(ROOT/'assets/v3/underdeck_shell/underdeck_shell.glb')
expected={'NavigationSurface','CoverSurface','CoverDetails','RoofSupports'}
check('four_runtime_meshes',set(asset['groups'])==expected)
check('all_node_transforms_identity',all(np.allclose(n['local_matrix_row_major'],np.eye(4),atol=1e-7)for n in asset['nodes']),asset['nodes'])
check('one_named_root',sum(n['name']=='UnderdeckShellArt'and n['parent']is None for n in asset['nodes'])==1)
for n in asset['nodes']:
    if n['name']in expected:check(n['name']+':fade_parent',n['parent']==('PermanentNavigation'if n['name']=='NavigationSurface'else'OccludingCover'))
check('exactly_three_materials',len(asset['materials'])==3,[m['name']for m in asset['materials']])
check('budget_22000_triangles_9_surfaces',asset['triangles']<=22000 and asset['surfaces']<=9,{'triangles':asset['triangles'],'surfaces':asset['surfaces']})
partition=json.loads((SRC/'evidence/surface_partition.json').read_text())
check('source_collision_hash_lock',partition['collision_sha256']=='8a9138bcf652ba71777aa89ec89bff8b790068b6e0c5b570c252560d51ee6473')
owners=[]
for r in partition['original']:
    p=np.array(r['points']);lo=p.min(0);hi=p.max(0);axis=int(np.argmin(hi-lo));owners.append((lo,hi,axis,r['area']))
alltri=np.concatenate([asset['groups'][g]['triangles_array']for g in expected])
base=np.concatenate([asset['groups'][g]['triangles_array']for g in ['NavigationSurface','CoverSurface']])
assigned=[[]for _ in owners];bad=[]
for idx,t in enumerate(base):
    lo=t.min(0);hi=t.max(0);area=np.linalg.norm(np.cross(t[1]-t[0],t[2]-t[0]))/2
    found=[i for i,(a,b,k,_)in enumerate(owners)if max(abs(t[:,k]-a[k]))<3e-6 and np.all(lo>=a-3e-6)and np.all(hi<=b+3e-6)]
    if len(found)==1 and area>1e-10:assigned[found[0]].append((idx,t,float(area)))
    else:bad.append({'triangle':idx,'owners':found,'area':float(area)})
check('every_base_triangle_on_unique_original_face',not bad,bad[:30])
area_errors=[{'owner':i,'expected':o[3],'actual':sum(t[2]for t in assigned[i])}for i,o in enumerate(owners)if abs(sum(t[2]for t in assigned[i])-o[3])>3e-5]
check('all_348_original_rectangles_full_area',not area_errors,area_errors)
def cross(a,b):return float(a[0]*b[1]-a[1]*b[0])
def intersection_area(tria,trib):
    # Convex clipping in the original surface plane, not bbox-overlap counts.
    poly=[p.copy()for p in tria];sgn=1 if cross(trib[1]-trib[0],trib[2]-trib[0])>=0 else-1
    for i in range(3):
        if not poly:return 0.0
        a,b=trib[i],trib[(i+1)%3];out=[]
        for j,p in enumerate(poly):
            q=poly[(j+1)%len(poly)];dp=sgn*cross(b-a,p-a);dq=sgn*cross(b-a,q-a)
            if dp>=-1e-9:out.append(p)
            if(dp>0)!=(dq>0) and abs(dp-dq)>1e-14:out.append(p+(q-p)*dp/(dp-dq))
        poly=out
    return abs(sum(cross(poly[i],poly[(i+1)%len(poly)])for i in range(len(poly))))*.5 if len(poly)>2 else 0.0
overlaps=[]
for i,rows in enumerate(assigned):
    axes=[k for k in range(3)if k!=owners[i][2]]
    for a in range(len(rows)):
      for b in range(a+1,len(rows)):
        ar=intersection_area(rows[a][1][:,axes],rows[b][1][:,axes])
        if ar>1e-7:overlaps.append({'owner':i,'triangles':[rows[a][0],rows[b][0]],'area':ar})
check('no_positive_area_overlap_on_base_faces',not overlaps,overlaps[:20])
def hits(tri,start,end):
    start=np.array(start);direction=np.array(end)-start;e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0]
    h=np.cross(np.broadcast_to(direction,e2.shape),e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-10
    inv=np.zeros(len(det));inv[valid]=1/det[valid];s=start-tri[:,0];u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=inv*np.einsum('ij,j->i',q,direction);t=inv*np.einsum('ij,ij->i',e2,q)
    mask=valid&(u>=-1e-7)&(v>=-1e-7)&(u+v<=1+1e-7)&(t>1e-6)&(t<1-1e-6)
    return np.flatnonzero(mask).tolist()
miss=[]
for x in np.linspace(-1.75,1.75,7):
 for y in np.linspace(.50,3.60,7):
    if hits(alltri,[x,y,8.8],[x,y,-8.8]):miss.append([float(x),float(y)])
check('49_actual_GL B_main_corridor_open_rays'.replace('GL B','GLB'),not miss,miss)
miss=[]
for z in np.linspace(1.95,5.05,7):
 for y in np.linspace(2.35,4.75,7):
    if hits(alltri,[8.8,y,z],[0,y,z]):miss.append([float(y),float(z)])
check('49_actual_GLB_east_window_turning_room_open_rays',not miss,miss)
nav=asset['groups']['NavigationSurface']['triangles_array'];cover=asset['groups']['CoverSurface']['triangles_array']
for name,p,y in [('main_floor',[0,0,-3],.45),('turning_floor',[2,0,3.5],.45),('side_landing',[6,0,3.5],2.3)]:
    a=[p[0],y+.1,p[2]];b=[p[0],y-.1,p[2]];check(name+':navigation_only',bool(hits(nav,a,b))and not hits(cover,a,b))
check('three_towers_actual_bounds',np.allclose(asset['groups']['RoofSupports']['bounds']['min'],[-8.506,6,-.506],atol=3e-6)and np.allclose(asset['groups']['RoofSupports']['bounds']['max'],[8.506,11.606,2.506],atol=3e-6),asset['groups']['RoofSupports']['bounds'])
for g in asset['groups'].values():g.pop('points');g.pop('triangles_array')
report={'asset':asset,'checks':checks,'passed':sum(c['passed']for c in checks),'failed':sum(not c['passed']for c in checks),'scope':'Raw binary identity hierarchy, UV/material binding, every original face coverage and nonoverlap, geometry ray openings; rays are NOT full FlightBody sweeps or engine physics/performance/visual acceptance.'}
(SRC/'evidence/glb_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':report['passed'],'failed':report['failed'],'asset':{k:asset[k]for k in ['sha256','bytes','triangles','surfaces','bounds']}},ensure_ascii=False))
assert not report['failed'],[c for c in checks if not c['passed']]
