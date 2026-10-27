"""Native phased delivery. Explicit root CPU2 window required for every phase.

Uses the already proven maintenance bake/join/binary-reader implementation.
Frozen author source remains separate; checkpoints preserve completed channels.
"""
from pathlib import Path
import sys, json, math, hashlib, collections, importlib.util, time, os
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CFG = json.loads((HERE/'contract.json').read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('proven_maintenance_delivery', ROOT/'asset_sources/v3/i2_maintenance_paving/delivery_p3/build_delivery.py')
NATIVE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NATIVE)
sys.path.insert(0, str(HERE.parent/'p1'))
import build_source as SOURCE
UV = 'DeliveryUV'
CHECKS = []


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
def check(name, ok, detail=None): CHECKS.append({'name': name, 'passed': bool(ok), 'detail': detail})
def verify():
    for name, expected in CFG['frozen_inputs'].items():
        assert sha(ROOT/name) == expected, 'Frozen input changed: '+name
def group_of(name):
    return next(k for k,g in CFG['groups'].items() if any(p['name']==name for p in g['pieces']))
def parts(): return sorted((o for o in bpy.data.objects if o.get('delivery_part')), key=lambda o:o.name)
def group_parts(key): return [o for o in parts() if o['delivery_group']==key]


def source_uv_proof(mesh):
    return {name: NATIVE.signatures(mesh, name) for name in ('SourceUV','ConcreteUV','PaintUV')}


def uv_density(objects, size):
    densities=[]; top_uv_area=0.0; top_area=0.0
    for obj in objects:
        mesh=obj.data;mesh.calc_loop_triangles();uv=mesh.uv_layers[UV]
        for tri in mesh.loop_triangles:
            p=[mesh.vertices[i].co for i in tri.vertices]
            if tri.normal.z < .99 or min(v.z for v in p)<-.01201: continue
            area=(p[1]-p[0]).cross(p[2]-p[0]).length/2
            if area<1e-12: continue
            u=[uv.data[i].uv.copy() for i in tri.loops]
            uv_area=abs((u[1].x-u[0].x)*(u[2].y-u[0].y)-(u[1].y-u[0].y)*(u[2].x-u[0].x))/2
            assert uv_area>1e-14, 'Visible top triangle has collapsed delivery UV'
            densities.append(size*math.sqrt(uv_area/area));top_uv_area+=uv_area;top_area+=area
    assert densities
    densities.sort()
    return {'size':size,'visible_upward_area_m2':top_area,'upward_uv_area':top_uv_area,
            'texels_per_m_min':densities[0],'texels_per_m_median':densities[len(densities)//2],
            'texels_per_m_max':densities[-1], 'source_4m_repeat_pixels_median':4*densities[len(densities)//2]}


def checkpoint():
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'uv_checkpoint.blend'))
    bpy.context.view_layer.update()
    info=json.loads((HERE/'uv_checkpoint.json').read_text(encoding='utf-8'))
    assert info['source_sha256']==CFG['source_sha256']
    for key in CFG['groups']:
        assert NATIVE.packed_signature(group_parts(key))==info['groups'][key]['uv_sha256']
    return info


def prepare():
    assert not (HERE/'uv_checkpoint.blend').exists(), 'UV checkpoint already exists; do not regenerate.'
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/CFG['source']))
    bpy.context.view_layer.update()
    assert SOURCE.editable_signature()==CFG['source_geometry_uv_signature']
    originals=sorted((o for o in bpy.data.objects if o.type=='MESH' and o.get('export_piece')),key=lambda o:o.name)
    assert len(originals)==92
    materials={};copies=[]
    for obj in originals:
        copy=bpy.data.objects.new('Delivery_'+obj.name,obj.data.copy())
        bpy.context.scene.collection.objects.link(copy)
        copy['delivery_part']=True;copy['source_piece']=obj.name;copy['delivery_group']=group_of(obj.name)
        for i,mat in enumerate(copy.data.materials):
            if mat.name not in materials:
                materials[mat.name]=mat.copy();materials[mat.name].name='DELIVERY_AUTHOR_'+mat.name
            copy.data.materials[i]=materials[mat.name]
        copy.data.uv_layers.new(name=UV)
        copy.data.uv_layers.active_index=len(copy.data.uv_layers)-1
        copy.data.uv_layers[UV].active_render=True
        copies.append(copy)
    info={'source_sha256':CFG['source_sha256'],'groups':{},'scope':'UV preparation only, not final image quality proof'}
    for key,g in CFG['groups'].items():
        selected=group_parts(key);NATIVE.select(selected)
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.005)
        bpy.ops.object.mode_set(mode='OBJECT')
        for o in selected: o.data.calc_loop_triangles()
        assert sum(len(o.data.loop_triangles) for o in selected)==g['triangles']
        for o in selected:
            original=next(src for src in originals if src.name==o['source_piece'])
            assert source_uv_proof(original.data)==source_uv_proof(o.data), 'Source per-corner layers or geometry changed'
            assert all(math.isfinite(v) and 0<=v<=1 for u in o.data.uv_layers[UV].data for v in u.uv)
        info['groups'][key]={'uv_sha256':NATIVE.packed_signature(selected),'density':uv_density(selected,g['size'])}
    for obj in list(bpy.data.objects):
        if obj.type=='MESH' and not obj.get('delivery_part'): obj.hide_render=True
    for image in bpy.data.images:
        if image.source=='FILE' and image.filepath:
            image.filepath=str(Path(bpy.path.abspath(image.filepath)).resolve())
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'uv_checkpoint.blend'),relative_remap=False)
    save(HERE/'uv_checkpoint.json',info)
    checkpoint()
    print(json.dumps({'stage':'uv_prepared','groups':info['groups']}),flush=True)


def bake(key):
    info=checkpoint();folder=HERE/key
    folder.mkdir(exist_ok=True);(folder/'textures').mkdir(exist_ok=True)
    NATIVE.HERE=folder
    NATIVE.CFG={'source_sha256':CFG['source_sha256'],'size':CFG['groups'][key]['size'],
                'material':CFG['groups'][key]['material']}
    selected=group_parts(key)
    for obj in parts(): obj.hide_render=obj not in selected
    material,textures=NATIVE.bake(selected,info['groups'][key]['uv_sha256'])
    assert len(textures)==4
    save(folder/'completed.json',{'group':key,'material':material.name,'textures':textures,
        'source_sha256':CFG['source_sha256'],'uv_sha256':info['groups'][key]['uv_sha256'],
        'baked_blend_sha256':sha(folder/'baked_editable.blend')})


def export():
    info=checkpoint();destination=HERE/'east_maintenance_extension.glb'
    assert not destination.exists(), 'Completed GLB attempts are immutable.'
    selected=[];expected={};textures={}
    root=bpy.data.objects.new(CFG['root']+'_Delivery',None)
    bpy.context.scene.collection.objects.link(root);selected.append(root)
    author_root=bpy.data.objects.get(CFG['root'])
    if author_root: author_root.name='AUTHOR_ONLY_'+CFG['root']
    root.name=CFG['root']
    for key,g in CFG['groups'].items():
        completed=json.loads((HERE/key/'completed.json').read_text(encoding='utf-8'))
        assert completed['source_sha256']==CFG['source_sha256'] and completed['uv_sha256']==info['groups'][key]['uv_sha256']
        assert sha(HERE/key/'baked_editable.blend')==completed['baked_blend_sha256']
        for tex in completed['textures']: assert sha(Path(tex['path']))==tex['sha256']
        with bpy.data.libraries.load(str(HERE/key/'baked_editable.blend'),link=False) as (available,loaded):
            assert g['material'] in available.materials
            loaded.materials=[g['material']]
        material=loaded.materials[0]
        assert material.name==g['material']
        obj=NATIVE.merged_copy(group_parts(key),key)
        for layer in list(obj.data.uv_layers):
            if layer.name!=UV: obj.data.uv_layers.remove(layer)
        obj.data.uv_layers.active_index=0;obj.data.uv_layers[UV].active_render=True
        obj.data.materials.clear();obj.data.materials.append(material)
        for face in obj.data.polygons: face.material_index=0
        obj.parent=root;obj.matrix_basis=Matrix.Identity(4)
        expected[key]=NATIVE.signatures(obj.data);assert sum(expected[key][0].values())==g['triangles']
        selected.append(obj);textures[key]=completed['textures']
    NATIVE.select(selected)
    bpy.ops.export_scene.gltf(filepath=str(destination),export_format='GLB',use_selection=True,export_apply=True,
        export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,
        export_lights=False,export_animations=False,export_extras=False)
    j,actual,bb,images=NATIVE.read(destination)
    check('exact two meshes and source triangle count',set(actual)==set(CFG['groups']) and sum(sum(v['triangles'].values()) for v in actual.values())==CFG['triangles'])
    check('exact source local bounds',bb==CFG['local_bounds_godot'],bb)
    check('only three identity nodes and no author/context geometry',len(j['nodes'])==3 and {n['name'] for n in j['nodes']}=={CFG['root'],*CFG['groups']} and all(NATIVE.node_identity(n) for n in j['nodes']))
    index=next(i for i,n in enumerate(j['nodes']) if n['name']==CFG['root'])
    check('single identity root with two direct mesh children',j['scenes'][j.get('scene',0)]['nodes']==[index] and {j['nodes'][i]['name'] for i in j['nodes'][index].get('children',[])}==set(CFG['groups']))
    check('exact two standard opaque material names',len(j['materials'])==2 and {m['name'] for m in j['materials']}=={g['material'] for g in CFG['groups'].values()} and all(m.get('alphaMode','OPAQUE')=='OPAQUE' for m in j['materials']))
    for key,g in CFG['groups'].items():
        check(key+' exact actual triangle and UV0 multisets',actual[key]['triangles']==expected[key][0] and actual[key]['corner_uv']==expected[key][1])
        check(key+' one PBR surface and finite unit normals',len(actual[key]['surfaces'])==1 and all(s['material']==g['material'] and s['normals_unit'] and set(s['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'} for s in actual[key]['surfaces']))
        mat=next(m for m in j['materials'] if m['name']==g['material']);pbr=mat['pbrMetallicRoughness']
        roles={'BaseColor':pbr.get('baseColorTexture'),'MR':pbr.get('metallicRoughnessTexture'),'Normal':mat.get('normalTexture')}
        check(key+' all three texture roles use UV0',all(t and t.get('texCoord',0)==0 for t in roles.values()))
        if all(roles.values()):
            embedded={role:images[j['textures'][t['index']]['source']] for role,t in roles.items()}
            check(key+' exact native atlas dimensions',all(i['size']==[g['size']]*2 for i in embedded.values()),embedded)
            for role in ('BaseColor','Normal'):
                original=next(t for t in textures[key] if t['role']==role)
                check(key+' '+role+' original native bake bytes embedded',embedded[role]['sha256']==original['sha256'])
    check('six embedded PNG textures only',len(images)==6 and len(j['textures'])==6)
    check('no emission or unlit and no camera light animation',all('KHR_materials_unlit' not in m.get('extensions',{}) and m.get('emissiveFactor',[0,0,0])==[0,0,0] for m in j['materials']) and not j.get('cameras') and not j.get('animations') and not j.get('extensions',{}).get('KHR_lights_punctual'))
    report={'status':'BINARY_PASSED_AWAITING_SAME_BYTE_REIMPORT' if all(c['passed'] for c in CHECKS) else 'FAILED_RETAINED',
            'checks':CHECKS,'path':str(destination),'sha256':sha(destination),'bytes':destination.stat().st_size,
            'bounds':bb,'groups':CFG['groups'],'triangles':CFG['triangles'],'images':images,'textures':textures,
            'source_sha256':CFG['source_sha256'],'uv_density':{k:v['density'] for k,v in info['groups'].items()},
            'scope':'Only visual asset. No colliders, world geometry replacement, Godot or performance proof.'}
    save(HERE/'delivery_report.json',report)
    assert all(c['passed'] for c in CHECKS), 'Binary validation failed; preserve attempt.'
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'delivery_scene.blend'),relative_remap=False)


def preview():
    report=json.loads((HERE/'delivery_report.json').read_text(encoding='utf-8'))
    path=Path(report['path']);assert report['status']=='BINARY_PASSED_AWAITING_SAME_BYTE_REIMPORT' and sha(path)==report['sha256']
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    meshes=sorted((o for o in bpy.data.objects if o.type=='MESH'),key=lambda o:o.name)
    assert {o.name for o in meshes}==set(CFG['groups'])
    j,actual,bb,images=NATIVE.read(path)
    readback=[]
    vertices=[];faces=[]
    for obj in meshes:
        obj.data.calc_loop_triangles()
        expected=actual[obj.name]['triangles'];observed=collections.Counter()
        for tri in obj.data.loop_triangles:
            observed[NATIVE.canon([tuple(float(v) for v in (obj.data.vertices[i].co.x,obj.data.vertices[i].co.z,-obj.data.vertices[i].co.y)) for i in tri.vertices])]+=1
        readback.append({'mesh':obj.name,'actual_triangles':len(obj.data.loop_triangles),'same_triangles':observed==expected})
        offset=len(vertices);vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
        faces.extend(tuple(offset+i for i in t.vertices) for t in obj.data.loop_triangles)
    assert all(v['same_triangles'] for v in readback)
    tree=BVHTree.FromPolygons(vertices,faces,all_triangles=True);probes=[]
    for hole in CFG['body_holes']:
        a,b,c,d=hole['rect'];hit=tree.ray_cast(Vector(SOURCE.plan.bg(((a+b)/2,1,(c+d)/2))),Vector((0,0,-1)),2)[0]
        probes.append({'hole':hole['id'],'center_has_no_asset_surface':hit is None});assert hit is None
    for image in bpy.data.images:
        if image.type=='RENDER_RESULT': continue
        _pixels=image.pixels[:4];assert image.has_data
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'same_byte_reimport.blend'),relative_remap=False)
    camera=SOURCE.studio();report['reimport']=readback;report['reimport_holes']=probes;report['previews']=[]
    for name,target,offset,scale in [('01-glb-overview',(20.7,0,7),(13,18,16),22),('02-glb-holes-and-covers',(19.6,0,4.4),(8,10,9),9.5)]:
        SOURCE.aim(camera,target,offset,scale);out=HERE/(name+'.png');assert not out.exists()
        bpy.context.scene.render.filepath=str(out);bpy.ops.render.render(write_still=True)
        report['previews'].append({'path':str(out),'sha256':sha(out),'scope':'Same-byte GLB reimported into Blender; only new asset, no original north tiles or support proxies; not Godot.'})
    assert sha(path)==report['sha256']
    report['status']='DELIVERY_CANDIDATE_AWAITING_ROOT_GAME_REVIEW';save(HERE/'delivery_report.json',report)


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    assert len(args)==1 and args[0] in ('prepare','floor','inspection','export','preview')
    stage=args[0];verify();start=time.monotonic()
    print(json.dumps({'stage':stage,'pid':os.getpid(),'cpu_threads':2}),flush=True)
    if stage=='prepare': prepare()
    elif stage in ('floor','inspection'): bake('FloorSurface' if stage=='floor' else 'InspectionBand')
    elif stage=='export': export()
    else: preview()
    verify();print(json.dumps({'stage':stage,'finished':True,'pid':os.getpid(),'elapsed_seconds':time.monotonic()-start}),flush=True)


if __name__=='__main__': main()
