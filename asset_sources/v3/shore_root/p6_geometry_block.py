# Source fragment embedded into build_shore_root_p6.py. No runtime export.
import bmesh

# The only continuous foundation is a low buried skirt, never a slope wall.
rows=[(-5.9,-2.7,2.7),(-5.1,-3.7,3.5),(-3.8,-4.25,4.4),
      (-2.8,-4.5,4.58),(-1.0,-4.4,4.58),(.8,-4.5,4.58),
      (2.5,-4.3,4.5),(3.9,-4.5,3.4),(4.55,-4.5,2.7),
      (5.0,-4.25,2.2),(5.75,-3.1,.8)]
vs=[];fs=[];columns=8
for z,left,right in rows:
    for j in range(columns):
        x=left+(right-left)*j/(columns-1)
        y=.16+.02*math.sin(x*.8+z*.6)
        if x<-.8 and z>3.9:y-=.13*math.exp(-((z-4.55)/.22)**2)
        vs.append((x,max(.025,y),z))
n=len(vs);vs +=[(x,0,z) for x,y,z in vs]
for r in range(len(rows)-1):
    for j in range(columns-1):
        a=r*columns+j
        fs.extend([(a,a+1,a+columns+1,a+columns),
                   (a+n,a+columns+n,a+columns+1+n,a+1+n)])
outline=list(range(columns))+[r*columns+columns-1 for r in range(1,len(rows))]
outline+=list(range(n-2,n-columns-1,-1))+[r*columns for r in range(len(rows)-2,0,-1)]
for i,a in enumerate(outline):b=outline[(i+1)%len(outline)];fs.append((a,b,b+n,a+n))
skirt=mesh('Buried_Skirt_Only_018m',vs,fs,[soil[1]],'buried low soil skirt')

cut_records=[]
def cut_rock(name,bounds,seed):
    x0,y0,z0,x1,y1,z1=bounds
    cx=(x0+x1)/2;cy=(y0+y1)/2;cz=(z0+z1)/2
    bm=bmesh.new()
    corners=[(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1),
             (x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)]
    vertices=[bm.verts.new(bp(p)) for p in corners]
    for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]:
        bm.faces.new([vertices[i] for i in face])
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    # Shared stratification inclination, with unequal directed break planes.
    planes=[((cx,y1-.08,cz),(-.045,1,.035)),
            ((x1-.18,cy,z1-.22),(1,.035,1)),
            ((x0+.13,cy,z1-.28),(-1,-.02,1)),
            ((x0+.28,cy,z0+.14),(-1,.04,-1)),
            ((x1-.25,cy,z0+.12),(1,-.025,-1)),
            ((x1-.07,cy,cz),(1,-.12,.075))]
    if seed%2==0:planes.append(((cx,y0+.05,z1-.075),(.13,-.22,1)))
    actual_cuts=[]
    for point,normal in planes:
        result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                 dist=1e-6,plane_co=bp(point),plane_no=bp(normal).normalized(),
                 clear_outer=True,clear_inner=False,use_snap_center=False)
        edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
        filled=bmesh.ops.holes_fill(bm,edges=edges,sides=0)['faces'] if edges else []
        actual_cuts.append({'point_godot':point,'normal_godot':normal,'cap_faces':len(filled)})
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.verts.ensure_lookup_table();bm.verts.index_update()
    vertices=[gp(v.co) for v in bm.verts];faces=[tuple(v.index for v in f.verts) for f in bm.faces]
    manifold=all(len(e.link_faces)==2 for e in bm.edges)
    bm.free()
    ob=mesh(name,vertices,faces,stone,'individually editable structural stone')
    # Colour follows real cut planes, not alternating painted triangles.
    for p in ob.data.polygons:p.material_index=1 if p.normal.z>.65 else (2 if p.normal.z<-.1 else 0)
    cut_records.append({'name':name,'bounds_requested_godot':bounds,'cuts':actual_cuts,
                        'closed_manifold_before_save':manifold,'faces':len(faces)})
    return ob

# Eight unequal bodies, with clear recesses between tiers on the visible right.
# The final bridge contact is a ninth short rock, not a 4.5m-high enclosing wall.
ROCKS=[
 ('R01_Low_West_Limestone',(-4.20,.04,-3.80,-.90,1.24,1.80)),
 ('R02_Low_Front_RootFoot',(-3.70,.035,1.10,2.70,1.38,4.04)),
 ('R03_Middle_North_Ledge',(-2.05,.08,-4.50,1.75,2.84,-.10)),
 ('R04_Middle_Back_Bearing',(.65,.08,-4.35,3.65,3.02,-.12)),
 ('R05_Middle_Front_Bearing',(.25,1.10,.22,3.92,3.02,4.04)),
 ('R06_Upper_Back_Limestone',(1.00,2.64,-3.20,3.62,4.44,.40)),
 ('R07_Upper_Front_Limestone',(1.48,2.72,-.28,4.34,4.48,3.16)),
 ('R08_Wet_Groove_OuterLip',(-4.17,.025,4.85,-1.45,.49,5.66))]
for i,(name,bounds) in enumerate(ROCKS):cut_rock(name,bounds,i)

# Precisely the final metre remains a flat 5.72m receiving interface.
outline=[(3.50,-2.79),(3.57,-2.86),(4.44,-2.86),(4.50,-2.80),
         (4.50,2.80),(4.44,2.86),(3.57,2.86),(3.50,2.79)]
vs=[(x,4.50,z) for x,z in outline]+[(x,4.25,z) for x,z in outline]
fs=[tuple(range(8)),tuple(reversed(range(8,16)))]
fs +=[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
mesh('R09_LastMetre_BridgeReceivingRock',vs,fs,stone,'individually editable structural stone')
bpy.context.view_layer.update();stone_objects=[o for o in parts if o['role']=='individually editable structural stone']
stone_tree=bvh(stone_objects+[skirt])

# Soil is restricted to stepped negative spaces. It is not a continuous ramp.
def soil_pocket(name,points):
    vs=[(x,y,z) for x,y,z in points]+[(x,max(.01,y-.24),z) for x,y,z in points]
    n=len(points);fs=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
    fs +=[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,vs,fs,[soil[0]],'soil filling rock negative space')
soil_pocket('Soil_West_Blend',[(-4.3,.34,0),(-3.85,.58,-.15),(-3.5,.58,.32),(-3.75,.38,.72),(-4.25,.24,.62)])
soil_pocket('Soil_Lower_RootPocket',[(-2.1,1.2,.65),(-1.15,1.35,.3),(-.75,1.40,.72),(-.9,1.27,1.45),(-1.8,1.24,1.38)])
soil_pocket('Soil_Middle_RockJoint',[(.30,2.73,-.4),(1.10,2.80,-.58),(1.50,2.86,-.18),(1.25,2.88,.48),(.56,2.76,.38)])
soil_pocket('Soil_Upper_RootCrease',[(2.50,4.30,2.55),(3.12,4.35,2.52),(3.32,4.40,2.83),(3.15,4.23,3.05),(2.68,4.13,2.91)])

def catmull(values,t):
    i=min(len(values)-2,int(t));f=t-i
    p0=Vector(values[max(i-1,0)]);p1=Vector(values[i]);p2=Vector(values[i+1]);p3=Vector(values[min(i+2,len(values)-1)])
    return .5*((2*p1)+(-p0+p2)*f+(2*p0-5*p1+4*p2-p3)*f*f+(-p0+3*p1-3*p2+p3)*f*f*f)

# Seven upper profile vertices create six longitudinal planes: broad asymmetric
# ridges and a shallow channel. Two lower vertices close a narrow underside.
PROFILE=[(-1,-.10),(-.76,.15),(-.38,.43),(-.04,.28),(.28,.50),(.69,.25),(1,-.08),(.55,-.45),(-.55,-.42)]
root_records=[]
def folded_root(name,control,widths,depths,twists):
    count=(len(control)-1)*5+1;n=len(PROFILE);centers=[];dimensions=[];verts=[];faces=[]
    for k in range(count):
        t=(len(control)-1)*k/(count-1);center=catmull(control,t)
        i=min(len(control)-2,int(t));f=t-i
        interpolate=lambda values:values[i]+(values[i+1]-values[i])*f
        centers.append(center);dimensions.append((interpolate(widths),interpolate(depths),interpolate(twists)))
    for i,center in enumerate(centers):
        tangent=(centers[min(i+1,count-1)]-centers[max(i-1,0)]).normalized()
        side=tangent.cross(Vector((0,1,0))).normalized();up=side.cross(tangent).normalized()
        width,depth,twist=dimensions[i]
        s=side*math.cos(twist)+up*math.sin(twist);u=up*math.cos(twist)-side*math.sin(twist)
        for j,(a,b) in enumerate(PROFILE):
            # Broad slowly shifting crest; no noise, cylinders or applied bark strips.
            ridge=b+(0.055*math.sin(i*.21+j*.8) if j in (2,3,4,5) else 0)
            p=center+s*(a*width*.5)+u*(ridge*depth)
            verts.append(tuple(p))
    faces=[tuple(reversed(range(n))),tuple((count-1)*n+j for j in range(n))]
    for i in range(count-1):
        for j in range(n):faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    ob=mesh(name,verts,faces,[bark[0]],'editable broad load-bearing root')
    ob['upper_longitudinal_planes']=6;ob['grain_direction']='along authored high-to-low centerline'
    contact=[]
    for i in range(count):
        lower=sorted([gp(v.co) for v in ob.data.vertices[i*n:(i+1)*n]],key=lambda p:p[1])[:3]
        gaps=[]
        for x,y,z in lower:
            h=top(stone_tree,x,z)
            if h is not None:gaps.append(y-h)
        contact.append({'section':i,'lowest_vertex_gaps':gaps,'minimum_gap':min(gaps) if gaps else None})
    root_records.append({'name':name,'contact_samples':contact,'control_godot':control})
    return ob

folded_root('Primary_Oblique_Twisted_Root',
 [(3.50,4.35,3.10),(2.35,3.28,3.25),(.85,2.90,3.00),(-.55,1.76,2.55),
  (-1.65,1.40,2.08),(-2.90,1.23,1.90),(-4.28,.20,1.65)],
 [1.05,1.55,1.95,2.05,1.75,1.15,.30],
 [.48,.80,1.10,1.05,.88,.60,.18],
 [.26,.11,-.18,-.23,.12,.29,.10])
folded_root('Lower_Fork_Grounding_In_Crease',
 [(-1.82,1.36,2.35),(-2.3,1.30,3.13),(-2.8,1.10,3.75),(-3.45,.22,4.12)],
 [.90,.78,.50,.18],[.54,.52,.38,.14],[.15,-.08,-.22,-.07])

