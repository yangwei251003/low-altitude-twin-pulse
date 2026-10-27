"""Read-only old full-source AO cage-ray identity at 32 diagnosed dark pixels.

Reconstructs the documented original 35mm vertex-normal cage. This records
geometric first hits, not instrumented Cycles stochastic AO history.
"""
from pathlib import Path
import sys, time, os, json
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import numpy as np
from mathutils import Vector
import common as C


def first_hit(data, bvh, ids, position, offset, group_labels):
    origin=position+offset; direction=-offset/np.linalg.norm(offset)
    p,n,i,dist=bvh.ray_cast(Vector(origin),Vector(direction),2.)
    if p is None: return {'hit':False}
    tid=int(ids[i]); weights=C.bary3(np.asarray(p),data['tri'][tid])
    cn=np.sum(data['normals'][tid]*weights[:,None],axis=0);cn/=np.linalg.norm(cn)
    return {'hit':True,'original_triangle':tid,'group':group_labels[tid], 'position':list(p),
            'distance_from_cage_m':float(dist),'geometric_normal':list(n),'corner_normal':cn.tolist(),
            'normal_dot_ray':float(np.asarray(n)@direction),'normal_dot_target':float(cn@(offset/np.linalg.norm(offset)))}


def main():
    start=time.monotonic();before=C.verify_inputs();C.write('inputs_before.json',before)
    bpy.ops.wm.open_mainfile(filepath=str(C.ROOT/C.CONTRACT['blend']))
    plan=json.loads((C.ROOT/C.CONTRACT['projection_groups']).read_text(encoding='utf-8'))
    current=C.read(bpy.data.objects['RepairLowFull']);oldlow=C.read(bpy.data.objects['LowFull'])
    oldhigh=C.read(bpy.data.objects['HighFull']);repairedhigh=C.read(bpy.data.objects['RepairHighFull'])
    assert np.array_equal(oldlow['tri'],current['tri']) and np.array_equal(oldlow['uv']['BakeUV'],current['uv']['BakeUV'])
    assert np.array_equal(oldhigh['tri'],repairedhigh['tri'])
    highlabels=C.labels(oldhigh,plan);full,full_ids=C.tree(oldhigh)
    groundids=np.asarray([i for i,g in enumerate(highlabels) if g=='ground_top'],np.int32)
    ground,ground_ids=C.tree(oldhigh,groundids)
    raw=json.loads((C.ROOT/C.CONTRACT['pixel_evidence']).read_text(encoding='utf-8'))['samples']
    samples=[r for r in raw if r['region']=='fragment_base' and r['low_luma']<.15 and r['high_luma']-r['low_luma']>.06]
    assert len(samples)==32 and all(r['low']['group']=='ground_top' for r in samples)
    ao_nodes=[]
    for mat in oldhigh['mesh'].materials:
        n=mat.node_tree.nodes['DIAG_AO']
        ao_nodes.append({'material':mat.name,'type':n.type,'only_local':n.only_local,'inside':n.inside,
                         'samples':n.samples,'distance':n.inputs['Distance'].default_value,'normal_linked':bool(n.inputs['Normal'].links)})
        assert n.type=='AMBIENT_OCCLUSION' and n.only_local and not n.inside
        assert abs(n.inputs['Distance'].default_value-.035)<1e-7
    C.write('old_source_AO_nodes.json',ao_nodes)
    rows=[];texels={}
    def cast(tid, weights):
        pos=np.sum(oldlow['tri'][tid]*weights[:,None],axis=0)
        off=np.sum(oldlow['vertex_normals'][oldlow['vi'][tid]]*weights[:,None],axis=0)*.035
        assert np.linalg.norm(off)>1e-6
        return {'low_original_triangle':int(tid),'barycentric':weights.tolist(),'low_position':pos.tolist(),
                'cage_offset':off.tolist(),'full_source':first_hit(oldhigh,full,full_ids,pos,off,highlabels),
                'matching_ground_source':first_hit(oldhigh,ground,ground_ids,pos,off,highlabels)}
    for r in samples:
        tid=r['low']['triangle']; weights=np.asarray(r['low']['barycentric'])
        row={'screen_pixel':r['pixel'],'old_AO_bilinear':r['maps']['bilinear']['ORM'][0],
             'surface_point_ray':cast(tid,weights),'texel_keys':[]}
        for tap in r['maps']['taps']:
            x,y=tap['pixel_bottom_origin']; owner=tap['interior_owner']
            assert owner>=0 and plan['full_triangle_groups'][owner]=='ground_top'
            key=f'{x},{y}';row['texel_keys'].append({'key':key,'bilinear_weight':tap['weight']})
            if key not in texels:
                uv=np.asarray([(x+.5)/1024.,(y+.5)/1024.])
                w=C.bary2(uv,oldlow['uv']['BakeUV'][owner]); assert min(w)>-1e-6
                texels[key]={'pixel_bottom_origin':[x,y],'old_AO':tap['values']['ORM'][0],**cast(owner,w)}
        rows.append(row)
    C.write('old_cage_ray_identity.json',{'screen_points':rows,'actual_texel_centers':list(texels.values()),
        'scope':'Original full-object first-hit reconstruction plus matched-ground control. AO shader samples are not re-executed or altered.'})
    allr=[r['surface_point_ray'] for r in rows]
    counts={}
    for r in allr:
        g=r['full_source'].get('group','MISS');counts[g]=counts.get(g,0)+1
    after=C.verify_inputs();assert after==before;C.write('inputs_after.json',after)
    C.write('result.json',{'status':'READONLY_AO_IDENTITY_COMPLETE','pid':os.getpid(),'seconds':time.monotonic()-start,
        'screen_points':len(rows),'unique_texel_centers':len(texels),'full_first_hit_groups':counts,
        'same_source_positions_and_BakeUV_verified':True,'input_hashes_unchanged':True,
        'saved':False,'baked':False,'rendered':False,'AO_modified':False,
        'limit':'First-hit identity can identify misprojection risk; it does not reproduce the historical stochastic AO integrator or prove every dark pixel is erroneous.'})


if __name__=='__main__':main()
