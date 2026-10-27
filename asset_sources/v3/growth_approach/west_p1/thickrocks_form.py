"""Bounded third form: four real interlocking stones + two natural fork copies.
Executed by build_west_approach.py in its explicit authoring namespace.
No shared files are written. Hidden source mesh remains editable in this .blend.
"""

FORK_SOURCE = PROJECT/'asset_sources/v3/shore_root/p9/rigid_root_main_form.blend'
FORK_SHA = sha(FORK_SOURCE)

def edge_half(x):
    # Only free edges withdraw. Exact west join and full-width bridge lip stay.
    # This recess contains the actual root section, not a hidden collision box.
    if x<.30: return 1.5-.38*x/.30
    if x<=1.95: return 1.12+.035*math.sin((x-.3)*3.1)
    if x<2.65: return 1.0879+(1.5-1.0879)*(x-1.95)/.70
    if x<=3.5: return 1.5
    return 1.5-.01*(x-3.5)/.25

def clipped_profile_top(column_indices, subdiv=4):
    vv=[]; ff=[]; cache={}
    def add(p):
        p=Vector(p)
        if abs(p.z)>1.0:
            original_half=1.5 if p.x<=3.5 else 1.5-.01*(p.x-3.5)/.25
            # Remap the entire outer 0.5m strip monotonically, never just pull
            # its boundary past the previous row and create folded triangles.
            new_abs=1+(abs(p.z)-1)*(edge_half(p.x)-1)/(original_half-1)
            p.z=math.copysign(new_abs,p.z)
            p.y=top_height(p.x,p.z)
        key=tuple(round(q,8) for q in p)
        if key not in cache:
            cache[key]=len(vv);vv.append(tuple(p))
        return cache[key]
    for col in column_indices:
        xa,a=SECTIONS[col];xb,b=SECTIONS[col+1]
        for j in range(len(a)-1):
            va=Vector((xa,a[j][1],a[j][0]));vb=Vector((xb,b[j][1],b[j][0]))
            vc=Vector((xb,b[j+1][1],b[j+1][0]));vd=Vector((xa,a[j+1][1],a[j+1][0]))
            for p,q,r in ((va,vb,vc),(va,vc,vd)):
                idx={}
                for u in range(subdiv+1):
                    for v in range(subdiv+1-u):
                        idx[u,v]=add(p+(q-p)*(u/subdiv)+(r-p)*(v/subdiv))
                for u in range(subdiv):
                    for v in range(subdiv-u):
                        ff.append((idx[u,v],idx[u+1,v],idx[u,v+1]))
                        if u+v<subdiv-1:
                            ff.append((idx[u+1,v],idx[u+1,v+1],idx[u,v+1]))
    counts={}
    for f in ff:
        for a,b in zip(f,f[1:]+f[:1]):
            key=tuple(sorted((a,b)));counts[key]=counts.get(key,0)+1
    neighbours={}
    for (a,b),n in counts.items():
        if n==1:
            neighbours.setdefault(a,[]).append(b);neighbours.setdefault(b,[]).append(a)
    assert all(len(v)==2 for v in neighbours.values())
    first=min(neighbours,key=lambda i:(vv[i][0],vv[i][2]))
    rim=[first];prior=-1;cur=first
    while True:
        nxt=next(i for i in neighbours[cur] if i!=prior)
        if nxt==first:break
        rim.append(nxt);prior,cur=cur,nxt
    assert len(rim)==len(neighbours)
    return vv,ff,rim

def upper_rock(name,columns,kind):
    vv,ff,rim=clipped_profile_top(columns)
    previous=rim
    for level,t in enumerate((.13,.63,1.0)):
        current=[]
        for idx in rim:
            x,top,z=vv[idx]
            if kind=='west':
                floor=1.72+.30*(x/1.5)+.23*(z+1.5)/3
                # A thick fractured upper block, not the former full-height post.
                # Unequal lower corner cuts form oblique faces around a fixed top.
                if x<.001: px=(.08,.23,.16)[level]+(.06,.13,.08)[level]*abs(z)/1.5
                else: px=x+(.015,-.12,-.04)[level]+.07*math.sin(z*1.5)
                pz=z*(.93,.81,.89)[level]+(.025,-.075,.045)[level]*math.sin(x*1.6)
                y=top*(1-t)+floor*t
            else:
                # This is a deep upper rock, not a thin lid. Its lower fracture
                # is oblique and bites between the two different lower stones.
                floor=2.55+.48*(z+1.5)/3+.12*(x-1.5)/2.25
                if x<1.501: px=(1.51,1.35,1.45)[level]+.08*math.sin(z*2)
                else: px=x-(.13,.51,.29)[level]*(x-1.5)/2.25-.10*(abs(z)/1.5)**2
                pz=z*(.94,.82,.88)[level]+(.025,.11,.065)[level]*math.sin((x-1.5)*1.8)
                y=top*(1-t)+floor*t
            current.append(len(vv));vv.append((max(.0,min(3.75,px)),y,max(-1.5,min(1.5,pz))))
        for k in range(len(rim)):
            kk=(k+1)%len(rim)
            ff.append((previous[k],current[k],current[kk],previous[kk]))
        previous=current
    ff.append(tuple(reversed(previous)))
    ob=mesh_object(name,vv,ff,[STONE,STONE_LIGHT,STONE_COOL])
    for poly in ob.data.polygons:
        normal=gd(poly.normal)
        if normal.y>.5:poly.material_index=1 if kind=='west' else 0
        elif normal.y<-.25:poly.material_index=2
        else:poly.material_index=0
    rocks.append(ob)
    return ob

upper_rock('Stone_A_WestJoinedMass',[0],'west')
upper_rock('Stone_B_UpperOffsetMass',[1,2],'upper')

def lower_rock(name,outline,top_values,phase):
    vv=[];n=len(outline)
    cx=sum(p[0] for p in outline)/n;cz=sum(p[1] for p in outline)/n
    for ring,t in enumerate((0,.12,.78,1)):
        for i,((x,z),height) in enumerate(zip(outline,top_values)):
            scale=(.89,1,.94,.86)[ring]
            px=cx+(x-cx)*scale+(.035,-.02,.06,-.035)[ring]*math.sin(i*1.2+phase)
            pz=cz+(z-cz)*scale+(.025,.0,-.025,.015)[ring]*math.cos(i*1.7+phase)
            y=height*t
            vv.append((max(.05,min(3.63,px)),y,max(-1.5,min(1.5,pz))))
    ff=[]
    for ring in range(3):
        for i in range(n):
            j=(i+1)%n
            ff.append((ring*n+i,ring*n+j,(ring+1)*n+j,(ring+1)*n+i))
    ff += [tuple(reversed(range(n))),tuple(range(3*n,4*n))]
    ob=mesh_object(name,vv,ff,[STONE,STONE_LIGHT,STONE_COOL])
    for f in ob.data.polygons:
        normal=gd(f.normal)
        f.material_index=1 if normal.y>.45 else (2 if normal.y<-.2 else 0)
    rocks.append(ob)

lower_rock('Stone_C_WestBasalFracture',[(.02,-1.24),(.65,-1.49),(1.72,-1.20),(2.04,-.18),(1.79,1.36),(.71,1.48),(.03,.79)],[2.23,2.16,2.42,2.85,2.56,2.37,2.17],.5)
lower_rock('Stone_D_EastDeepLayer',[(1.36,-1.30),(2.23,-1.49),(3.27,-1.23),(3.52,-.25),(3.17,1.45),(2.32,1.32),(1.44,.57)],[3.18,3.47,3.23,3.12,3.31,3.65,3.43],1.8)

def bvh_for(obs):
    points=[];tris=[]
    for ob in obs:
        ob.data.calc_loop_triangles();off=len(points)
        points += [ob.matrix_world@v.co for v in ob.data.vertices]
        tris += [tuple(off+i for i in t.vertices) for t in ob.data.loop_triangles]
    return BVHTree.FromPolygons(points,tris,all_triangles=True)

bpy.context.view_layer.update()
rock_bvh=bvh_for(rocks)
root_support=[]

# Genuine tree-base/fork mesh, not a newly generated uniform tube. Work on a
# copy, retain its original source coordinates and metadata inside this blend.
with bpy.data.libraries.load(str(FORK_SOURCE),link=False) as (src,dst):
    dst.objects=['P9_Natural_Fork_Rigid_3x_No_Stretch']
fork=dst.objects[0]
assert fork is not None
fork.parent=None;fork.matrix_world.identity()
archive=bpy.data.collections.new('READONLY_NATURAL_SOURCE_COPY_NOT_RENDERED')
scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
archive.objects.link(fork);fork.name='OriginalNaturalFork_SourceCoordinates';fork.hide_render=True
fork['source_sha256']=FORK_SHA
fork['source_url']='https://polyhaven.com/a/island_tree_01'
fork['source_rights']='CC0; provenance inherited from frozen shore_root/p9/README.md'
source_originals=[gd(v.co) for v in fork.data.vertices]

def natural_root(name,side,offset_x):
    ob=bpy.data.objects.new(name,fork.data.copy());model.objects.link(ob);ob.parent=root
    # Limit only the inward branch and two already identified thin side spurs.
    # The resulting cut faces are explicitly buried, not left as saw-cut tips.
    bm=bmesh.new();bm.from_mesh(ob.data)
    for point,normal in [((-.6,0,0),(-1,0,0)),((.4,0,0),(1,0,0))]:
        cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bl(point),plane_no=bl(normal),dist=1e-6,clear_outer=True)
        edge=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
        if edge:bmesh.ops.holes_fill(bm,edges=edge,sides=0)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    originals=[gd(v.co) for v in ob.data.vertices]
    # The measured source trunk twists: its exposed X is only ~.11m at Y=.8,
    # versus .35m at Y=.2. Preserve each section and translate it as a whole;
    # the former global X=.4 assumption buried the central trunk.
    slice_max=[]
    for j in range(44):
        yy=.1+j*.05
        values=[p.x for p in originals if abs(p.y-yy)<=.075]
        slice_max.append(max(values) if values else .4)
    def outer_x(yy):
        t=max(0.,min(42.999,(yy-.1)/.05));i=int(t)
        return slice_max[i]*(1-(t-i))+slice_max[i+1]*(t-i)
    for vert,p in zip(ob.data.vertices,originals):
        # Uniform scale in all source axes; bending round the rock does NOT
        # squash its normal section into a band. Roughly half embeds in stone.
        scale=1.10
        x=offset_x+(p.y-.1)*scale
        # Negative source Z is the thick natural fork, not unwanted inward
        # material. The previous Z>=-.35 cut removed most of that main fork.
        run=.80-p.z*scale
        edge=edge_half(x)
        radius=.10
        start=edge-radius
        if run<=start:
            z=side*run
            base=Vector((x,top_height(x,z),z));normal=Vector((0,1,0))
        elif run<=start+radius*math.pi*.5:
            a=(run-start)/radius
            z=side*(start+radius*math.sin(a))
            base=Vector((x,top_height(x,side*edge)-radius*(1-math.cos(a)),z))
            normal=Vector((0,math.cos(a),side*math.sin(a)))
        else:
            y=top_height(x,side*edge)-radius-(run-start-radius*math.pi*.5)
            hit,_,_,_=rock_bvh.ray_cast(bl((x,y,side*3)),bl((0,0,-side)),6.)
            if hit is None: raise AssertionError(('natural root lacks physical stone support',name,tuple(p),x,y))
            base=gd(hit);normal=Vector((0,0,side))
        burial=.42*max(0.,1.-(p.y-.1)/.18)
        burial += .42*max(0.,1.-(2.2-p.y)/.18)
        # Only the branch entering the protected central road is buried.
        burial += .55*max(0.,min(1.,(.93-run)/.18))
        exposure=.24
        if abs(normal.z)>.001:
            # Expose only the part which fits the hard border. This is a local
            # embedding translation of the original section, not flattening it.
            max_out=(1.49-abs(base.z))/abs(normal.z)
            exposure=min(exposure,max_out-.012)
        normal_distance=(p.x-outer_x(p.y))*scale+exposure-burial
        q=base+normal*normal_distance
        vert.co=bl(q)
    ob.data.materials.clear();ob.data.materials.append(BARK)
    for p in ob.data.polygons:p.use_smooth=True
    bpy.context.view_layer.objects.active=ob
    dec=ob.modifiers.new('SourceForkModerateDecimation','DECIMATE');dec.ratio=.52;dec.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=dec.name)
    ob['source']='frozen shore_root/p9 tree-base/fork copy, uniform 1.10 scale with measured-section translation and surface bending; no normal flattening'
    ob['source_sha256']=FORK_SHA
    ob['collision_source']='same_visible_triangles'
    ob['pruning']='source X[-.6,.4], original Z fork retained, pre-existing Y[.1,2.2]; end caps buried; inward fork embeds below protected road'
    objects.append(ob)
    root_support.append({'object':name,'source_sha256':FORK_SHA,'uniform_scale':1.10,'offset_x':offset_x,'side':side,'normal_scale':1.0,'bending':'top-to-side rounded lip radius .10m; actual section outer-X positioning','section_y_step_m':.05,'section_outer_x':slice_max,'exposed_outer_surface_m':.24,'end_cap_burial_m':.42})

natural_root('Root_NaturalSouthFork',1,.13)
natural_root('Root_NaturalNorthFork',-1,.20)
assert sha(FORK_SOURCE)==FORK_SHA
