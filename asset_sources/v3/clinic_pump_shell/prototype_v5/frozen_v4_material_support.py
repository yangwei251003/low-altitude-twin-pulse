"""V4 SOURCE ONLY: frozen V3 geometry, new atlas/UV/materials, same camera.
Run only after root grants CPU2. No image pixel edits, bake, GLB or runtime writes.
"""
from pathlib import Path
import bpy, bmesh, json, hashlib, math, os, shutil, struct, time
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
V3 = HERE.parent / 'prototype_v3'
SOURCE = V3 / 'pump_shell_prototype.blend'
SOURCE_SHA = '02e1e003d0012f3a0e25226635b29a8f8c9869cb67e973fa0f37b061ae4dd003'
GEOMETRY_SHA = '70d3a68c7af57a88254afcb0f0490d9ad6374abf5878d9eddba49345cd1108d7'
OLD_ATLAS = ROOT / 'references/v3/production/clinic_pump_shell/material_atlas_v1.png'
NEW_ATLAS = ROOT / 'references/v3/production/clinic_pump_shell/material_atlas_v2.png'
OLD_SHA = '3ae5cab8887bbd167251668b26f94cc2f9128636f27954e1d887864f54da8797'
NEW_SHA = '7dda1e9da03d56820a37df7636e0ad5ad4abba43474849c7e1dbbafe81138a15'
REGIONS = {'Wall': (0, .5, .5, 1), 'Zinc': (.5, .5, 1, 1),
           'Concrete': (0, 0, .5, .5), 'Teal': (.5, 0, 1, .5),
           'Yellow': (.5, 0, 1, .5), 'Seal': (.5, 0, 1, .5)}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def gp(p):
    return Vector((p[0], p[2], -p[1]))

def geometry_digest(objects):
    dg = bpy.context.evaluated_depsgraph_get(); h = hashlib.sha256(); rows = []
    for o in sorted(objects, key=lambda q: q.name):
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world); me.calc_loop_triangles()
        h.update(o.name.encode('utf-8') + b'\0')
        for v in me.vertices: h.update(struct.pack('<3f', *v.co))
        for tri in me.loop_triangles: h.update(struct.pack('<3I', *tri.vertices))
        bm = bmesh.new(); bm.from_mesh(me)
        rows.append({'name': o.name, 'vertices': len(me.vertices), 'triangles': len(me.loop_triangles),
                     'nonmanifold_edges': sum(not e.is_manifold for e in bm.edges)})
        bm.free(); bpy.data.meshes.remove(me)
    return {'sha256': h.hexdigest(), 'parts': rows, 'triangles': sum(r['triangles'] for r in rows)}

def add_finish_uv(o):
    """Only UV data changes. All polygons/vertices/modifiers remain frozen V3."""
    me = o.data
    assert 'FinishUV' not in me.uv_layers
    me.uv_layers.new(name='FinishUV')
    # Reacquire handles after adding UV storage; older RNA handles may invalidate.
    uv = me.uv_layers['FinishUV']; panel = me.uv_layers['PanelUV']
    sizes = me.color_attributes['FaceSize']; purpose = me.color_attributes['SurfaceUse']
    seed = hashlib.sha256(o.name.encode()).digest(); f = o['finish']; rect = REGIONS[f]
    rows = []
    for poly in me.polygons:
        li0 = poly.loop_indices[0]
        sx, sy = tuple(sizes.data[li0].color)[:2]
        use = tuple(purpose.data[li0].color)
        exterior = use[2] > .5
        regime = 'normalized_component'
        for li in poly.loop_indices:
            u, v = tuple(panel.data[li].uv)
            if f == 'Zinc' and o.name.startswith('RoofZincPanel'):
                # One complete roof quadrant per 8.14m panel, no FRACT/repeat.
                idx = int(o.name.rsplit('_', 1)[1])
                u = 1-u if idx == 1 else u
                v = 1-v if idx == 2 else v
                u, v = .025 + .95*u, .025 + .95*v
                regime = 'single_roof_panel_no_repeat'
            elif f == 'Zinc':
                u, v = .38 + .18*u, .38 + .18*v
                regime = 'quiet_zinc_fastener_crop'
            elif f == 'Teal':
                along, across = (u, v) if sx >= sy else (v, u)
                long_m, width_m = max(sx, sy), min(sx, sy)
                # Atlas is deliberately authored as a beam strip: 8.5m x .8m.
                # Short bars crop a short length; narrow bars crop one broken edge.
                span = min(.96, max(.035, long_m / 8.5))
                band = min(.94, max(.025, width_m / .8))
                start = .02 + (seed[0]/255) * (.96-span)
                along = 1-along if seed[1] & 1 else along
                u = start + span*along
                v = .015 + band*across if seed[2] & 1 else .985 - band*across
                regime = 'metre_cropped_beam_strip_8p5_by_p8'
            elif f == 'Concrete':
                # Only exterior vertical foot faces use this UV. Other faces use
                # the V1 clean concrete branch with its original metric sampling.
                u = .025 + .95*(1-u if seed[0] & 1 else u)
                v = .005 + .645*v
                regime = 'new_exterior_foot_bottom_aligned' if exterior else 'old_clean_concrete_branch'
            elif f == 'Wall':
                u = 1-u if seed[1] & 1 else u
                u, v = .035 + .93*u, .035 + .93*v
                regime = 'broad_wall_face_once'
            elif f == 'Yellow':
                # Narrow real paint strip; use a crop of existing irregular loss,
                # not new rectangular stains or global noise.
                u, v = .01 + .33*v, .005 + .13*u
                regime = 'yellow_edge_undercoat_mask_crop'
            else:
                u, v = .4 + .2*u, .4 + .2*v
            a, b, c, d = rect; pad = 2/1254
            uv.data[li].uv = (a+pad+u*(c-a-2*pad), b+pad+v*(d-b-2*pad))
        rows.append({'polygon': poly.index, 'face_metres': [sx, sy], 'regime': regime,
                     'exterior_foot_only': exterior, 'normal_godot': list(gp(poly.normal))})
    me.uv_layers.active_index = me.uv_layers.find('FinishUV')
    for layer in me.uv_layers: layer.active_render = layer.name == 'FinishUV'
    o['v4_uv_note'] = 'Explicit FinishUV; MetricUV and PanelUV retained unchanged.'
    return {'object': o.name, 'finish': f, 'faces': rows}

def make_material(finish, new_image, old_image):
    m = bpy.data.materials.new('PS_V4_' + finish); m.use_nodes = True
    n = m.node_tree.nodes; n.clear(); links = m.node_tree.links
    def put(v, sock):
        if hasattr(v, 'node'): links.new(v, sock)
        else: sock.default_value = v
    def op(kind, a, b=0):
        q=n.new('ShaderNodeMath'); q.operation=kind; put(a,q.inputs[0]); put(b,q.inputs[1]); return q.outputs[0]
    def add(a,b): return op('ADD',a,b)
    def mul(a,b): return op('MULTIPLY',a,b)
    def sub(a,b): return op('SUBTRACT',a,b)
    def clamp(a): return op('MINIMUM',1,op('MAXIMUM',0,a))
    def ramp(a,lo,hi): return clamp(op('DIVIDE',sub(a,lo),hi-lo))
    def mix(f,a,b,label):
        q=n.new('ShaderNodeMixRGB'); q.label=label; put(f,q.inputs[0]); put(a,q.inputs[1]); put(b,q.inputs[2]); return q.outputs[0]
    uv=n.new('ShaderNodeUVMap'); uv.uv_map='FinishUV'
    tex=n.new('ShaderNodeTexImage'); tex.image=new_image; tex.extension='EXTEND'; tex.interpolation='Linear'; tex.name='UneditedAtlasV2'
    links.new(uv.outputs['UV'],tex.inputs['Vector'])
    rgb=n.new('ShaderNodeSeparateColor'); links.new(tex.outputs['Color'],rgb.inputs[0])
    gray=n.new('ShaderNodeRGBToBW'); links.new(tex.outputs['Color'],gray.inputs[0]); lum=gray.outputs[0]
    # Author-assigned response masks. Color cannot recover true scanned PBR.
    neutral=clamp(sub(1,op('DIVIDE',sub(op('MAXIMUM',rgb.outputs['Red'],op('MAXIMUM',rgb.outputs['Green'],rgb.outputs['Blue'])),op('MINIMUM',rgb.outputs['Red'],op('MINIMUM',rgb.outputs['Green'],rgb.outputs['Blue']))),.20)))
    loss=mul(ramp(lum,.075,.23),neutral)
    oxide=mul(ramp(sub(rgb.outputs['Red'],mul(rgb.outputs['Green'],1.25)),.003,.045),sub(1,ramp(lum,.24,.4)))
    color=tex.outputs['Color']; rough=.68; metal=0.; height=lum; distance=.0008; strength=.10
    if finish=='Zinc':
        color=mix(.90,(.30,.31,.31,1),color,'90% atlas color; V3 was 32%')
        bloom=ramp(lum,.24,.50)
        rough=add(.48,mul(bloom,.32)); metal=mul(.58,sub(1,mul(bloom,.67)))
        distance=.0008; strength=.10
    elif finish=='Teal':
        color=mix(.92,(.045,.10,.115,1),color,'92% atlas; spatial chips carried by component UV crop')
        exposed=mul(loss,sub(1,oxide))
        rough=add(sub(.69,mul(exposed,.17)),mul(oxide,.20))
        metal=add(.03,mul(exposed,.53)); distance=.0005; strength=.10
    elif finish=='Wall':
        color=mix(.90,(.32,.38,.40,1),color,'Quiet broad painted face; no six engraved streak masks')
        rough=add(.66,mul(loss,.13)); metal=.025; distance=.00035; strength=.07
    elif finish=='Concrete':
        metric=n.new('ShaderNodeUVMap'); metric.uv_map='MetricUV'
        ms=n.new('ShaderNodeSeparateXYZ'); links.new(metric.outputs['UV'],ms.inputs[0])
        phase=n.new('ShaderNodeVertexColor'); phase.layer_name='UVPhase'
        ps=n.new('ShaderNodeSeparateColor'); links.new(phase.outputs['Color'],ps.inputs[0])
        comb=n.new('ShaderNodeCombineXYZ')
        for axis,ch in [('X','Red'),('Y','Green')]:
            val=add(.006,mul(op('FRACT',add(op('DIVIDE',ms.outputs[axis],1.8),ps.outputs[ch])),.488))
            links.new(val,comb.inputs[axis])
        tx=n.new('ShaderNodeTexImage'); tx.image=old_image; tx.extension='EXTEND'; tx.name='OriginalCleanConcreteV1'
        links.new(comb.outputs[0],tx.inputs['Vector'])
        clean=mix(.52,(.31,.295,.27,1),tx.outputs['Color'],'Original V1 clean floor base color, unchanged')
        use=n.new('ShaderNodeVertexColor'); use.layer_name='SurfaceUse'
        sep=n.new('ShaderNodeSeparateColor'); links.new(use.outputs['Color'],sep.inputs[0]); ext=sep.outputs['Blue']
        color=mix(ext,clean,color,'New damp atlas ONLY on outward vertical foot faces')
        wet=sub(1,ramp(lum,.085,.25))
        rough=sub(.86,mul(mul(ext,wet),.32)); metal=0
        noise=n.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=110; noise.inputs['Detail'].default_value=2
        links.new(metric.outputs['UV'],noise.inputs['Vector']); height=noise.outputs['Fac']; distance=.0015; strength=.12
    elif finish=='Yellow':
        damaged=clamp(add(mul(loss,.78),mul(oxide,.35)))
        color=mix(damaged,(.58,.36,.035,1),(.22,.205,.17,1),'Sparse chip loss in real entry paint, not added rectangle geometry')
        rough=add(.72,mul(damaged,.12)); metal=0; distance=.00025; strength=.08
    elif finish=='Seal':
        color=(.022,.027,.028,1); rough=.89; metal=0; distance=.0002; strength=.05
    bs=n.new('ShaderNodeBsdfPrincipled'); bs.name='PumpPrincipled'
    out=n.new('ShaderNodeOutputMaterial'); links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    put(color,bs.inputs['Base Color']); put(clamp(rough),bs.inputs['Roughness']); put(clamp(metal),bs.inputs['Metallic'])
    bs.inputs['Emission Strength'].default_value=0; bs.inputs['Alpha'].default_value=1
    bump=n.new('ShaderNodeBump'); bump.name='ShallowMaterialOnly'; bump.inputs['Distance'].default_value=distance; bump.inputs['Strength'].default_value=strength
    put(height,bump.inputs['Height']); links.new(bump.outputs['Normal'],bs.inputs['Normal'])
    m['source_only']='Authored interpretation of color + shallow response. Not a recovered complete PBR atlas; no bake/export in V4 preview.'
    m['maximum_bump_distance_m']=distance
    return m

def main():
    start=time.time(); assert not (HERE/'pump_shell_prototype.blend').exists(),'Preserve prior run before any rerun.'
    assert sha(SOURCE)==SOURCE_SHA and sha(OLD_ATLAS)==OLD_SHA and sha(NEW_ATLAS)==NEW_SHA
    evidence=HERE/'evidence'; inputs=HERE/'source_inputs'; evidence.mkdir(exist_ok=True); inputs.mkdir(exist_ok=True)
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'source_only':True}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE)); bpy.context.view_layer.update()
    parts=[o for o in bpy.data.objects if o.get('editable_piece')]
    before=geometry_digest(parts); assert before['sha256']==GEOMETRY_SHA
    plan=json.loads((HERE.parent/'planning/contract.json').read_text(encoding='utf-8'))
    layout=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'))
    actual={s['id']:s for s in layout['fixed_solids']}
    for s in plan['fixed_shell_solids']:
        assert actual[s['id']]['min']==s['world_min'] and actual[s['id']]['max']==s['world_max']
    oldcopy=inputs/'material_atlas_v1_UNEDITED.png'; newcopy=inputs/'material_atlas_v2_UNEDITED.png'
    shutil.copyfile(OLD_ATLAS,oldcopy); shutil.copyfile(NEW_ATLAS,newcopy)
    # Redirect old source images before saving to a different directory.
    old_image=None
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            resolved=Path(bpy.path.abspath(im.filepath)); assert resolved.is_file() and sha(resolved)==OLD_SHA
            im.filepath=str(oldcopy); im.colorspace_settings.name='sRGB'; im.reload(); old_image=im
    assert old_image is not None
    new_image=bpy.data.images.load(str(newcopy),check_existing=False); new_image.colorspace_settings.name='sRGB'
    mats={f:make_material(f,new_image,old_image) for f in REGIONS}
    mapping=[]
    for o in parts:
        mapping.append(add_finish_uv(o)); o.data.materials.clear(); o.data.materials.append(mats[o['finish']]); o.hide_render=False
    bpy.context.view_layer.update(); after=geometry_digest(parts)
    assert before['sha256']==after['sha256']==GEOMETRY_SHA
    inherited=json.loads((V3/'evidence/geometry_report.json').read_text(encoding='utf-8'))
    checks=[{'name':'evaluated V3 geometry exact digest, including object names and winding','passed':before['sha256']==after['sha256']},
            {'name':'200 editable pieces, 7584 actual triangles','passed':len(parts)==200 and after['triangles']==7584},
            {'name':'every original part remains closed','passed':all(r['nonmanifold_edges']==0 for r in after['parts'])},
            {'name':'new FinishUV explicit on all parts; original two UV layers retained','passed':all([u.name for u in o.data.uv_layers]==['MetricUV','PanelUV','FinishUV'] for o in parts)},
            {'name':'six assigned author materials, no emission','passed':len(mats)==6 and all(m.node_tree.nodes['PumpPrincipled'].inputs['Emission Strength'].default_value==0 for m in mats.values())},
            {'name':'roof material has no FRACT/repetition node','passed':not any(n.type=='MATH' and n.operation=='FRACT' for n in mats['Zinc'].node_tree.nodes)}]
    report={'status':'GEOMETRY_CHECKED_NOT_YET_RENDERED','checks':checks,'geometry':after,'source_v3_sha256':SOURCE_SHA,
            'new_atlas_sha256':NEW_SHA,'clean_interior_atlas_sha256':OLD_SHA,'atlas_original_pixels':[1254,1254],
            'geometry_contract_scope':'Exact V3 geometry; inherited doorway/containment checks are historical source tests, not new Godot QA.',
            'historical_v3_checks':inherited['checks'],'mapping':mapping,'material_count':6,
            'limitations':['Atlas is base color only; rough/metal masks are author estimates.','No bake/GLB/runtime changes.','Source cutaway is not production fader evidence.']}
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not all(c['passed'] for c in checks):
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend')); raise RuntimeError('V4 gate failed before render.')
    scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=24
    scene.render.threads_mode='FIXED'; scene.render.threads=2
    # Retain V3 camera, exposure, light energy and neutral review floor exactly.
    report['camera']={'location_blender':list(scene.camera.location),'ortho_scale':scene.camera.data.ortho_scale,
                      'resolution':[scene.render.resolution_x,scene.render.resolution_y],'view':scene.view_settings.view_transform,'exposure':scene.view_settings.exposure}
    blend=HERE/'pump_shell_prototype.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath: im.filepath=bpy.path.relpath(im.filepath)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend)); scene=bpy.context.scene
    images=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath)); digest=sha(p)
            assert p.is_file() and digest in [OLD_SHA,NEW_SHA]; im.reload()
            first_pixel=tuple(im.pixels[:4])  # Force Blender's lazy file-image load.
            assert len(first_pixel)==4 and im.has_data
            assert tuple(im.size)==(1254,1254)
            images.append({'path':im.filepath,'resolved':str(p),'sha256':digest,'size':list(im.size),'colorspace':im.colorspace_settings.name,'loaded_first_pixel':first_pixel})
    assert {x['sha256'] for x in images}=={OLD_SHA,NEW_SHA}
    reopened=geometry_digest([o for o in bpy.data.objects if o.get('editable_piece')]); assert reopened['sha256']==GEOMETRY_SHA
    report['reopened_source_images']=images; report['reopened_geometry_sha256']=reopened['sha256']
    outputs=[]
    for name,cut in [('pump_shell_full',False),('pump_shell_source_cutaway',True)]:
        for o in bpy.data.objects:
            if o.get('editable_piece'): o.hide_render=cut and o.get('runtime_group') in ['WestCover','EastCover','NorthCover','RoofCover']
        path=evidence/(name+'.png'); scene.render.filepath=str(path); bpy.ops.render.render(write_still=True)
        outputs.append({'path':str(path),'sha256':sha(path),'scope':'Offline source material review; source cutaway is not actual game opacity.'})
    report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',blend_sha256=sha(blend),images=outputs,elapsed_seconds=time.time()-start)
    assert sha(SOURCE)==SOURCE_SHA
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':after['triangles']}),flush=True)

if __name__=='__main__': main()
