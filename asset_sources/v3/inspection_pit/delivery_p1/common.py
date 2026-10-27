"""Pit-only adaptation of proven pump/rack delivery helpers; no shared edits."""
from pathlib import Path
import bpy, math, json, hashlib, shutil, statistics
from mathutils import Matrix, Vector

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
CONTRACT = json.loads((OUT/'input_contract.json').read_text(encoding='utf-8'))
assert CONTRACT['locked'], 'Root final source has not been locked'
SOURCE = ROOT/CONTRACT['source']
SOURCE_SHA = CONTRACT['source_sha256']
GROUPS = CONTRACT['groups']
ROOT_NAME = CONTRACT['root_name']
UVS = ('MetricUV', 'WallUV', 'AggregateUV', 'PaintUV')

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name, row):
    (OUT/name).write_text(json.dumps(row, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')
def gp(v): return [float(v[0]), float(v[2]), float(-v[1])]
def source_check():
    assert sha(SOURCE) == SOURCE_SHA
    assert sha(ROOT/CONTRACT['source_report']) == CONTRACT['source_report_sha256']
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.hide_set(False); ob.hide_viewport=False; ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[-1]
def shader(mat):
    rows=[n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED']
    assert len(rows)==1, mat.name
    return rows[0]
def image_audit(copy=False):
    rows=[]; (OUT/'source_inputs').mkdir(exist_ok=True)
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath: continue
        src=Path(bpy.path.abspath(im.filepath)).resolve()
        packed=bytes(im.packed_file.data) if im.packed_file else None
        if copy:
            dst=OUT/'source_inputs'/src.name
            original=src.read_bytes() if src.is_file() else packed
            assert original, (im.name, 'no original image bytes')
            if packed is not None: assert hashlib.sha256(packed).digest()==hashlib.sha256(original).digest()
            if dst.exists(): assert dst.read_bytes()==original
            else: dst.write_bytes(original)
            im.filepath=str(dst); src=dst
        assert src.is_file(), (im.name,str(src))
        pixel=list(im.pixels[:4])
        assert len(pixel)==4 and im.has_data and all(math.isfinite(v) for v in pixel), im.name
        rows.append({'image':im.name,'path':str(src),'sha256':sha(src),'bytes':src.stat().st_size,
                     'size':list(im.size),'space':im.colorspace_settings.name,'pixel':pixel,
                     'packed':bool(im.packed_file)})
    return rows
def audit_shader(mat):
    todo=[shader(mat)]; seen=set(); nodes=[]
    while todo:
        node=todo.pop()
        if node.name in seen: continue
        seen.add(node.name)
        assert node.type not in {'TEX_COORD','NEW_GEOMETRY','OBJECT_INFO'}, (mat.name,node.name)
        if node.type.startswith('TEX_') and 'Vector' in node.inputs:
            assert node.inputs['Vector'].is_linked, (mat.name,node.name,'implicit coordinates')
        if node.type=='UVMAP': assert node.uv_map in UVS, (mat.name,node.uv_map)
        todo.extend(link.from_node for socket in node.inputs for link in socket.links)
        nodes.append({'name':node.name,'type':node.type})
    return {'material':mat.name,'nodes':nodes,'explicit_source_UV':True}
def group_for(ob):
    role=ob.get('role')
    if role in {'Wall','Coping'} or ob.name.endswith('Backing'): return 'WallConcrete'
    if role in {'Floor','Ramp'} or ob.name.startswith('RecessedRampGroove'): return 'FloorAndRamp'
    assert role in {'Steel','Teal','Yellow','Seam'}, (ob.name,role)
    return 'Hardware'
def normal_angle(a,b):
    a=[float(x) for x in a]; b=[float(x) for x in b]
    cross=[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
    return math.degrees(math.atan2(math.sqrt(sum(x*x for x in cross)),sum(x*y for x,y in zip(a,b))))
def make_proxy(parts, group):
    dg=bpy.context.evaluated_depsgraph_get(); verts=[]; faces=[]; mids=[]; mats=[]; normals=[]
    uvs={name:[] for name in UVS}; mapping=[]; original=[]
    for ob in sorted(parts,key=lambda p:p.name):
        matrix=ob.matrix_world.copy(); assert matrix.determinant()>0, ob.name
        nm=matrix.to_3x3().inverted().transposed()
        me=bpy.data.meshes.new_from_object(ob.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
        me.calc_loop_triangles(); offset=len(verts)
        verts.extend(tuple(matrix@v.co) for v in me.vertices)
        for tri in me.loop_triangles:
            poly=me.polygons[tri.polygon_index]; mat=me.materials[poly.material_index]
            assert mat is not None, (ob.name,poly.index,poly.material_index)
            if mat not in mats: mats.append(mat)
            faces.append(tuple(offset+v for v in tri.vertices)); mids.append(mats.index(mat))
            mapping.append({'object':ob.name,'role':ob['role'],'source_polygon':poly.index,
                            'source_triangle':tri.index,'material':mat.name})
            for li in tri.loops:
                normals.append(tuple((nm@me.corner_normals[li].vector).normalized()))
                for name in UVS:
                    assert name in me.uv_layers, (ob.name,name)
                    uvs[name].append(tuple(me.uv_layers[name].data[li].uv))
        original.append({'object':ob.name,'triangles':len(me.loop_triangles),
                         'matrix_world':[list(r) for r in matrix]})
        bpy.data.meshes.remove(me)
    me=bpy.data.meshes.new(group+'_ExactSourceTriangles'); me.from_pydata(verts,[],faces); me.update()
    for mat in mats: me.materials.append(mat)
    for poly,mid in zip(me.polygons,mids): poly.material_index=mid; poly.use_smooth=True
    me.normals_split_custom_set(normals)
    for name,values in uvs.items():
        me.uv_layers.new(name=name)
        # Acquire by name only after creating the layer; never reuse stale RNA handles.
        for loop,value in zip(me.uv_layers[name].data,values): loop.uv=value
    assert len(me.polygons)==len(mapping)
    position_error=max(abs(float(a)-float(b)) for v,p in zip(me.vertices,verts) for a,b in zip(v.co,p))
    assert position_error<=1e-5, (group,'source position copy',position_error)
    assert all(tuple(p.vertices)==f and p.material_index==mid for p,f,mid in zip(me.polygons,faces,mids))
    assert all(tuple(loop.uv)==v for name,values in uvs.items() for loop,v in zip(me.uv_layers[name].data,values))
    angular=max(normal_angle(a,b.vector) for a,b in zip(normals,me.corner_normals))
    assert angular<=.1, (group,'corner normal angle',angular)
    ob=bpy.data.objects.new(group+'_BakeProxy',me); bpy.context.scene.collection.objects.link(ob)
    assert ob.matrix_world==Matrix.Identity(4)
    return ob,mapping,{'parts':original,'triangles':len(faces),'position_copy_max_m':position_error,
                       'corner_normal_max_degrees':angular,
                       'materials':[audit_shader(mat) for mat in mats]}

def priority(group, info, normal, center):
    ng=gp(normal); pg=gp(center)
    if info['object'].endswith('Backing') or info['object']=='BuriedRampFront': return .18
    if group=='FloorAndRamp': return 1.0 if ng[1]>.5 else .20
    if group=='Hardware': return .35 if ng[1]<-.7 else 1.0
    if ng[1]>.5: return 1.0  # exposed coping
    if ng[1]<-.5: return .18
    inward=ng[0]*(-pg[0])+ng[2]*(-pg[2])
    return 1.0 if inward>0 else .58

def atlas(proxy, mapping, size):
    """Dominant-normal charts per original convex piece, weighted metric density.

    Original shader UVs are untouched. Distinct charts have an 8px gap; all
    evaluated triangles are retained. No centroid-only UV validity shortcut.
    """
    me=proxy.data; charts={}
    for poly,info in zip(me.polygons,mapping):
        p=[me.vertices[v].co for v in poly.vertices]
        normal=(p[1]-p[0]).cross(p[2]-p[0])
        assert normal.length>0, (proxy.name,info,'zero source triangle')
        normal.normalize(); axis=max(range(3),key=lambda k:abs(normal[k])); sign=1 if normal[axis]>0 else -1
        axes=((1,2),(2,0),(0,1))[axis]
        points=[(float(v[axes[0]])*sign,float(v[axes[1]])) for v in p]
        key=(info['object'],axis,sign)
        center=sum(p,Vector())/3
        c=charts.setdefault(key,{'key':key,'faces':[],'uv':{},'points':[],
                                'weight':priority(proxy.name.removesuffix('_BakeProxy'),info,normal,center)})
        c['faces'].append(poly.index)
        for li,uv in zip(poly.loop_indices,points): c['uv'][li]=uv; c['points'].append(uv)
        c['weight']=max(c['weight'],priority(proxy.name.removesuffix('_BakeProxy'),info,normal,center))
    for c in charts.values():
        c['lo']=[min(p[i] for p in c['points']) for i in range(2)]
        c['span']=[max(p[i] for p in c['points'])-c['lo'][i] for i in range(2)]
        assert min(c['span'])>0, (c['key'],c['span'])
    pad=4
    def packed(density):
        rects=[]
        for index,c in enumerate(charts.values()):
            dims=[max(3,math.ceil(v*density*c['weight'])) for v in c['span']]
            rotate=dims[1]>dims[0]
            w,h=(dims[::-1] if rotate else dims)
            rects.append((w+2*pad,h+2*pad,index,rotate,dims))
        # Deterministic first-fit decreasing shelves. No engine-dependent pack transform.
        shelves=[]; found={}
        for w,h,i,rot,dims in sorted(rects,key=lambda r:(-r[1],-r[0],r[2])):
            if w>size or h>size: return None
            slot=next((s for s in shelves if s['height']>=h and s['x']+w<=size),None)
            if slot is None:
                y=sum(s['height'] for s in shelves)
                if y+h>size: return None
                slot={'y':y,'x':0,'height':h}; shelves.append(slot)
            found[i]=(slot['x']+pad,slot['y']+pad,rot,dims); slot['x']+=w
        return found
    low,high=.1,2048.
    assert packed(low) is not None, (proxy.name,'minimum chart packing exhausted')
    for _ in range(28):
        mid=(low+high)*.5
        if packed(mid) is None: high=mid
        else: low=mid
    placements=packed(low); me.uv_layers.new(name='DeliveryUV'); layer=me.uv_layers['DeliveryUV']
    for index,c in enumerate(charts.values()):
        x,y,rot,dims=placements[index]
        for li,p in c['uv'].items():
            q=[(p[k]-c['lo'][k])*dims[k]/c['span'][k] for k in range(2)]
            if rot:q=q[::-1]
            layer.data[li].uv=((x+q[0])/size,(y+q[1])/size)
        c['density']=[dims[k]/c['span'][k] for k in range(2)]
    me.uv_layers.active_index=me.uv_layers.find('DeliveryUV')
    for uv in me.uv_layers: uv.active_render=uv.name=='DeliveryUV'
    areas=[]; density=[]; summaries=[]
    for poly,info in zip(me.polygons,mapping):
        uv=[tuple(layer.data[i].uv) for i in poly.loop_indices]
        assert all(math.isfinite(v) and 0<=v<=1 for p in uv for v in p)
        area=abs((uv[1][0]-uv[0][0])*(uv[2][1]-uv[0][1])-(uv[1][1]-uv[0][1])*(uv[2][0]-uv[0][0]))*.5
        assert area>0, (proxy.name,info,'zero DeliveryUV area')
        areas.append(area); density.append(math.sqrt(area/poly.area)*size)
    # True pixel-centre footprint of every UV triangle (not bounding-box occupancy).
    import numpy as np
    occupancy=np.zeros((size,size),dtype=np.bool_)
    for poly in me.polygons:
        uv=np.array([tuple(layer.data[i].uv) for i in poly.loop_indices],dtype=np.float64)*size
        x0=max(0,int(np.floor(uv[:,0].min()))); x1=min(size,int(np.ceil(uv[:,0].max())))
        y0=max(0,int(np.floor(uv[:,1].min()))); y1=min(size,int(np.ceil(uv[:,1].max())))
        if x1<=x0 or y1<=y0:continue
        xx,yy=np.meshgrid(np.arange(x0,x1)+.5,np.arange(y0,y1)+.5)
        e=[]
        for a,b in zip(uv,np.roll(uv,-1,axis=0)):
            e.append((b[0]-a[0])*(yy-a[1])-(b[1]-a[1])*(xx-a[0]))
        mask=((e[0]>=0)&(e[1]>=0)&(e[2]>=0))|((e[0]<=0)&(e[1]<=0)&(e[2]<=0))
        occupancy[y0:y1,x0:x1]|=mask
    for c in charts.values():
        summaries.append({'source_object':c['key'][0],'axis':c['key'][1],'sign':c['key'][2],
                          'faces':len(c['faces']),'weight':c['weight'],'density_xy_px_per_m':c['density']})
    me.calc_tangents(uvmap='DeliveryUV')
    assert all(math.isfinite(v) for loop in me.loops for v in loop.tangent)
    me.free_tangents()
    return {'size':size,'charts':len(charts),'chart_gap_px':2*pad,'bake_extension_px':2,
            'UV_min_triangle_area':min(areas),'actual_pixel_centres_occupied':int(occupancy.sum()),
            'occupied_fraction':float(occupancy.mean()),'nominal_primary_density':low,
            'all_triangle_density_min_median_max':[min(density),statistics.median(density),max(density)],
            'chart_details':summaries}

def triangle_rows(mesh, uv_name='DeliveryUV'):
    mesh.calc_loop_triangles()
    return [[{'p':gp(mesh.vertices[v].co),'n':gp(mesh.corner_normals[li].vector),
              'uv':list(mesh.uv_layers[uv_name].data[li].uv)} for v,li in zip(t.vertices,t.loops)] for t in mesh.loop_triangles]
