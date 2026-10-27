"""Read saved projection tools; never rebuild, bake, render or save the scene."""
from pathlib import Path
import sys,os,json,hashlib,time,math
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[5]
OUT=Path(os.environ['MATCHED_GROUP_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
CONTRACT=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
def check_inputs():
    rows=[]
    for rel,e in CONTRACT['inputs'].items():
        p=ROOT/rel;actual={'sha256':sha(p),'bytes':p.stat().st_size}
        assert actual==e,(rel,actual,e);rows.append({'path':rel,**actual})
    return rows


def read_mesh(me):
    me.calc_loop_triangles()
    coords=np.asarray([tuple(v.co) for v in me.vertices],np.float64)
    vertices=np.asarray([tuple(t.vertices) for t in me.loop_triangles],np.int32)
    loops=np.asarray([tuple(t.loops) for t in me.loop_triangles],np.int32)
    normals=np.asarray([tuple(n.vector) for n in me.corner_normals],np.float64)
    result={'coords':coords,'vertices':vertices,'loops':loops,'positions':coords[vertices],
            'normals':normals[loops],'vertex_normals':np.asarray([tuple(v.normal) for v in me.vertices],np.float64)}
    if 'BakeUV' in me.uv_layers:
        u=np.asarray([tuple(d.uv) for d in me.uv_layers['BakeUV'].data],np.float64);result['uv']=u[loops]
    return result


def normal_angles(a,b):
    a=a/np.linalg.norm(a,axis=-1)[...,None];b=b/np.linalg.norm(b,axis=-1)[...,None]
    return np.degrees(np.arccos(np.clip(np.sum(a*b,axis=-1),-1.,1.)))


def key(points):return tuple(sorted(tuple(round(float(v),8) for v in p) for p in points))
def uv_bary(p,q):
    a,b,c=q;d=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);assert abs(d)>1e-14
    v=((p[0]-a[0])*(c[1]-a[1])-(p[1]-a[1])*(c[0]-a[0]))/d
    w=((b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0]))/d
    return np.asarray([1-v-w,v,w],np.float64)


def xyz_bary(p,q):
    a,b,c=q;n=np.cross(b-a,c-a);den=np.dot(n,n);assert den>1e-28
    v=np.dot(np.cross(p-a,c-a),n)/den;w=np.dot(np.cross(b-a,p-a),n)/den
    return np.asarray([1-v-w,v,w],np.float64)


def main():
    started=time.monotonic();before=check_inputs();write('inputs_before.json',before)
    source=ROOT/CONTRACT['blend'];bpy.ops.wm.open_mainfile(filepath=str(source))
    prepared=source.parent
    plan=json.loads((prepared/'projection_groups.json').read_text(encoding='utf-8'))
    oldrows=json.loads((prepared/'bad_pixel_source_normals.json').read_text(encoding='utf-8'))['samples']
    oldfailure=json.loads((prepared/'post_run_gate_audit.json').read_text(encoding='utf-8'))
    arrays={name:read_mesh(bpy.data.objects[name].data) for name in ('HighGround','LowGround','HighSolids','LowSolids','LowFull')}
    tools={};copy_rows=[];fail=[]
    for g in plan['groups']:
        category='Ground' if g['name'].startswith('ground_') else 'Solids'
        high=bpy.data.objects[g['source']];low=bpy.data.objects[g['target']];cage=bpy.data.objects[g['cage']]
        assert not high.modifiers and not low.modifiers and not cage.modifiers,('Unexpected saved projection modifier',g['name'])
        actual={'high':read_mesh(high.data),'low':read_mesh(low.data),'cage':read_mesh(cage.data)}
        row={'group':g['name'],'source':high.name,'target':low.name,'cage':cage.name}
        for role,original_name in [('high','High'+category),('low','Low'+category)]:
            ids=np.asarray(g[role+'_meta']['original_triangles'],np.int32)
            original=arrays[original_name];copy=actual[role]
            positions_equal=np.array_equal(copy['positions'],original['positions'][ids])
            angles=normal_angles(copy['normals'],original['normals'][ids])
            r={'triangles':len(ids),'position_winding_exact':positions_equal,'split_normal_max_angle_deg':float(angles.max()),
               'matrix_exact':all(tuple(a)==tuple(b) for a,b in zip(bpy.data.objects[original_name].matrix_world,(high if role=='high' else low).matrix_world))}
            if role=='low':r['BakeUV_exact']=np.array_equal(copy['uv'],original['uv'][ids])
            row[role]=r
            if not positions_equal or not r['matrix_exact'] or r['split_normal_max_angle_deg']>=.1 or not r.get('BakeUV_exact',True):
                fail.append({'stage':'copy_identity','group':g['name'],'role':role,'evidence':r})
        ids=np.asarray(g['low_meta']['original_triangles'],np.int32);original=arrays['Low'+category]
        expected_offsets=original['vertex_normals'][original['vertices'][ids]]*.035
        actual_offsets=actual['cage']['positions']-actual['low']['positions']
        cage_error=float(np.max(np.linalg.norm(actual_offsets-expected_offsets,axis=-1)))
        cage_topology=np.array_equal(actual['cage']['vertices'],actual['low']['vertices'])
        cage_matrix=all(tuple(a)==tuple(b) for a,b in zip(cage.matrix_world,low.matrix_world))
        row['cage_original_offset_max_error_m']=cage_error;row['cage_target_topology_exact']=cage_topology;row['cage_target_matrix_exact']=cage_matrix
        if cage_error>1e-7 or not cage_topology or not cage_matrix:fail.append({'stage':'cage_identity','group':g['name'],'evidence':row})
        tools[g['name']]={'plan':g,'data':actual,'high_object':high,'lookup':{key(p):i for i,p in enumerate(actual['low']['positions'])}}
        copy_rows.append(row)
    write('actual_copy_identity.json',{'groups':copy_rows,'failures':fail,'scope':'Actual saved triangles, winding, split normals, BakeUV and original35mm cage offsets. No objects created.'})
    if fail:
        write('result.json',{'status':'FAIL_COPY_IDENTITY','failures':fail,'pid':os.getpid(),'seconds':time.monotonic()-started,'baked':False,'rendered':False})
        raise AssertionError(('Saved projection copy failed',len(fail)))
    for name,t in tools.items():
        a=t['data']['high'];t['tree']=BVHTree.FromPolygons([Vector(p) for p in a['coords']],[tuple(v) for v in a['vertices']],all_triangles=True)
    rows=[];fail=[]
    for old in oldrows:
        t=tools[old['group']];lo=t['data']['low'];hi=t['data']['high'];ca=t['data']['cage']
        original_points=arrays['LowFull']['positions'][old['low_full_triangle']]
        tid=t['lookup'][key(original_points)]
        w=uv_bary(np.asarray(old['uv']),lo['uv'][tid]);position=np.sum(lo['positions'][tid]*w[:,None],axis=0)
        origin=np.sum(ca['positions'][tid]*w[:,None],axis=0);off=origin-position
        low_normal=np.sum(lo['normals'][tid]*w[:,None],axis=0);low_normal/=np.linalg.norm(low_normal)
        hit,gn,hid,dist=t['tree'].ray_cast(Vector(origin),Vector(-off).normalized(),.12)
        row={'pixel':old['pixel'],'group':old['group'],'actual_source_object':t['high_object'].name,'target_triangle':tid,
             'uv':old['uv'],'low_position':position.tolist(),'cage_origin':origin.tolist(),'cage_offset':off.tolist(),
             'original_closed_source_hit':old['hit'],'matched_group_hit':hid,'ray_distance_m':dist}
        if hit is None:row['failure']='matched_source_miss'
        else:
            hw=xyz_bary(np.asarray(hit),hi['positions'][hid]);sn=np.sum(hi['normals'][hid]*hw[:,None],axis=0);sn/=np.linalg.norm(sn)
            geometric=np.asarray(gn);gd=float(np.dot(geometric,low_normal));sd=float(np.dot(sn,low_normal))
            original_id=t['plan']['high_meta']['original_triangles'][hid]
            row.update(original_source_triangle_id=original_id,source_identity_verified=True,high_barycentric=hw.tolist(),
                       high_geometric_normal=list(gn),high_interpolated_corner_normal=sn.tolist(),
                       geometric_dot_low=gd,corner_dot_low=sd,geometric_angle_deg=math.degrees(math.acos(max(-1.,min(1.,gd)))),
                       corner_angle_deg=math.degrees(math.acos(max(-1.,min(1.,sd)))))
            if gd<=0 or sd<=0:row['failure']='matched_high_normal_faces_away'
        if 'failure' in row:fail.append(row)
        rows.append(row)
    write('matched_bad_pixel_rays.json',{'samples':rows,'failures':fail,'original_cross_component_failures_retained':oldfailure['wrong_components'],
                                       'scope':'Independent rays against actual saved matching high tool only; not an executed Cycles bake.'})
    after=check_inputs();assert before==after;write('inputs_after.json',after)
    special=[r for r in rows if r['pixel']==[860,849]]
    result={'status':'PASS_MATCHED_GROUP_PREFLIGHT' if not fail else 'FAIL_MATCHED_GROUP_PREFLIGHT','pid':os.getpid(),
            'seconds':time.monotonic()-started,'copies_checked':len(copy_rows),'pixels_checked':len(rows),'failures':len(fail),
            'former_cross_component_pixel':special,'input_hashes_unchanged':True,'source_blend_sha256':sha(source),
            'objects_created':False,'geometry_material_uv_modified':False,'source_saved':False,'baked':False,'rendered':False,
            'limit':'Passing permits considering a later bake; it does not prove that the black rim is repaired.'}
    write('result.json',result)
    assert not fail,('Matched source preflight failed',len(fail))


if __name__=='__main__':main()
