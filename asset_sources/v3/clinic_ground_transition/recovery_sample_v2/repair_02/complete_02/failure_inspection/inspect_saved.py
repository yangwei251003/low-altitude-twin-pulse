"""Read actual failed low copy; no mutation, save, bake or rendering."""
from pathlib import Path
import sys,os,time,json,hashlib
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]))
import bpy
import numpy as np
import common as C

FAIL=HERE.parent/'run_20261020_024131_329955'


def main():
    start=time.monotonic();path=FAIL/'failed_pipeline.blend';before=C.sha(path)
    inputs=C.verify_inputs();bpy.ops.wm.open_mainfile(filepath=str(path))
    source=C.read(bpy.data.objects['RepairLowFull']);actual=C.read(bpy.data.objects['BoundaryLowFull'])
    mapping=json.loads((FAIL/'BoundaryLowFull_original_face_and_corner_mapping.json').read_text(encoding='utf-8'))
    ids=np.asarray(mapping['original_triangle'],np.int32);weights=np.asarray(mapping['original_corner_barycentrics'],np.float64)
    expected=np.einsum('nij,njk->nik',weights,source['tri'][ids]);error=np.linalg.norm(actual['tri']-expected,axis=-1)
    normal=np.einsum('nij,njk->nik',weights,source['normals'][ids]);normal/=np.linalg.norm(normal,axis=-1)[...,None]
    an=actual['normals']/np.linalg.norm(actual['normals'],axis=-1)[...,None]
    angle=np.degrees(np.arccos(np.clip(np.sum(normal*an,axis=-1),-1,1)))
    order=np.argsort(angle.ravel())[::-1][:12];worst=[]
    for flat in order:
        tid,corner=np.unravel_index(flat,angle.shape)
        worst.append({'candidate_triangle':int(tid),'candidate_corner':int(corner),'original_triangle':int(ids[tid]),
                      'angle_deg':float(angle[tid,corner]),'position_error_m':float(error[tid,corner]),
                      'weights':weights[tid,corner].tolist(),'expected_normal':normal[tid,corner].tolist(),'actual_normal':an[tid,corner].tolist(),
                      'candidate_position':actual['tri'][tid,corner].tolist(),'original_smooth':bool(source['smooth'][ids[tid]]),'candidate_smooth':bool(actual['smooth'][tid]),
                      'original_triangle_normals':source['normals'][ids[tid]].tolist()})
    matrix_same=all(tuple(a)==tuple(b) for a,b in zip(actual['object'].matrix_world,source['object'].matrix_world))
    report={'status':'READONLY_FAILURE_NUMBERS','pid':os.getpid(),'seconds':time.monotonic()-start,
            'max_position_error_m':float(error.max()),'max_normal_angle_deg':float(angle.max()),'corners_over_001deg':int((angle>.01).sum()),
            'matrix_same':matrix_same,'UV_max_interpolation_error':{u:float(np.abs(actual['uv'][u]-np.einsum('nij,njk->nik',weights,source['uv'][u][ids])).max()) for u in source['uv']},
            'worst_normals':worst,'source_has_custom_normals':source['mesh'].has_custom_normals,'candidate_has_custom_normals':actual['mesh'].has_custom_normals,
            'source_sharp_edges':sum(e.use_edge_sharp for e in source['mesh'].edges),'candidate_sharp_edges':sum(e.use_edge_sharp for e in actual['mesh'].edges),
            'saved_blend_unchanged':C.sha(path)==before,'inputs_unchanged':C.verify_inputs()==inputs,'source_saved':False,'rendered':False,'baked':False}
    assert report['saved_blend_unchanged'] and report['inputs_unchanged']
    C.write('failure_numbers.json',report)
    print(json.dumps({k:v for k,v in report.items() if k!='worst_normals'}),flush=True)


if __name__=='__main__':main()
