"""Bounded P10 repair: local branch-base excision and exposed upper rock edge.

Never changes the bridge/P10/runtime. Geometry gates precede the one fixed-camera
assembly preview. PBR/export are separate later steps, not part of this script.
"""
import bpy, bmesh, hashlib, json, math, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
OUT=Path(__file__).resolve().parent
PROJECT=OUT.parents[3]
P10=OUT.parent/'p10/root_shoulder_contact_p10.blend'
BRIDGE=PROJECT/'assets/v3/root_arch/f1_root_arch.glb'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
frozen={str(p.relative_to(PROJECT)):sha(p) for p in [P10,BRIDGE]}
prior=json.loads((OUT.parent/'p10/p10_geometry_report.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(P10))
scene=bpy.context.scene
camera_matrix=scene.camera.matrix_world.copy();camera_size=scene.camera.data.ortho_scale
root=bpy.data.objects['P10_NaturalMainRoot_TrueCrossSectionCuts']
high=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff']
collection=root.users_collection[0]
collection.name='P12_SHORE_ROOT_EDITABLE'
asset_parts=[o for o in collection.objects if o.type=='MESH' and not o.hide_render]
archive=bpy.data.collections.new('P12_UNCHANGED_P10_ARCHIVE')
scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
for ob in asset_parts:
    cp=ob.copy();cp.data=ob.data.copy();archive.objects.link(cp)
    cp.name='BeforeP12_'+ob.name;cp.hide_render=True;cp.hide_viewport=True
    ob.data=ob.data.copy()

def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def clamp(x):return max(0.,min(1.,x))
def smooth(x):x=clamp(x);return x*x*(3-2*x)
def bvh(ob):
    ob.data.calc_loop_triangles()
    return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],
        [tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
def topology(ob):
    bm=bmesh.new();bm.from_mesh(ob.data);unseen=set(bm.verts);parts=[]
    while unseen:
        stack=[unseen.pop()];n=0
        while stack:
            v=stack.pop();n+=1
            for e in v.link_edges:
                j=e.other_vert(v)
                if j in unseen:unseen.remove(j);stack.append(j)
        parts.append(n)
    result={'components':sorted(parts,reverse=True),'boundary_edges':sum(e.is_boundary for e in bm.edges),
            'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'signed_volume':bm.calc_volume(signed=True)}
    bm.free();return result
def bounds(ob):
    p=[gp(ob.matrix_world@v.co) for v in ob.data.vertices]
    return {'min':[min(v[i] for v in p) for i in range(3)],'max':[max(v[i] for v in p) for i in range(3)]}
def surface(tree,x,z):
    p=tree.ray_cast(bp((x,8,z)),bp((0,-1,0)),15)[0]
    return gp(p) if p is not None else None
def inside_votes(tree,point):
    votes=[]
    for direction in [Vector((.937,.281,.207)),Vector((-.193,.931,.311)),Vector((.271,-.347,.898))]:
        direction.normalize();start=point.copy();crossings=0
        for _ in range(80):
            location,_,_,_=tree.ray_cast(start,direction,50)
            if location is None:break
            crossings+=1;start=location+direction*.0001
        votes.append(bool(crossings%2))
    return votes

original_high_tree=bvh(high)

# Use a measured connected branch above its own neck section. Although the
# section operation subdivides the mesh, only the selected leaf component is
# deleted. Main branches crossing the same source height are never discarded.
pruning=[]
def prune_leaf(label,height,section_xz,maximum_faces):
    bm=bmesh.new();bm.from_mesh(root.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        plane_co=Vector((0,0,height)),plane_no=Vector((0,0,1)),dist=1e-6,
        clear_inner=False,clear_outer=False)
    above={f for f in bm.faces if all(v.co.z>=height-2e-6 for v in f.verts)
           and any(v.co.z>height+2e-6 for v in f.verts)}
    groups=[]
    while above:
        stack=[above.pop()];group=[]
        while stack:
            f=stack.pop();group.append(f)
            for e in f.edges:
                if all(abs(v.co.z-height)<3e-6 for v in e.verts):continue
                for adjacent in e.link_faces:
                    if adjacent in above:above.remove(adjacent);stack.append(adjacent)
        groups.append(group)
    target=Vector((section_xz[0],-section_xz[1],height))
    def score(group):
        verts={v for f in group for v in f.verts if abs(v.co.z-height)<3e-6}
        return ((sum((v.co for v in verts),Vector())/len(verts))-target).length if verts else 1e6
    group=min(groups,key=score);distance=score(group)
    assert distance<.13 and 10<len(group)<maximum_faces,(label,distance,len(group))
    old_faces=len(bm.faces)
    bmesh.ops.delete(bm,geom=group,context='FACES')
    orphans=[v for v in bm.verts if not v.link_faces]
    if orphans:bmesh.ops.delete(bm,geom=orphans,context='VERTS')
    boundary=[e for e in bm.edges if e.is_boundary]
    assert boundary and all(abs(v.co.z-height)<4e-6 for e in boundary for v in e.verts),label
    # A recessed geometric skin patch, not an exposed planar saw cap. The
    # outer neck is retained, the two inner rings recede toward the parent.
    first=boundary[0].verts[0];ordered=[first];previous=None;current=first
    while True:
        nexts=[e.other_vert(current) for e in current.link_edges if e in boundary and e.other_vert(current)!=previous]
        nxt=nexts[0]
        if nxt==first:break
        ordered.append(nxt);previous,current=current,nxt
        assert len(ordered)<=len(boundary),label
    assert len(ordered)==len(boundary),('multiple neck loops',label)
    centre=sum((v.co for v in ordered),Vector())/len(ordered)
    inner=[]
    for v in ordered:
        p=centre+(v.co-centre)*.45;p.z-=.032
        inner.append(bm.verts.new(p))
    midpoint=centre.copy();midpoint.z-=.055;cv=bm.verts.new(midpoint)
    for i in range(len(ordered)):
        j=(i+1)%len(ordered)
        bm.faces.new([ordered[i],ordered[j],inner[j],inner[i]])
        bm.faces.new([inner[i],inner[j],cv])
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    for f in bm.faces:f.smooth=True;f.material_index=0
    bm.to_mesh(root.data);bm.free();root.data.update()
    pruning.append({'label':label,'source_y_neck':height,'section_xz':section_xz,
        'selected_component_faces':len(group),'section_centre_error':distance,
        'retained_outer_neck_vertices':len(ordered),'new_skin_recess_source_m':.055,
        'global_plane_deletion':False,'old_face_count':old_faces})

prune_leaf('upper_horizontal_stump_and_its_fine_offshoots',1.40,(-.381,-.195),5000)
prune_leaf('front_inward_fine_branch',1.65,(.071,-.552),2800)

# Preserve the actual engineering face and last metre. The exposed high cap
# is locally lowered and edged with three broad breaks; the buried root base
# is a protected region, not moved to accommodate the stone.
base_points=[root.matrix_world@v.co for v in root.data.vertices if abs(v.co.z-.1)<1e-5]
base_tree=KDTree(len(base_points))
for i,p in enumerate(base_points):base_tree.insert(p,i)
base_tree.balance()
protected_face_before=sorted(tuple(round(q,6) for q in v.co) for v in high.data.vertices if abs(v.co.x-4.5)<2e-5)
bm=bmesh.new();bm.from_mesh(high.data)
# The broad cap has large n-gons; triangulate/subdivide only the upper region
# before giving it non-planar relief, so a renderer cannot invent a diagonal.
caps=[f for f in bm.faces if all(v.co.z>4.80 for v in f.verts)
      or (all(v.co.z>=4.49999 for v in f.verts) and all(abs(v.co.x-3.5)<1e-5 for v in f.verts))]
if caps:bmesh.ops.triangulate(bm,faces=caps)
for _ in range(4):
    edges=[e for e in bm.edges if (all(v.co.z>4.75 for v in e.verts)
           or (all(v.co.z>=4.49999 for v in e.verts) and all(abs(v.co.x-3.5)<1e-5 for v in e.verts))) and e.calc_length()>.38]
    if not edges:break
    bmesh.ops.subdivide_edges(bm,edges=edges,cuts=1,use_grid_fill=True)
modified=[]
for v in bm.verts:
    p=gp(v.co);x,y,z=p
    if y<=3.50 or x>3.50001 or (x>=3.50 and y<=4.50001):continue
    # Protect the measured cap itself. The prior rectangular fallback mask
    # was unnecessary (the first apparent failure was an edge-normal tie) and
    # left an artificial broad flat shelf in the assembled image.
    _,_,distance=base_tree.find(v.co)
    protection=smooth((distance-.14)/.42)
    # The 4.95m edge at X=3.5 is NOT the 4.5m walkable join. Keeping that
    # exposed high edge while lowering its neighbour created a knife-like
    # strip in the first preview. Retain the actual lower join, lower its lip.
    across=1.0 if y>4.50001 else smooth((3.50-x)/.36)
    height=smooth((y-3.5)/1.30)
    amount=protection*across*height
    if amount<=1e-8:continue
    # Broad, low-frequency shoulders and two broken edge recesses. This is
    # actual vertex relief in the retained stone, not a textured flat cover.
    drop=(.24+.18*abs(math.sin(.82*x+.38*z))
          +.46*math.exp(-((x-1.25)/.80)**2-((z+2.5)/1.20)**2)
          +.30*math.exp(-((x-2.65)/.57)**2-((z-1.60)/.90)**2))
    p.y-=drop*amount
    if y>4.5 and x>3.15:
        # Compress the lip monotonically towards its own 4.5m foot. Merely
        # subtracting a constant drop from near-foot vertices folds the wall
        # below the protected join. The first numeric trial caught that.
        top_height=4.56+.025*math.sin(z*1.3)
        mapped=4.5+(y-4.5)*(top_height-4.5)/.45
        p.y=y+(mapped-y)*protection
    rear=smooth((-z-2.20)/1.30)
    p.z+=(.18+.24*abs(math.sin(x*1.2+.3)))*rear*amount
    front=smooth((z-1.8)/1.0)
    p.z-=(.08+.16*abs(math.cos(x*1.8)))*front*amount
    v.co=bp(p);modified.append([float(x),float(y),float(z),float(p.y)])
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(high.data);bm.free();high.data.update()
protected_face_after=sorted(tuple(round(q,6) for q in v.co) for v in high.data.vertices if abs(v.co.x-4.5)<2e-5)
assert protected_face_before==protected_face_after,'BridgeJoin actual face must remain byte-coordinate identical'
for f in high.data.polygons:f.use_smooth=True

names={root:'Root_MainFork',high:'Rock_HighShoulder'}
for old,new in [('P10_BackMiddle_NaturalRock01','Rock_RearFoot'),('P10_FrontLower_NaturalRock04','Rock_FrontFoot'),('P10_LowToe_NaturalRock03','Rock_LowToe')]:
    names[bpy.data.objects[old]]=new
for ob,name in names.items():ob.name=name
asset_root=bpy.data.objects.new('ShoreRootT03A',None);collection.objects.link(asset_root)
for ob in asset_parts:
    matrix=ob.matrix_world.copy();ob.parent=asset_root;ob.matrix_world=matrix
for name,p in [('GroundOrigin',(0,0,0)),('BridgeJoin',(4.5,4.5,0)),('WestBlend',(-4.3,.34,0))]:
    ob=bpy.data.objects.new(name,None);collection.objects.link(ob);ob.parent=asset_root;ob.location=bp(p)
bpy.context.view_layer.update()
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
for ob in asset_parts:
    t=topology(ob);check(ob.name+'_closed_single_solid',len(t['components'])==1 and not t['boundary_edges'] and not t['nonmanifold_edges'] and t['signed_volume']>0,t)
rt=bvh(root)
for record,stone_name in zip(prior['contacts'],['Rock_RearFoot','Rock_FrontFoot','Rock_LowToe']):
    x,z=record['target_xz'];wp=rt.ray_cast(bp((x,-3,z)),bp((0,1,0)),12)[0]
    sp=surface(bvh(bpy.data.objects[stone_name]),x,z)
    burial=sp.y-gp(wp).y if wp is not None and sp is not None else None
    check(stone_name+'_retained_actual_contact',burial is not None and .025<burial<.035,{'root':list(gp(wp)) if wp is not None else None,'stone':list(sp) if sp is not None else None,'burial_m':burial})
    check(stone_name+'_foot_enters_ground',bounds(bpy.data.objects[stone_name])['min'][1]<=.01)
ht=bvh(high);outside=[]
for pt in base_points:
    near,n,_,distance=ht.find_nearest(pt)
    votes=inside_votes(ht,pt)
    # At a crease the same nearest point may be returned with either adjacent
    # face normal. Normal-dot is not the distance to the solid boundary.
    # Keep the 8mm minimum but use Euclidean distance and closed-solid parity.
    if near is None or distance<.008 or sum(votes)<2:
        oldnear,oldnormal,_,olddist=original_high_tree.find_nearest(pt)
        outside.append({'point':list(gp(pt)),'new_nearest':list(gp(near)) if near is not None else None,
                        'new_normal':list(gp(n)) if n is not None else None,'new_signed':(pt-near).dot(n) if near is not None else None,
                        'actual_nearest_distance_m':distance,'inside_votes':votes,
                        'original_nearest':list(gp(oldnear)),'original_normal':list(gp(oldnormal)),
                        'original_signed':(pt-oldnear).dot(oldnormal)})
check('root_high_cut_remains_fully_inside_stone',len(base_points)>100 and not outside,{'points':len(base_points),'outside':outside})
hits=[]
for x in [3.55,4.,4.49]:
    for z in [-2.75,-1.375,0,1.375,2.75]:
        p=surface(ht,x,z);hits.append({'xz':[x,z],'point':list(p) if p is not None else None})
check('retained_last_metre_5_5m_interface',all(h['point'] is not None and abs(h['point'][1]-4.5)<.001 for h in hits),hits)
check('actual_X4_5_face_unchanged',protected_face_before==protected_face_after,{'vertices':len(protected_face_before)})
bb={o.name:bounds(o) for o in asset_parts}
check('engineering_9x12_under5m',all(b['min'][0]>=-4.55 and b['max'][0]<=4.501 and b['min'][2]>=-6 and b['max'][2]<=6 and b['max'][1]<=5.001 for b in bb.values()),bb)
check('all_frozen_inputs_unchanged',all(sha(PROJECT/p)==s for p,s in frozen.items()))
check('same_camera_as_P10',scene.camera.matrix_world==camera_matrix and scene.camera.data.ortho_scale==camera_size)
triangles={}
for ob in asset_parts:ob.data.calc_loop_triangles();triangles[ob.name]=len(ob.data.loop_triangles)
report={'stage':'P12 bounded basic-form candidate; not PBR or runtime','frozen_inputs':frozen,'pruning':pruning,
        'upper_rock_changed_vertices':len(modified),'bounds':bb,'triangles':triangles,'checks':checks,
        'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),
        'camera_preserved':True,'limits':['Local inset bark repair is authored geometry, not untouched scan.','No contact proof from visual bridge occlusion.','No Godot or gameplay acceptance.']}
(OUT/'p12_source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P12_GATES '+json.dumps({'passed':report['passed'],'total':report['total'],'triangles':triangles}),flush=True)
for c in checks:
    if not c['pass']:print('P12_FAIL '+json.dumps(c),flush=True)
assert report['all_pass'],'Do not render or export failed geometry'
source=OUT/'shore_root_t03a_p12.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
report['source_sha256']=sha(source)
(OUT/'p12_source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')

if '--render' in sys.argv:
    existing=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(BRIDGE))
    imported=[o for o in bpy.data.objects if o not in existing];roots=[o for o in imported if o.parent not in imported]
    assert len(roots)==1 and roots[0].name=='F1RootArch';roots[0].location+=bp((24.5,0,0))
    def basic(name,colour):
        m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF')
        p.inputs['Base Color'].default_value=(*colour,1);p.inputs['Roughness'].default_value=.87;p.inputs['Specular IOR Level'].default_value=.16
        return m
    colours={'WalkableRoot':(.285,.225,.165),'StoneRemnants':(.28,.285,.27),'Moss':(.17,.23,.14),'Foliage':(.21,.27,.16)}
    for ob in imported:
        if ob.type!='MESH':continue
        m=basic('AssemblyOnly_'+ob.name,colours[ob.name])
        for i in range(len(ob.data.materials)):ob.data.materials[i]=m
    bpy.context.view_layer.update()
    assert scene.camera.matrix_world==camera_matrix and scene.camera.data.ortho_scale==camera_size
    scene.render.filepath=str(OUT/'p12-basic-readonly-bridge-assembly.png')
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=12
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'shore_root_p12_basic_assembly.blend'))
    bpy.ops.render.render(write_still=True)
assert all(sha(PROJECT/p)==s for p,s in frozen.items())
print('P12_SOURCE_COMPLETE_INPUTS_UNCHANGED',flush=True)
