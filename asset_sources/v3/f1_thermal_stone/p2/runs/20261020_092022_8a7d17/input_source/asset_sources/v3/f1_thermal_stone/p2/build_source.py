"""P2: six thick stone masses, a real segmented collar, sculpted roots and organic moss.
Reuses P1's frozen audit/studio/Boolean bookkeeping. No runtime exports.
"""
import importlib.util, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("thermal_source_p1_frozen",HERE.parent/"p1/build_source.py")
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
FOOT=[(-1.28,-.68),(-1.03,-.84),(1.07,-.84),(1.29,-.60),(1.29,.59),(1.06,.82),(-1.08,.82),(-1.29,.61)]
SEEDS=[(-.78,-.40),(.43,-.43),(-.95,.29),(.08,.13),(.99,.27),(.08,.68)]
SHIFTS=[.075,.025,-.025,0,-.035,-.065]

def height(x,z):return 1.43-.18*x-.30*z
base.NORMAL=Vector((.18,1,.30)).normalized()
base.CENTER=Vector((.16,height(.16,.16),.16))

def clip(poly,n,d):
    out=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        av=a[0]*n[0]+a[1]*n[1]-d;bv=b[0]*n[0]+b[1]*n[1]-d
        if av<=1e-10:out.append(a)
        if (av<0)!=(bv<0):
            t=av/(av-bv);out.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
    return out

def cells():
    out=[]
    for i,a in enumerate(SEEDS):
        poly=list(FOOT)
        for j,b in enumerate(SEEDS):
            if i==j:continue
            n=(b[0]-a[0],b[1]-a[1])
            # Actual 14mm total mortar-free seams, not a shader grid.
            d=(b[0]**2+b[1]**2-a[0]**2-a[1]**2)/2-.007*math.hypot(*n)
            poly=clip(poly,n,d)
        if len(poly)<3:raise RuntimeError("Empty authored stone region")
        out.append(poly)
    return out

def material_adjust(m,family):
    n=m.node_tree.nodes;l=m.node_tree.links;p=n.get("Principled BSDF")
    source=p.inputs["Base Color"].links[0].from_socket
    mix=n.new("ShaderNodeMixRGB");mix.blend_type="MIX"
    mix.inputs[0].default_value=.13 if family=="stone" else .24
    mix.inputs[2].default_value=(.33,.285,.205,1) if family=="stone" else (.14,.075,.034,1)
    l.new(source,mix.inputs[1]);l.new(mix.outputs[0],p.inputs["Base Color"])
    return m

def temperature_material(name,strength):
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links
    p=n.get("Principled BSDF");p.inputs["Metallic"].default_value=0;p.inputs["Roughness"].default_value=.48
    neutral=n.new("ShaderNodeRGB");neutral.name="DELIVERY_NEUTRAL_ALBEDO";neutral.outputs[0].default_value=(.61,.64,.61,1)
    tint=n.new("ShaderNodeRGB");tint.name="PREVIEW_TEMPERATURE_20";tint.outputs[0].default_value=(.10,.62,.65,1)
    mul=n.new("ShaderNodeMixRGB");mul.blend_type="MULTIPLY";mul.inputs[0].default_value=1
    l.new(neutral.outputs[0],mul.inputs[1]);l.new(tint.outputs[0],mul.inputs[2])
    l.new(mul.outputs[0],p.inputs["Base Color"]);l.new(mul.outputs[0],p.inputs["Emission Color"])
    p.inputs["Emission Strength"].default_value=strength
    m["delivery_neutral_albedo"]=[.61,.64,.61];m["preview_tint_not_bake_input"]=True
    m["temperature_state_is_presentation_only"]=20
    return m

def prism(name,poly,bottom,shift,mat,bevel):
    vs=[(x,bottom,z) for x,z in poly]+[(x,height(x,z)+shift,z) for x,z in poly]
    n=len(poly);faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    o=base.mesh_object(name,vs,faces,mat);base.bevel(o,bevel);return o

def collar_piece(index,start,end,mat):
    normal=base.NORMAL;u=base.U;v=normal.cross(u).normalized();c=base.CENTER
    count=5;vs=[]
    for h in [-.086,.037]:
        for r in [.396,.604]:
            for j in range(count+1):
                a=start+(end-start)*j/count
                vs.append(c+normal*h+r*(math.cos(a)*u+math.sin(a)*v))
    n=count+1;faces=[]
    for j in range(count):
        faces.extend([(j,j+1,n+j+1,n+j),(2*n+j,3*n+j,3*n+j+1,2*n+j+1),
                      (j,2*n+j,2*n+j+1,j+1),(n+j,n+j+1,3*n+j+1,3*n+j)])
    faces.extend([(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)])
    o=base.mesh_object("StoneCollar_%02d"%index,vs,faces,mat)
    base.bevel(o,.012);return o

def crystal(mat):
    n=24;c=base.CENTER;normal=base.NORMAL;u=base.U;v=normal.cross(u).normalized();vs=[]
    for ring in range(3):
        for i in range(n):
            a=i*math.tau/n
            r=[.373,.356,.205][ring]
            h=[-.065,-.018,.009+.004*math.sin(i*2.3)][ring]
            vs.append(c+normal*h+r*(math.cos(a)*u+math.sin(a)*v))
    vs.extend([c+normal*.023,c-normal*.065]);faces=[]
    for ring in range(2):
        for i in range(n):
            j=(i+1)%n;faces.append((ring*n+i,ring*n+j,(ring+1)*n+j,(ring+1)*n+i))
    for i in range(n):
        j=(i+1)%n;faces.extend([(2*n+i,2*n+j,3*n),(i,3*n+1,j)])
    o=base.mesh_object("TemperatureCore",vs,faces,mat);base.uv_project(o)
    o["outward_normal_godot"]=list(normal);o["display_only_temperature"]=20
    return o

def sculpted_root(name,controls,radius,sides,mat):
    pts=base.catmull(controls,steps=9);verts=[];distance=[0]
    for i,p in enumerate(pts):
        if i:distance.append(distance[-1]+(p-pts[i-1]).length)
        tangent=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
        if p.y>1.48 or p.y<.20:outward=Vector((0,1,0))
        else:outward=Vector((p.x*.8,.06,p.z*1.5)).normalized()
        n=(outward-tangent*outward.dot(tangent)).normalized()
        if n.length<.8:raise RuntimeError("Root frame collapsed")
        side=tangent.cross(n).normalized()
        t=i/(len(pts)-1)
        end_factor=.30+.70*min(1,t*8,(1-t)*8)
        r=radius*end_factor*(1+.17*math.sin(t*math.tau*1.7)+.08*math.sin(t*17+1))
        flat=.26 if p.y<.20 else .49
        for j in range(sides):
            a=j*math.tau/sides
            # Three continuous broad ridges are actual cross-section geometry.
            ridge=1+.14*math.cos(3*a+.23*math.sin(t*6))
            verts.append(p+side*(math.cos(a)*r*ridge)+n*(math.sin(a)*r*flat*ridge))
    faces=[]
    for i in range(len(pts)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces += [tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))]
    o=base.mesh_object(name,verts,faces,mat);mesh=o.data;uv=mesh.uv_layers.new(name="PaintUV");uv.active_render=True
    for p in mesh.polygons:
        js=[mesh.loops[li].vertex_index%sides for li in p.loop_indices];seam=0 in js and sides-1 in js
        for li in p.loop_indices:
            vi=mesh.loops[li].vertex_index;j=vi%sides
            if len(p.vertices)==4:uv.data[li].uv=(1 if seam and j==0 else j/sides,distance[vi//sides]/1.8)
            else:uv.data[li].uv=(.5+.45*math.cos(j*math.tau/sides),.5+.45*math.sin(j*math.tau/sides))
        p.use_smooth=len(p.vertices)==4
    o["continuous_ridges"]=3;o["root_profile"]="flat contact side, varying width, integral ridges"
    return o

def moss_patch(index,center,radii,mat):
    x,z=center;k=min(range(len(SEEDS)),key=lambda i:(x-SEEDS[i][0])**2+(z-SEEDS[i][1])**2)
    ring=[];count=13
    for i in range(count):
        a=i*math.tau/count;r=1+.20*math.sin(i*2.37+index)+.09*math.sin(i*4.1)
        xx=x+math.cos(a)*radii[0]*r;zz=z+math.sin(a)*radii[1]*r
        ring.append((xx,height(xx,zz)+SHIFTS[k]+.004,zz))
    vs=ring+[(p[0],p[1]+.013+.005*math.sin(i*1.8),p[2]) for i,p in enumerate(ring)]
    faces=[tuple(reversed(range(count))),tuple(range(count,2*count))]
    faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    o=base.mesh_object("MossOrganic_%02d"%index,vs,faces,mat);base.uv_project(o)
    return o

def build():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.unit_settings.system="METRIC";scene.unit_settings.scale_length=1
    base.MODEL=bpy.data.collections.new("F1ThermalStone_EDITABLE");scene.collection.children.link(base.MODEL)
    base.STUDIO=bpy.data.collections.new("STUDIO_NOT_EXPORTED");scene.collection.children.link(base.STUDIO)
    stone=material_adjust(base.material("FT_WarmFacetedStone","stone"),"stone")
    bark=material_adjust(base.material("FT_ContinuousBark","bark"),"bark")
    moss=base.material("FT_SparseMoss","moss")
    core=temperature_material("FT_TemperatureCore",.10);inlay=temperature_material("FT_HeatInlays",.07)
    # A low complete foundation seals the bottom of the six genuinely thick masses.
    foundation=base.stone_box("StoneFoundation",(0,.125,0),(2.55,.25,1.62),stone,.07)
    parts=[]
    for i,poly in enumerate(cells()):
        o=prism("StoneMass_%02d"%(i+1),poly,.20,SHIFTS[i],stone,[.055,.075,.045,.045,.060,.055][i])
        base.cut(o,base.cylinder("CUT_core_cradle",base.CENTER+base.NORMAL*.035,.624,.30,collection=base.STUDIO))
        parts.append(o)
    collars=[]
    for i in range(8):
        a=i*math.tau/8
        collars.append(collar_piece(i+1,a+.018,a+math.tau/8-.018,stone))
    # Two true open-topped stone seams cross the collar and carry inset channels.
    endpoints=[Vector((-.64,height(-.64,.49),.49)),Vector((1.00,height(1.00,.39),.39))]
    for i,end in enumerate(endpoints):
        direction=(end-base.CENTER).normalized();start=base.CENTER+direction*.385;mid=(start+end)/2
        across=base.NORMAL.cross(direction).normalized();length=(end-start).length
        for o in parts+collars:
            base.cut(o,base.oriented_box("CUT_inset_groove",mid+base.NORMAL*.04,direction,across,base.NORMAL,(length/2,.062,.10),collection=base.STUDIO))
        o=base.oriented_box("HeatInlays_"+str(i+1),mid-base.NORMAL*.046,direction,across,base.NORMAL,(length/2-.012,.041,.018),inlay)
        base.uv_project(o)
    for o in parts+collars:base.uv_project(o,True)
    crystal(core)
    sculpted_root("RootBindings_Main",[
        (-1.12,.055,.77),(-1.31,.36,.56),(-1.29,.92,.13),(-1.12,1.58,-.43),
        (-.77,1.84,-.62),(-.30,1.82,-.66),(.23,1.73,-.68),(.77,1.59,-.61),
        (1.19,1.35,-.37),(1.32,.94,.15),(1.30,.46,.59),(1.09,.06,.80)],.175,22,bark)
    sculpted_root("RootBindings_Front",[
        (1.28,.57,.66),(.95,.47,.79),(.48,.35,.85),(-.06,.24,.88),
        (-.59,.17,.88),(-1.06,.055,.86)],.139,18,bark)
    for i,(p,s) in enumerate([((-.77,-.42),(.16,.085)),((.72,-.54),(.15,.075)),
                                ((-1.02,.27),(.10,.12)),((.98,.48),(.11,.09))]):
        moss_patch(i+1,p,s,moss)
    root=bpy.data.objects.new("F1ThermalStone",None);base.MODEL.objects.link(root)
    for o in list(base.MODEL.objects):
        if o!=root:o.parent=root;o["scope"]="source visual only; unchanged original Box collision"
    root["origin_godot"]=[0,0,0];root["world_bottom_origin"]=[-29,0,8];root["no_runtime_lights"]=True
    root["delivery_plan"]="6 meshes / 5 materials: Stone, Roots, Moss, TemperatureCore, HeatInlays_1, HeatInlays_2"
    return root

base.build=build
if __name__=="__main__":base.main()

