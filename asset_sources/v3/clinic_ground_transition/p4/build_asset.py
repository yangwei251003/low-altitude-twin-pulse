"""P4: same soil grain multiplied by dampness. Exact P3 geometry and BakeUV.
No further scatter, no new geometry. One bounded CPU2 source render.
"""
from pathlib import Path
import bpy,json,hashlib,importlib.util,sys,time,os,shutil
OUT=Path(__file__).resolve().parent;P3=OUT.parent/'p3';sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('frozen_p3_helpers',P3/'build_asset.py');H=importlib.util.module_from_spec(spec);spec.loader.exec_module(H);H.OUT=OUT
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def geometry_signature():
    rows=[]
    for o in sorted(bpy.data.objects,key=lambda o:o.name):
        if o.type!='MESH' or o.name=='STUDIO_ONLY_FLOOR':continue
        rows.append({'name':o.name,'matrix':[list(r) for r in o.matrix_world],'vertices':[list(v.co) for v in o.data.vertices],'faces':[list(p.vertices) for p in o.data.polygons],'uv':[[u.name,[list(d.uv) for d in u.data]] for u in o.data.uv_layers]})
    return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()
def main():
    start=time.time();source=P3/'uv_checkpoint.blend';source_sha=sha(source);assert not (OUT/'editable_source.blend').exists()
    for sub in ['textures','evidence','source_inputs']:(OUT/sub).mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(source));before=geometry_signature();scene=bpy.context.scene;scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
    copied=OUT/'source_inputs/material_atlas_v1_UNEDITED.png';shutil.copyfile(P3/'source_inputs/material_atlas_v1_UNEDITED.png',copied)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=str(copied)
    m=bpy.data.materials['SOURCE_soil'];m.name='SOURCE_soil_P4_same_grain_damp';n=m.node_tree.nodes;l=m.node_tree.links;bs=next(x for x in n if x.type=='BSDF_PRINCIPLED');old=bs.inputs['Base Color'].links[0].from_node
    assert old.type=='MIX_RGB' and old.blend_type=='MIX';dry=old.inputs[1].links[0].from_socket;wet=old.inputs[0].links[0].from_socket
    assert dry.node.type=='MIX_RGB'
    mult=n.new('ShaderNodeMath');mult.operation='MULTIPLY';mult.name='WetOnly_52PercentMaximumDarkening';l.new(wet,mult.inputs[0]);mult.inputs[1].default_value=.52
    factor=n.new('ShaderNodeMath');factor.operation='SUBTRACT';factor.name='BoundedDampFactor_1_to_048';factor.inputs[0].default_value=1;l.new(mult.outputs[0],factor.inputs[1])
    color=n.new('ShaderNodeMixRGB');color.name='SameDryGrain_MultipliedNotReplaced';color.blend_type='MULTIPLY';color.inputs[0].default_value=1;l.new(dry,color.inputs[1]);l.new(factor.outputs[0],color.inputs[2]);l.new(color.outputs[0],bs.inputs['Base Color'])
    old.label='P3 independently sampled wet image: disconnected in P4, retained for diagnosis'
    audit={'source_checkpoint':str(source),'source_checkpoint_sha256':source_sha,'previous_base_node':old.name,'dry_base_source':dry.node.name,'wet_factor_source':wet.node.name,'new_base_node':color.name,'formula':'same_dry_RGB * (1 - 0.52 * min(1,1.08*actual_wet))','roughness_unchanged':True,'geometry_uv_signature_before':before,'geometry_uv_signature_after_material_edit':geometry_signature()};assert geometry_signature()==before
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_source.blend'),relative_remap=False)
    proxy=bpy.data.objects['BakeProxy'];maps=[]
    for channel in ['BaseColor','ORM','Normal']:
        maps.append(H.bake(proxy,channel));(OUT/'bake_report.json').write_text(json.dumps({'status':'CHECKPOINT_'+channel,'maps':maps},indent=2),encoding='utf-8')
    final=H.final_mat(maps);proxy.data.materials.clear();proxy.data.materials.append(final)
    for p in proxy.data.polygons:p.material_index=0
    assert geometry_signature()==before
    blend=OUT/'baked_source.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(blend));reopened=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath));assert p.is_file();im.reload();pixel=tuple(im.pixels[:4]);assert len(pixel)==4 and im.has_data;reopened.append({'path':str(p),'sha256':sha(p),'colorspace':im.colorspace_settings.name})
    assert geometry_signature()==before and sha(source)==source_sha
    scene=bpy.context.scene;scene.cycles.samples=24;image=OUT/'evidence/transition_source_p4.png';scene.render.filepath=str(image);bpy.ops.render.render(write_still=True)
    report=json.loads((P3/'production_report.json').read_text());report.update(status='P4_MATERIAL_ONLY_RENDERED_PENDING_REVIEW',material_change=audit,maps=maps,reopened_images=reopened,source_sha256=sha(OUT/'editable_source.blend'),baked_source_sha256=sha(blend),geometry_uv_unchanged_from_p3=True,preview_sha256=sha(image),seconds=time.time()-start)
    (OUT/'production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');(OUT/'material_change.json').write_text(json.dumps(audit,indent=2),encoding='utf-8');print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-start}),flush=True)
if __name__=='__main__':main()
