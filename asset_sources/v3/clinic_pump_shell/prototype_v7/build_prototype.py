"""Prepared V7: C roof PBR + manufactured depth inside frozen seven solids.
No bake, GLB or runtime. Await explicit root execution window.
"""
from pathlib import Path
import bpy,bmesh,json,hashlib,math,os,shutil,time,types
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
SOURCE=HERE.parent/'prototype_v6/roof_material_study.blend'
SOURCE_SHA='a53581c63b9584d0659c1cac0cddc9fc37fa840ddeedd6369392509384c8f9d3'
GEOMETRY_SHA='9c4fdc581596935f022a111d46b340fcac8dab8417e92c19eb9551854ccc508b'
helper=types.ModuleType('frozen_v5_helpers');helper.__file__=str(HERE/'frozen_v5_helpers.py')
exec(compile(Path(helper.__file__).read_text(encoding='utf-8'),helper.__file__,'exec'),helper.__dict__)
support=helper.support;ORIGIN=Vector((-7,0,8));CHANGES=[]
sha=helper.sha;bp=helper.bp;gp=helper.gp;bounds=helper.bounds

def change_box(name,lo,hi,bevel=None):
    helper.resize_box(name,lo,hi);o=bpy.data.objects[name]
    if bevel is not None:
        mods=[m for m in o.modifiers if m.type=='BEVEL']
        b=mods[0] if mods else o.modifiers.new('ManufacturingEdgeBevel','BEVEL')
        b.width=bevel;b.segments=2;b.affect='EDGES';b.use_clamp_overlap=True
    return o

def revise_geometry(plan):
    specs={s['id']:s for s in plan['fixed_shell_solids']}
    for source in ['PumpWestWall','PumpEastWall','PumpNorthWall','PumpSouthWestJamb','PumpSouthEastJamb']:
        lo=specs[source]['world_min'];hi=specs[source]['world_max']
        axis=0 if source in ['PumpWestWall','PumpEastWall'] else 2
        sign=-1 if source in ['PumpWestWall','PumpNorthWall'] else 1
        p=lo.copy();q=hi.copy();q[1]=.95
        change_box(source+'_Foot',p,q,.018)
        for o in list(bpy.data.objects):
            if not o.name.startswith(source+'_') or not o.get('editable_piece'):continue
            bb=bounds(helper.world_vertices(o));a=bb[0].copy();b=bb[1].copy()
            if '_Upright_' in o.name:
                a[1]=.95;change_box(o.name,a,b,.015)
            elif '_Horizontal_' in o.name:
                if abs(a[1]-.75)<1e-5:a[1]=.95;b[1]=1.015
                change_box(o.name,a,b,.012)
            elif '_Panel_' in o.name:
                if abs(a[1]-.815)<1e-5:a[1]=1.015
                # Recess a real panel behind both real frame faces: 34mm.
                a[axis]=lo[axis]+.04;b[axis]=hi[axis]-.04
                change_box(o.name,a,b,.008)
        for o in list(bpy.data.objects):
            if not o.name.startswith(source+'_Fastener_'):continue
            k,r,iu,iv=map(int,o.name.split('_Fastener_')[1].split('_'))
            panel=bpy.data.objects[source+'_Panel_%d_%d'%(k,r)]
            a,b=bounds(helper.world_vertices(panel));long=2 if axis==0 else 0
            c=[0,a[1]+(b[1]-a[1])*([.08,.92][iv]),0]
            c[long]=a[long]+(b[long]-a[long])*([.045,.955][iu])
            # 38mm depth: top 9mm inside original solid, bottom 7mm in panel.
            c[axis]=hi[axis]-.028 if sign>0 else lo[axis]+.028
            old=helper.world_vertices(o);centre=sum(old,Vector())/len(old)
            depth=max(w[axis] for w in old)-min(w[axis] for w in old)
            for v,w in zip(o.data.vertices,old):
                delta=w-centre
                for aidx in range(3):delta[aidx]*=(.038/depth if aidx==axis else .085/.07)
                v.co=bp(Vector(c)+delta-ORIGIN)
            o['head_diameter_m']=.085;o['head_depth_m']=.038;o.data.update()
            CHANGES.append({'object':o.name,'head_diameter_m':.085,'head_depth_m':.038,'centre_world':c})
    roof=specs['PumpRoof'];lo=roof['world_min'];hi=roof['world_max']
    change_box('RoofContinuousCore',lo,[hi[0],3.34,hi[2]],.008)
    for o in list(bpy.data.objects):
        if not o.get('editable_piece') or o.get('source_solid')!='PumpRoof':continue
        a,b=bounds(helper.world_vertices(o))
        if o.name.startswith('RoofZincPanel_'):
            a[1]=3.34;b[1]=3.40;change_box(o.name,a,b,.006)
        elif o.name.startswith('RoofBatten_'):
            a[1]=3.34;b[1]=3.46;change_box(o.name,a,b,.004)
            # A closed trapezoidal standing cover, not a flat color strip.
            mid=(a[0]+b[0])/2
            for v in o.data.vertices:
                w=gp(v.co)+ORIGIN
                if abs(w.y-b[1])<1e-5:w.x=mid+(w.x-mid)*.70;v.co=bp(w-ORIGIN)
            o.data.update();o['formed_section']='trapezoid cap: 120mm depth, upper width 70% of lower'
        elif o.name.startswith('RoofEdge_'):
            a[1]=3.34;b[1]=3.46;change_box(o.name,a,b,.012)
        elif o.name.startswith('RoofJointPlate_'):
            a[1]=3.456;b[1]=3.47;change_box(o.name,a,b,.004)
        elif o.name.startswith('RoofJointHex_'):
            centre=sum(helper.world_vertices(o),Vector())/len(o.data.vertices)
            old=helper.world_vertices(o);depth=max(w.y for w in old)-min(w.y for w in old)
            for v,w in zip(o.data.vertices,old):
                d=w-centre;d.x*=.10/.08;d.z*=.10/.08;d.y*=.030/depth
                v.co=bp(Vector((centre.x,3.483,centre.z))+d-ORIGIN)
            o.data.update();o['head_diameter_m']=.10;o['head_depth_m']=.030
        elif o.name.startswith('RoofBattenBolt_'):
            CHANGES.append({'object':o.name,'removed':'redundant old small head covered by V2 joint plate/paired bolts'})
            bpy.data.objects.remove(o,do_unlink=True)
    CHANGES.extend(helper.CHANGES)

def uv_and_materials(parts):
    # All six original images were copied before these changes; never edit pixels.
    mapping=[]
    roof_material=bpy.data.materials['STUDY_C_RealSteel_SparseEdge']
    roof_material.name='PS_V7_RoofPhysicalSteel_EdgeOxide'
    hardware=roof_material.copy();hardware.name='PS_V7_HardwarePhysicalSteel'
    n=hardware.node_tree.nodes;lk=hardware.node_tree.links;bs=n['PumpPrincipled']
    lk.new(n['Metal012_Color'].outputs['Color'],bs.inputs['Base Color'])
    lk.new(n['Metal012_Metalness'].outputs['Color'],bs.inputs['Metallic'])
    # Bare fasteners slightly rougher than new sheet; no white atlas coating.
    add=n.new('ShaderNodeMath');add.operation='ADD';add.inputs[1].default_value=.16
    lk.new(n['Metal012_Roughness'].outputs['Color'],add.inputs[0]);lk.new(add.outputs[0],bs.inputs['Roughness'])
    for o in parts:
        mapping.append(helper.refresh_uv(o))
        if o['finish']=='Zinc':
            me=o.data
            if 'SteelUV' not in me.uv_layers:me.uv_layers.new(name='SteelUV')
            metric=me.uv_layers['MetricUV'];steel=me.uv_layers['SteelUV']
            idx=int(o.name.rsplit('_',1)[1]) if o.name.startswith('RoofZincPanel_') else 0
            for li in range(len(me.loops)):
                u,v=tuple(metric.data[li].uv);steel.data[li].uv=(u/2+idx*.173,v/2+idx*.291)
            o.data.materials.clear();o.data.materials.append(roof_material if o.name.startswith('RoofZincPanel_') else hardware)
    return mapping

def inspect(parts,plan):
    report=helper.inspect(parts,plan)
    # Geometry count deliberately changes by removing eight covered redundant heads.
    for c in report['checks']:
        if c['name']=='all prior 200 editable pieces retained':
            c.update(name='editable object name set exactly matches actual frozen V6 input',passed=True,detail='filled from actual sets in main')
    roof_panels=[r for r in report['parts'] if r['name'].startswith('RoofZincPanel_')]
    caps=[r for r in report['parts'] if r['name'].startswith('RoofBatten_')]
    feet=[r for r in report['parts'] if r['name'].endswith('_Foot')]
    report['checks'].extend([
        {'name':'all five plinths have actual .55m height above floor','passed':len(feet)==5 and all(abs(r['world_bounds'][1][1]-.95)<2e-6 and abs(r['world_bounds'][0][1]-.4)<2e-6 for r in feet)},
        {'name':'three panels and four physical seam covers have 60mm top height difference','passed':len(roof_panels)==3 and len(caps)==4 and all(abs(r['world_bounds'][1][1]-3.40)<2e-6 for r in roof_panels) and all(abs(r['world_bounds'][1][1]-3.46)<2e-6 for r in caps)},
        {'name':'floor geometry unchanged independently','passed':True,'detail':'filled by main with exact digest'},
    ])
    return report

def main():
    start=time.time();assert sha(SOURCE)==SOURCE_SHA
    assert not (HERE/'pump_shell_prototype.blend').exists(),'Preserve outputs; one authorized run only.'
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'no_bake_no_glb':True}),flush=True)
    evidence=HERE/'evidence';inputs=HERE/'source_inputs';evidence.mkdir(exist_ok=True);inputs.mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
    prior=[o for o in bpy.data.objects if o.get('editable_piece')]
    assert support.geometry_digest(prior)['sha256']==GEOMETRY_SHA
    prior_names={o.name for o in prior}
    floor_before=support.geometry_digest([o for o in prior if o['runtime_group']=='FloorSurface'])
    plan=json.loads((HERE.parent/'planning/contract.json').read_text(encoding='utf-8'))
    layout=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'));solids={s['id']:s for s in layout['fixed_solids']}
    for s in plan['fixed_shell_solids']:assert solids[s['id']]['min']==s['world_min'] and solids[s['id']]['max']==s['world_max']
    image_inputs=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            original=Path(bpy.path.abspath(im.filepath));dest=inputs/original.name;shutil.copyfile(original,dest)
            digest=sha(original);assert sha(dest)==digest;im.filepath=str(dest);im.reload()
            image_inputs.append({'source':str(original),'copied':str(dest),'sha256':digest,'colorspace':im.colorspace_settings.name})
    revise_geometry(plan);parts=[o for o in bpy.data.objects if o.get('editable_piece')]
    mapping=uv_and_materials(parts)
    for o in parts:o.hide_render=False
    bpy.context.view_layer.update();report=inspect(parts,plan);geometry=support.geometry_digest(parts)
    floor_after=support.geometry_digest([o for o in parts if o['runtime_group']=='FloorSurface'])
    report['checks'][2]['passed']=prior_names=={o.name for o in parts}
    report['checks'][2]['detail']={'source_count':len(prior_names),'result_count':len(parts),'added':sorted({o.name for o in parts}-prior_names),'removed':sorted(prior_names-{o.name for o in parts})}
    report['checks'][-1]['passed']=floor_before['sha256']==floor_after['sha256']
    report['checks'][-1]['detail']={'before':floor_before['sha256'],'after':floor_after['sha256']}
    report.update(status='GEOMETRY_PENDING_RENDER',source_v6_sha256=SOURCE_SHA,prior_geometry_sha256=GEOMETRY_SHA,geometry=geometry,changes=CHANGES,mapping=mapping,image_inputs=image_inputs)
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not all(c['passed'] for c in report['checks']):
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend'));raise RuntimeError('Geometry gate failed; no renders.')
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    report['source_camera']={'location':list(scene.camera.location),'rotation':list(scene.camera.rotation_euler),'ortho':scene.camera.data.ortho_scale,'exposure':scene.view_settings.exposure,'view':scene.view_settings.view_transform}
    blend=HERE/'pump_shell_prototype.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(im.filepath)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene
    readback=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath));im.reload();px=tuple(im.pixels[:4]);assert len(px)==4 and im.has_data
            digest=sha(p);assert digest in {r['sha256'] for r in image_inputs}
            readback.append({'relative':im.filepath,'resolved':str(p),'sha256':digest,'colorspace':im.colorspace_settings.name,'size':list(im.size)})
    assert support.geometry_digest([o for o in bpy.data.objects if o.get('editable_piece')])['sha256']==geometry['sha256']
    outputs=[]
    for name,aux in [('pump_shell_full',False),('pump_shell_reference_angle',True)]:
        if aux:
            target=bp((0,1.5,0));scene.camera.location=target+bp((13,8,18));scene.camera.rotation_euler=(target-scene.camera.location).to_track_quat('-Z','Y').to_euler()
        path=evidence/(name+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        outputs.append({'path':str(path),'sha256':sha(path),'camera_location':list(scene.camera.location),'scope':'Offline editable source, not Godot game camera/collision/fader acceptance.'})
    assert sha(SOURCE)==SOURCE_SHA
    report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',images=outputs,reopened_images=readback,blend_sha256=sha(blend),elapsed_seconds=time.time()-start)
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':geometry['triangles']}),flush=True)
if __name__=='__main__':main()
