"""Read existing sources, quantify evaluated bevel UV roundoff, render once.

No source geometry, material, camera, UV or .blend is rewritten by this entry.
"""
from pathlib import Path
import sys,time,os,json
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_source import geometry_report
from inspect_reopen import source_signature
from common import bpy,HERE,image_audit,sha

OUT=HERE/'resume_preview_01'

def evaluated_uvs():
    deps=bpy.context.evaluated_depsgraph_get();result={}
    for ob in sorted((o for o in bpy.data.objects if o.type=='MESH' and (o.get('editable_piece') or o.get('high_source'))),key=lambda x:x.name):
        ev=ob.evaluated_get(deps);m=ev.to_mesh(preserve_all_data_layers=True,depsgraph=deps)
        try:
            result[ob.name]={u.name:[tuple(q.uv) for q in u.data] for u in m.uv_layers}
            face_ids=[0]*len(m.loops)
            for face in m.polygons:
                for li in face.loop_indices:face_ids[li]=face.index
            result[ob.name]['__loop_faces__']=face_ids
        finally:ev.to_mesh_clear()
    return result

def main():
    began=time.monotonic();print(json.dumps({'stage':'existing_source_UV_compare_and_render','pid':os.getpid(),'CPU_threads':2}),flush=True)
    OUT.mkdir(exist_ok=True);assert not (OUT/'01-single-object.png').exists()
    sources=[HERE/'source_diagnostic_checkpoint.blend',HERE/'west_landing_platform_editable.blend']
    original=json.loads((HERE/'geometry_report.json').read_text(encoding='utf-8'))
    diagnosis=json.loads((HERE/'reopen_diagnosis/report.json').read_text(encoding='utf-8'))
    source_shas={str(p):sha(p) for p in sources};states=[];expected={r['name']:r for r in original['parts']}
    for index,p in enumerate(sources):
        bpy.ops.wm.open_mainfile(filepath=str(p));bpy.context.view_layer.update()
        raw=source_signature();assert raw==diagnosis['results'][index]['source_signature']
        report=geometry_report()
        for row in report['parts']:
            assert {k:v for k,v in row.items() if k!='UV_sha256'}=={k:v for k,v in expected[row['name']].items() if k!='UV_sha256'},row['name']
        states.append({'raw':raw,'UV':evaluated_uvs(),'images':image_audit(),'geometry':report})
    assert states[0]['raw']==states[1]['raw']
    maxima={};worst=[]
    for name,layers in states[0]['UV'].items():
        for layer,values in layers.items():
            if layer=='__loop_faces__':continue
            other=states[1]['UV'][name][layer];assert len(values)==len(other)
            assert layers['__loop_faces__']==states[1]['UV'][name]['__loop_faces__']
            maximum=0.;at=None;affected=set();changed_loops=0
            for i,(a,b) in enumerate(zip(values,other)):
                delta=max(abs(float(x)-float(y)) for x,y in zip(a,b))
                if delta:affected.add(layers['__loop_faces__'][i]);changed_loops+=1
                if delta>maximum:maximum=delta;at={'loop':i,'checkpoint':a,'editable':b}
            maxima[layer]=max(maxima.get(layer,0.),maximum)
            if maximum:worst.append({'object':name,'layer':layer,'maximum_absolute_difference':maximum,
                                    'affected_faces':sorted(affected),'changed_loops':changed_loops,**at})
    material_uvs={m.name:[{'node':n.name,'type':n.bl_idname,'uv_map':n.uv_map} for n in m.node_tree.nodes if n.bl_idname in ('ShaderNodeUVMap','ShaderNodeNormalMap')]
                  for m in bpy.data.materials if m.use_nodes and m.name.startswith('WestLanding_')}
    record={'source_sha256':source_shas,'raw_positions_winding_material_group_UV_exact':True,
            'evaluated_geometry_normals_volume_bounds_exact':True,'maximum_evaluated_UV_difference':maxima,
            'evaluated_UV_tolerance':1e-5,'maximum_difference_at_2K_texels':max(maxima.values())*2048,
            'material_actual_UV_nodes':material_uvs,'nonzero_objects_layers':worst,'reopened_images':states[1]['images']}
    (OUT/'validation.json').write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
    assert max(maxima.values())<=1e-5,('UV exceeded delivery precision',maxima)
    assert maxima['MetricUV']==0,('Actual steel source UV changed',maxima)
    assert [(r['sha256'],r['size'],r['space']) for r in states[0]['images']]==[(r['sha256'],r['size'],r['space']) for r in states[1]['images']]
    scene=bpy.context.scene;scene.render.filepath=str(OUT/'01-single-object.png');bpy.ops.render.render(write_still=True)
    assert source_shas=={str(p):sha(p) for p in sources}
    result={'status':'EXISTING_SOURCE_RENDERED_PENDING_ART_REVIEW','pid':os.getpid(),'elapsed_seconds':time.monotonic()-began,
            'source':str(sources[1]),'source_sha256':source_shas[str(sources[1])],
            'image':scene.render.filepath,'image_sha256':sha(scene.render.filepath),
            'low_parts':original['editable_low_parts'],'low_triangles':original['low_triangles'],
            'runtime_mesh_triangles':original['runtime_mesh_triangles'],'high_only_triangles':original['high_only_triangles'],
            'geometry_changed':False,'source_rewritten':False,'baked':False,'exported':False,
            'scope':'Offline single-object source preview only; no game integration validation'}
    (OUT/'result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False),flush=True)

if __name__=='__main__':main()
