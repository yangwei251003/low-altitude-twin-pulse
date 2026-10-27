"""Prepared V5 only. Requires a new explicit root CPU2 execution window.
Visual detail dimensions may change INSIDE the seven existing solid boxes.
No runtime/GLB/bake. Frozen V4 source and every older file remain read-only.
"""
from pathlib import Path
import bpy, bmesh, json, hashlib, math, os, shutil, time, types
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[3]; ORIGIN=Vector((-7,0,8))
V4=HERE.parent/'prototype_v4'; SOURCE=V4/'pump_shell_prototype.blend'
SOURCE_SHA='e574cb20bfaec67ed789f320067bfc326bb9754631a69134b2edc98a1caf512f'
SUPPORT_PATH=HERE/'frozen_v4_material_support.py'
support=types.ModuleType('frozen_v4_material_support'); support.__file__=str(SUPPORT_PATH)
exec(compile(SUPPORT_PATH.read_text(encoding='utf-8'),str(SUPPORT_PATH),'exec'),support.__dict__)
CHANGES=[]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return Vector((p[0],p[2],-p[1]))
def bounds(points): return [[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]]
def world_vertices(o): return [gp(v.co)+ORIGIN for v in o.data.vertices]
def resize_box(name,lo,hi):
    o=bpy.data.objects[name]; old=bounds(world_vertices(o))
    for v in o.data.vertices:
        w=gp(v.co)+ORIGIN
        q=Vector([lo[a]+(w[a]-old[0][a])/(old[1][a]-old[0][a])*(hi[a]-lo[a]) for a in range(3)])
        v.co=bp(q-ORIGIN)
    o.data.update(); CHANGES.append({'object':name,'old_world_bounds':old,'new_world_bounds':[list(lo),list(hi)],'method':'Affine resizing of this existing manufactured detail only; no whole-shell deformation.'})
def position_bolt(name,centre,normal_axis,radius_ratio,diameter):
    o=bpy.data.objects[name]; vs=world_vertices(o); old=sum(vs,Vector())/len(vs)
    for v,w in zip(o.data.vertices,vs):
        d=w-old
        for a in range(3):
            if a!=normal_axis: d[a]*=radius_ratio
        v.co=bp(Vector(centre)+d-ORIGIN)
    o['head_diameter_m']=diameter; o.data.update()
    CHANGES.append({'object':name,'old_centre_world':list(old),'new_centre_world':list(centre),'head_diameter_m':diameter})

def revise_geometry(plan):
    specs={s['id']:s for s in plan['fixed_shell_solids']}
    for source in ['PumpWestWall','PumpEastWall','PumpNorthWall','PumpSouthWestJamb','PumpSouthEastJamb']:
        lo=specs[source]['world_min']; hi=specs[source]['world_max']
        axis=0 if source in ['PumpWestWall','PumpEastWall'] else 2; long=2 if axis==0 else 0
        sign=-1 if source in ['PumpWestWall','PumpNorthWall'] else 1
        count=3 if source in ['PumpWestWall','PumpEastWall','PumpNorthWall'] else 1
        edges=[lo[long]+(hi[long]-lo[long])*i/count for i in range(count+1)]
        # Edge uprights .16 -> .24m; intermediate uprights .13 -> .20m.
        spans=[(edges[i]+(.24 if i==0 else .10),edges[i+1]-(.24 if i==count-1 else .10)) for i in range(count)]
        rails=[(lo[long],spans[0][0])]+[(spans[i-1][1],spans[i][0]) for i in range(1,count)]+[(spans[-1][1],hi[long])]
        for i,(a,b) in enumerate(rails):
            p=lo.copy(); q=hi.copy(); p[long]=a; q[long]=b; p[1]=.75; p[axis]+=.006; q[axis]-=.006
            resize_box(source+'_Upright_'+str(i),p,q)
        # Wider real top and middle members consume panel area, never the opening.
        rows=[(.815,2.98)] if count==1 else [(.815,1.89),(1.955,2.98)]
        for k,(a,b) in enumerate(spans):
            for r,(y0,y1) in enumerate(rows):
                p=lo.copy(); q=hi.copy(); p[long]=a; q[long]=b; p[1]=y0; q[1]=y1; p[axis]+=.018; q[axis]-=.018
                resize_box(source+'_Panel_%d_%d'%(k,r),p,q)
                for iu,u in enumerate([.045,.955]):
                    for iv,v in enumerate([.08,.92]):
                        c=[0,y0+(y1-y0)*v,0]; c[long]=a+(b-a)*u; c[axis]=hi[axis]-.013 if sign>0 else lo[axis]+.013
                        position_bolt(source+'_Fastener_%d_%d_%d_%d'%(k,r,iu,iv),c,axis,.035/.026,.07)
            for j,(y0,y1) in enumerate([(.75,.815),(2.98,3.2)]+([] if count==1 else [(1.89,1.955)])):
                p=lo.copy(); q=hi.copy(); p[long]=a; q[long]=b; p[1]=y0; q[1]=y1; p[axis]+=.006; q[axis]-=.006
                resize_box(source+'_Horizontal_%d_%d'%(k,j),p,q)
        if 'South' in source:
            xa=hi[0]-.225 if 'WestJamb' in source else lo[0]+.025
            resize_box(source+'_EntryPaint',[xa,.4,hi[2]-.004],[xa+.20,1.15,hi[2]-.001])
    roof=specs['PumpRoof']; lo=roof['world_min']; hi=roof['world_max']; edges=[lo[0],-8.7,-5.3,hi[0]]
    for i in range(3):
        inset_a=.18 if i==0 else .14; inset_b=.18 if i==2 else .14
        resize_box('RoofZincPanel_'+str(i),[edges[i]+inset_a,3.43,lo[2]+.22],[edges[i+1]-inset_b,3.482,hi[2]-.22])
    for i,x in enumerate(edges):
        a=lo[0] if i==0 else x-.14; b=hi[0] if i==3 else x+.14
        if i==0: b=lo[0]+.18
        if i==3: a=hi[0]-.18
        resize_box('RoofBatten_'+str(i),[a,3.43,lo[2]],[b,3.49,hi[2]])
        cx=min(hi[0]-.21,max(lo[0]+.21,x))
        for j,z in enumerate([lo[2]+.19,hi[2]-.19]):
            resize_box('RoofJointPlate_%d_%d'%(i,j),[cx-.21,3.478,z-.19],[cx+.21,3.492,z+.19])
            for k,dx in enumerate([-.095,.095]):
                position_bolt('RoofJointHex_%d_%d_%d'%(i,j,k),[cx+dx,3.496,z],1,.04/.035,.08)
    for old_z,new_z0,new_z1 in [(lo[2],lo[2],lo[2]+.22),(hi[2]-.18,hi[2]-.22,hi[2])]:
        for i in range(3):
            xa=edges[i]+(.18 if i==0 else .14); xb=edges[i+1]-(.18 if i==2 else .14)
            resize_box('RoofEdge_%s_%d'%(old_z,i),[xa,3.43,new_z0],[xb,3.49,new_z1])

def refresh_uv(o):
    me=o.data; bb=bounds([gp(v.co) for v in me.vertices])
    me.uv_layers.remove(me.uv_layers['FinishUV'])
    metric=me.uv_layers['MetricUV']; panel=me.uv_layers['PanelUV']; sizes=me.color_attributes['FaceSize']; wear=me.color_attributes['WearControl']
    for poly in me.polygons:
        gn=gp(poly.normal); axis=max(range(3),key=lambda a:abs(gn[a])); axes=(0,2) if axis==1 else ((2,1) if axis==0 else (0,1))
        for li in poly.loop_indices:
            q=gp(me.vertices[me.loops[li].vertex_index].co)
            metric.data[li].uv=(q[axes[0]],q[axes[1]])
            panel.data[li].uv=tuple((q[a]-bb[0][a])/max(1e-9,bb[1][a]-bb[0][a]) for a in axes)
            sizes.data[li].color=(bb[1][axes[0]]-bb[0][axes[0]],bb[1][axes[1]]-bb[0][axes[1]],0,1)
            w=tuple(wear.data[li].color)
            wear.data[li].color=(w[0],w[1],min(.80,w[2]*1.1),min(.105,max(.075,w[3]*1.5)))
    row=support.add_finish_uv(o)
    if o.name.startswith('RoofZincPanel'):
        idx=int(o.name.rsplit('_',1)[1]); uv=me.uv_layers['FinishUV']; panel=me.uv_layers['PanelUV']
        # Distinct windows and rotations; not three near-identical mirrored sheets.
        configs=[(0,(.02,.02,.98,.98)),(2,(.10,.025,.95,.85)),(1,(.025,.10,.86,.97))]
        rotation,crop=configs[idx]
        for poly in me.polygons:
            for li in poly.loop_indices:
                u,v=tuple(panel.data[li].uv)
                if rotation==1: u,v=v,1-u
                elif rotation==2: u,v=1-u,1-v
                u=crop[0]+u*(crop[2]-crop[0]); v=crop[1]+v*(crop[3]-crop[1])
                uv.data[li].uv=(.5016+.4968*u,.5016+.4968*v)
        row['v5_roof_uv']={'quarter_turns':rotation,'normalized_crop':crop,'repeat':False}
    return row

def revise_materials(mats):
    for f,m in mats.items(): m.name='PS_V5_'+f
    zinc=mats['Zinc']; n=zinc.node_tree.nodes; lk=zinc.node_tree.links
    mix=next(q for q in n if q.type=='MIX_RGB' and q.label.startswith('90% atlas'))
    mix.inputs[0].default_value=.73; mix.label='73% roof atlas with soft compressed whites'
    tex=n['UneditedAtlasV2']; gray=n.new('ShaderNodeRGBToBW'); lk.new(tex.outputs['Color'],gray.inputs[0])
    def mathnode(nodes,links,kind,a,b=0):
        q=nodes.new('ShaderNodeMath'); q.operation=kind
        for x,s in [(a,q.inputs[0]),(b,q.inputs[1])]:
            if hasattr(x,'node'): links.new(x,s)
            else: s.default_value=x
        return q.outputs[0]
    def z(kind,a,b=0): return mathnode(n,lk,kind,a,b)
    peak=z('MAXIMUM',z('SUBTRACT',gray.outputs[0],.22),0)
    factor=z('DIVIDE',1,z('ADD',1,z('MULTIPLY',peak,.80)))
    tone=n.new('ShaderNodeMixRGB'); tone.blend_type='MULTIPLY'; tone.inputs[0].default_value=1
    lk.new(tex.outputs['Color'],tone.inputs[1]); lk.new(factor,tone.inputs[2]); lk.new(tone.outputs[0],mix.inputs[2])
    bloom=z('MINIMUM',1,z('MAXIMUM',0,z('DIVIDE',z('SUBTRACT',gray.outputs[0],.24),.26)))
    bs=n['PumpPrincipled']; lk.new(z('ADD',.42,z('MULTIPLY',bloom,.24)),bs.inputs['Roughness'])
    lk.new(z('SUBTRACT',.65,z('MULTIPLY',bloom,.29)),bs.inputs['Metallic'])
    n['ShallowMaterialOnly'].inputs['Distance'].default_value=.00035; n['ShallowMaterialOnly'].inputs['Strength'].default_value=.06
    teal=mats['Teal']; tm=next(q for q in teal.node_tree.nodes if q.type=='MIX_RGB' and q.label.startswith('92% atlas'))
    tm.inputs[0].default_value=.80; tm.inputs[1].default_value=(.16,.235,.25,1); tm.label='80% atlas, restrained lighter desaturated teal binder'
    # Six faint, soft gravity streaks begin at existing upper fasteners.
    # No height/bump indentation is added and no random wall-wide dirt.
    wall=mats['Wall']; n=wall.node_tree.nodes; lk=wall.node_tree.links
    def w(kind,a,b=0): return mathnode(n,lk,kind,a,b)
    uv=n.new('ShaderNodeUVMap'); uv.uv_map='PanelUV'; uvse=n.new('ShaderNodeSeparateXYZ'); lk.new(uv.outputs['UV'],uvse.inputs[0])
    size=n.new('ShaderNodeVertexColor'); size.layer_name='FaceSize'; ss=n.new('ShaderNodeSeparateColor'); lk.new(size.outputs['Color'],ss.inputs[0])
    ctrl=n.new('ShaderNodeVertexColor'); ctrl.layer_name='WearControl'; cs=n.new('ShaderNodeSeparateColor'); lk.new(ctrl.outputs['Color'],cs.inputs[0])
    distance=w('MULTIPLY',w('SUBTRACT',.92,uvse.outputs['Y']),ss.outputs['Green'])
    positive=w('GREATER_THAN',distance,0); t=w('MINIMUM',1,w('MAXIMUM',0,w('DIVIDE',distance,cs.outputs['Blue'])))
    taper=w('MULTIPLY',w('SUBTRACT',1,t),w('SUBTRACT',1,t))
    sigma=w('MAXIMUM',.004,w('MULTIPLY',ctrl.outputs['Alpha'],w('ADD',.16,w('MULTIPLY',w('SUBTRACT',1,t),.20))))
    stripes=[]
    for xpos,channel in [(.045,'Red'),(.955,'Green')]:
        dx=w('MULTIPLY',w('SUBTRACT',uvse.outputs['X'],xpos),ss.outputs['Red'])
        gaussian=w('EXPONENT',w('MULTIPLY',-.5,w('POWER',w('DIVIDE',dx,sigma),2)))
        stripes.append(w('MULTIPLY',gaussian,cs.outputs[channel]))
    mask=w('MULTIPLY',.24,w('MULTIPLY',positive,w('MULTIPLY',taper,w('ADD',stripes[0],stripes[1]))))
    bs=n['PumpPrincipled']; prior=bs.inputs['Base Color'].links[0].from_socket
    rain=n.new('ShaderNodeMixRGB'); rain.label='Six faint actual-fastener rain trails, 7.5–10.5cm full width'
    lk.new(mask,rain.inputs[0]); lk.new(prior,rain.inputs[1]); rain.inputs[2].default_value=(.13,.095,.065,1); lk.new(rain.outputs[0],bs.inputs['Base Color'])

def inspect(parts,plan):
    dg=bpy.context.evaluated_depsgraph_get(); specs={s['id']:s for s in plan['fixed_shell_solids']}; rows=[]; verts=[]; tris=[]
    for o in parts:
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg); me.transform(o.matrix_world); me.calc_loop_triangles()
        bb=bounds([gp(v.co)+ORIGIN for v in me.vertices]); s=specs[o['source_solid']]
        bm=bmesh.new(); bm.from_mesh(me); bad=sum(not e.is_manifold for e in bm.edges); bm.free()
        rows.append({'name':o.name,'world_bounds':bb,'triangles':len(me.loop_triangles),'nonmanifold':bad,
                     'inside_original_solid':all(bb[0][i]>=s['world_min'][i]-2e-6 and bb[1][i]<=s['world_max'][i]+2e-6 for i in range(3))})
        start=len(verts); verts.extend([v.co.copy() for v in me.vertices]); tris.extend([tuple(start+i for i in t.vertices) for t in me.loop_triangles]); bpy.data.meshes.remove(me)
    checks=[]
    def check(name,ok,detail=None): checks.append({'name':name,'passed':bool(ok),'detail':detail})
    check('every revised detail remains inside its original one of seven solid boxes',all(r['inside_original_solid'] for r in rows))
    check('individual editable parts remain closed',all(r['nonmanifold']==0 for r in rows))
    check('all prior 200 editable pieces retained',len(parts)==200)
    bvh=BVHTree.FromPolygons(verts,tris,all_triangles=True); rays=[]
    for x in [-8.69,-7,-5.31]:
        for y in [.41,1.8,3.19]:
            hit=bvh.ray_cast(bp(Vector((x,y,13))-ORIGIN),bp((0,0,-1)),1.05)[0]; rays.append(hit is None)
    check('3.4 by 2.8m doorway nine boundary/interior rays clear',all(rays),rays)
    hit=bvh.ray_cast(bp(Vector((-7.2,1,11.8))-ORIGIN),Vector((0,0,-1)),1.2)[0]
    check('interior floor remains Y.4',hit is not None and abs(gp(hit).y-.4)<2e-6)
    hit=bvh.ray_cast(bp(Vector((-7,1,12.125))-ORIGIN),Vector((0,0,-1)),1.2)[0]
    check('no invented raised threshold past Z12',hit is None)
    check('all source group identities retained',{o['runtime_group'] for o in parts}=={'FloorSurface','WallFeetAndJambs','WestCover','EastCover','NorthCover','RoofCover'})
    check('two yellow strips exactly .20 wide and .75 high starting Y.4',all(abs((b:=bounds(world_vertices(bpy.data.objects[s+'_EntryPaint'])))[0][1]-.4)<2e-6 and abs(b[1][1]-1.15)<2e-6 and abs(b[1][0]-b[0][0]-.20)<2e-6 for s in ['PumpSouthWestJamb','PumpSouthEastJamb']))
    return {'checks':checks,'parts':rows,'triangles':sum(r['triangles'] for r in rows),'limits':'Source box containment/closure and rays only. Not full inter-part self-intersection, production collision or actual flight QA.'}

def main():
    start=time.time(); assert sha(SOURCE)==SOURCE_SHA; assert not (HERE/'pump_shell_prototype.blend').exists()
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'source_only':True}),flush=True)
    evidence=HERE/'evidence'; inputs=HERE/'source_inputs'; evidence.mkdir(exist_ok=True); inputs.mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE)); bpy.context.view_layer.update()
    parts=[o for o in bpy.data.objects if o.get('editable_piece')]
    before=support.geometry_digest(parts); assert before['sha256']==support.GEOMETRY_SHA
    plan=json.loads((HERE.parent/'planning/contract.json').read_text(encoding='utf-8'))
    actual=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'))
    specs={s['id']:s for s in actual['fixed_solids']}
    for s in plan['fixed_shell_solids']: assert specs[s['id']]['min']==s['world_min'] and specs[s['id']]['max']==s['world_max']
    images={}
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath)); digest=sha(p); assert digest in [support.OLD_SHA,support.NEW_SHA]
            dest=inputs/('material_atlas_v1_UNEDITED.png' if digest==support.OLD_SHA else 'material_atlas_v2_UNEDITED.png')
            shutil.copyfile(p,dest); im.filepath=str(dest); im.reload(); images[digest]=im
    revise_geometry(plan); mapping=[refresh_uv(o) for o in parts]
    mats={f:support.make_material(f,images[support.NEW_SHA],images[support.OLD_SHA]) for f in support.REGIONS}; revise_materials(mats)
    for o in parts: o.data.materials.clear(); o.data.materials.append(mats[o['finish']]); o.hide_render=False
    bpy.context.view_layer.update(); report=inspect(parts,plan); after=support.geometry_digest(parts)
    report.update(status='GEOMETRY_CHECKED_PENDING_RENDER',source_v4_sha256=SOURCE_SHA,before_geometry_sha256=before['sha256'],geometry=after,
                  geometry_changed_by_root_authorization=True,changes=CHANGES,mapping=mapping,no_bake_no_glb_no_runtime=True)
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not all(c['passed'] for c in report['checks']):
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend')); raise RuntimeError('Containment/opening gate failed; no render.')
    scene=bpy.context.scene; scene.cycles.device='CPU'; scene.cycles.samples=24; scene.render.threads_mode='FIXED'; scene.render.threads=2
    report['camera']={'location_blender':list(scene.camera.location),'ortho_scale':scene.camera.data.ortho_scale,'resolution':[scene.render.resolution_x,scene.render.resolution_y],'view':scene.view_settings.view_transform,'exposure':scene.view_settings.exposure}
    blend=HERE/'pump_shell_prototype.blend'; bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath: im.filepath=bpy.path.relpath(im.filepath)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False); bpy.ops.wm.open_mainfile(filepath=str(blend)); scene=bpy.context.scene
    readback=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath)); digest=sha(p); assert digest in [support.OLD_SHA,support.NEW_SHA]
            im.reload(); pixel=tuple(im.pixels[:4]); assert len(pixel)==4 and im.has_data and tuple(im.size)==(1254,1254)
            readback.append({'relative':im.filepath,'resolved':str(p),'sha256':digest,'size':list(im.size),'colorspace':im.colorspace_settings.name})
    reopened=support.geometry_digest([o for o in bpy.data.objects if o.get('editable_piece')]); assert reopened['sha256']==after['sha256']
    outputs=[]
    for name,cut in [('pump_shell_full',False),('pump_shell_source_cutaway',True)]:
        for o in bpy.data.objects:
            if o.get('editable_piece'): o.hide_render=cut and o.get('runtime_group') in ['WestCover','EastCover','NorthCover','RoofCover']
        p=evidence/(name+'.png'); scene.render.filepath=str(p); bpy.ops.render.render(write_still=True); outputs.append({'path':str(p),'sha256':sha(p),'scope':'Offline source review, not actual game fader or flight evidence.'})
    report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',images=outputs,reopened_images=readback,reopened_geometry_sha256=reopened['sha256'],blend_sha256=sha(blend),elapsed_seconds=time.time()-start)
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert sha(SOURCE)==SOURCE_SHA
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':report['triangles']}),flush=True)
if __name__=='__main__': main()
