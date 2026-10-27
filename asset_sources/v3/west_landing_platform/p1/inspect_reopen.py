"""Bounded read-only comparison of the two saved first-run source files."""
from pathlib import Path
import sys,json,time,os,hashlib
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_source import geometry_report
from common import bpy,HERE,image_audit,sha

def source_signature():
    rows=[]
    for ob in sorted((o for o in bpy.data.objects if o.type=='MESH' and (o.get('editable_piece') or o.get('high_source'))),key=lambda x:x.name):
        m=ob.data
        rows.append({'name':ob.name,'parent':ob.parent.name,'matrix':[list(r) for r in ob.matrix_local],
                     'vertices':[list(v.co) for v in m.vertices],
                     'faces':[(list(p.vertices),p.material_index,p.use_smooth) for p in m.polygons],
                     'UV':{u.name:[list(v.uv) for v in u.data] for u in m.uv_layers},
                     'materials':[x.name for x in m.materials]})
    groups={'positions':['vertices'],'winding_material':['faces','materials'],'group_transform':['parent','matrix'],'UV':['UV']}
    return {label:hashlib.sha256(json.dumps([{k:r[k] for k in ['name']+keys} for r in rows],sort_keys=True,separators=(',',':')).encode()).hexdigest() for label,keys in groups.items()}

def main():
    began=time.monotonic();print(json.dumps({'stage':'read_only_reopen_diagnosis','pid':os.getpid(),'threads':2}),flush=True)
    out=HERE/'reopen_diagnosis';out.mkdir(exist_ok=True)
    original=json.loads((HERE/'geometry_report.json').read_text(encoding='utf-8'))
    inputs=[HERE/'source_diagnostic_checkpoint.blend',HERE/'west_landing_platform_editable.blend']
    before={str(p):sha(p) for p in inputs};results=[]
    for p in inputs:
        bpy.ops.wm.open_mainfile(filepath=str(p));bpy.context.view_layer.update()
        images=image_audit();current=geometry_report();old={r['name']:r for r in original['parts']};differences=[]
        for row in current['parts']:
            for key,value in row.items():
                if value!=old[row['name']][key]:differences.append({'object':row['name'],'field':key,'before':old[row['name']][key],'reopened':value})
        (out/(p.stem+'_actual_geometry.json')).write_text(json.dumps(current,indent=2),encoding='utf-8')
        results.append({'input':str(p),'input_sha256':before[str(p)],'source_signature':source_signature(),
                        'evaluated_signature':current['geometry_sha256'],'differences_from_pre_save_report':differences,
                        'images':images,'low_triangles':current['low_triangles'],'runtime_mesh_triangles':current['runtime_mesh_triangles']})
    assert {str(p):sha(p) for p in inputs}==before
    result={'status':'READ_ONLY_DIAGNOSIS_COMPLETE','pid':os.getpid(),'seconds':time.monotonic()-began,
            'input_SHA_unchanged':True,'results':results,
            'two_saved_sources_raw_mesh_UV_material_equal':results[0]['source_signature']==results[1]['source_signature'],
            'two_saved_sources_evaluated_equal':results[0]['evaluated_signature']==results[1]['evaluated_signature']}
    (out/'report.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps({'pid':os.getpid(),'seconds':result['seconds'],'differences':[len(r['differences_from_pre_save_report']) for r in results],
                      'raw_equal':result['two_saved_sources_raw_mesh_UV_material_equal'],'evaluated_equal':result['two_saved_sources_evaluated_equal']}),flush=True)

if __name__=='__main__':main()
