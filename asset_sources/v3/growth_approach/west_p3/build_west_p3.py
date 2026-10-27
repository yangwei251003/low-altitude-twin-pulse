"""West P3: rebuild four CLOSED thick stones, not the rejected P2 lid topology.

Blender 5.2 bundled Python; writes ONLY this directory, CPU 2:
blender --background --factory-startup --threads 2 --python-exit-code 1
  --python asset_sources/v3/growth_approach/west_p3/build_west_p3.py [-- --no-render]

P2 and its embedded natural-source copy remain read-only. Basic colours only;
the GLB is a placement-review asset, not a runtime or final PBR deliverable.
"""
import bpy, bmesh, math, json, hashlib, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

BASE=Path(__file__).resolve().parent
sys.path.insert(0,str(BASE))
from geometry_checks import strict_self_intersections
PROJECT=BASE.parents[3]
P2=BASE.parent/'west_p2'
SOURCE=P2/'growth_approach_west_p2.blend'
LAYOUT=PROJECT/'data/v3/terrain/f1_growth_crossing.json'
REFERENCE=PROJECT/'references/v3/production/growth_approach/growth_approach_west_reference_v2.png'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
source_sha=sha(SOURCE)
assert source_sha=='0d56dd85793d7d3b5e92e8cc24015bc1399af182d028ec73516303abeb2c3dfc'
BASE.mkdir(parents=True,exist_ok=True)
(BASE/'.gdignore').write_text('\n',encoding='utf8')
(BASE/'input_f1_growth_crossing.json').write_bytes(LAYOUT.read_bytes())
data=json.loads(LAYOUT.read_text(encoding='utf-8-sig'))
west=next(a for a in data['approaches'] if a['id']=='west')
sections=[(s['x']+14.5,[(z-25,y) for z,y in s['top_zy']]) for s in west['sections']]
def bl(p):return Vector((p[0],-p[2],p[1]))
def gd(p):return Vector((p[0],p[2],-p[1]))
def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)

original_top=[]
for k in range(len(sections)-1):
    xa,a=sections[k];xb,b=sections[k+1]
    for j in range(len(a)-1):
        aa=Vector((xa,a[j][1],a[j][0]));bb=Vector((xb,b[j][1],b[j][0]))
        cc=Vector((xb,b[j+1][1],b[j+1][0]));dd=Vector((xa,a[j+1][1],a[j+1][0]))
        original_top.extend([(aa,bb,cc),(aa,cc,dd)])
def top_height(x,z):
    for p,q,r in original_top:
        den=(q.z-r.z)*(p.x-r.x)+(r.x-q.x)*(p.z-r.z)
        u=((q.z-r.z)*(x-r.x)+(r.x-q.x)*(z-r.z))/den
        v=((r.z-p.z)*(x-r.x)+(p.x-r.x)*(z-r.z))/den
        if min(u,v,1-u-v)>=-1e-6:return u*p.y+v*q.y+(1-u-v)*r.y
    raise ValueError(('not on actual top profile',x,z))

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
root=bpy.data.objects['GrowthApproachWest'];model=root.users_collection[0]
model.name='EDITABLE_WEST_P3'
anchors=[o for o in model.objects if o.type=='EMPTY' and o!=root]
archive=bpy.data.collections.new('REJECTED_P2_EDITABLE_PARTS_NOT_EXPORTED')
scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
old_meshes=[o for o in model.objects if o.type=='MESH']
for ob in old_meshes:
    for col in list(ob.users_collection):col.objects.unlink(ob)
    archive.objects.link(ob);ob.parent=None;ob.hide_render=True;ob.name='FrozenP2_'+ob.name
root['status']='p3_thick_stone_topology_basic_material_review_only'
root['p2_input_sha256']=source_sha;root['world_origin_godot']=[-14.5,0.,25.]
root['geometry_scope']='new thick-rock topology; west/end anchors and central carrying surface fixed; free side rim lowered only'

def material(name,color,rough=.9):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough
    return m
STONE=material('P3_Stone_WarmGray',(.37,.345,.275))
STONE_LIGHT=material('P3_Stone_CutFace',(.49,.46,.375))
STONE_DARK=material('P3_Stone_Recess',(.205,.226,.218))
BARK=material('P3_Natural_Root',(.23,.132,.062),.94)
rocks=[];objects=[]

def mesh_object(name,vv,ff,mats):
    me=bpy.data.meshes.new(name+'_EditableMesh');me.from_pydata([bl(v) for v in vv],[],ff);me.update()
    ob=bpy.data.objects.new(name,me);model.objects.link(ob);ob.parent=root
    for mat in mats:me.materials.append(mat)
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
    bm.to_mesh(me);bm.free();me.update()
    for face in me.polygons:
        n=gd(face.normal)
        face.material_index=1 if n.y>.65 else (2 if n.y<-.25 else 0)
    ob['collision_source']='same actual visible triangles; no cover slab or hidden box'
    objects.append(ob)
    return ob

def clip(poly,distance):
    out=[]
    eps=1e-6
    for p,q in zip(poly,poly[1:]+poly[:1]):
        a,b=distance(p),distance(q)
        if a>=-eps:out.append(p)
        if (a>eps and b<-eps) or (a<-eps and b>eps):out.append(p+(q-p)*(a/(a-b)))
    clean=[]
    for p in out:
        if not clean or (p-clean[-1]).length>1e-8:clean.append(p)
    if len(clean)>1 and (clean[0]-clean[-1]).length<1e-8:clean.pop()
    return clean

def make_top(which):
    vv=[];ff=[];cache={}
    def add(p):
        p=p.copy()
        # Keep the central 1.7m strip and both real assembly interfaces EXACT.
        # Only free side margins descend; no entire top-vertex preservation.
        edge=smooth(.85,1.5,abs(p.z))
        end=smooth(0.,.42,p.x)*(1-smooth(3.04,3.5,p.x))
        p.y-=edge*end*(.21 if p.z>0 else .14)
        key=tuple(math.floor(v/1e-5) for v in p)
        for dx in (-1,0,1):
            for dy in (-1,0,1):
                for dz in (-1,0,1):
                    for idx in cache.get((key[0]+dx,key[1]+dy,key[2]+dz),[]):
                        if (p-Vector(vv[idx])).length<3e-6:return idx
        idx=len(vv);vv.append(tuple(p));cache.setdefault(key,[]).append(idx)
        return idx
    # Preserve all actual source triangle planes, then split at carrying-strip
    # boundaries and an oblique rock seam. No re-interpolation across a crease.
    xs=[0.,.3,.7,1.1,1.5,2.05,2.45,2.55,2.65,2.8,3.5,3.751]
    for tri in original_top:
        for lo,hi in [(-1.51,-.85),(-.85,.85),(.85,1.51)]:
            strip=clip(list(tri),lambda p:p.z-lo)
            strip=clip(strip,lambda p:hi-p.z) if strip else []
            for left,right in zip(xs,xs[1:]):
                poly=clip(strip,lambda p:p.x-left) if strip else []
                poly=clip(poly,lambda p:right-p.x) if poly else []
                poly=clip(poly,lambda p:(1 if which=='west' else -1)*(1.92+.14*p.z-p.x)) if poly else []
                if len(poly)<3:continue
                ids=[add(p) for p in poly]
                for j in range(1,len(ids)-1):
                    if len({ids[0],ids[j],ids[j+1]})==3 and (Vector(vv[ids[j]])-Vector(vv[ids[0]])).cross(Vector(vv[ids[j+1]])-Vector(vv[ids[0]])).length>1e-10:
                        ff.append((ids[0],ids[j],ids[j+1]))
    counts={}
    for f in ff:
        for a,b in zip(f,f[1:]+f[:1]):
            key=tuple(sorted((a,b)));counts[key]=counts.get(key,0)+1
    neighbours={}
    for (a,b),n in counts.items():
        if n==1:neighbours.setdefault(a,[]).append(b);neighbours.setdefault(b,[]).append(a)
    assert all(len(v)==2 for v in neighbours.values()),('open_top_boundary',which,neighbours)
    first=min(neighbours,key=lambda i:(vv[i][0],vv[i][2]));rim=[first];prev=-1;cur=first
    while True:
        nxt=next(i for i in neighbours[cur] if i!=prev)
        if nxt==first:break
        rim.append(nxt);prev,cur=cur,nxt
    assert len(rim)==len(neighbours)
    return vv,ff,rim

def upper(name,which):
    vv,ff,rim=make_top(which);previous=rim
    for level,t in enumerate((.075,.48,.88,1.0)):
        current=[]
        for idx in rim:
            x,top,z=vv[idx]
            floor=(1.85+.08*x+.11*z) if which=='west' else (2.12+.035*x-.11*z)
            # Deep face immediately beneath the top. Side recession stays
            # shallow: no old >0.5m projecting pointed lid above a narrow post.
            side=abs(z)/1.5
            if which=='west':
                cx=.90
                sx=(.985,.97,.94,.91)[level]
                pz=z*(.96,.94,.90,.90)[level]+.015*math.sin(x*1.7)
                px=cx+(x-cx)*sx+.025*z
            else:
                cx=2.73
                sx=(.98,.96,.92,.90)[level]
                pz=z*(.96,.94,.92,.92)[level]-.015*math.sin(x*1.4)
                px=cx+(x-cx)*sx-.025*z
            if abs(z)>1e-8:
                # Carve the ROCK to accommodate the rigid natural root. This
                # is one broad side recess, not a discontinuous per-root-vertex
                # projection or a circumferential waist around the whole piece.
                shift=0.0 if z>0 else .10
                groove=smooth(.60+shift,1.0+shift,x)*(1-smooth(2.05+shift,2.55+shift,x))
                outer=1.485-(0.,.43,.30,.055)[level]*groove
                half=1.5 if x<=3.5 else 1.5-.04*(x-3.5)
                # Apply a continuous monotone cross-section, also along the
                # diagonal INTERIOR seam. A hard abs(Z) mask folded its corner.
                pz=z*outer/half
            current.append(len(vv));vv.append((max(.012,min(3.71,px)),top*(1-t)+floor*t,max(-1.49,min(1.49,pz))))
        for i in range(len(rim)):
            j=(i+1)%len(rim);ff.append((previous[i],current[i],current[j],previous[j]))
        previous=current
    ff.append(tuple(reversed(previous)))
    ob=mesh_object(name,vv,ff,[STONE,STONE_LIGHT,STONE_DARK]);rocks.append(ob)
    ob['new_topology']='full-depth oblique fracture block; no inherited P2 vertices or thin floating lid'

upper('Stone_A_WestBearingMass','west')
upper('Stone_B_EastBearingMass','east')

def lower(name,outline,heights,phase):
    cx=sum(p[0] for p in outline)/len(outline);cz=sum(p[1] for p in outline)/len(outline)
    vv=[];n=len(outline)
    for ring,t in enumerate((0.,.1,.84,1.)):
        s=(.94,1.,.97,.91)[ring]
        for i,((x,z),height) in enumerate(zip(outline,heights)):
            vv.append((cx+(x-cx)*s+.018*math.sin(i+phase)*t,height*t,cz+(z-cz)*s+.012*math.cos(i+phase)*t))
    ff=[]
    for ring in range(3):
        for i in range(n):
            j=(i+1)%n;ff.append((ring*n+i,ring*n+j,(ring+1)*n+j,(ring+1)*n+i))
    ff.extend([tuple(reversed(range(n))),tuple(range(3*n,4*n))])
    ob=mesh_object(name,vv,ff,[STONE,STONE_LIGHT,STONE_DARK]);rocks.append(ob)
    ob['new_topology']='unequal basal fracture volume; laterally offset from upper seam, no decorative slab'

lower('Stone_C_BroadWestFoundation',[(.025,-1.22),(.34,-1.49),(1.82,-1.47),(2.42,-.63),(2.25,.85),(1.73,1.49),(.29,1.49),(.025,.79)],
      [2.16,2.13,2.40,2.45,2.52,2.38,2.17,2.18],.35)
lower('Stone_D_SlantedEastFoundation',[(1.70,-1.18),(2.23,-1.49),(3.37,-1.47),(3.68,-.68),(3.58,.90),(3.13,1.49),(2.23,1.49),(1.57,.58)],
      [2.72,2.77,2.67,2.63,2.54,2.50,2.60,2.73],1.6)

def make_bvh(obs):
    vv=[];ff=[];owners=[]
    for ob in obs:
        ob.data.calc_loop_triangles();off=len(vv)
        vv.extend([ob.matrix_world@v.co for v in ob.data.vertices])
        for tri in ob.data.loop_triangles:ff.append(tuple(off+i for i in tri.vertices));owners.append(ob.name)
    return BVHTree.FromPolygons(vv,ff,all_triangles=True),owners
bpy.context.view_layer.update();rock_bvh,_=make_bvh(rocks)
natural=bpy.data.objects['OriginalNaturalFork_SourceCoordinates']
root_endpoints=[];root_visibility=[];root_repairs=[]
def natural_root(name,side):
    ob=bpy.data.objects.new(name,natural.data.copy());model.objects.link(ob);ob.parent=root
    bm=bmesh.new();bm.from_mesh(ob.data)
    for point,normal in [((-.6,0,0),(-1,0,0)),((.4,0,0),(1,0,0))]:
        cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bl(point),plane_no=bl(normal),dist=1e-6,clear_outer=True)
        edges=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
        if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    source_audit=strict_self_intersections(ob)
    if source_audit['strict_crossing_count']:
        ob.data.calc_loop_triangles()
        badverts={i for pair in source_audit['examples'] for t in pair['triangles'] for i in ob.data.loop_triangles[t].vertices}
        before={i:ob.data.vertices[i].co.copy() for i in badverts}
        extent=max((a-b).length for a in before.values() for b in before.values())
        assert extent<.06,('natural source repair would exceed bounded 6cm patch',extent)
        bm=bmesh.new();bm.from_mesh(ob.data);bm.verts.ensure_lookup_table()
        selected=[bm.verts[i] for i in badverts]
        for _ in range(5):bmesh.ops.smooth_vert(bm,verts=selected,factor=.45,use_axis_x=True,use_axis_y=True,use_axis_z=True)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
        after_audit=strict_self_intersections(ob)
        repair={'mesh':name,'source_crossings':source_audit['strict_crossing_count'],'after_crossings':after_audit['strict_crossing_count'],
                'bounded_patch_diameter_m':extent,'edited_vertex_count':len(badverts),
                'maximum_displacement_m':max((ob.data.vertices[i].co-before[i]).length for i in badverts)}
        root_repairs.append(repair)
        assert after_audit['strict_crossing_count']==0,repair
    originals=[gd(v.co) for v in ob.data.vertices]
    scale=1.05;angle=.06 if side>0 else -.055
    cx=.43 if side>0 else .48;base_y=3.10 if side>0 else 3.12
    failures=[]
    for v,p in zip(ob.data.vertices,originals):
        u=p.y-.1;w=p.z
        x=cx+scale*(u*math.cos(angle)-w*math.sin(angle))
        y=base_y+scale*(u*math.sin(angle)+w*math.cos(angle))
        hit,_,_,_=rock_bvh.ray_cast(bl((x,y,side*3)),bl((0,0,-side)),6.)
        if hit is None:failures.append({'source':list(p),'mapped_xy':[x,y]});continue
        surface=gd(hit)
        # RIGID uniform-scale mapping. The rock receives a broad recess;
        # source triangles are not warped across discontinuous rock seams.
        z=side*(1.00+p.x*scale)
        q=Vector((x,y,z));v.co=bl(q)
        if p.y<.10001 or p.y>2.19999:
            root_endpoints.append({'root':name,'source_y':p.y,'actual':list(q),'front_surface':list(surface),'embed_depth':(surface.z-z)*side})
    if failures:raise RuntimeError(json.dumps({'root_without_stone_support':name,'count':len(failures),'samples':failures[:8]}))
    ob.data.materials.clear();ob.data.materials.append(BARK)
    for p in ob.data.polygons:p.use_smooth=True
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
    bm.to_mesh(ob.data);bm.free();ob.data.update()
    ob['source_url']='https://polyhaven.com/a/island_tree_01'
    ob['source_sha256']=natural.get('source_sha256','')
    ob['source_rights']='CC0 natural tree-base/fork; not a claimed naked-root scan'
    ob['mapping']='rigid uniform1.05 scale and rotation; original fork thickness retained; rock side recess receives source; bounded original3cm fold repair recorded'
    ob['collision_source']='same visible triangles'
    objects.append(ob)
    return ob
natural_root('Root_NaturalSouthFork',1)
natural_root('Root_NaturalNorthFork',-1)
bpy.context.view_layer.update()

checks=[]
def check(name,ok,**detail):checks.append({'name':name,'passed':bool(ok),**detail})
combined,owners=make_bvh(objects)
def down(x,z):
    hit,_,_,_=combined.ray_cast(bl((x,8,z)),bl((0,-1,0)),10)
    return gd(hit).y if hit is not None else None
pts=[gd(o.matrix_world@v.co) for o in objects for v in o.data.vertices]
mins=[min(p[i] for p in pts) for i in range(3)];maxs=[max(p[i] for p in pts) for i in range(3)]
check('actual_all_vertices_in_original_envelope',all(mins[i]>=a-1e-5 and maxs[i]<=b+1e-5 for i,(a,b) in enumerate(zip((0,0,-1.5),(3.75,5.25,1.5)))),minimum=mins,maximum=maxs)
for j,(z,y) in enumerate(sections[0][1]):
    got=down(.000001,z if abs(z)<1.5 else z*.999999)
    check('west_measured_join_'+str(j),got is not None and abs(got-y)<.0001,actual=got,expected=y,z=z)
for label,x,y,w in [('formal_lip',3.5,5.25,1.5),('lower_nose',3.749999,5.20,1.49)]:
    values=[]
    for i in range(31):
        z=-w+.00001+(2*w-.00002)*i/30;got=down(x,z)
        values.append({'z':z,'actual':got})
    check(label+'_full_width',all(q['actual'] is not None and abs(q['actual']-y)<.0001 for q in values),expected=y,samples=values)
central=[]
for i in range(41):
    x=.001+3.748*i/40
    for z in (-.85,-.425,0,.425,.85):
        got=down(x,z);expected=top_height(x,z);central.append({'x':x,'z':z,'expected':expected,'actual':got})
check('central_1p7m_strip_same_actual_surface',all(q['actual'] is not None and abs(q['actual']-q['expected'])<.0002 for q in central),count=len(central))
prior=json.loads((P2/'geometry_report.json').read_text(encoding='utf8'))
for name,expected in prior['anchors_godot_local'].items():
    got=gd(bpy.data.objects[name].matrix_world.translation)
    check('anchor_'+name,(got-Vector(expected)).length<1e-7,actual=list(got))
check('root_unit_transform',root.matrix_basis.is_identity)
check('both_root_source_end_caps_embedded',bool(root_endpoints) and min(q['embed_depth'] for q in root_endpoints)>.05,
      samples=len(root_endpoints),minimum_embed_depth=min(q['embed_depth'] for q in root_endpoints))
for ob in objects:
    bm=bmesh.new();bm.from_mesh(ob.data)
    bad=sum(not e.is_manifold for e in bm.edges);zero=sum(f.calc_area()<1e-10 for f in bm.faces);volume=bm.calc_volume(signed=True);bm.free()
    check('closed_'+ob.name,bad==0,nonmanifold_edges=bad)
    check('positive_solid_'+ob.name,volume>0 and zero==0,signed_volume=volume,zero_area_faces=zero)
self_audit=[strict_self_intersections(ob) for ob in objects]
for item in self_audit:check('strict_no_self_crossing_'+item['mesh'],item['strict_crossing_count']==0,report=item)
check('p2_input_unchanged',sha(SOURCE)==source_sha)
for ob in objects:ob.data.calc_loop_triangles()
triangles=sum(len(o.data.loop_triangles) for o in objects)
report={'status':'p3_basic_material_candidate_pending_actual_assembly_review','world_origin':[-14.5,0,25],'local_bounds':[mins,maxs],
 'inputs':{'p2_blend':str(SOURCE.relative_to(PROJECT)),'p2_sha256':source_sha,'layout_sha256':sha(LAYOUT),'reference_sha256':sha(REFERENCE),'script_sha256':sha(__file__)},
 'observations':['P2 actual02/03/04 showed paper lid over columns and suspended natural fork','P3 replaces all four stones rather than preserving rejected topology; only assembly/carrying interfaces fixed'],
 'geometry':{'mesh_count':len(objects),'triangles':triangles,'materials':sorted({m.name for o in objects for m in o.data.materials}),'collision':'same visible triangles; no hidden box or separate flat top'},
 'anchors_godot_local':prior['anchors_godot_local'],'central_samples':central,'root_end_samples':root_endpoints,'root_source_repairs':root_repairs,'self_intersections':self_audit,'checks':checks,
 'failures':[c for c in checks if not c['passed']],
 'limits':['basic materials only, not final UV/PBR','offline render is not actual game capture','per-mesh self-intersection report is separate; intentional root/stone embed is not a self-crossing','root-agent actual assembly/physics review still required']}
blend=BASE/'growth_approach_west_p3.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False);report['blend_sha256']=sha(blend)
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if report['failures']:
    print('WEST_P3_FAIL',json.dumps(report['failures'],ensure_ascii=False));raise RuntimeError('P3 geometric interface check failed')
bpy.ops.object.select_all(action='DESELECT')
for ob in [root]+objects+anchors:ob.hide_set(False);ob.select_set(True)
bpy.context.view_layer.objects.active=root
glb=BASE/'west_p3_review.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_animations=False)
report['review_glb']={'path':glb.name,'sha256':sha(glb),'bytes':glb.stat().st_size}
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if '--no-render' not in sys.argv:
    target=bl((1.85,2.6,0));scene.camera.location=target+bl((32,39,32))
    scene.camera.rotation_euler=(target-scene.camera.location).to_track_quat('-Z','Y').to_euler();scene.camera.data.ortho_scale=8.1
    scene.render.filepath=str(BASE/'west_p3_default_direction.png');bpy.ops.render.render(write_still=True)
    report['offline_preview']={'path':'west_p3_default_direction.png','sha256':sha(BASE/'west_p3_default_direction.png'),'direction':[32,39,32],'not_game_screenshot':True}
    (BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('WEST_P3_READY',json.dumps({'checks':len(checks),'failures':len(report['failures']),'triangles':triangles,'glb':report['review_glb']},ensure_ascii=False))
