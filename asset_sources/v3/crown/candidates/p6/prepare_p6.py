"""One p6 source candidate. P5 runtime/source inputs are read-only.
Measure actual CoreSeed projected area along game OFFSET(32,39,32), not anchors.
"""
import bpy, math, json, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;CROWN=HERE.parents[1];INPUT=CROWN/'parasitic_crown.blend'
assert hashlib.sha256(INPUT.read_bytes()).hexdigest()=='0fddfb5f30fb63a29ece632d22ce07ba5b27bfbb5ef64d53c31f57a33991d4f7'
bpy.ops.wm.open_mainfile(filepath=str(INPUT));scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=10
model=bpy.data.collections['Crown_EDITABLE_MASTER'];objects=list(model.objects);meshes=[o for o in objects if o.type=='MESH']
rest={o.name:o.matrix_basis.copy() for o in objects if o.type=='EMPTY'}
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def replace(o,vertices,faces,uvs=None):
    inv=o.matrix_world.inverted();data=bpy.data.meshes.new(o.name+'_P6');data.from_pydata([tuple(inv@bp(p)) for p in vertices],[],faces);data.update()
    for mat in o.data.materials:data.materials.append(mat)
    o.data=data
    if uvs:
        uv=data.uv_layers.new(name='PaintUV');uv.active_render=True
        for poly,values in zip(data.polygons,uvs):
            for li,value in zip(poly.loop_indices,values):uv.data[li].uv=value
def rib(o,path,radii):
    ps=[Vector(p)for p in path];samples=[];rs=[]
    for k in range(len(ps)-1):
        a=ps[max(0,k-1)];b=ps[k];c=ps[k+1];d=ps[min(len(ps)-1,k+2)]
        for step in range(8):
            t=step/8;samples.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3));rs.append(radii[k]*(1-t)+radii[k+1]*t)
    samples.append(ps[-1]);rs.append(radii[-1]);verts=[];faces=[];uvs=[];sides=8
    for k,p in enumerate(samples):
        tangent=(samples[min(k+1,len(samples)-1)]-samples[max(0,k-1)]).normalized();axis=tangent.cross(Vector((0,1,0))).normalized()
        if axis.length<.1:axis=tangent.cross(Vector((1,0,0))).normalized()
        other=tangent.cross(axis).normalized()
        for j in range(sides):verts.append(tuple(p+axis*math.cos(j*math.tau/sides)*rs[k]+other*math.sin(j*math.tau/sides)*rs[k]*.75))
    for k in range(len(samples)-1):
        for j in range(sides):
            jj=(j+1)%sides;faces.append((k*sides+j,k*sides+jj,(k+1)*sides+jj,(k+1)*sides+j));uvs.append([(j/sides,k/(len(samples)-1)),((j+1)/sides,k/(len(samples)-1)),((j+1)/sides,(k+1)/(len(samples)-1)),(j/sides,(k+1)/(len(samples)-1))])
    for k in [0,len(samples)-1]:faces.append(tuple(k*sides+j for j in range(sides)));uvs.append([(.5+.45*math.cos(j*math.tau/sides),.5+.45*math.sin(j*math.tau/sides))for j in range(sides)])
    replace(o,verts,faces,uvs)
def area(o):return sum(p.area for p in o.data.polygons)
leaf_areas={}
for side in [-1,1]:
    name='LeafMembrane_'+str(side);o=bpy.data.objects[name];old_area=area(o)
    base=[(.95,.65,-1.15),(1.25,1.65,-1.45),(1.55,2.45,-1.80),(2.05,2.62,-1.65),(2.58,2.35,-1.85),(2.50,1.95,-2.02),(3.02,2.08,-1.87),(2.90,1.10,-2.30),(2.60,.50,-2.55),(2.25,.20,-2.50),(1.90,.40,-2.20),(1.45,.28,-1.65)]
    points=[(side*x,y-(.12 if side<0 and i>1 else 0),z)for i,(x,y,z)in enumerate(base)];center=Vector((side*2.02,1.27,-1.87));n=len(points)
    inner=[Vector(p).lerp(center,.30)+Vector((0,.07,.035))for p in points]
    verts=points+[tuple(p)for p in inner]+[tuple(center)]+[(x,y-.05,z-.018)for x,y,z in points]+[tuple(center-Vector((0,.05,.018)))]
    coords=np.array(points);uv=[((abs(p[0])-.95)/2.1,(p[1]-.1)/2.6)for p in points];cu=(.51,.45);inner_uv=[(u*.7+cu[0]*.3,v*.7+cu[1]*.3)for u,v in uv]
    faces=[];uvs=[]
    for j in range(n):
        k=(j+1)%n;faces.extend([(j,k,n+k,n+j),(n+j,n+k,2*n),(2*n+1+k,2*n+1+j,3*n+1),(j,2*n+1+j,2*n+1+k,k)])
        uvs.extend([[uv[j],uv[k],inner_uv[k],inner_uv[j]],[inner_uv[j],inner_uv[k],cu],[uv[k],uv[j],cu],[(0,.01),(0,.04),(1,.04),(1,.01)]])
    replace(o,verts,faces,uvs);leaf_areas[name]={'old_surface_area':old_area,'new_surface_area':area(o),'ratio':area(o)/old_area}
    rib(bpy.data.objects['LeafSpar_'+str(side)],[points[0],points[1],points[2]],[.17,.13,.018])
    rib(bpy.data.objects['LeafOuterRib_'+str(side)],[points[1],tuple(center),points[4],points[6]],[.12,.10,.07,.012])
    rib(bpy.data.objects['LeafLowerRib_'+str(side)],[points[0],tuple(center),points[8],points[9]],[.12,.10,.05,.01])
untwisted_leaf_vertices={}
for side in [-1,1]:
    pivot=gp(bpy.data.objects['LeafPivot_'+('L'if side<0 else'R')].matrix_world.translation)
    for prefix in ['LeafMembrane_','LeafSpar_','LeafOuterRib_','LeafLowerRib_']:
        o=bpy.data.objects[prefix+str(side)];before=[gp(o.matrix_world@v.co)for v in o.data.vertices]
        if prefix=='LeafMembrane_':untwisted_leaf_vertices[o.name]=before
        for vertex,p in zip(o.data.vertices,before):
            delta=p-pivot;distance=math.hypot(delta.x,delta.z);weight=min(1.0,distance/1.05)
            angle=math.radians((48 if side<0 else -22)*weight);turned=Matrix.Rotation(angle,3,'Y')@delta
            turned.y+=.10*math.sin(min(1.0,distance/2.3)*math.pi)
            vertex.co=o.matrix_world.inverted()@bp(pivot+turned)
        o.data.update()
    leaf_areas['LeafMembrane_'+str(side)]['twisted_surface_area']=area(bpy.data.objects['LeafMembrane_'+str(side)])
# Retain the full sleeve mesh/topology, but reshape the three front rings into
# an asymmetric raised aperture. The actual +X/+Y/+Z camera needed this clearance.
sleeve=bpy.data.objects['Torso_ContinuousRootSleeve'];original_profiles={4:(1.25,1.37,1.13,-.28),5:(1.60,.90,.90,-.48),6:(.70,.78,.78,-.48)}
new_profiles={4:(1.25,1.50,1.25,-.05,.12),5:(1.60,1.22,1.27,-.05,.28),6:(.70,.90,1.05,-.32,.08)}
for vertex in sleeve.data.vertices:
    k=vertex.index//24
    if k not in new_profiles:continue
    z,rx,ry,cy,cx=new_profiles[k];j=vertex.index%24;a=j*math.tau/24;factor=1+.075*math.sin(3*a+k*.6)+.025*math.cos(5*a-k*.9)
    point=(cx+math.cos(a)*rx*factor,cy+math.sin(a)*ry*factor,z+.06*math.cos(a*2+k))
    vertex.co=sleeve.matrix_world.inverted()@bp(point)
sleeve.data.update()
for side in [-1,1]:
    brow=bpy.data.objects['BrowRoot_'+str(side)]
    for vertex in brow.data.vertices:
        p=gp(brow.matrix_world@vertex.co);weight=max(0,1-abs(abs(p.x)-.50)/.90)
        p.y+=(.55 if side>0 else .25)*weight;p.x+=side*.10*weight;p.z-=.18*weight
        vertex.co=brow.matrix_world.inverted()@bp(p)
    brow.data.update()
def pose(angles):
    for name,matrix in rest.items():bpy.data.objects[name].matrix_basis=matrix.copy()
    for name,deg,axis in zip(['CrownPlatePivot_L','CrownPlatePivot_R','CrownPlatePivot_C'],angles,['Z','Z','X']):bpy.data.objects[name].matrix_basis=rest[name]@Matrix.Rotation(math.radians(deg),4,axis)
    bpy.context.view_layer.update()
def tree(core_only=False,with_names=False):
    verts=[];faces=[];names=[]
    for o in meshes:
        if (o.name=='CoreSeed')!=core_only:continue
        off=len(verts);verts.extend(gp(o.matrix_world@v.co)for v in o.data.vertices);o.data.calc_loop_triangles()
        for p in o.data.loop_triangles:faces.append(tuple(off+i for i in p.vertices));names.append(o.name)
    result=BVHTree.FromPolygons(verts,faces,all_triangles=True)
    return (result,names)if with_names else result
direction=Vector((32,39,32)).normalized();right=Vector((0,1,0)).cross(direction).normalized();up=direction.cross(right).normalized()
def projected_leaf_area(o,override=None):
    vs=override if override is not None else [gp(o.matrix_world@v.co)for v in o.data.vertices]
    o.data.calc_loop_triangles();triangles=[tuple(t.vertices)for t in o.data.loop_triangles];leaf_tree=BVHTree.FromPolygons(vs,triangles,all_triangles=True)
    xy=np.array([[p.dot(right),p.dot(up)]for p in vs]);low=xy.min(0);span=xy.max(0)-low;hits=0;resolution=100
    for iy in range(resolution):
        for ix in range(resolution):
            origin=right*(low[0]+(ix+.5)*span[0]/resolution)+up*(low[1]+(iy+.5)*span[1]/resolution)+direction*30
            hits+=leaf_tree.ray_cast(origin,-direction,60)[0]is not None
    return {'projected_area_m2':float(hits*span[0]*span[1]/resolution**2),'pixels':hits,'grid':resolution}
leaf_projection={name:{'before_twist':projected_leaf_area(bpy.data.objects[name],vs),'after_twist':projected_leaf_area(bpy.data.objects[name])}for name,vs in untwisted_leaf_vertices.items()}
seed=bpy.data.objects['CoreSeed'];seed_points=[gp(seed.matrix_world@v.co)for v in seed.data.vertices]
projected=np.array([[v.dot(right),v.dot(up)]for v in seed_points]);minimum=projected.min(0);maximum=projected.max(0)
core_tree=tree(True);samples=[];grid=120
for iy in range(grid):
    y=minimum[1]+(iy+.5)/grid*(maximum[1]-minimum[1])
    for ix in range(grid):
        x=minimum[0]+(ix+.5)/grid*(maximum[0]-minimum[0]);origin=right*x+up*y+direction*30
        hit=core_tree.ray_cast(origin,-direction,60)
        if hit[0]is not None:samples.append((origin,hit[3]))
def visibility(angles):
    pose(angles);occluders,names=tree(with_names=True);visible=0;blocked_by={}
    for origin,distance in samples:
        hit=occluders.ray_cast(origin,-direction,distance-1e-5)
        visible+=hit[0]is None
        if hit[0]is not None:blocked_by[names[hit[2]]]=blocked_by.get(names[hit[2]],0)+1
    return {'angles':angles,'core_alone_pixels':len(samples),'visible_pixels':visible,'visible_fraction':visible/len(samples),'grid':grid,'basis_direction':list(direction),'occluders':dict(sorted(blocked_by.items(),key=lambda p:-p[1]))}
closed=visibility([0,0,0]);baseline=visibility([-48,48,-32]);chosen=visibility([-60,72,-58]);trials=[chosen]
if chosen['visible_fraction']<2/3:
    for r in [78,84,90]:
        for c in [-64,-72,-80]:
            value=visibility([-60,r,c]);trials.append(value)
            if value['visible_fraction']>=2/3:break
        if trials[-1]['visible_fraction']>=2/3:break
    chosen=max(trials,key=lambda t:t['visible_fraction'])
angles=chosen['angles'];sweep=[]
for amount in np.linspace(0,1,65):
    pose([deg*amount for deg in angles]);verts=np.array([list(gp(o.matrix_world@v.co))for o in meshes for v in o.data.vertices]);sweep.append({'amount':float(amount),'min':verts.min(0).tolist(),'max':verts.max(0).tolist(),'radius':float(np.linalg.norm(verts[:,[0,2]],axis=1).max())})
assert max(v['radius']for v in sweep)<=4.00001 and min(v['min'][1]for v in sweep)>=-3.00001 and max(v['max'][1]for v in sweep)<=3.00001
report={'stage':'source p6 single geometry candidate; not game accepted','input_p5_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),'closed':closed,'p5_angle_baseline_same_geometry':baseline,'candidate':chosen,'angle_trials_numerical_only':trials,'leaf_surface_areas':leaf_areas,'changed_body_meshes':{'Torso_ContinuousRootSleeve':{'rings':[4,5,6],'new_profiles_z_rx_ry_cy_cx':new_profiles},'BrowRoot_1':'weighted lift <=.55, outward <=.1, back <=.18; endpoints remain connected','BrowRoot_-1':'weighted lift <=.25, outward <=.1, back <=.18'},'sampled_sweep':sweep,'continuous_sweep':'pending actual candidate GLB analytic audit','camera_offset':[32,39,32],'camera_target_size':26,'projection_method':'120x120 uniform core-alone projected bounding box, ray to actual seed surface; intervening whole body triangles counted as occlusion','surface_triangle_count':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)}
report['leaf_projected_silhouette']=leaf_projection
(HERE/'geometry_review.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
pose([0,0,0]);bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'parasitic_crown_p6_geometry.blend'))
print('P6_GEOMETRY',json.dumps({'closed':closed,'p5_angles':baseline,'candidate':chosen,'leaves':leaf_areas,'triangles':report['surface_triangle_count']}),flush=True)
# Two same-angle shape studies. Flat stone/root are deliberate review materials,
# not a final PBR claim; core/leaf retain their actual color signals.
for name,color in [('Crown_WarmStone',(.48,.465,.42,1)),('Crown_ChestnutBark',(.135,.075,.038,1))]:
    material=bpy.data.materials.get(name);p=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    for link in list(p.inputs['Base Color'].links):material.node_tree.links.remove(link)
    p.inputs['Base Color'].default_value=color
    for link in list(p.inputs['Normal'].links):material.node_tree.links.remove(link)
leaf=bpy.data.materials['Crown_LeafMembrane'];p=next(n for n in leaf.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
for link in list(p.inputs['Normal'].links):leaf.node_tree.links.remove(link)
for node in leaf.node_tree.nodes:
    if node.type=='TEX_IMAGE' and 'basecolor'in node.image.name:node.image=bpy.data.images.load(str(CROWN/'material_references/leaf_reference_p4.png'),check_existing=True)
camera=scene.camera;camera.location=bp((32,39,32));camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=26
scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
for label,values in [('closed',[0,0,0]),('open',angles)]:
    pose(values);scene.render.filepath=str(HERE/('p6_geometry_'+label+'_game_angle.png'));bpy.ops.render.render(write_still=True)
print('P6_GAME_ANGLE_PREVIEWS_DONE',flush=True)
