"""No render/bake/geometry edit: distinguish cage hit, tangent join and UV faults."""
import sys, math, time, os
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import numpy as np
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import common as C

def tri_key(me,t):
    uv=me.uv_layers['BakeUV']
    return tuple(sorted(tuple(round(x,7) for x in (*me.vertices[me.loops[li].vertex_index].co,*uv.data[li].uv)) for li in t.loops))

def corners(me,t):
    uv=me.uv_layers['BakeUV']
    return {tuple(round(x,7) for x in (*me.vertices[me.loops[li].vertex_index].co,*uv.data[li].uv)):li for li in t.loops}

def tangent_triangle_copy(source):
    """Unlinked diagnostic-only mesh from Blender's existing loop triangles.

    calc_tangents rejects n-gons. Preserve original corner normals explicitly,
    so creating this temporary triangle representation cannot silently smooth
    the evaluated shading frame. No scene object or original data is replaced.
    """
    source.calc_loop_triangles()
    triangles=list(source.loop_triangles)
    me=bpy.data.meshes.new('DIAGNOSTIC_ONLY_'+source.name)
    me.from_pydata([tuple(v.co) for v in source.vertices],[],[tuple(t.vertices) for t in triangles]);me.update()
    normals=[]
    for p,t in zip(me.polygons,triangles):
        p.use_smooth=source.polygons[t.polygon_index].use_smooth
        normals.extend(tuple(source.corner_normals[li].vector) for li in t.loops)
    for old in source.uv_layers:
        layer=me.uv_layers.new(name=old.name)
        for p,t in zip(me.polygons,triangles):
            for new_li,old_li in zip(p.loop_indices,t.loops):layer.data[new_li].uv=tuple(old.data[old_li].uv)
    me.normals_split_custom_set(normals);me.update();me.calc_loop_triangles()
    errors=[C.angle(Vector(n),me.corner_normals[i].vector) or 0 for i,n in enumerate(normals)]
    return me,{'source':source.name,'source_triangles':len(triangles),'temporary_triangles':len(me.loop_triangles),
        'normal_copy_max_angle_deg':max(errors),'method':'Existing loop triangle indices/UV and explicit source corner normals; unlinked mesh, original objects untouched'}

def tangent_comparison(ground,full):
    for me in (ground,full):me.calc_loop_triangles();me.calc_tangents(uvmap='BakeUV')
    table={tri_key(full,t):t for t in full.loop_triangles}
    rows=[];missing=[]
    for t in ground.loop_triangles:
        ft=table.get(tri_key(ground,t))
        if ft is None:missing.append(t.index);continue
        fc=corners(full,ft)
        for key,li in corners(ground,t).items():
            fi=fc[key]
            rows.append({'triangle':t.index,'loop':li,'full_loop':fi,
                'normal_angle_deg':C.angle(ground.corner_normals[li].vector,full.corner_normals[fi].vector),
                'tangent_angle_deg':C.angle(ground.loops[li].tangent,full.loops[fi].tangent),
                'bitangent_sign_changed':ground.loops[li].bitangent_sign!=full.loops[fi].bitangent_sign})
    return {'unmatched_ground_triangles':missing,'corner_count':len(rows),
        'max_normal_angle_deg':max((r['normal_angle_deg'] or 0) for r in rows),
        'max_tangent_angle_deg':max((r['tangent_angle_deg'] or 0) for r in rows),
        'bitangent_sign_changes':sum(r['bitangent_sign_changed'] for r in rows),
        'largest_tangent_differences':sorted(rows,key=lambda r:r['tangent_angle_deg'] or 0,reverse=True)[:20]}

def image_array(name):
    im=bpy.data.images[name];a=np.empty(len(im.pixels),dtype=np.float32);im.pixels.foreach_get(a)
    return a.reshape((im.size[1],im.size[0],4))

def sample(a,uv):
    # Actual Image Texture Linear sampling convention: pixel centers at (i+.5)/N.
    h,w,_=a.shape;x=max(0,min(w-1,float(uv.x)*w-.5));y=max(0,min(h-1,float(uv.y)*h-.5))
    ix,iy=int(x),int(y);jx,jy=min(w-1,ix+1),min(h-1,iy+1);fx,fy=x-ix,y-iy
    return ((a[iy,ix]*(1-fx)+a[iy,jx]*fx)*(1-fy)+(a[jy,ix]*(1-fx)+a[jy,jx]*fx)*fy)[:3]

def face_kind(me,t):
    p=me.polygons[t.polygon_index]
    return 'top' if p.use_smooth else ('bottom' if p.normal.z<-.9 else 'side')

def edge_near(me,t):
    return any(abs(abs(me.vertices[v].co.x)-.45)<2e-6 or abs(me.vertices[v].co.y+.9)<2e-6 for v in t.vertices)

def uv_area(me,t,name):
    q=[me.uv_layers[name].data[i].uv for i in t.loops]
    return abs((q[1].x-q[0].x)*(q[2].y-q[0].y)-(q[1].y-q[0].y)*(q[2].x-q[0].x))*.5

def main():
    started=time.monotonic();C.open_source();before=C.fingerprints()
    lo,lo_copy=tangent_triangle_copy(bpy.data.objects['LowGround'].data)
    full,full_copy=tangent_triangle_copy(bpy.data.objects['LowFull'].data)
    hi=bpy.data.objects['HighGround'].data
    C.write('temporary_tangent_meshes.json',[lo_copy,full_copy])
    for me in (lo,hi,full):me.calc_loop_triangles()
    tangent=tangent_comparison(lo,full);C.write('tangent_join_check.json',tangent)
    tree=BVHTree.FromPolygons([v.co for v in hi.vertices],[tuple(t.vertices) for t in hi.loop_triangles],all_triangles=True)
    normal=image_array('Study1K_Normal');orm=image_array('Study1K_ORM')
    uv=lo.uv_layers['BakeUV'];rows=[];side=[]
    # Centroids of all triangles; seven samples on actual outer-boundary triangles.
    bary=[(1/3,1/3,1/3),(.96,.02,.02),(.02,.96,.02),(.02,.02,.96),(.49,.49,.02),(.49,.02,.49),(.02,.49,.49)]
    for t in lo.loop_triangles:
        kind=face_kind(lo,t);rim=edge_near(lo,t)
        if kind=='side':side.append({'triangle':t.index,'area':t.area,'source_uv_areas':{n:uv_area(lo,t,n) for n in ('RockScanUV','SoilScanUV')},'bake_uv_area':uv_area(lo,t,'BakeUV')})
        coords=[lo.vertices[i].co for i in t.vertices]
        # Exact 35mm vertex-normal cage construction used by the frozen script.
        offsets=[lo.vertices[i].normal*.035 for i in t.vertices]
        for bi,weights in enumerate(bary if rim else bary[:1]):
            p=sum((q*w for q,w in zip(coords,weights)),Vector())
            off=sum((q*w for q,w in zip(offsets,weights)),Vector())
            uvp=sum((uv.data[li].uv*w for li,w in zip(t.loops,weights)),Vector((0,0)))
            tex=sample(normal,uvp);a=sample(orm,uvp)
            splitn=sum((lo.corner_normals[li].vector*w for li,w in zip(t.loops,weights)),Vector()).normalized()
            tangentv=sum((lo.loops[li].tangent*w for li,w in zip(t.loops,weights)),Vector()).normalized()
            sign=sum(lo.loops[li].bitangent_sign*w for li,w in zip(t.loops,weights))
            bitangent=splitn.cross(tangentv)*(1 if sign>=0 else -1)
            tn=Vector(tuple(float(v)*2-1 for v in tex))
            decoded=(tangentv*tn.x+bitangent*tn.y+splitn*tn.z).normalized()
            hit,hn,idx,dist=tree.ray_cast(p+off,-off.normalized(),.12)
            nearest,nn,ni,nd=tree.find_nearest(p)
            hit_kind=face_kind(hi,hi.loop_triangles[idx]) if hit is not None else None
            nearest_kind=face_kind(hi,hi.loop_triangles[ni]) if nearest is not None else None
            mapped_angle=C.angle(decoded,splitn)
            # Evidence flags only, not replacement pass/fail tolerances.
            abnormal=(mapped_angle is not None and mapped_angle>60) or a[0]<.2
            if rim or abnormal:
                rows.append({'low_triangle':t.index,'bary_sample':bi,'barycentric':weights,'kind':kind,'rim':rim,
                    'position_blender':list(p),'uv':list(uvp),'normal_rgb':tex.tolist(),'ao_rough_metal':a.tolist(),
                    'normal_against_split_deg':mapped_angle,'tangent_dot_normal':tangentv.dot(splitn),'tangent_normal_length':tn.length,
                    'cage_origin':list(p+off),'cage_direction':list(-off.normalized()),
                    'reconstructed_ray_hit_triangle':idx,'reconstructed_ray_hit_kind':hit_kind,'ray_distance':dist,
                    'ray_hit_against_split_deg':C.angle(hn,splitn) if hit is not None else None,
                    'nearest_triangle':ni,'nearest_kind':nearest_kind,'nearest_distance':nd,
                    'hit_displacement_from_low_m':(hit-p).length if hit is not None else None,
                    'cage_hit_other_surface_kind':hit_kind is not None and hit_kind!=kind,'diagnostic_flag':bool(abnormal)})
    C.write('boundary_rays_and_normals.json',{'scope':'Independent BVH reconstruction of the authored cage, not instrumentation of Cycles internal bake hits. Face-group changes at exact corners can be ambiguous; use rendered toggles and actual UV data together.','samples':rows})
    C.write('side_uv_diagnosis.json',{'side_triangles':side,'zero_RockScanUV_area_count':sum(r['source_uv_areas']['RockScanUV']<1e-14 for r in side),'zero_SoilScanUV_area_count':sum(r['source_uv_areas']['SoilScanUV']<1e-14 for r in side),'geometry_or_uv_modified':False})
    assert before==C.fingerprints(),'diagnostic modified geometry/UV'
    C.check_inputs()
    C.write('diagnostic_result.json',{'status':'EVIDENCE_ONLY_NO_REPAIR_OR_VISUAL_PASS','pid':os.getpid(),'seconds':time.monotonic()-started,'ground_triangles':len(lo.loop_triangles),'recorded_boundary_or_abnormal_samples':len(rows),'ray_other_surface_kind_count':sum(r['cage_hit_other_surface_kind'] for r in rows),'normal_over_60deg_count':sum((r['normal_against_split_deg'] or 0)>60 for r in rows),'ao_below_point2_count':sum(r['ao_rough_metal'][0]<.2 for r in rows),'mesh_digests':before,'tangent_join':tangent,'rendered':False})

if __name__=='__main__':main()
