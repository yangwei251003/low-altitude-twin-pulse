"""Sequential exact half-plane crops. Every intermediate body remains closed.
Only original edge IDs identify shared intersections; UVs remain per corner.
"""
import math, collections
import bpy
from mathutils import Vector

UVS=['SurfaceMetric','FrontFaceUV']
ATTRS=['SourceHeight','SourceX','WaterFacing','RepairUse','ExposedSurface']
def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return [float(p.x),float(p.z),float(-p.y)]

def interpolate(a,b,t,point):
    n=(a['n']*(1-t)+b['n']*t).normalized()
    return dict(p=point,n=n,uv={k:tuple(a['uv'][k][j]*(1-t)+b['uv'][k][j]*t for j in range(2)) for k in UVS},
                attr={k:a['attr'][k]*(1-t)+b['attr'][k]*t for k in ATTRS})

def topology(faces):
    found=collections.defaultdict(list)
    for fi,f in enumerate(faces):
        for a,b in zip(f['ids'],f['ids'][1:]+f['ids'][:1]):found[tuple(sorted((a,b)))].append((fi,a,b))
    return found

def triangulate_ring(ring,points,outward,label):
    """Constrained ears retain every cut boundary vertex, including collinear
    subdivisions. A miter can cross an authored recessed construction joint;
    a centroid fan would incorrectly bridge that concavity.
    """
    horizontal=Vector((-outward.y,outward.x,0)).normalized()
    coords={i:(sum(float(points[i][j])*float(horizontal[j]) for j in range(3)),float(points[i].z)) for i in ring}
    def turn(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    signed=sum(coords[a][0]*coords[b][1]-coords[b][0]*coords[a][1] for a,b in zip(ring,ring[1:]+ring[:1]))
    direction=1 if signed>0 else -1
    pending=list(ring);triangles=[]
    while len(pending)>3:
        found=False
        for k,b in enumerate(pending):
            a=pending[k-1];c=pending[(k+1)%len(pending)]
            pa,pb,pc=coords[a],coords[b],coords[c]
            if turn(pa,pb,pc)*direction<=0:continue
            blocked=False
            for i in pending:
                if i in (a,b,c):continue
                q=coords[i]
                if min(turn(pa,pb,q)*direction,turn(pb,pc,q)*direction,turn(pc,pa,q)*direction)>=0:
                    blocked=True;break
            if blocked:continue
            triangles.append([a,b,c]);pending.pop(k);found=True;break
        assert found,(label,'cap constrained triangulation stalled',len(pending))
    triangles.append(pending)
    assert len(triangles)==len(ring)-2
    assert all((points[b]-points[a]).cross(points[c]-points[a]).dot(outward)>0 for a,b,c in triangles),(label,'cap winding/zero area')
    return triangles

def surface_copy(original,omit_caps,name,front_min_x=None):
    """Face subset without bmesh conversion: preserve the actual split normals."""
    old=original;selected=[p for p in old.polygons if old.attributes['ClosureCapPlane'].data[p.index].value not in omit_caps]
    polygons=[]
    for source in selected:
        cs=[dict(p=old.vertices[old.loops[li].vertex_index].co.copy(),n=old.corner_normals[li].vector.copy(),
            uv={k:tuple(old.uv_layers[k].data[li].uv) for k in UVS},attr={k:old.attributes[k].data[li].value for k in ATTRS}) for li in source.loop_indices]
        # North west wing meets the old west wall's end. Remove only the new
        # coincident front-plane patch; top/land volume and original wall stay.
        if front_min_x is not None and all(abs(c['p'].y)<1e-7 for c in cs):
            clipped=[]
            for a,b in zip(cs,cs[1:]+cs[:1]):
                da,db=a['p'].x-front_min_x,b['p'].x-front_min_x
                if da>=0:clipped.append(a)
                if (da>=0)!=(db>=0):
                    t=da/(da-db);p=a['p'].lerp(b['p'],t);p.x=front_min_x
                    clipped.append(interpolate(a,b,t,p))
            cs=clipped
        for i in range(1,len(cs)-1):
            tri=[cs[0],cs[i],cs[i+1]]
            if (tri[1]['p']-tri[0]['p']).cross(tri[2]['p']-tri[0]['p']).length_squared>0:
                polygons.append((tri,source.material_index,source.use_smooth))
    mesh=bpy.data.meshes.new(name)
    corners=[c for p,_,_ in polygons for c in p]
    mesh.from_pydata([c['p'] for c in corners],[],[(i,i+1,i+2) for i in range(0,len(corners),3)]);mesh.update()
    for material in old.materials:mesh.materials.append(material)
    for p,(_,mid,smooth) in zip(mesh.polygons,polygons):p.material_index=mid;p.use_smooth=smooth
    mesh.normals_split_custom_set([tuple(c['n']) for c in corners])
    for name in UVS:mesh.uv_layers.new(name=name)
    for name in ATTRS:mesh.attributes.new(name=name,type='FLOAT',domain='CORNER')
    for li,c in enumerate(corners):
        for name in UVS:mesh.uv_layers[name].data[li].uv=c['uv'][name]
        for name in ATTRS:mesh.attributes[name].data[li].value=c['attr'][name]
    return mesh

def crop_mesh(old,planes,label):
    old.calc_loop_triangles();points=[v.co.copy() for v in old.vertices]
    faces=[]
    for ti,t in enumerate(old.loop_triangles):
        corners=[]
        for vi,li in zip(t.vertices,t.loops):
            corners.append(dict(p=points[vi],n=old.corner_normals[li].vector.copy(),
                uv={k:tuple(old.uv_layers[k].data[li].uv) for k in UVS},
                attr={k:float(old.attributes[k].data[li].value) if old.attributes.get(k) else 0. for k in ATTRS}))
        faces.append(dict(ids=list(t.vertices),corners=corners,material=old.polygons[t.polygon_index].material_index,source=ti,cap=None))
    report=[]
    for pi,(nx,nz,d) in enumerate(planes):
        inward=Vector((nx,-nz,0));outward=-inward
        cache={};result=[]
        def signed(point):return float(inward.dot(point))-d
        for face in faces:
            polygon=[dict(c,vi=vi) for c,vi in zip(face['corners'],face['ids'])];out=[]
            for a,b in zip(polygon,polygon[1:]+polygon[:1]):
                da,db=signed(a['p']),signed(b['p']);ia,ib=da>=0.,db>=0.
                if ia:out.append(a)
                if ia!=ib:
                    t=da/(da-db)
                    if t<=1e-14: out.append(a);continue
                    if t>=1-1e-14: out.append(b);continue
                    key=tuple(sorted((a['vi'],b['vi'])))
                    if key not in cache:
                        first,last=[points[i] for i in key]
                        fa,fb=signed(first),signed(last);u=fa/(fa-fb)
                        point=Vector(tuple(float(first[j])+(float(last[j])-float(first[j]))*u for j in range(3)))
                        # Canonical point is computed once for the shared edge.
                        point+=inward*((d-float(inward.dot(point)))/inward.length_squared)
                        cache[key]=len(points);points.append(point)
                    vi=cache[key];out.append(dict(interpolate(a,b,t,points[vi]),vi=vi))
            for j in range(1,len(out)-1):
                cs=[out[0],out[j],out[j+1]];ids=[c['vi'] for c in cs]
                if len(set(ids))<3:continue
                if (cs[1]['p']-cs[0]['p']).cross(cs[2]['p']-cs[0]['p']).length_squared==0:
                    raise AssertionError((label,pi,'new zero area triangle',face['source']))
                result.append(dict(face,ids=ids,corners=cs))
        edges=topology(result)
        boundary=[occ[0] for occ in edges.values() if len(occ)==1]
        assert all(abs(signed(points[a]))<2e-6 and abs(signed(points[b]))<2e-6 for _,a,b in boundary),(label,pi,'off-plane boundary')
        follows={b:a for _,a,b in boundary}
        assert len(follows)==len(boundary),(label,pi,'branched cut ring')
        rings=[]
        while follows:
            start=min(follows);ring=[start]
            while True:
                nxt=follows.pop(ring[-1])
                if nxt==start:break
                assert nxt in follows,(label,pi,'open cut ring',nxt)
                ring.append(nxt)
            rings.append(ring)
        # Source is one solid. Multiple rings may be holes; do not fill each
        # independently and thereby conceal an unsupported topology.
        assert len(rings)==1,(label,pi,'expected one actual body cut ring',list(map(len,rings)))
        ring=rings[0]
        front_x=d/nx if abs(nx)>.01 else 0.
        def cap_corner(p):
            x,y,z=gp(p)
            if abs(nx)>.01:
                distance=math.hypot(x-front_x,z)
                source_x=front_x+math.copysign(distance,nx)
                metric=(distance,y)
            else:source_x=x;metric=(x,y)
            return dict(p=p,n=outward.normalized(),uv={'SurfaceMetric':metric,'FrontFaceUV':((source_x+2)/4,(y+2.8)/2.8)},
                attr={'SourceHeight':y,'SourceX':x,'WaterFacing':0.,'RepairUse':0.,'ExposedSurface':1. if abs(nx)>.01 else 0.})
        minimum=float('inf')
        for ids in triangulate_ring(ring,points,outward,(label,pi)):
            a,b,c=ids;cross=(points[b]-points[a]).cross(points[c]-points[a])
            minimum=min(minimum,cross.length*.5)
            result.append(dict(ids=ids,corners=[cap_corner(points[i]) for i in ids],material=0,source=None,cap=pi))
        edges=topology(result)
        assert all(len(v)==2 and v[0][1:]==v[1][1:][::-1] for v in edges.values()),(label,pi,'not oriented closed')
        report.append(dict(plane=pi,coefficients=[nx,nz,d],shared_intersections=len(cache),boundary_segments=len(ring),minimum_cap_triangle_m2=minimum))
        faces=result
    # Compact away unused source vertices, preserving all retained coordinates.
    used=sorted({i for f in faces for i in f['ids']});mapping={v:i for i,v in enumerate(used)}
    mesh=bpy.data.meshes.new(label+'_TrueCropped')
    mesh.from_pydata([points[i] for i in used],[],[[mapping[i] for i in f['ids']] for f in faces]);mesh.update()
    for material in old.materials:mesh.materials.append(material)
    for polygon,face in zip(mesh.polygons,faces):polygon.material_index=face['material'];polygon.use_smooth=True
    mesh.normals_split_custom_set([tuple(c['n']) for f in faces for c in f['corners']])
    for name in UVS:mesh.uv_layers.new(name=name)
    for name in ATTRS:mesh.attributes.new(name=name,type='FLOAT',domain='CORNER')
    mesh.attributes.new(name='ClosureCapPlane',type='INT',domain='FACE')
    for polygon,face in zip(mesh.polygons,faces):
        mesh.attributes['ClosureCapPlane'].data[polygon.index].value=-1 if face['cap'] is None else face['cap']
        for li,c in zip(polygon.loop_indices,face['corners']):
            for name in UVS:mesh.uv_layers[name].data[li].uv=c['uv'][name]
            for name in ATTRS:mesh.attributes[name].data[li].value=c['attr'][name]
    volume=sum(points[f['ids'][0]].dot(points[f['ids'][1]].cross(points[f['ids'][2]]))/6 for f in faces)
    assert volume>0,(label,'nonpositive signed volume',volume)
    mesh.calc_loop_triangles()
    return mesh,dict(planes=report,triangles=len(mesh.loop_triangles),signed_volume_m3=volume,
                    closed_edges=True,retained_source_triangles=len({f['source'] for f in faces if f['source'] is not None}),
                    cap_triangles=sum(f['cap'] is not None for f in faces))
