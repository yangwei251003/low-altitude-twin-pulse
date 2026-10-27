"""Blender CPU-only GLB roundtrip and geometric contract checks, no Godot import.
Run after both build commands. Use render_fantasy_kit.py for imported-GLB previews.
Writes only this kit's artifact folder. A pass is not gameplay/graphics/performance evidence.
"""
import bpy,json,struct,hashlib,math,sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[3]
ART=ROOT/'artifacts/v3/art/fantasy_kit'

def binary_check(path):
    blob=path.read_bytes(); chunk_len=struct.unpack_from('<I',blob,12)[0]
    doc=json.loads(blob[20:20+chunk_len]); binary=blob[28+chunk_len:]
    def values(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
        count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        fmt='<'+fmt*count;size=struct.calcsize(fmt)
        off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
        return [struct.unpack_from(fmt,binary,off+i*stride) for i in range(a['count'])]
    rows=[];triangles=0
    for mi,mesh in enumerate(doc['meshes']):
        node=next(n for n in doc['nodes'] if n.get('mesh')==mi)
        for prim in mesh['primitives']:
            attr=prim['attributes']; mat=doc['materials'][prim['material']]
            assert 'TEXCOORD_0' in attr,(node['name'],'missing UV0')
            assert 'TEXCOORD_1' not in attr,(node['name'],'unexpected UV1')
            uv=values(attr['TEXCOORD_0']);indices=[x[0] for x in values(prim['indices'])]
            assert len(uv)==doc['accessors'][attr['POSITION']]['count']
            flat=sum(all(abs(uv[j][0])+abs(uv[j][1]-1)<1e-8 for j in indices[i:i+3]) for i in range(0,len(indices),3))
            assert flat==0,(node['name'],'join-default UV triangles',flat)
            assert all(math.isfinite(x) for u in uv for x in u)
            pbr=mat['pbrMetallicRoughness']
            assert 'baseColorTexture' in pbr and 'metallicRoughnessTexture' in pbr and 'normalTexture' in mat,mat['name']
            n=len(indices)//3; triangles+=n
            rows.append({'node':node['name'],'material':mat['name'],'triangles':n,'vertices':len(uv),'join_default_uv_triangles':flat})
    assert triangles<=25000,triangles
    assert len(doc['materials'])<=4
    return {'sha256':hashlib.sha256(blob).hexdigest(),'bytes':len(blob),'triangles':triangles,'materials':len(doc['materials']),'embedded_images':len(doc.get('images',[])),'primitives':rows,'pivot_nodes':[n for n in doc['nodes'] if n.get('name','').startswith('LeafPivot_') and 'mesh' not in n]},doc

def bvh(items):
    bpy.context.view_layer.update();verts=[];faces=[]
    for ob in items:
        n=len(verts);verts.extend(ob.matrix_world@v.co for v in ob.data.vertices)
        faces.extend(tuple(n+i for i in p.vertices) for p in ob.data.polygons)
    return BVHTree.FromPolygons(verts,faces)

def bounds(items):
    bpy.context.view_layer.update();coords=[o.matrix_world@v.co for o in items for v in o.data.vertices]
    mn=[min(v[i] for v in coords) for i in range(3)];mx=[max(v[i] for v in coords) for i in range(3)]
    return {'min':mn,'max':mx,'size':[mx[i]-mn[i] for i in range(3)]}

all_reports=[]
for name in ('rootstone_terrace','photosensitive_roots'):
    path=ROOT/'assets/v3/fantasy_kit'/(name+'.glb')
    report,doc=binary_check(path)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(path))
    items=[o for o in bpy.context.scene.objects if o.type=='MESH']
    report['name']=name;report['roundtrip_bounds_blender']=bounds(items)
    report['godot_bounds_note']='Convert Blender (x,y,z) to Godot (x,z,-y). GLB stores Y-up.'
    tree=bvh(items)
    if name=='rootstone_terrace':
        clear=0
        for ix in range(21):
            for iz in range(17):
                x=-2.05+4.10*ix/20;z=.30+3.15*iz/16
                loc,normal,index,distance=tree.ray_cast(Vector((x,-5,z)),Vector((0,1,0)),10)
                assert loc is None,('cave_blocked',x,z,list(loc) if loc else None)
                clear+=1
        # Independent vertical flights confirm a substantial roof and usable upper surface.
        roof=[]
        for x,y in ((0,0),(-1,-1),(1,1),(-3,-1.4),(3,1.4)):
            hit=tree.ray_cast(Vector((x,y,10)),Vector((0,0,-1)),12)
            assert hit[0] is not None and 5.0<hit[0].z<6.2,(x,y,hit)
            roof.append({'x':x,'y':y,'top_z':hit[0].z})
        report['clear_tunnel_rays']=clear;report['clear_tunnel_box_blender']={'min':[-2.05,-5,.30],'max':[2.05,5,3.45],'width':4.1,'height':3.15}
        report['upper_surface_samples']=roof
    else:
        ps=[bpy.data.objects.get('LeafPivot_'+x) for x in ('N','E','S','W')]
        assert all(ps) and len(ps)==4
        closed={o.name:o.matrix_world.copy() for o in ps}
        static=[o for o in items if o.parent not in ps]
        before=bounds(static)
        travel=[]
        for p in ps:
            original=p.matrix_basis.copy()
            children=[o for o in items if o.parent==p]
            assert len(children)==2,(p.name,len(children))
            tip_before=max((o.matrix_world@v.co for o in children for v in o.data.vertices),key=lambda q:q.z)
            p.matrix_basis=original@Matrix.Rotation(math.radians(-58),4,'X')
            bpy.context.view_layer.update()
            tip_after=max((o.matrix_world@v.co for o in children for v in o.data.vertices),key=lambda q:q.z)
            before_radius=math.hypot(tip_before.x,tip_before.y);after_radius=math.hypot(tip_after.x,tip_after.y)
            assert after_radius>before_radius+.20,(p.name,'wrong opening direction',before_radius,after_radius)
            travel.append({'pivot':p.name,'open_angle_local_x_degrees':-58,'closed_top_radius':before_radius,'open_top_radius':after_radius,'pivot_blender':list(p.matrix_world.translation)})
        report['opened_bounds_blender']=bounds(items);report['leaf_motion']=travel
        assert bounds(static)==before,'leaf motion moved basin/core'
        report['static_root_core_unchanged_during_open']=True
        report['idle_emission_note']='Seed-heart material idle emission 0.22; gameplay should brighten on light receipt.'
    report['status']='PASS'
    all_reports.append(report)
    (ART/(name+'_verified.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('KIT_VERIFIED',json.dumps(report))
print('BOTH_ASSETS_PASS')
