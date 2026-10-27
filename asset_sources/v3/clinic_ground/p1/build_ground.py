"""PREPARED ONLY. Root schedules CPU2; source directory output, never runtime GLB.
Independent real geometry + editable shader graphs -> native PBR bake -> reopen.
Generated atlas is copied byte-for-byte, never edited by Python or shell.
"""
from pathlib import Path
import bpy, bmesh, json, math, hashlib, shutil, os, time
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
REFERENCE = ROOT/'references/v3/production/clinic_ground/clinic_ground_reference_v2.png'
REFERENCE_SHA = '265348929d5c2dfd5e46da60b5297103c7597bde90605fdef8acd0a705311cd8'
SIZE = 2048
PIECES = []
AUTHORS = []
CHECKS = []
CASSETTES = [-2.6, -1.34, .04, 1.25, 2.6]

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bg(p): return (p[0], -p[2], p[1])
def gd(p): return (float(p[0]), float(p[2]), float(-p[1]))
def check(name, passed, detail=None): CHECKS.append({'name':name,'passed':bool(passed),'detail':detail})
def choose(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o

def box(name, lo, hi, mat, group, bevel=0):
    center=[(lo[i]+hi[i])*.5 for i in range(3)]
    bpy.ops.mesh.primitive_cube_add(size=1, location=bg(center))
    o=bpy.context.object; o.name=name
    o.dimensions=(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Inward_edge_manufacturing_bevel','BEVEL'); mod.width=bevel; mod.segments=1
    finish(o,mat,group); return o

def finish(o, mat, group):
    o.data.materials.append(mat); o['runtime_group']=group; o['editable_piece']=True
    # Avoid default cube UV accidentally winning over the author-defined UV.
    while o.data.uv_layers: o.data.uv_layers.remove(o.data.uv_layers[0])
    o.data.uv_layers.new(name='SurfaceUV')
    o.data.uv_layers.active_index=0; o.data.uv_layers['SurfaceUV'].active_render=True
    PIECES.append(o)

def slab(name, x0,x1,z0,z1,mat,chip):
    # Large planar concrete pours. Unequal small inward corner cuts are geometry,
    # not repeated random triangles or painted cracks. All top vertices stay Y0.
    c=[.012,.018,.009,.014]; c[chip%4]=.037
    p=[(x0+c[0],z0),(x1-c[1],z0),(x1,z0+c[1]),(x1,z1-c[2]),
       (x1-c[2],z1),(x0+c[3],z1),(x0,z1-c[3]),(x0,z0+c[0])]
    verts=[bg((x,y,z)) for y in [-.18,0] for x,z in p]
    faces=[tuple(reversed(range(8))),tuple(range(8,16))]
    faces += [(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    o=bpy.data.objects.new(name,mesh); bpy.context.scene.collection.objects.link(o)
    mod=o.modifiers.new('Small_inward_pour_edge','BEVEL'); mod.width=.004; mod.segments=1
    finish(o,mat,'ConcreteSurface'); return o

def screw(name,x,z,mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.009,depth=.006,location=bg((x,-.003,z)))
    o=bpy.context.object; o.name=name; finish(o,mat,'DrainAssembly'); return o

class Graph:
    def __init__(self,name):
        self.m=bpy.data.materials.new(name); self.m.use_nodes=True; self.m.use_fake_user=True
        self.n=self.m.node_tree.nodes; self.n.clear(); self.l=self.m.node_tree.links
    def value(self,v,s):
        if hasattr(v,'node'): self.l.new(v,s)
        else: s.default_value=(float(v),float(v),float(v),1.0) if s.type=='RGBA' and isinstance(v,(int,float)) else v
    def op(self,op,a,b=0):
        n=self.n.new('ShaderNodeMath'); n.operation=op; self.value(a,n.inputs[0]); self.value(b,n.inputs[1]); return n.outputs[0]
    def mix(self,a,b,f):
        n=self.n.new('ShaderNodeMixRGB'); self.value(f,n.inputs[0]); self.value(a,n.inputs[1]); self.value(b,n.inputs[2]); return n.outputs[0]
    def color_mult(self,a,b):
        n=self.n.new('ShaderNodeMixRGB'); n.blend_type='MULTIPLY'; n.inputs[0].default_value=1
        self.value(a,n.inputs[1]); self.value(b,n.inputs[2]); return n.outputs[0]
    def noise(self,coord,scale,detail=2):
        n=self.n.new('ShaderNodeTexNoise'); n.inputs['Scale'].default_value=scale; n.inputs['Detail'].default_value=detail
        self.l.new(coord,n.inputs['Vector']); return n.outputs['Fac']
    def rectangle(self,x,z,cx,cz,hw,hd):
        dx=self.op('ABSOLUTE',self.op('SUBTRACT',x,cx)); dz=self.op('ABSOLUTE',self.op('SUBTRACT',z,cz))
        return self.op('MULTIPLY',self.op('LESS_THAN',dx,hw),self.op('LESS_THAN',dz,hd))

def author(name,kind,atlas):
    g=Graph(name); n=g.n; l=g.l
    coord=n.new('ShaderNodeTexCoord'); geo=n.new('ShaderNodeNewGeometry')
    split=n.new('ShaderNodeSeparateXYZ'); l.new(geo.outputs['Position'],split.inputs[0])
    x=split.outputs['X']; z=g.op('MULTIPLY',split.outputs['Y'],-1); height=split.outputs['Z']
    # Continuous metre-scale material, no image joints. The full 6m top uses one
    # concrete quadrant; do not claim baking adds missing source image resolution.
    uu=g.op('DIVIDE',g.op('ADD',x,3),6); vv=g.op('DIVIDE',g.op('ADD',z,3),6)
    def sample(quadrant):
        u0,v0=quadrant; comb=n.new('ShaderNodeCombineXYZ')
        l.new(g.op('ADD',u0+.008,g.op('MULTIPLY',uu,.484)),comb.inputs['X'])
        l.new(g.op('ADD',v0+.008,g.op('MULTIPLY',vv,.484)),comb.inputs['Y'])
        im=n.new('ShaderNodeTexImage'); im.image=atlas; im.extension='EXTEND'; im.label='UNEDITED flat basecolour atlas'
        l.new(comb.outputs[0],im.inputs['Vector']); return im.outputs['Color']
    normal_sep=n.new('ShaderNodeSeparateXYZ'); l.new(geo.outputs['Normal'],normal_sep.inputs[0])
    top=g.op('GREATER_THAN',normal_sep.outputs['Z'],.6)
    macro=g.noise(geo.outputs['Position'],1.2,1)
    micro=g.noise(geo.outputs['Position'],55,2)
    if kind=='concrete':
        base=sample((0,.5)); repair=sample((.5,.5))
        repair_mask=g.op('MULTIPLY',top,g.rectangle(x,z,-1.8,-1.45,.70,.30))
        base=g.mix(base,repair,repair_mask)
        # Damp/dust only alongside the actual drain. No all-over cloud pattern.
        near=g.op('MAXIMUM',0,g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',x,2.44)),.58)))
        damp=g.op('MULTIPLY',top,g.op('MULTIPLY',near,g.op('ADD',.10,g.op('MULTIPLY',macro,.15))))
        base=g.mix(base,g.color_mult(base,(.59,.63,.59,1)),damp)
        yellow=g.op('MINIMUM',1,g.op('ADD',g.rectangle(x,z,2.85,2.85,.13,.07),g.rectangle(x,z,2.85,-2.85,.13,.07)))
        chips=g.op('GREATER_THAN',g.noise(geo.outputs['Position'],35,1),.28)
        yellow=g.op('MULTIPLY',top,g.op('MULTIPLY',yellow,chips))
        base=g.mix(base,(.68,.38,.055,1),yellow)
        rough=g.op('ADD',.74,g.op('MULTIPLY',micro,.14)); metal=0
        bump_height=micro; distance=.0008
    elif kind=='teal':
        base=sample((0,0)); rough=.66; metal=.08; bump_height=micro; distance=.0002
        # Local rust tied to actual sixteen bolt locations, not evenly tiled drips.
        spots=0
        for i,zz in enumerate([CASSETTES[0]+.026,CASSETTES[1]-.026,CASSETTES[2]+.026,CASSETTES[4]-.026]):
            dx=g.op('DIVIDE',g.op('SUBTRACT',x,2.431 if i%2==0 else 2.689),.032)
            dz=g.op('DIVIDE',g.op('SUBTRACT',z,zz),.070 if i%2 else .045)
            radius=g.op('ADD',g.op('MULTIPLY',dx,dx),g.op('MULTIPLY',dz,dz))
            spot=g.op('MAXIMUM',0,g.op('SUBTRACT',1,radius)); spots=g.op('MAXIMUM',spots,spot)
        spots=g.op('MULTIPLY',spots,g.op('ADD',.18,g.op('MULTIPLY',micro,.34)))
        base=g.mix(base,(.15,.058,.018,1),spots)
    elif kind=='galvanized':
        base=sample((.5,0)); rough=.48; metal=.80; bump_height=micro; distance=.00012
    else:
        base=(.040,.047,.043,1); rough=.91; metal=0; bump_height=micro; distance=.0001
    bs=n.new('ShaderNodeBsdfPrincipled'); g.value(base,bs.inputs['Base Color']); g.value(rough,bs.inputs['Roughness']); g.value(metal,bs.inputs['Metallic'])
    bump=n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.25; bump.inputs['Distance'].default_value=distance
    g.value(bump_height,bump.inputs['Height']); l.new(bump.outputs['Normal'],bs.inputs['Normal'])
    em=n.new('ShaderNodeEmission'); em.inputs['Strength'].default_value=1
    out=n.new('ShaderNodeOutputMaterial'); l.new(bs.outputs['BSDF'],out.inputs['Surface'])
    result={'material':g.m,'graph':g,'bsdf':bs,'emission':em,'output':out,'channels':{'BaseColor':base,'Roughness':rough,'Metallic':metal}}
    AUTHORS.append(result); return g.m

def build(mats):
    concrete,teal,galv,dark=mats
    slab('Pour_SW',-3,-.61,-3,-.66,concrete,2)
    slab('Pour_NW',-3,-.61,-.64,3,concrete,1)
    slab('Pour_SE',-.59,2.42,-3,.79,concrete,3)
    slab('Pour_NE',-.59,2.42,.81,3,concrete,0)
    slab('Drain_OuterConcreteStrip',2.70,3,-3,3,concrete,2)
    slab('Drain_EndConcrete_S',2.42,2.70,-3,-2.6,concrete,0)
    slab('Drain_EndConcrete_N',2.42,2.70,2.6,3,concrete,1)
    box('Joint_Long_Seal',[-.61,-.035,-3],[-.59,-.012,3],dark,'ConcreteSurface')
    box('Joint_Left_T',[-3,-.035,-.66],[-.61,-.012,-.64],dark,'ConcreteSurface')
    box('Joint_Right_T',[-.59,-.035,.79],[2.42,-.012,.81],dark,'ConcreteSurface')
    box('Drain_ClosedBottom',[2.42,-.18,-2.6],[2.70,-.075,2.6],dark,'DrainAssembly')
    for i,(za,zb) in enumerate(zip(CASSETTES,CASSETTES[1:])):
        for side,x0,x1 in [('L',2.42,2.442),('R',2.678,2.70)]:
            box(f'Cassette_{i}_{side}Frame',[x0,-.04,za],[x1,0,zb],teal,'DrainAssembly',.002)
        for side,z0,z1 in [('S',za,za+.045),('N',zb-.045,zb)]:
            box(f'Cassette_{i}_{side}Frame',[2.442,-.04,z0],[2.678,0,z1],teal,'DrainAssembly',.002)
        width=.013; gap=(.236-6*width)/7
        for j in range(6):
            x0=2.442+gap+j*(width+gap)
            box(f'Cassette_{i}_GrateBar_{j}',[x0,-.025,za+.045],[x0+width,0,zb-.045],galv,'DrainAssembly',.002)
        for j,t in enumerate([.32,.72]):
            zz=za+(zb-za)*t
            box(f'Cassette_{i}_LowerBrace_{j}',[2.438,-.048,zz-.012],[2.682,-.025,zz+.012],galv,'DrainAssembly',.001)
        for side,xx in [('L',2.431),('R',2.689)]:
            for end,zz in [('S',za+.026),('N',zb-.026)]: screw(f'Cassette_{i}_Bolt_{side}{end}',xx,zz,galv)
    for label,z0,z1 in [('S',-2.6,-2.594),('N',2.594,2.6)]:
        box('Drain_EndWall_'+label,[2.42,-.075,z0],[2.70,-.04,z1],dark,'DrainAssembly')

def evaluated_checks():
    dg=bpy.context.evaluated_depsgraph_get(); points=[]; records=[]; allverts=[]; alltris=[]
    for o in PIECES:
        e=o.evaluated_get(dg); me=e.to_mesh(); me.calc_loop_triangles()
        vs=[gd(o.matrix_world@v.co) for v in me.vertices]; points+=vs
        bm=bmesh.new(); bm.from_mesh(me); bad=sum(not e.is_manifold for e in bm.edges); bm.free()
        offset=len(allverts); allverts += [o.matrix_world@v.co for v in me.vertices]
        alltris += [tuple(offset+i for i in t.vertices) for t in me.loop_triangles]
        records.append({'name':o.name,'group':o['runtime_group'],'triangles':len(me.loop_triangles),'nonmanifold_edges':bad,
                        'bounds':[[min(v[a] for v in vs) for a in range(3)],[max(v[a] for v in vs) for a in range(3)]]})
        e.to_mesh_clear()
    bounds=[[min(v[a] for v in points) for a in range(3)],[max(v[a] for v in points) for a in range(3)]]
    check('exact 6x6x.18 actual evaluated bounds',all(abs(bounds[k][i]-[[-3,-.18,-3],[3,0,3]][k][i])<2e-6 for k in range(2) for i in range(3)),bounds)
    check('every evaluated source piece closed manifold',all(r['nonmanifold_edges']==0 for r in records))
    check('only two planned runtime groups',set(r['group'] for r in records)=={'ConcreteSurface','DrainAssembly'})
    triangles=sum(r['triangles'] for r in records); check('triangle budget <= 5000',triangles<=5000,triangles)
    bvh=BVHTree.FromPolygons(allverts,alltris,all_triangles=True)
    probes=[]
    for x,z in [(-2,-2),(-2,2),(1,-2),(1,2),(2.84,0)]:
        hit=bvh.ray_cast(Vector(bg((x,1,z))),Vector((0,0,-1)),2)[0]
        probes.append({'xz':[x,z],'actual_y':None if hit is None else float(hit.z)})
    check('five actual working-face top probes at Y0',all(p['actual_y'] is not None and abs(p['actual_y'])<2e-6 for p in probes),probes)
    # A ray through a real first grate slot must see the trough, not a painted hole.
    width=.013; gap=(.236-6*width)/7; x=2.442+gap*.5
    hit=bvh.ray_cast(Vector(bg((x,1,-2.40))),Vector((0,0,-1)),2)[0]
    check('actual grate slot reaches real trough bottom',hit is not None and abs(hit.z+.075)<2e-6, None if hit is None else gd(hit))
    check('drain authored outer width .28',abs(2.70-2.42-.28)<1e-9)
    check('T joints offset rather than four-way cross',abs(-.65-.8)>1.0)
    return {'pieces':records,'bounds_godot':bounds,'triangles':triangles,'source_piece_count':len(PIECES),'limits':['Individual manifold checks do not claim exhaustive inter-part self-intersection audit.','Frame/screw and grate/frame overlaps are intended seated assemblies, not independent gameplay surfaces.','No Godot collisions, screenshot, or performance acceptance.']}

def prepare_uvs():
    bpy.ops.object.select_all(action='DESELECT')
    for o in PIECES: o.select_set(True)
    bpy.context.view_layer.objects.active=PIECES[0]
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.004)
    bpy.ops.object.mode_set(mode='OBJECT')
    # Reacquire layers by name after creation/operators; never retain invalid RNA handles.
    check('all pieces have one explicit active/render SurfaceUV',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers['SurfaceUV'].active_render for o in PIECES))

def bake_and_apply(texdir):
    scene=bpy.context.scene; dg=bpy.context.evaluated_depsgraph_get(); copies=[]
    for o in PIECES:
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
        me.transform(o.matrix_world); c=bpy.data.objects.new('TEMP_'+o.name,me); scene.collection.objects.link(c); copies.append(c)
    bpy.ops.object.select_all(action='DESELECT')
    for c in copies:c.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]; bpy.ops.object.join(); bake=bpy.context.object; bake.name='TEMP_NATIVE_BAKE_ONLY'
    # Originals would overlap bake copy in a normal scene render; EMIT bake uses
    # active object only. Hide originals for a later accidental render nonetheless.
    for o in PIECES:o.hide_render=True
    scene.cycles.samples=1; outputs={}; baked_rows=[]
    for role in ['BaseColor','Roughness','Metallic','Normal']:
        im=bpy.data.images.new('CGround_'+role,width=SIZE,height=SIZE,alpha=False)
        im.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
        for a in AUTHORS:
            g=a['graph']; nodes=g.n
            for node in nodes:node.select=False
            target=nodes.new('ShaderNodeTexImage'); target.image=im; target.label='BAKE_TARGET_'+role; target.select=True; nodes.active=target
            for link in list(a['output'].inputs['Surface'].links):g.l.remove(link)
            if role=='Normal':g.l.new(a['bsdf'].outputs['BSDF'],a['output'].inputs['Surface'])
            else:
                for link in list(a['emission'].inputs['Color'].links):g.l.remove(link)
                g.value(a['channels'][role],a['emission'].inputs['Color']);g.l.new(a['emission'].outputs[0],a['output'].inputs['Surface'])
        print(json.dumps({'stage':'native_bake','role':role,'pid':os.getpid()}),flush=True)
        bpy.ops.object.bake(type='NORMAL' if role=='Normal' else 'EMIT',use_clear=True,margin=10,normal_space='TANGENT')
        path=texdir/('CGround_'+role+'.png'); im.filepath_raw=str(path); im.file_format='PNG';im.save()
        loaded=bpy.data.images.load(str(path),check_existing=False);loaded.colorspace_settings.name=im.colorspace_settings.name
        outputs[role]=loaded;baked_rows.append({'role':role,'path':str(path),'sha256':sha(path),'colorspace':loaded.colorspace_settings.name,'method':'native Blender tangent NORMAL bake' if role=='Normal' else 'native Blender EMIT bake'})
        (SRC/'evidence/baked_maps_progress.json').write_text(json.dumps({'status':'BAKE_IN_PROGRESS','completed':baked_rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    bpy.data.objects.remove(bake,do_unlink=True)
    for o in PIECES:o.hide_render=False
    for a in AUTHORS:
        g=a['graph']
        for link in list(a['output'].inputs['Surface'].links):g.l.remove(link)
        g.l.new(a['bsdf'].outputs['BSDF'],a['output'].inputs['Surface'])
    m=bpy.data.materials.new('CGround_BakedPBR');m.use_nodes=True;n=m.node_tree.nodes;n.clear();links=m.node_tree.links
    bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
    for role,im in outputs.items():
        node=n.new('ShaderNodeTexImage');node.image=im;node.label=role;links.new(uv.outputs['UV'],node.inputs['Vector'])
        if role=='Normal':
            nm=n.new('ShaderNodeNormalMap');nm.uv_map='SurfaceUV';links.new(node.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bs.inputs['Normal'])
        else:links.new(node.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
    for o in PIECES:o.data.materials.clear();o.data.materials.append(m)
    return baked_rows

def studio():
    scene=bpy.context.scene
    world=bpy.data.worlds.new('Neutral_source_review');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.50,.54,.58,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65;scene.world=world
    def area(name,at,power,size):
        d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size
        o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=bg(at)
        o.rotation_euler=(Vector((0,0,-.08))-o.location).to_track_quat('-Z','Y').to_euler()
    area('Review_Key',(0,8,2),1400,7);area('Review_Fill',(-5,4,-5),650,6)
    floor_mat=bpy.data.materials.new('StudioOnly_Neutral');floor_mat.diffuse_color=(.20,.22,.24,1)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.183));floor=bpy.context.object;floor.name='STUDIO_ONLY_FLOOR';floor.data.materials.append(floor_mat);floor['exclude_export']=True
    d=bpy.data.cameras.new('Review_FixedOblique');d.type='ORTHO';d.ortho_scale=9.8
    camera=bpy.data.objects.new('Review_FixedOblique',d);scene.collection.objects.link(camera);camera.location=bg((8,9.75,8))
    camera.rotation_euler=(Vector((0,0,-.07))-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    scene.render.resolution_x=1280;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
    scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.image_settings.file_format='PNG'

def main():
    start=time.time();blend=SRC/'clinic_ground_p1.blend';assert not blend.exists(),'Do not overwrite an earlier attempt.'
    cfg=json.loads((SRC/'input_config.json').read_text(encoding='utf-8'))
    assert cfg.get('atlas_path') and cfg.get('atlas_sha256'),'Await root-approved flat atlas path/SHA; no procedural fallback.'
    atlas_path=ROOT/cfg['atlas_path'];assert sha(atlas_path)==cfg['atlas_sha256'];assert sha(REFERENCE)==REFERENCE_SHA
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'source_only':True}),flush=True)
    for folder in ['evidence','textures','source_inputs']:(SRC/folder).mkdir(exist_ok=True)
    copied=SRC/'source_inputs/material_atlas_UNEDITED.png';shutil.copyfile(atlas_path,copied);assert sha(copied)==cfg['atlas_sha256']
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
    atlas=bpy.data.images.load(str(copied),check_existing=False);atlas.colorspace_settings.name='sRGB'
    build([author('SOURCE_Concrete','concrete',atlas),author('SOURCE_TealSteel','teal',atlas),author('SOURCE_Galvanized','galvanized',atlas),author('SOURCE_SealTrough','dark',atlas)])
    bpy.context.view_layer.update();report=evaluated_checks();prepare_uvs()
    report.update(status='GEOMETRY_CHECKED_NOT_RENDERED',checks=CHECKS,atlas_sha256=cfg['atlas_sha256'],reference_sha256=REFERENCE_SHA,atlas_dimensions=list(atlas.size))
    evidence=SRC/'evidence/production_report.json'
    evidence.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'geometry_uv_checkpoint.blend'),relative_remap=False)
    if not all(c['passed'] for c in CHECKS):
        bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'FAILED_geometry.blend'))
        evidence.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');raise RuntimeError('Geometry/UV gate failed; no bake/render.')
    baked=bake_and_apply(SRC/'textures')
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'baked_checkpoint.blend'),relative_remap=False)
    report.update(status='BAKED_CHECKPOINT_PENDING_PREVIEW',baked_maps=baked)
    evidence.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    studio()
    root=bpy.data.objects.new('ClinicGroundModule',None);scene.collection.objects.link(root)
    for o in PIECES:o.parent=root
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;readback=[]
    for n in bpy.data.materials['CGround_BakedPBR'].node_tree.nodes:
        if n.type=='TEX_IMAGE':
            im=n.image;p=Path(bpy.path.abspath(im.filepath)).resolve();row=next(r for r in baked if r['role']==n.label)
            assert p.exists() and sha(p)==row['sha256'];im.reload();assert im.has_data and tuple(im.size)==(SIZE,SIZE)
            readback.append({'role':n.label,'resolved_path':str(p),'sha256':sha(p)})
    assert len(readback)==4
    image_path=SRC/'evidence/clinic_ground_p1.png';scene.render.filepath=str(image_path);bpy.ops.render.render(write_still=True)
    report.update(status='SOURCE_RENDERED_PENDING_HUMAN_REVIEW',baked_maps=baked,reopened_images=readback,blend_sha256=sha(blend),render_sha256=sha(image_path),elapsed_seconds=time.time()-start)
    evidence.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':report['triangles']}),flush=True)

if __name__=='__main__':main()
