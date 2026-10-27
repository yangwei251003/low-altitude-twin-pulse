"""P3 static preparation. Load immutable P2; UV/material change only.
No bake, GLB, engine integration, pixel manipulation or geometry rebuild.
Execute only when root grants the next serial CPU2 window.
"""
from pathlib import Path
import sys,os,time,json,hashlib,struct,importlib.util
sys.dont_write_bytecode=True
import bpy

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
P2=HERE.parent/'p2';SOURCE=P2/'i2_canal_revetment_p2.blend'
SOURCE_SHA='f0604cca6362a5eeac95bdc2804d88c2414b091cfe26c1694159ce362d82af0f'
OLD_SHA='11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406'
FRONT_SHA='32df77336c0abf940f7db69ee85e4f22f9eb64af22dc881d8c2e762b73861cba'
OLD=HERE/'source_inputs/clinic_ground_material_atlas_UNEDITED.png'
FRONT=HERE/'source_inputs/revetment_front_basecolor_v2_UNEDITED.png'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,value):Path(p).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def audit_images(label):
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        absolute=Path(bpy.path.abspath(im.filepath)).resolve()
        assert absolute.is_file(),(label,im.name,str(absolute))
        digest=sha(absolute);assert digest in (OLD_SHA,FRONT_SHA),(label,im.name,digest)
        im.reload();first=tuple(im.pixels[:4]);k=(int(im.size[0])*int(im.size[1])//2)*4;middle=tuple(im.pixels[k:k+4])
        assert len(first)==4 and len(middle)==4 and im.has_data and min(im.size)>0,(label,im.name,first,middle,im.has_data)
        assert im.colorspace_settings.name=='sRGB'
        rows.append({'name':im.name,'path':str(absolute),'stored_path':im.filepath,'sha256':digest,'size':list(im.size),'first_pixel':first,'middle_pixel':middle,'has_data_after_read':im.has_data,'colorspace':im.colorspace_settings.name})
    assert len(rows)==2 and {r['sha256'] for r in rows}=={OLD_SHA,FRONT_SHA},rows
    return rows

def geometry_digest(parts):
    h=hashlib.sha256();dg=bpy.context.evaluated_depsgraph_get();totals=[]
    for o in sorted(parts,key=lambda o:o.name):
        h.update(o.name.encode('utf-8'));h.update(struct.pack('<16d',*(c for row in o.matrix_world for c in row)))
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.calc_loop_triangles()
        h.update(struct.pack('<III',len(me.vertices),len(me.polygons),len(me.loop_triangles)))
        for v in me.vertices:h.update(struct.pack('<3f',*v.co))
        for t in me.loop_triangles:h.update(struct.pack('<3I',*t.vertices))
        totals.append({'name':o.name,'triangles':len(me.loop_triangles)})
        bpy.data.meshes.remove(me)
    return {'sha256':h.hexdigest(),'parts':totals,'triangles':sum(x['triangles'] for x in totals),'scope':'actual evaluated vertex/triangle/order and transforms; UV/material intentionally excluded'}

def add_front_uv(o,gp):
    if 'FrontFaceUV' in o.data.uv_layers:raise RuntimeError('Unexpected prior FrontFaceUV')
    o.data.uv_layers.new(name='FrontFaceUV')
    # Reacquire after allocating UV; preserve the old explicit metric UV.
    uv=o.data.uv_layers['FrontFaceUV'];old=o.data.uv_layers['SurfaceMetric']
    old.active_render=True;o.data.uv_layers.active_index=o.data.uv_layers.find('SurfaceMetric')
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            p=gp(o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co)
            uv.data[li].uv=((p.x+2.)/4.,(p.y+2.8)/2.8)
    return {'name':o.name,'uv':'FrontFaceUV','formula':'u=(localX+2)/4; v=(localY+2.8)/2.8','no_warp':True}

def revise_material(mat,image,aggregate=False):
    nodes=mat.node_tree.nodes;links=mat.node_tree.links
    bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='FrontFaceUV';uv.label='Full 4m x 2.8m; no perspective warp'
    tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.extension='EXTEND';tex.interpolation='Linear';tex.label='Unedited native imagegen front colour only'
    links.new(uv.outputs['UV'],tex.inputs['Vector'])
    old_link=next(iter(bs.inputs['Base Color'].links),None)
    if old_link:
        old_socket=old_link.from_socket;links.remove(old_link)
    else:old_socket=None
    if aggregate:
        links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    else:
        facing=nodes.new('ShaderNodeAttribute');facing.attribute_name='WaterFacing'
        mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MIX';mix.label='Front: new colour; side/back: frozen P2 source'
        if old_socket:links.new(old_socket,mix.inputs[1])
        else:mix.inputs[1].default_value=(.34,.325,.30,1)
        links.new(facing.outputs['Fac'],mix.inputs[0]);links.new(tex.outputs['Color'],mix.inputs[2]);links.new(mix.outputs[0],bs.inputs['Base Color'])
    # Do not turn generated pores/light rims into geometric height or normals.
    for link in list(bs.inputs['Normal'].links):links.remove(link)
    for link in list(bs.inputs['Metallic'].links):links.remove(link)
    bs.inputs['Metallic'].default_value=0.
    for link in list(bs.inputs['Roughness'].links):links.remove(link)
    def math_node(op,a,b):
        node=nodes.new('ShaderNodeMath');node.operation=op
        for value,socket in ((a,node.inputs[0]),(b,node.inputs[1])):
            if hasattr(value,'node'):links.new(value,socket)
            else:socket.default_value=value
        return node.outputs[0]
    if aggregate:bs.inputs['Roughness'].default_value=.83
    else:
        height=nodes.new('ShaderNodeAttribute');height.attribute_name='SourceHeight'
        wet=math_node('ADD',.5,math_node('MULTIPLY',math_node('SUBTRACT',-1.2,height.outputs['Fac']),12))
        wet=math_node('MINIMUM',1,math_node('MAXIMUM',0,wet))
        rough=math_node('SUBTRACT',.88,math_node('MULTIPLY',wet,.23))
        patch=nodes.new('ShaderNodeAttribute');patch.attribute_name='RepairUse'
        rough=math_node('MAXIMUM',rough,math_node('MULTIPLY',patch.outputs['Fac'],.87))
        links.new(rough,bs.inputs['Roughness'])
    bs.inputs['Emission Color'].default_value=(0,0,0,1);bs.inputs['Emission Strength'].default_value=0
    mat['p3_front_image_sha256']=FRONT_SHA;mat['p3_neutral_normal_no_colour_height']=True
    return {'name':mat.name,'image_sha256':FRONT_SHA,'normal_input_linked':bool(bs.inputs['Normal'].links),'metallic':bs.inputs['Metallic'].default_value,'roughness':'independent dry .88 / wet .65 / repair .87' if not aggregate else '.83','emission_strength':bs.inputs['Emission Strength'].default_value,'front_image_weight':1.0,'unchanged_side_back_branch':not aggregate}

def main():
    start=time.time();evidence=HERE/'evidence';evidence.mkdir(exist_ok=True)
    final=HERE/'i2_canal_revetment_p3.blend';assert not final.exists()
    assert sha(SOURCE)==SOURCE_SHA and sha(OLD)==OLD_SHA and sha(FRONT)==FRONT_SHA
    dump(HERE/'process.json',{'pid':os.getpid(),'status':'SOURCE_MATERIAL_RUNNING','threads':2,'source_only':True})
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2}),flush=True)
    spec=importlib.util.spec_from_file_location('frozen_p2_geometry_readonly',P2/'build_source.py');support=importlib.util.module_from_spec(spec);spec.loader.exec_module(support)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    support.PARTS.clear();support.PARTS.extend(o for o in bpy.data.objects if o.get('editable_piece',False))
    assert len(support.PARTS)==8
    before=geometry_digest(support.PARTS)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            original=Path(bpy.path.abspath(im.filepath)).resolve();assert sha(original)==OLD_SHA
            im.filepath=str(OLD.resolve())
    image=bpy.data.images.load(str(FRONT.resolve()),check_existing=False);image.colorspace_settings.name='sRGB'
    preflight=audit_images('before UV/source save')
    uv_rows=[]
    for o in support.PARTS:
        if o.name in ('ConcreteBody_4m_Closed','RepairAggregate_Embedded'):uv_rows.append(add_front_uv(o,support.gp))
    mat_rows=[]
    for name in ['Revetment_Concrete_0','Revetment_Concrete_1','Revetment_Concrete_2','Repair_ExposedAggregate']:
        mat_rows.append(revise_material(bpy.data.materials[name],image,name=='Repair_ExposedAggregate'))
    bpy.context.view_layer.update();after=geometry_digest(support.PARTS);assert before==after
    report=support.inspect();assert report['passed'] and report['triangles']==5116
    report.update(status='MATERIAL_PREPARED',input_images=preflight,uv=uv_rows,materials=mat_rows,geometry_before=before,geometry_after=after,p2_source_unchanged=sha(SOURCE)==SOURCE_SHA,source_only=True,no_bake_no_export=True)
    dump(evidence/'geometry_material_report.json',report)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
    audit_images('before checkpoint');bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'material_checkpoint.blend'),relative_remap=False)
    support.camera_view('reference');bpy.ops.wm.save_as_mainfile(filepath=str(final),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(final),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(final))
    support.PARTS.clear();support.PARTS.extend(o for o in bpy.data.objects if o.get('editable_piece',False))
    report['reopened_images']=audit_images('reopened final')
    report['geometry_reopened']=geometry_digest(support.PARTS);assert before==report['geometry_reopened']
    report['reopened_geometry']=support.inspect();assert report['reopened_geometry']['passed']
    outputs=[]
    for kind,name in [('reference','01-reference-oblique.png'),('scale26','02-isolated-26m-readability.png')]:
        view=support.camera_view(kind);bpy.context.scene.render.filepath=str(evidence/name);bpy.ops.render.render(write_still=True)
        outputs.append({'path':str(evidence/name),'sha256':sha(evidence/name),'camera':view})
    assert sha(SOURCE)==SOURCE_SHA
    report.update(status='RENDERED_REQUIRES_HUMAN_REVIEW',outputs=outputs,blend_sha256=sha(final),elapsed_seconds=time.time()-start,p2_source_unchanged=True)
    dump(evidence/'geometry_material_report.json',report);print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':report['triangles']}),flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:
        import traceback
        dump(HERE/'failure.json',{'type':type(error).__name__,'message':str(error),'traceback':traceback.format_exc()})
        try:
            for im in bpy.data.images:
                if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
            bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'failed_source.blend'),relative_remap=False)
        except Exception as snapshot_error:print('ERROR failure snapshot:',repr(snapshot_error),flush=True)
        raise
