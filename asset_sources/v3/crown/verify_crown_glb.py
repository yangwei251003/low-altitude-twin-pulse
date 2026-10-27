"""Read real GLB bytes, check moving geometry and round-trip through Blender.
Run Blender CPU 2; --render requests imported-GLB two-pose studio evidence.
Does not run Godot and is not a gameplay/performance or aesthetic acceptance.
"""
import bpy, json, struct, hashlib, math, sys
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

SOURCE=Path(__file__).resolve().parent;PROJECT=SOURCE.parents[2];ART=PROJECT/'artifacts/v3/art/crown';VERSION='p5'
PATH=PROJECT/'assets/v3/crown/parasitic_crown.glb';raw=PATH.read_bytes()
assert raw[:4]==b'glTF' and struct.unpack_from('<II',raw,4)==(2,len(raw))
chunks={};offset=12
while offset<len(raw):
    length,kind=struct.unpack_from('<II',raw,offset);chunks[kind]=raw[offset+8:offset+8+length];offset+=8+length
g=json.loads(chunks[0x4E4F534A]);binary=chunks[0x004E4942]
TYPES={5120:np.int8,5121:np.uint8,5122:np.int16,5123:np.uint16,5125:np.uint32,5126:np.float32}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def accessor(index):
    a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];dt=np.dtype(TYPES[a['componentType']]);width=WIDTH[a['type']]
    start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width*dt.itemsize)
    assert start+(a['count']-1)*stride+width*dt.itemsize<=len(binary)
    return np.ndarray((a['count'],width),dtype=dt,buffer=binary,offset=start,strides=(stride,dt.itemsize)).copy()
def rotation(angle,axis):
    return np.array(Matrix.Rotation(angle,4,axis),dtype=np.float64)
def local(node):
    if 'matrix' in node:return np.array(node['matrix'],dtype=float).reshape((4,4),order='F')
    from mathutils import Quaternion
    m=np.eye(4);q=node.get('rotation',[0,0,0,1]);m[:3,:3]=np.array(Quaternion((q[3],q[0],q[1],q[2])).to_matrix())@np.diag(node.get('scale',[1,1,1]));m[:3,3]=node.get('translation',[0,0,0]);return m
nodes=g['nodes'];byname={n['name']:i for i,n in enumerate(nodes)};parent={child:i for i,n in enumerate(nodes) for child in n.get('children',[])}
PIVOTS={'CrownPlatePivot_L':(-48,'Y'),'CrownPlatePivot_R':(48,'Y'),'CrownPlatePivot_C':(-32,'X')}
def worlds(amount=0):
    cache={}
    def resolve(i):
        if i in cache:return cache[i]
        m=local(nodes[i]);name=nodes[i].get('name','')
        if name in PIVOTS:
            deg,axis=PIVOTS[name];m=m@rotation(math.radians(deg*amount),axis)
        cache[i]=resolve(parent[i])@m if i in parent else m;return cache[i]
    for i in range(len(nodes)):resolve(i)
    return cache
def points(matrix,positions):return positions@matrix[:3,:3].T+matrix[:3,3]
geometry=[];uv_bad=0;triangles=0;primitive_records=[]
for ni,node in enumerate(nodes):
    if 'mesh' not in node:continue
    for primitive in g['meshes'][node['mesh']]['primitives']:
        assert primitive.get('mode',4)==4
        attrs=primitive['attributes'];assert 'POSITION'in attrs and 'NORMAL'in attrs and 'TEXCOORD_0'in attrs
        assert not any(k.startswith('TEXCOORD_') and k!='TEXCOORD_0' for k in attrs),attrs
        p=accessor(attrs['POSITION']);uv=accessor(attrs['TEXCOORD_0']);normal=accessor(attrs['NORMAL']);indices=accessor(primitive['indices']).ravel().reshape((-1,3))
        assert np.isfinite(p).all() and np.isfinite(uv).all() and np.isfinite(normal).all() and indices.max()<len(p)
        assert uv.min()>=-.0001 and uv.max()<=1.0001
        d1=p[indices[:,1]]-p[indices[:,0]];d2=p[indices[:,2]]-p[indices[:,0]];valid=np.linalg.norm(np.cross(d1,d2),axis=1)>1e-9
        a=uv[indices[:,1]]-uv[indices[:,0]];b=uv[indices[:,2]]-uv[indices[:,0]];bad=int(np.sum(valid&(np.abs(a[:,0]*b[:,1]-a[:,1]*b[:,0])<=1e-10)))
        uv_bad+=bad;triangles+=len(indices);geometry.append((ni,p,indices));primitive_records.append({'node':node['name'],'material':g['materials'][primitive['material']]['name'],'vertices':len(p),'triangles':len(indices),'uv0_range':[float(uv.min()),float(uv.max())],'collapsed_nondegenerate_uv_triangles':bad})
assert uv_bad==0,uv_bad
assert len(g['materials'])==4 and len(geometry)==76 and triangles==30546
def check_texture_coords(value):
    if isinstance(value,dict):
        if 'index'in value and ('texCoord'in value):assert value['texCoord']==0,value
        for v in value.values():check_texture_coords(v)
    elif isinstance(value,list):
        for v in value:check_texture_coords(v)
check_texture_coords(g['materials'])
for name in ['ParasiticCrown','Core','CoreSeed',*PIVOTS,*['Claw'+part+'_'+slot for part in ['Shoulder','Wrist','Contact'] for slot in ['FL','FR','BL','BR']],'LeafPivot_L','LeafPivot_R']:assert name in byname,name
closed=worlds(0);core=closed[byname['Core']][:3,3];assert np.linalg.norm(core-np.array([0,-.5,1.09]))<1e-5
for slot in ['FL','FR','BL','BR']:
    shoulder=byname['ClawShoulder_'+slot];wrist=byname['ClawWrist_'+slot];contact=byname['ClawContact_'+slot]
    assert parent[wrist]==shoulder and parent[contact]==wrist
    assert abs(closed[contact][1,3]+3)<1e-5
for name in PIVOTS:assert np.max(np.abs(local(nodes[byname[name]])[:3,:3]-np.eye(3)))<1e-6
def tree_at(amount,only_armor=False):
    ws=worlds(amount);verts=[];faces=[]
    for ni,p,indices in geometry:
        name=nodes[ni]['name']
        if name=='CoreSeed' or (only_armor and not name.startswith('CrownArmor_')):continue
        start=len(verts);verts.extend(Vector(v) for v in points(ws[ni],p));faces.extend(tuple(int(i)+start for i in face) for face in indices)
    return BVHTree.FromPolygons(verts,faces,all_triangles=True)
poses=[]
for amount in [0,.25,.5,.75,1]:
    ws=worlds(amount);verts=np.concatenate([points(ws[ni],p) for ni,p,_ in geometry]);radius=np.sqrt(verts[:,0]**2+verts[:,2]**2).max()
    assert radius<=4.00001 and verts[:,1].min()>=-3.00001 and verts[:,1].max()<=3.00001
    t=tree_at(amount);hits=[]
    for x in [-.25,0,.25]:
        for y in [-.85,-.5,-.15]:
            a=Vector((x,y,6));b=Vector((x,y,1.09));delta=b-a;hit=t.ray_cast(a,delta.normalized(),delta.length)
            hits.append({'origin':list(a),'target':list(b),'blocked':hit[0] is not None,'hit_distance':hit[3]})
    if amount in (0,1):assert sum(h['blocked'] for h in hits)==(9 if amount==0 else 0)
    poses.append({'amount':amount,'min':verts.min(0).tolist(),'max':verts.max(0).tolist(),'radius':float(radius),'core_rays':hits})
# Analytic continuous 0..open-angle sweep, not an interpolation-sample claim.
all_closed=np.concatenate([points(closed[ni],p) for ni,p,_ in geometry]);minimum=all_closed.min(0);maximum=all_closed.max(0);maxradius=float(np.linalg.norm(all_closed[:,[0,2]],axis=1).max())
arc_vertices=0
for ni,p,indices in geometry:
    chain=ni;which=None
    while True:
        if nodes[chain].get('name')in PIVOTS:which=chain;break
        if chain not in parent:break
        chain=parent[chain]
    if which is None:continue
    name=nodes[which]['name'];degree,axis_name=PIVOTS[name];limit=math.radians(degree);lo,hi=sorted([0,limit]);pivot=closed[which][:3,3]
    axis=closed[which][:3,:3]@np.eye(3)[{'X':0,'Y':1,'Z':2}[axis_name]];axis/=np.linalg.norm(axis)
    for pt in points(closed[ni],p):
        arc_vertices+=1;v=pt-pivot;b=pivot+axis*np.dot(axis,v);a=v-axis*np.dot(axis,v);c=np.cross(axis,v)
        angles=[lo,hi]
        for k in range(3):
            stationary=math.atan2(c[k],a[k])
            angles.extend(t for t in [stationary-2*math.pi,stationary-math.pi,stationary,stationary+math.pi,stationary+2*math.pi] if lo<=t<=hi)
        c1=2*(b[0]*a[0]+b[2]*a[2]);s1=2*(b[0]*c[0]+b[2]*c[2]);c2=.5*(a[0]**2+a[2]**2-c[0]**2-c[2]**2);s2=a[0]*c[0]+a[2]*c[2]
        coefficients=np.trim_zeros(np.array([-s1+2*s2,-2*c1+8*c2,-12*s2,-2*c1-8*c2,s1+2*s2]),'f')
        if len(coefficients)>1:
            for value in np.roots(coefficients):
                if abs(value.imag)<1e-8:
                    angle=2*math.atan(float(value.real))
                    if lo<=angle<=hi:angles.append(angle)
        extrema=np.array([b+a*math.cos(t)+c*math.sin(t) for t in angles]);minimum=np.minimum(minimum,extrema.min(0));maximum=np.maximum(maximum,extrema.max(0));maxradius=max(maxradius,float(np.linalg.norm(extrema[:,[0,2]],axis=1).max()))
assert minimum[1]>=-3.00001 and maximum[1]<=3.00001 and maxradius<=4.00001,(minimum,maximum,maxradius)
near=tree_at(0,True).find_nearest(Vector(core));assert near[0] is not None
def mesh_set(wanted):
    vv=[];ff=[]
    for ni,p,indices in geometry:
        if not wanted(nodes[ni]['name']):continue
        start=len(vv);vv.extend(points(closed[ni],p));ff.extend(tuple(int(i)+start for i in f)for f in indices)
    verts=np.array(vv);faces=np.array(ff,dtype=int);unique,inverse=np.unique(verts,axis=0,return_inverse=True);faces=inverse[faces]
    edges=np.unique(np.sort(np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]),axis=1),axis=0)
    return unique,faces,edges
seed_v,seed_f,seed_e=mesh_set(lambda n:n=='CoreSeed');armor_v,armor_f,armor_e=mesh_set(lambda n:n.startswith('CrownArmor_'))
armor_tree=tree_at(0,True);seed_tree=BVHTree.FromPolygons([Vector(v)for v in seed_v],seed_f.tolist(),all_triangles=True)
surface_gap=min([armor_tree.find_nearest(Vector(v))[3]for v in seed_v]+[seed_tree.find_nearest(Vector(v))[3]for v in armor_v])
intersections=0
for vs,es,tree in [(seed_v,seed_e,armor_tree),(armor_v,armor_e,seed_tree)]:
    for edge in es:
        a,b=vs[edge];d=b-a;length=np.linalg.norm(d)
        if length>1e-8 and tree.ray_cast(Vector(a),Vector(d/length),float(length))[0]is not None:intersections+=1
if intersections:surface_gap=0.0
else:
    q=armor_v[armor_e[:,0]];d2=armor_v[armor_e[:,1]]-q;e=np.sum(d2*d2,axis=1)[None,:]
    for start in range(0,len(seed_e),64):
        pairs=seed_e[start:start+64];p=seed_v[pairs[:,0]][:,None,:];d1=(seed_v[pairs[:,1]]-seed_v[pairs[:,0]])[:,None,:];r=p-q[None,:,:]
        a=np.sum(d1*d1,axis=2);b=np.sum(d1*d2[None,:,:],axis=2);c=np.sum(d1*r,axis=2);f=np.sum(d2[None,:,:]*r,axis=2);den=a*e-b*b
        s=np.clip(np.divide(b*f-c*e,den,out=np.zeros_like(den),where=abs(den)>1e-18),0,1);t=(b*s+f)/np.maximum(e,1e-20)
        s=np.where(t<0,np.clip(-c/np.maximum(a,1e-20),0,1),s);s=np.where(t>1,np.clip((b-c)/np.maximum(a,1e-20),0,1),s);t=np.clip(t,0,1)
        distances=np.linalg.norm(r+s[:,:,None]*d1-t[:,:,None]*d2[None,:,:],axis=2);surface_gap=min(surface_gap,float(distances.min()))
report={'stage':'candidate actual GLB binary and offline roundtrip; not game acceptance','glb_path':str(PATH.relative_to(PROJECT)),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'mesh_nodes':len(geometry),'triangles':triangles,'materials':[m['name']for m in g['materials']],'primitive_uv_index_checks':primitive_records,'poses':poses,'continuous_crown_arc':{'vertex_count':arc_vertices,'min':minimum.tolist(),'max':maximum.tolist(),'radius':maxradius,'method':'Rodrigues axis extrema + quartic tan-half-angle radial stationary roots'},'core_anchor':core.tolist(),'nearest_closed_crown_surface':{'point':list(near[0]),'distance':near[3]},'nodes':[]}
report['core_seed_closed_armor_surface_gap']={'distance':surface_gap,'edge_face_intersections':intersections,'method':'actual GLB triangle vertex-face BVH + all edge-edge segment distances + both edge-face intersection directions','seed_min':seed_v.min(0).tolist(),'seed_max':seed_v.max(0).tolist()}
report['image_buffers']=[]
for img in g['images']:
    view=g['bufferViews'][img['bufferView']];start=view.get('byteOffset',0);data=binary[start:start+view['byteLength']]
    assert data[:8]==b'\x89PNG\r\n\x1a\n';width,height=struct.unpack_from('>II',data,16);assert width<=2048 and height<=2048
    report['image_buffers'].append({'name':img.get('name'),'width':width,'height':height,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
report['material_mesh_groups']={m['name']:[r['node']for r in primitive_records if r['material']==m['name']]for m in g['materials']}
for name,i in byname.items():
    report['nodes'].append({'name':name,'parent':nodes[parent[i]].get('name')if i in parent else None,'local_matrix_rows':local(nodes[i]).tolist(),'world_position':closed[i][:3,3].tolist()})
if '--render'in sys.argv:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'parasitic_crown.blend'))
    scene=bpy.context.scene;scene.cycles.device='CPU';scene.cycles.samples=12;scene.render.threads_mode='FIXED';scene.render.threads=2
    for o in list(bpy.data.collections['Crown_EDITABLE_MASTER'].objects):bpy.data.objects.remove(o,do_unlink=True)
    before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(PATH));imported=set(bpy.data.objects)-before
    lookup={o.name:o for o in imported};rest={name:lookup[name].matrix_basis.copy() for name in PIVOTS}
    for label,amount in [('closed',0),('open',1)]:
        for name,(deg,axis)in PIVOTS.items():lookup[name].matrix_basis=rest[name]@Matrix.Rotation(math.radians(deg*amount),4,'Z'if axis=='Y'else axis)
        bpy.context.view_layer.update();path=ART/('crown_glb_'+label+'_'+VERSION+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        report['roundtrip_'+label]={'path':str(path.relative_to(PROJECT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source':'Blender import of exact hashed GLB; source studio camera and lighting'}
out=ART/('crown_glb_validation_'+VERSION+'.json');out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('CROWN_GLB_VERIFIED',json.dumps({k:report[k]for k in ['sha256','bytes','mesh_nodes','triangles','materials','continuous_crown_arc','nearest_closed_crown_surface']}),flush=True)
