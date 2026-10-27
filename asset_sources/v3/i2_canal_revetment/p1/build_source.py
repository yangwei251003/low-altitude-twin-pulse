"""Source-only revetment P1. Run only in root's assigned CPU2 window.
Reuses approved clinic-ground P2 atlas scale/color handling, not its geometry.
No bake, GLB, runtime modification or perspective-reference projection.
"""
from pathlib import Path
import bpy, bmesh, math, json, hashlib, os, time
from mathutils import Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
ATLAS=HERE/'source_inputs/clinic_ground_material_atlas_UNEDITED.png'
ATLAS_SHA='11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406'
REFERENCE=ROOT/'references/v3/production/i2_canal_revetment/i2_canal_revetment_reference_v1.png'
REFERENCE_SHA='8b1d536a88ac17014dfa8ae0ad0abbe9112489ec7bb801146ce037a2b3e04a3d'
FIXINGS=[(-1.55,-.65),(.38,-.89)]
PARTS=[]

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return Vector((p[0],p[2],-p[1]))
def dump(p,value): Path(p).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

class Graph:
    # Small explicit-node helper adapted from frozen clinic_ground/p1.
    def __init__(self,name):
        self.m=bpy.data.materials.new(name);self.m.use_nodes=True
        self.n=self.m.node_tree.nodes;self.n.clear();self.l=self.m.node_tree.links
    def val(self,v,s):
        if hasattr(v,'node'):self.l.new(v,s)
        else:s.default_value=(v,v,v,1) if s.type=='RGBA' and isinstance(v,(float,int)) else v
    def op(self,op,a,b=0):
        n=self.n.new('ShaderNodeMath');n.operation=op;self.val(a,n.inputs[0]);self.val(b,n.inputs[1]);return n.outputs[0]
    def mix(self,a,b,f):
        n=self.n.new('ShaderNodeMixRGB');self.val(f,n.inputs[0]);self.val(a,n.inputs[1]);self.val(b,n.inputs[2]);return n.outputs[0]
    def mult(self,a,b):
        n=self.n.new('ShaderNodeMixRGB');n.blend_type='MULTIPLY';n.inputs[0].default_value=1;self.val(a,n.inputs[1]);self.val(b,n.inputs[2]);return n.outputs[0]
    def clamp(self,a):return self.op('MINIMUM',1,self.op('MAXIMUM',0,a))
    def noise(self,vec,scale,detail=1):
        n=self.n.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=scale;n.inputs['Detail'].default_value=detail;self.l.new(vec,n.inputs['Vector']);return n.outputs['Fac']

def material(name,kind,atlas,offset=0):
    g=Graph(name);n=g.n;l=g.l
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceMetric';sep=n.new('ShaderNodeSeparateXYZ');l.new(uv.outputs['UV'],sep.inputs[0])
    u,v=sep.outputs['X'],sep.outputs['Y']
    ah=n.new('ShaderNodeAttribute');ah.attribute_name='SourceHeight';h=ah.outputs['Fac']
    ax=n.new('ShaderNodeAttribute');ax.attribute_name='SourceX';x=ax.outputs['Fac']
    af=n.new('ShaderNodeAttribute');af.attribute_name='WaterFacing';front=af.outputs['Fac']
    macro=g.noise(uv.outputs[0],3.2);micro=g.noise(uv.outputs[0],48,2)
    def sample(quadrant,scale=1.8,shift=0):
        comb=n.new('ShaderNodeCombineXYZ')
        for socket,value,start,delta in [(comb.inputs['X'],u,quadrant[0],.13+offset+shift),(comb.inputs['Y'],v,quadrant[1],.39+shift)]:
            mirrored=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',value,scale),delta),1)
            g.val(g.op('ADD',start+.008,g.op('MULTIPLY',mirrored,.484)),socket)
        tex=n.new('ShaderNodeTexImage');tex.image=atlas;tex.extension='EXTEND';tex.label='Unedited flat atlas; 1.8m metric patch, source1254px'
        l.new(comb.outputs[0],tex.inputs['Vector']);return tex.outputs['Color']
    if kind=='concrete':
        # Grey finer-trowel quadrant; P2-scale 1.8m keeps aggregate small.
        base=g.mix((.33,.315,.285,1),sample((.5,.5)),.70)
        repair_radius=g.op('ADD',g.op('POWER',g.op('DIVIDE',g.op('SUBTRACT',x,1.43),.40),2),g.op('POWER',g.op('DIVIDE',g.op('ADD',h,1.70),.49),2))
        repair=g.clamp(g.op('MULTIPLY',g.op('SUBTRACT',g.op('ADD',.95,g.op('MULTIPLY',macro,.18)),repair_radius),7))
        base=g.mix(base,g.mix((.31,.30,.275,1),sample((0,.5),1.8,.23),.48),g.op('MULTIPLY',repair,front))
        # Height controls a broad continuous damp region; macro only breaks its
        # narrow tide edge by +/-18mm, not whole-wall random cloud tint.
        water_edge=g.op('ADD',-1.2,g.op('MULTIPLY',g.op('SUBTRACT',macro,.5),.036))
        wet=g.clamp(g.op('ADD',.5,g.op('MULTIPLY',g.op('SUBTRACT',water_edge,h),12)))
        depth=g.clamp(g.op('DIVIDE',g.op('SUBTRACT',-1.2,h),1.6))
        damp=g.op('MULTIPLY',wet,g.op('ADD',.66,g.op('MULTIPLY',depth,.23)))
        base=g.mix(base,g.mult(base,(.43,.54,.54,1)),damp)
        salt=g.clamp(g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',h,water_edge)),.035)))
        salt=g.op('MULTIPLY',salt,g.clamp(g.op('MULTIPLY',g.op('SUBTRACT',macro,.39),3)))
        base=g.mix(base,(.43,.425,.36,1),g.op('MULTIPLY',salt,.50))
        rust=0
        for i,(fx,fy) in enumerate(FIXINGS):
            down=g.op('SUBTRACT',fy-.10,h);length=.66 if i==0 else .90
            run=g.op('MULTIPLY',g.op('GREATER_THAN',down,0),g.clamp(g.op('SUBTRACT',1,g.op('DIVIDE',down,length))))
            drift=g.op('ADD',fx,g.op('MULTIPLY',g.op('SUBTRACT',macro,.5),.018))
            width=g.op('MULTIPLY',.040 if i==0 else .055,g.op('ADD',.30,g.op('MULTIPLY',run,.70)))
            strip=g.clamp(g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',x,drift)),width)))
            rust=g.op('MAXIMUM',rust,g.op('MULTIPLY',strip,run))
        base=g.mix(base,(.235,.12,.045,1),g.op('MULTIPLY',front,g.op('MULTIPLY',rust,.58)))
        algae=g.op('MULTIPLY',g.clamp(g.op('DIVIDE',g.op('SUBTRACT',-2.18,h),.5)),g.clamp(g.op('MULTIPLY',g.op('SUBTRACT',macro,.34),1.8)))
        base=g.mix(base,g.mult(base,(.64,.74,.53,1)),g.op('MULTIPLY',algae,.45))
        rough=g.op('SUBTRACT',g.op('ADD',.82,g.op('MULTIPLY',micro,.09)),g.op('MULTIPLY',wet,.20));metal=0;distance=.0007
    elif kind=='paint':
        base=g.mix((.025,.075,.079,1),sample((0,0),.7),.72);rough=.68;metal=.08;distance=.00015
    elif kind=='metal':
        base=(.19,.21,.205,1);rough=.46;metal=1;distance=.00008
    else:
        base=(.075,.08,.074,1);rough=.93;metal=0;distance=.0002
    bs=n.new('ShaderNodeBsdfPrincipled');g.val(base,bs.inputs['Base Color']);g.val(rough,bs.inputs['Roughness']);g.val(metal,bs.inputs['Metallic'])
    bs.inputs['Emission Color'].default_value=(0,0,0,1);bs.inputs['Emission Strength'].default_value=0
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.20;bump.inputs['Distance'].default_value=distance;g.val(micro,bump.inputs['Height']);l.new(bump.outputs['Normal'],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs['BSDF'],out.inputs['Surface'])
    g.m['source_only_unbaked']=True;g.m['reference_texture_not_projected']=True
    return g.m

def finish(obj,mats,bevel=0):
    for m in mats:obj.data.materials.append(m)
    while obj.data.uv_layers:obj.data.uv_layers.remove(obj.data.uv_layers[0])
    obj.data.uv_layers.new(name='SurfaceMetric');obj.data.uv_layers.active_index=0
    for name in ['SourceHeight','SourceX','WaterFacing']:obj.data.attributes.new(name,'FLOAT','CORNER')
    # Attribute allocation can invalidate prior RNA layer handles: reacquire.
    uv=obj.data.uv_layers['SurfaceMetric'];uv.active_render=True
    attrs={name:obj.data.attributes[name] for name in ['SourceHeight','SourceX','WaterFacing']}
    for poly in obj.data.polygons:
        norm=gp(poly.normal);axis=max(range(3),key=lambda i:abs(norm[i]))
        for li in poly.loop_indices:
            point=gp(obj.matrix_world@obj.data.vertices[obj.data.loops[li].vertex_index].co)
            uv.data[li].uv=(point.x,point.y) if axis==2 else (point.z,point.y) if axis==0 else (point.x,point.z)
            attrs['SourceHeight'].data[li].value=point.y;attrs['SourceX'].data[li].value=point.x;attrs['WaterFacing'].data[li].value=max(0,norm.z)
    if bevel:
        mod=obj.modifiers.new('Physical_inward_edge_bevel','BEVEL');mod.width=bevel;mod.segments=2;mod.limit_method='ANGLE';mod.angle_limit=.5;mod.use_clamp_overlap=True
    obj['editable_piece']=True;obj['runtime_group']='Revetment';PARTS.append(obj)

def body(mats):
    # One closed core with an explicit stepped front grid. Recesses are geometry,
    # no Boolean ambiguity, no coplanar decorative box on the water-side plane.
    xs=sorted(set([-2,-1.10,-1.08,.78,.80,2]+[a+d for a,b in FIXINGS for d in [-.105,.105]]))
    ys=sorted(set([-2.8,-2.77,-.14,0]+[b+d for a,b in FIXINGS for d in [-.105,.105]]))
    verts=[];faces=[];indices=[];lookup={}
    def vertex(p):
        key=tuple(round(v,7) for v in p)
        if key not in lookup:lookup[key]=len(verts);verts.append(bp(p))
        return lookup[key]
    def face(ps,mat=0):faces.append(tuple(vertex(p) for p in ps));indices.append(mat)
    def dep(x,y):
        if any(abs(x-a)<.105 and abs(y-b)<.105 for a,b in FIXINGS):return -.035
        if -2.77<y<-.14 and (-1.10<x<-1.08 or .78<x<.80):return -.014
        return 0.0
    depths={}
    for i,(a,b) in enumerate(zip(xs,xs[1:])):
        for j,(c,d) in enumerate(zip(ys,ys[1:])):
            z=dep((a+b)/2,(c+d)/2);depths[i,j]=z
            zone=0 if (a+b)/2 < -1.09 else 1 if (a+b)/2 < .79 else 2
            face([(a,c,z),(b,c,z),(b,d,z),(a,d,z)],3 if z==-.014 else zone)
            face([(a,d,-.35),(b,d,-.35),(b,c,-.35),(a,c,-.35)],zone)
    ni=len(xs)-1;nj=len(ys)-1
    for i in range(ni):
        for j in range(nj):
            a,b=xs[i:i+2];c,d=ys[j:j+2];z=depths[i,j]
            if i+1<ni:
                other=depths[i+1,j]
                if other!=z:face([(b,c,z),(b,d,z),(b,d,other),(b,c,other)])
            if j+1<nj:
                other=depths[i,j+1]
                if other!=z:face([(a,d,z),(b,d,z),(b,d,other),(a,d,other)])
            if i==0:face([(a,c,-.35),(a,d,-.35),(a,d,z),(a,c,z)])
            if i==ni-1:face([(b,c,z),(b,d,z),(b,d,-.35),(b,c,-.35)])
            if j==0:face([(a,c,z),(b,c,z),(b,c,-.35),(a,c,-.35)])
            if j==nj-1:face([(a,d,-.35),(b,d,-.35),(b,d,z),(a,d,z)])
    me=bpy.data.meshes.new('ContinuousCore_SteppedRecessTopology');me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    obj=bpy.data.objects.new('ConcreteBody_4m_Closed',me);bpy.context.scene.collection.objects.link(obj)
    finish(obj,mats,.008)
    for polygon,idx in zip(me.polygons,indices):polygon.material_index=idx
    return obj

def box(name,at,size,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp(at));o=bpy.context.object;o.name=name;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);finish(o,[mat],.002);return o

def cylinder(name,x,y,z,r,depth,vertices,mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=bp((x,y,z)),rotation=(math.pi/2,0,0))
    o=bpy.context.object;o.name=name;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);finish(o,[mat],.0008);return o

def audit_images(label):
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        absolute=Path(bpy.path.abspath(im.filepath)).resolve()
        assert absolute.is_file(),f'{label} missing {im.name}: {absolute}'
        digest=sha(absolute);assert digest==ATLAS_SHA,(im.name,digest)
        im.reload();first=tuple(im.pixels[:4]);k=(int(im.size[0])*int(im.size[1])//2)*4;middle=tuple(im.pixels[k:k+4])
        assert len(first)==4 and len(middle)==4 and im.has_data and min(im.size)>0,(im.name,first,middle,im.has_data)
        assert im.colorspace_settings.name=='sRGB'
        rows.append({'name':im.name,'path':str(absolute),'stored_path':im.filepath,'sha256':digest,'size':list(im.size),'first_pixel':first,'middle_pixel':middle,'has_data_after_read':im.has_data,'colorspace':im.colorspace_settings.name})
    assert len(rows)==1,len(rows)
    return rows

def inspect():
    dg=bpy.context.evaluated_depsgraph_get();rows=[];all_points=[]
    for obj in PARTS:
        me=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.transform(obj.matrix_world);me.calc_loop_triangles()
        pts=[gp(v.co) for v in me.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)];all_points.extend(pts)
        bm=bmesh.new();bm.from_mesh(me);bad_edges=sum(not e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True);bm.free()
        uv=me.uv_layers.get('SurfaceMetric');assert uv is not None and len(uv.data)==len(me.loops)
        uv_finite=all(math.isfinite(c) for p in uv.data for c in p.uv)
        valid=bad_edges==0 and volume>0 and uv_finite and lo[0]>=-2.000001 and hi[0]<=2.000001 and lo[1]>=-2.800001 and hi[1]<=.000001 and lo[2]>=-.350001 and hi[2]<=.000001
        if 'Fixing' in obj.name:valid=valid and hi[2]<=-.006
        rows.append({'name':obj.name,'bounds':[lo,hi],'triangles':len(me.loop_triangles),'nonmanifold_edges':bad_edges,'signed_closed_volume_m3':volume,'uv_name':uv.name,'uv_finite':uv_finite,'passed':valid})
        bpy.data.meshes.remove(me)
    lo=[min(p[i] for p in all_points) for i in range(3)];hi=[max(p[i] for p in all_points) for i in range(3)]
    exact=all(abs(a-b)<1e-6 for a,b in zip(lo+hi,[-2,-2.8,-.35,2,0,0]))
    return {'parts':rows,'triangles':sum(r['triangles'] for r in rows),'bounds':[lo,hi],'contract_bounds_exact':exact,'passed':exact and all(r['passed'] for r in rows),'waterline_y':-1.2,'scope':'Source topology/AABB/UV only; no game physics or final art.'}

def studio():
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    world=bpy.data.worlds.new('NeutralReview');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.42,.45,.48,1);world.node_tree.nodes['Background'].inputs[1].default_value=.24;scene.world=world
    for name,at,power,size in [('Key',(2.5,4,5),470,5),('Fill',(-4,1,2),180,4)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=bp(at);o.rotation_euler=(bp((0,-1.4,-.1))-o.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200,location=bp((0,-2.805,0)));floor=bpy.context.object;floor.name='STUDIO_ONLY_GROUND'
    mat=bpy.data.materials.new('STUDIO_NeutralGrey');mat.use_nodes=True;bs=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if bs is None:bs=mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled');out=mat.node_tree.nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(bs.outputs[0],out.inputs[0])
    bs.inputs['Base Color'].default_value=(.18,.19,.20,1);bs.inputs['Roughness'].default_value=.96;floor.data.materials.append(mat)
    camera=bpy.data.cameras.new('ReviewCamera');o=bpy.data.objects.new('ReviewCamera',camera);scene.collection.objects.link(o);camera.type='ORTHO';camera.clip_end=300;scene.camera=o

def camera_view(kind):
    scene=bpy.context.scene;target=Vector((0,-1.4,-.175))
    if kind=='reference':at=target+Vector((6,4.8,10));scale=5.6;resolution=(1440,1080)
    else:at=target+Vector((32,39,32));scale=26;resolution=(1280,720)
    camera=scene.camera;camera.location=bp(at);camera.rotation_euler=(bp(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
    scene.render.resolution_x,scene.render.resolution_y=resolution
    frame=camera.data.view_frame(scene=scene);height=max(p.y for p in frame)-min(p.y for p in frame)
    camera.data.ortho_scale*=scale/height
    frame=camera.data.view_frame(scene=scene);height=max(p.y for p in frame)-min(p.y for p in frame)
    assert abs(height-scale)<1e-4,(height,scale)
    return {'kind':kind,'godot_location':list(at),'godot_target':list(target),'actual_ortho_height_m':height,'blender_ortho_scale':camera.data.ortho_scale,'resolution':list(resolution),'note':'Isolated source-only scale/readability view; not actual game lighting/HUD.'}

def main():
    began=time.time();evidence=HERE/'evidence';evidence.mkdir(exist_ok=True);final=HERE/'i2_canal_revetment_p1.blend';assert not final.exists()
    assert sha(ATLAS)==ATLAS_SHA and sha(REFERENCE)==REFERENCE_SHA
    dump(HERE/'process.json',{'pid':os.getpid(),'status':'BUILD_RUNNING','threads':2,'source_only':True});print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2}),flush=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    atlas=bpy.data.images.load(str(ATLAS.resolve()),check_existing=False);atlas.colorspace_settings.name='sRGB'
    preflight=audit_images('before nodes')
    concrete=[material('Revetment_Concrete_'+str(i),'concrete',atlas,o) for i,o in enumerate([.0,.37,.74])]
    seal=material('Recessed_ConstructionSeal','seal',atlas);paint=material('Embedded_TealPaint','paint',atlas);metal=material('Inset_BoltSteel','metal',atlas)
    body(concrete+[seal])
    for i,(x,y) in enumerate(FIXINGS):
        box(f'Fixing_{i}_EmbeddedPlate',(x,y,-.031),(.170,.170,.010),paint)
        cylinder(f'Fixing_{i}_Washer',x,y,-.024,.033,.006,12,metal)
        cylinder(f'Fixing_{i}_HexHead',x,y,-.015,.026,.016,6,metal)
    bpy.context.view_layer.update();report=inspect();report.update(input_images=preflight,reference_sha256=REFERENCE_SHA,atlas_sha256=ATLAS_SHA,geometry_generated=True,source_only=True,no_bake_no_export=True)
    dump(evidence/'geometry_material_report.json',report)
    # Resolve every image in the current file context BEFORE any checkpoint save.
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
    audit_images('before checkpoint');bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'geometry_checkpoint.blend'),relative_remap=False)
    if not report['passed']:raise RuntimeError('Actual closed geometry/bounds gate failed; checkpoint preserved, no render.')
    studio();camera_view('reference');bpy.ops.wm.save_as_mainfile(filepath=str(final),relative_remap=False)
    # Absolute images already resolved; only now remap relative to final file.
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(final),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(final))
    report['reopened_images']=audit_images('reopened final blend')
    PARTS.clear();PARTS.extend(sorted([o for o in bpy.data.objects if o.get('editable_piece',False)],key=lambda o:o.name))
    reopened=inspect();assert reopened['passed'] and reopened['triangles']==report['triangles'] and len(PARTS)==7
    report['reopened_geometry']=reopened;outputs=[]
    for kind,name in [('reference','01-reference-oblique.png'),('scale26','02-isolated-26m-readability.png')]:
        view=camera_view(kind);bpy.context.scene.render.filepath=str(evidence/name);bpy.ops.render.render(write_still=True);outputs.append({'path':str(evidence/name),'sha256':sha(evidence/name),'camera':view})
    report.update(status='RENDERED_REQUIRES_HUMAN_REVIEW',outputs=outputs,blend_sha256=sha(final),elapsed_seconds=time.time()-began,source_originals_unchanged=sha(ATLAS)==ATLAS_SHA and sha(REFERENCE)==REFERENCE_SHA)
    dump(evidence/'geometry_material_report.json',report);print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-began,'triangles':report['triangles']}),flush=True)

if __name__=='__main__':main()
