"""Four-post structure candidate. NEW REAL OBSTRUCTIONS, not the current layout. No runtime GLB or core writes.
Run only in an explicitly released Blender CPU2 window. Basic materials, not PBR approval.
The imagegen tank/deck proportions are not used as dimensions.
"""
from pathlib import Path
import sys, json, math, time, hashlib, os
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parents[4]
SRC = Path(__file__).resolve().parent
EVID = SRC / 'evidence'
WORLD_ORIGIN = Vector((-9.0, 6.0, -7.0))
LAYOUT_PATH = ROOT / 'data/v3/terrain/i2_clinic_layout.json'
LAYOUT_SHA = '4369c0a9c07a0517cb220c713ae0f5f31a3cbdecf063b15e49bb646c313ef6cd'
checks = []
asset_meshes = []
editable_parts = []

def check(name, ok, detail=None):
    checks.append({'name': name, 'passed': bool(ok), 'detail': detail})

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def bp(world):
    v = Vector(world) - WORLD_ORIGIN
    return Vector((v.x, -v.z, v.y))

def gp(local):
    return Vector((local.x, local.z, -local.y)) + WORLD_ORIGIN

def material(name, srgb, metallic=0.0, roughness=.65, alpha=1.0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in srgb)
    m.diffuse_color=(*linear,alpha)
    # Blender 5.2 may initialize a new material with an empty node tree.
    m.node_tree.nodes.clear()
    bs=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output=m.node_tree.nodes.new('ShaderNodeOutputMaterial')
    m.node_tree.links.new(bs.outputs['BSDF'],output.inputs['Surface'])
    bs.inputs['Base Color'].default_value=(*linear,1)
    bs.inputs['Metallic'].default_value=metallic
    bs.inputs['Roughness'].default_value=roughness
    bs.inputs['Alpha'].default_value=alpha
    return m

def mesh_obj(name, vertices, faces, collection, mats, indices=None, parent=None):
    me=bpy.data.meshes.new(name+'_Mesh')
    me.from_pydata([bp(v) for v in vertices],[],faces);me.update()
    o=bpy.data.objects.new(name,me);collection.objects.link(o);o.parent=parent
    for m in mats:me.materials.append(m)
    if indices:
        for f,i in zip(me.polygons,indices):f.material_index=i
    uv=me.uv_layers.new(name='SurfaceUV');me.uv_layers.active_index=0;uv.active_render=True
    # Basic planar UVs are placeholders for later authored atlas; no final PBR claim.
    for face in me.polygons:
        dominant=max(range(3),key=lambda a:abs(face.normal[a]));axes=[a for a in range(3) if a!=dominant]
        for li in face.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(co[axes[0]]/4.0,co[axes[1]]/4.0)
    o['source_world_origin']=list(WORLD_ORIGIN)
    return o

def box_geometry(lo,hi):
    x,y,z=lo;X,Y,Z=hi
    return [(x,y,z),(X,y,z),(X,Y,z),(x,Y,z),(x,y,Z),(X,y,Z),(X,Y,Z),(x,Y,Z)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]

def box(name,lo,hi,mats,indices=None,visible=True,collection=None,parent=None):
    vertices,faces=box_geometry(lo,hi)
    o=mesh_obj(name,vertices,faces,collection or source,mats,indices,parent=parent or root)
    o['world_min']=list(lo);o['world_max']=list(hi);o.hide_render=not visible
    if collection is None:
        editable_parts.append(o)
        if visible:asset_meshes.append(o)
    return o

def union_surface(solids):
    # Exact orthogonal union of only old deck/tongue/post/floor, eliminating internal
    # coincident source-box faces without moving the Y6 top or adding decorative caps.
    cuts=[sorted(set(float(b[k]) for s in solids for b in (s['min'],s['max']))) for k in range(3)]
    occupied=set()
    for i in range(len(cuts[0])-1):
        for j in range(len(cuts[1])-1):
            for k in range(len(cuts[2])-1):
                mid=[(cuts[a][n]+cuts[a][n+1])/2 for a,n in enumerate((i,j,k))]
                if any(all(s['min'][a]<mid[a]<s['max'][a] for a in range(3)) for s in solids):occupied.add((i,j,k))
    verts=[];faces=[];mi=[];lookup={}
    # Face order agrees with box_geometry, outward in Godot and Blender coordinates.
    neighbors=[(0,0,-1),(0,0,1),(0,-1,0),(0,1,0),(-1,0,0),(1,0,0)]
    for cell in sorted(occupied):
        lo=[cuts[a][cell[a]] for a in range(3)];hi=[cuts[a][cell[a]+1] for a in range(3)]
        vv,ff=box_geometry(lo,hi)
        for side,(face,offset) in enumerate(zip(ff,neighbors)):
            if tuple(cell[a]+offset[a] for a in range(3)) in occupied:continue
            ids=[]
            for vi in face:
                key=tuple(vv[vi])
                if key not in lookup:lookup[key]=len(verts);verts.append(key)
                ids.append(lookup[key])
            faces.append(ids)
            centre=[sum(vv[v][a] for v in face)/4 for a in range(3)]
            if side==3:
                inside_tank=-9.8<=centre[0]<=-8.2 and -7.5<=centre[2]<=-6.5
                mi.append(3 if inside_tank and centre[1]>5.8 else (1 if centre[1]>5.8 else 2))
            else:mi.append(2 if side==2 or centre[1]<.3 or 5.1<centre[1]<5.6 else 0)
    return mesh_obj('DeckAssembly_VisibleUnion',verts,faces,source,[blue,deck_mat,steel,ivory],mi,root)

def bounds(o):
    coords=[gp(o.matrix_world @ v.co) for v in o.data.vertices]
    return [[min(v[a] for v in coords) for a in range(3)],[max(v[a] for v in coords) for a in range(3)]]

def bvh(objects):
    verts=[];faces=[]
    for o in objects:
        off=len(verts);verts.extend([gp(o.matrix_world @ v.co) for v in o.data.vertices])
        faces.extend([tuple(off+i for i in f.vertices) for f in o.data.polygons])
    return BVHTree.FromPolygons(verts,faces,all_triangles=False)

def aim(o,target):
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

def run():
    global source,root,blue,deck_mat,steel,ivory
    started=time.time();EVID.mkdir(exist_ok=True)
    blend=SRC/'clinic_gravity_structure_v2.blend'
    assert not blend.exists(), 'Do not overwrite an existing study; archive/version intentionally.'
    layout=json.loads(LAYOUT_PATH.read_text(encoding='utf8'))
    assert digest(LAYOUT_PATH)==LAYOUT_SHA, 'Layout changed: re-read contract before constructing.'
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'outputs':str(SRC)},ensure_ascii=True),flush=True)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    source=bpy.data.collections.new('Editable_ClinicCistern_A');scene.collection.children.link(source)
    preview=bpy.data.collections.new('PREVIEW_ONLY_DO_NOT_EXPORT');scene.collection.children.link(preview)
    root=bpy.data.objects.new('ClinicCisternDeck',None);source.objects.link(root)
    root['godot_world_translation']=list(WORLD_ORIGIN);root['basis']='identity';root['stage']='proposed four-post structure, pending layout/physics acceptance; not runtime export'
    blue=material('CG_BluePaint_BASIC',(.18,.34,.37),.08,.62)
    deck_mat=material('CG_SolidDeck_BASIC',(.48,.50,.48),.06,.72)
    steel=material('CG_DullSteel_BASIC',(.25,.29,.29),.55,.55)
    ivory=material('CG_CleanIvoryLining_BASIC',(.80,.80,.73),0,.62)
    window=material('CG_ClearWindow_PREVIEW',(.76,.91,.91),0,.12,.12)
    water=material('CG_Water_PREVIEW_NOT_RUNTIME',(.14,.61,.67),0,.24,.67)
    solids={s['id']:s for s in layout['fixed_solids']}
    plan=json.loads((SRC/'structure_plan.json').read_text(encoding='utf8'))
    assert plan['static_conflicts']==0, 'Static conflict must be resolved before building.'
    assert digest(LAYOUT_PATH)==plan['source_hashes']['data/v3/terrain/i2_clinic_layout.json']
    solids.update({p['id']:p for p in plan['parts']})
    selected=[solids[n] for n in ['UpperWorkDeck','ValveWorkPad']]+plan['parts']
    floor={'id':'CisternFloor','min':[-9.92,5.88,-7.62],'max':[-8.08,6,-6.38]}
    for s in selected+[floor]:box(s['id'],s['min'],s['max'],[blue],visible=False)
    union=union_surface(selected+[floor]);asset_meshes.append(union)
    # The exposed 0.4m deck depth is a closed torsion-box form. Editable internal
    # web/diaphragm guides stay inside it and never become invisible collision props.
    structure=bpy.data.collections.new('INTERNAL_BOX_GIRDER_EDIT_GUIDES');scene.collection.children.link(structure)
    for n,x in enumerate([-11.2,-9.0,-6.3]):
        o=box('BoxGirderWeb_'+str(n),[x-.035,5.65,-9.85],[x+.035,5.95,-5.85],[steel],visible=False,collection=structure)
        o['construction_guide_only']=True
    for n,z in enumerate([-9.2,-7.0,-5.9]):
        o=box('BoxGirderDiaphragm_'+str(n),[-11.85,5.65,z-.035],[-5.15,5.95,z+.035],[steel],visible=False,collection=structure)
        o['construction_guide_only']=True
    # Side/rear walls preserve the exact original solids and inner opening.
    box('CisternLeftWall',[-9.92,6,-7.62],[-9.8,9,-6.38],[blue,ivory],[0,0,0,0,0,1])
    box('CisternRightWall',[-8.2,6,-7.62],[-8.08,9,-6.38],[blue,ivory],[0,0,0,0,1,0])
    box('CisternBackWall',[-9.8,6,-7.62],[-8.2,9,-7.5],[blue,ivory],[0,1,0,0,0,0])
    # Window and frame partition the old front wall, never intrude into the cavity.
    box('CisternFrontWindow',[-9.70,6.15,-6.50],[-8.30,8.85,-6.38],[window])
    for name,lo,hi in [
        ('FrontFrameLeft',[-9.8,6,-6.5],[-9.7,9,-6.38]),
        ('FrontFrameRight',[-8.3,6,-6.5],[-8.2,9,-6.38]),
        ('FrontFrameBottom',[-9.7,6,-6.5],[-8.3,6.15,-6.38]),
        ('FrontFrameTop',[-9.7,8.85,-6.5],[-8.3,9,-6.38])]:box(name,lo,hi,[blue])
    anchor=bpy.data.objects.new('SourceWaterBase',None);source.objects.link(anchor);anchor.parent=root
    anchor.location=(0,0,0);anchor['runtime_only_water_origin']=True
    water_preview=box('PreviewWater_3200L_NOT_EXPORT',[-9.797,6.002,-7.497],[-8.203,8,-6.503],[water],collection=preview,parent=None)
    water_preview.parent=None;water_preview['exclude_export']=True;water_preview['volume_litres_preview']=3200
    # Verify real generated vertices, not only the constants above.
    bpy.context.view_layer.update()
    checks.clear()
    check('layout SHA equals reviewed contract',digest(LAYOUT_PATH)==LAYOUT_SHA)
    check('source world translation fixed',list(WORLD_ORIGIN)==[-9,6,-7])
    for name in ['UpperWorkDeck','ValveWorkPad']+[p['id'] for p in plan['parts']]:
        o=bpy.data.objects[name];expected=[solids[name]['min'],solids[name]['max']];actual=bounds(o)
        check(name+' exact vertex bounds',max(abs(a-b) for aa,bb in zip(actual,expected) for a,b in zip(aa,bb))<2e-6,actual)
    allcoords=[gp(o.matrix_world@v.co) for o in asset_meshes for v in o.data.vertices]
    total=[[min(v[a] for v in allcoords) for a in range(3)],[max(v[a] for v in allcoords) for a in range(3)]]
    check('retained deck/tank overall range with new interior supports',max(abs(a-b) for aa,bb in zip(total,[[-12,0,-10],[-5,9,-4.4]]) for a,b in zip(aa,bb))<2e-6,total)
    check('four real posts replacing old eccentric single post',len([o for o in editable_parts if o.name.startswith('SupportLeg_')])==4 and 'UpperDeckLeg' not in bpy.data.objects)
    check('two real longitudinal box beams below deck',len([o for o in editable_parts if o.name.startswith('LongitudinalBeam_')])==2)
    check('SourceWaterBase local origin',anchor.location.length<1e-8)
    check('tank inner 1.6 by 3 by 1',layout['tanks']['I2:clean_cistern']['inner_size']==[1.6,3,1])
    check('glass retained inside old wall',all(-9.8-1e-6<=gp(v.co).x<=-8.2+1e-6 and 6<=gp(v.co).y<=9 and -6.5-1e-6<=gp(v.co).z<=-6.38+1e-6 for v in bpy.data.objects['CisternFrontWindow'].data.vertices))
    check('preview water separate from source root',water_preview.parent is None and water_preview.get('exclude_export',False))
    nav=bvh([union]);support_samples=[]
    for x,z in [(-11.5,-7),(-7,-9),(-5.3,-6),(-8,-5),(-6.3,-4.7),(-9,-7)]:
        hit=nav.ray_cast(Vector((x,6.2,z)),Vector((0,-1,0)),.5)
        support_samples.append({'xz':[x,z],'hit_y':None if hit[0] is None else float(hit[0].y)})
    check('real deck/tongue top rays hit Y6',all(s['hit_y'] is not None and abs(s['hit_y']-6)<2e-6 for s in support_samples),support_samples)
    tree=bvh(asset_meshes)
    check('unchanged actual open tank rim',all(tree.ray_cast(Vector((x,9.2,z)),Vector((0,-1,0)),.35)[0] is None for x in [-9.5,-9,-8.5] for z in [-7.3,-7,-6.7]))
    check('open underdeck route no new brace',tree.ray_cast(Vector((-8,3,-10.2)),Vector((0,0,1)),6.2)[0] is None)
    topology=[]
    for o in [union]+[o for o in editable_parts if not o.hide_render]:
        bm=bmesh.new();bm.from_mesh(o.data)
        topology.append({'name':o.name,'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'volume':abs(bm.calc_volume(signed=True))});bm.free()
    check('each actual solid closed',all(t['nonmanifold_edges']==0 and t['volume']>0 for t in topology),topology)
    check('reserved valve+bolt volume clear',all(not (max(bounds(o)[0][0],-8.6)<min(bounds(o)[1][0],-6.2) and max(bounds(o)[0][1],6.55)<min(bounds(o)[1][1],7.3) and max(bounds(o)[0][2],-5.5)<min(bounds(o)[1][2],-3.15)) for o in asset_meshes if o!=union))
    check('no runtime export attempted',True,'This script has no GLB exporter and writes only its source directory.')
    report={'status':'GEOMETRY_PENDING_RENDER' if all(c['passed'] for c in checks) else 'FAILED_BEFORE_RENDER','pid':os.getpid(),'layout_sha256':digest(LAYOUT_PATH),'world_origin':list(WORLD_ORIGIN),'actual_world_bounds':total,'checks':checks,'scope':'NEW four-post/foot/joint/beam blocking candidate; current shared layout unchanged. Closed edges and selected rays, NOT full self-intersection/structural load/FlightBody/Godot validation.','reference':'v3 only for I-B material/tank/deck; four-support structure explicitly authorized after v1 failure, not claimed to be in the generated image.', 'proposed_new_solids':plan['parts'], 'replace_existing':plan['replace_existing'],'water':'Preview collection only, runtime water remains independently controlled.'}
    (EVID/'structure_geometry_v2.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    if not all(c['passed'] for c in checks):raise RuntimeError('Basic geometry failed; kept editable failure blend/report, no render.')
    # A single complete basic-material image, not a game capture.
    studio=bpy.data.collections.new('STUDIO_ONLY_DO_NOT_EXPORT');scene.collection.children.link(studio)
    floor_mat=material('StudioNeutral',(.50,.52,.52),0,.85)
    box('StudioFloor',[-55,-.055,-55],[55,-.025,55],[floor_mat],collection=studio,parent=None)
    camera_data=bpy.data.cameras.new('BasicFormCamera');camera=bpy.data.objects.new('BasicFormCamera',camera_data);studio.objects.link(camera)
    target=bp((-8.55,4.3,-7.2));camera.location=target+Vector((32,-32,31))*.65;aim(camera,target)
    camera_data.type='ORTHO';camera_data.ortho_scale=13.6;scene.camera=camera
    for name,world,energy,size in [('Key',(-1,19,6),1800,10),('Fill',(-20,12,1),1000,12),('Rim',(-10,16,-18),1400,8)]:
        light_data=bpy.data.lights.new(name,'AREA');light_data.energy=energy;light_data.shape='DISK';light_data.size=size
        light=bpy.data.objects.new(name,light_data);studio.objects.link(light);light.location=bp(world);aim(light,target)
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.65,.68,.70,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
    bpy.context.view_layer.update()
    projected=[world_to_camera_view(scene,camera,bp(v)) for v in allcoords]
    check('all asset vertices fit complete image',all(.02<c.x<.98 and .02<c.y<.98 and c.z>0 for c in projected),{'projected_min':[min(c.x for c in projected),min(c.y for c in projected)],'projected_max':[max(c.x for c in projected),max(c.y for c in projected)]})
    report['checks']=checks
    if not checks[-1]['passed']:
        report['status']='FAILED_CAMERA_FIT_NO_RENDER';(EVID/'structure_geometry_v2.json').write_text(json.dumps(report,indent=2)+'\n');bpy.ops.wm.save_as_mainfile(filepath=str(blend));raise RuntimeError('Camera fit failed')
    image=EVID/'clinic_gravity_structure_v2.png';scene.render.image_settings.file_format='PNG';scene.render.filepath=str(image)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend));bpy.ops.render.render(write_still=True)
    report.update(status='STRUCTURAL_CANDIDATE_RENDERED_PENDING_ROOT_REVIEW',image=str(image),image_sha256=digest(image),blend_sha256=digest(blend),elapsed_seconds=time.time()-started,render_threads=2)
    (EVID/'structure_geometry_v2.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'checks':len(checks),'failed':sum(not c['passed'] for c in checks),'seconds':report['elapsed_seconds'],'image':str(image)},ensure_ascii=True),flush=True)

if __name__=='__main__':run()
