"""F1 thermal stone P1 editable source. No GLB, game code, or runtime lights."""
from pathlib import Path
import argparse, hashlib, json, math, os, sys
import bpy, bmesh
from mathutils import Vector
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ASSET = HERE.parent
ROOT = ASSET.parents[2]
TEX = ASSET / "inputs/textures"
CAMERA_G = Vector((32,39,32))
MODEL = None
STUDIO = None

def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return [float(p.x),float(p.z),float(-p.y)]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def relink(o, collection):
    for c in list(o.users_collection): c.objects.unlink(o)
    collection.objects.link(o)

def normals(mesh):
    bm=bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free(); mesh.update()

def mesh_object(name, verts, faces, mat):
    mesh=bpy.data.meshes.new(name+"_Editable")
    mesh.from_pydata([bp(v) for v in verts],[],faces); mesh.update()
    if mesh.validate(verbose=True): raise RuntimeError("Unexpected mesh repair: "+name)
    normals(mesh)
    o=bpy.data.objects.new(name,mesh); MODEL.objects.link(o)
    o.data.materials.append(mat); o["asset_family"]="F-B"; o["entity_id"]="F1:thermal"
    return o

def bevel(o,width):
    bpy.context.view_layer.objects.active=o
    mod=o.modifiers.new("Editable_edge_planes","BEVEL")
    mod.width=width; mod.segments=1; mod.affect="EDGES"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    normals(o.data)

def uv_project(o,stone=False):
    m=o.data; uv=m.uv_layers.new(name="PaintUV"); uv.active_render=True
    bounds=[(min(v.co[k] for v in m.vertices),max(v.co[k] for v in m.vertices)) for k in range(3)]
    column=sum(o.name.encode())%4
    for p in m.polygons:
        axis=max(range(3),key=lambda k:abs(p.normal[k])); axes=[k for k in range(3) if k!=axis]
        row=2 if p.normal.z>.35 else 0 if p.normal.z<-.55 else 1
        for li in p.loop_indices:
            co=m.vertices[m.loops[li].vertex_index].co
            if stone:
                u,v=[(co[k]-bounds[k][0])/max(1e-8,bounds[k][1]-bounds[k][0]) for k in axes]
                uv.data[li].uv=((column+.04+.92*u)/4,(row+.04+.92*v)/4)
            else: uv.data[li].uv=(co[axes[0]]*.7,co[axes[1]]*.7)

def material(name,family):
    m=bpy.data.materials.new(name);m.use_nodes=True
    n=m.node_tree.nodes; l=m.node_tree.links; bs=n.get("Principled BSDF")
    bs.inputs["Metallic"].default_value=0
    for channel,socket in [("BaseColor","Base Color"),("Roughness","Roughness"),("Normal","Normal")]:
        im=bpy.data.images.load(str(TEX/("FB_"+family+"_"+channel+".png")),check_existing=True)
        if channel!="BaseColor":im.colorspace_settings.name="Non-Color"
        im.pack();t=n.new("ShaderNodeTexImage");t.image=im
        uv=n.new("ShaderNodeUVMap");uv.uv_map="PaintUV";l.new(uv.outputs["UV"],t.inputs["Vector"])
        if channel=="Normal":
            nm=n.new("ShaderNodeNormalMap");nm.uv_map="PaintUV"
            nm.inputs["Strength"].default_value=.28 if family=="stone" else .38
            l.new(t.outputs["Color"],nm.inputs["Color"]);l.new(nm.outputs["Normal"],bs.inputs["Normal"])
        elif channel=="BaseColor":
            hs=n.new("ShaderNodeHueSaturation");hs.inputs["Saturation"].default_value=.85 if family=="stone" else .90
            hs.inputs["Value"].default_value=.94 if family=="stone" else .95
            l.new(t.outputs["Color"],hs.inputs["Color"]);l.new(hs.outputs["Color"],bs.inputs[socket])
        else:l.new(t.outputs["Color"],bs.inputs[socket])
    return m

def core_material(name,strength):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(.025,.29,.30,1)
    p.inputs["Metallic"].default_value=0
    p.inputs["Roughness"].default_value=.49
    p.inputs["Emission Color"].default_value=(.025,.29,.30,1)
    p.inputs["Emission Strength"].default_value=strength
    m["display_temperature_only"]=20;m["state_driver"]="Root-owned future temperature presentation"
    return m

def stone_box(name,center,size,mat,width):
    x,y,z=[a/2 for a in size]
    vs=[(center[0]+a*x,center[1]+b*y,center[2]+c*z)
        for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1),(-1,1,-1),(1,1,-1),(1,1,1),(-1,1,1)]]
    o=mesh_object(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    bevel(o,width);uv_project(o,True);return o

def top_y(x,z):return 1.55-.18*x-.30*z
NORMAL=Vector((.18,1,.30)).normalized()
U=Vector((1,-.18,0)).normalized()
V=NORMAL.cross(U).normalized()
CENTER=Vector((.28,top_y(.28,.23),.23))

def cut(body,cutter):
    bpy.context.view_layer.objects.active=body
    m=body.modifiers.new("Actual_shallow_recess","BOOLEAN");m.operation="DIFFERENCE";m.solver="EXACT";m.object=cutter
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter,do_unlink=True);normals(body.data)

def cylinder(name,center,radius,depth,mat=None,collection=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius,depth=depth,location=bp(center))
    o=bpy.context.object;o.name=name;relink(o,collection or MODEL)
    o.rotation_mode="QUATERNION";o.rotation_quaternion=Vector((0,0,1)).rotation_difference(bp(NORMAL))
    if mat:o.data.materials.append(mat)
    return o

def oriented_box(name,center,u,v,n,half,mat=None,collection=None):
    vs=[Vector(center)+u*(a*half[0])+v*(b*half[1])+n*(c*half[2])
        for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([bp(p) for p in vs],[],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]);mesh.update();normals(mesh)
    o=bpy.data.objects.new(name,mesh);(collection or MODEL).objects.link(o)
    if mat:o.data.materials.append(mat)
    return o

def catmull(points,steps=8):
    pts=[Vector(p) for p in points];out=[]
    for i in range(len(pts)-1):
        a,b,c,d=pts[max(0,i-1)],pts[i],pts[i+1],pts[min(len(pts)-1,i+2)]
        for j in range(steps):
            t=j/steps
            out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    return out+[pts[-1]]

def root_tube(name,controls,radius,mat):
    pts=catmull(controls);sides=10;verts=[];dist=[0.0];previous_u=None
    for i,p in enumerate(pts):
        if i:dist.append(dist[-1]+(p-pts[i-1]).length)
        tangent=(pts[min(len(pts)-1,i+1)]-pts[max(0,i-1)]).normalized()
        if previous_u is None:
            ref=Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((1,0,0))
            u=tangent.cross(ref).normalized()
        else:
            u=(previous_u-tangent*previous_u.dot(tangent)).normalized()
        v=tangent.cross(u).normalized();previous_u=u
        t=i/(len(pts)-1);r=radius*(.30+.70*min(1,t*8,(1-t)*8))
        for j in range(sides):
            a=j*math.tau/sides;rj=r*(1+.06*math.sin(j*3+i*.12))
            verts.append(p+rj*(math.cos(a)*u+math.sin(a)*v))
    faces=[]
    for i in range(len(pts)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces+=[tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))]
    o=mesh_object(name,verts,faces,mat);m=o.data;uv=m.uv_layers.new(name="PaintUV");uv.active_render=True
    for p in m.polygons:
        js=[m.loops[li].vertex_index%sides for li in p.loop_indices]
        seam=0 in js and sides-1 in js
        for li in p.loop_indices:
            vi=m.loops[li].vertex_index;j=vi%sides
            u=1.0 if seam and j==0 else j/sides
            if len(p.vertices)==4:uv.data[li].uv=(u,dist[vi//sides]/1.2)
            else:uv.data[li].uv=(.5+.45*math.cos(j*math.tau/sides),.5+.45*math.sin(j*math.tau/sides))
        p.use_smooth=len(p.vertices)==4
    o["continuous_root_control_points_godot"]=[list(p) for p in controls]
    return o

def build():
    global MODEL,STUDIO
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.unit_settings.system="METRIC";scene.unit_settings.scale_length=1
    MODEL=bpy.data.collections.new("F1ThermalStone_EDITABLE");scene.collection.children.link(MODEL)
    STUDIO=bpy.data.collections.new("STUDIO_NOT_EXPORTED");scene.collection.children.link(STUDIO)
    stone=material("FT_WarmFacetedStone","stone");bark=material("FT_ContinuousBark","bark");moss=material("FT_SparseMoss","moss")
    core=core_material("FT_TemperatureCore",.13);inlay=core_material("FT_HeatInlays",.08)
    foot=[(-1.28,-.68),(-1.03,-.84),(1.07,-.84),(1.29,-.60),(1.29,.59),(1.06,.82),(-1.08,.82),(-1.29,.61)]
    verts=[(x,0,z) for x,z in foot]+[(x,top_y(x,z),z) for x,z in foot]
    faces=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    body=mesh_object("StoneBody",verts,faces,stone)
    bevel(body,.065)
    cut(body,cylinder("CUT_core",CENTER+NORMAL*.005,.49,.17,collection=STUDIO))
    channel_ends=[Vector((-.61,top_y(-.61,.49),.49)),Vector((.99,top_y(.99,.49),.49))]
    inlays=[]
    for i,end in enumerate(channel_ends):
        direction=(end-CENTER).normalized();start=CENTER+direction*.43
        mid=(start+end)/2;across=NORMAL.cross(direction).normalized();length=(end-start).length
        cut(body,oriented_box("CUT_groove",mid+NORMAL*.01,direction,across,NORMAL,(length/2,.065,.07),collection=STUDIO))
        o=oriented_box("HeatInlays_"+str(i+1),mid-NORMAL*.037,direction,across,NORMAL,(length/2-.012,.046,.018),inlay)
        uv_project(o);inlays.append(o)
    uv_project(body,True)
    c=cylinder("TemperatureCore",CENTER-NORMAL*.048,.432,.045,core)
    bevel(c,.009);uv_project(c)
    c["outward_normal_godot"]=list(NORMAL);c["display_only_temperature"]=20
    # Four broad shoulders retain substantial mass; no rubble/noise field.
    for name,loc,size,w in [
        ("StoneFoot_Left",(-1.13,.25,.55),(.56,.50,.51),.06),
        ("StoneFoot_Right",(1.12,.29,.54),(.56,.58,.52),.06),
        ("StoneShoulder_Back",(-.68,1.67,-.52),(.89,.54,.55),.075),
        ("StoneShoulder_Right",(1.05,1.08,-.36),(.49,.68,.50),.05)]:
        stone_box(name,loc,size,stone,w)
    root_tube("RootBindings_West",[
        (-.89,.10,.83),(-1.12,.43,.73),(-1.25,1.03,.30),(-1.12,1.68,-.40),
        (-.64,1.82,-.64),(-.12,1.72,-.66),(.42,1.57,-.50)],.145,bark)
    root_tube("RootBindings_East",[
        (1.03,.10,.82),(1.25,.48,.69),(1.32,.96,.22),(1.24,1.35,-.35),
        (.91,1.64,-.68),(.40,1.74,-.71),(-.06,1.78,-.64)],.128,bark)
    root_tube("RootBindings_Front",[
        (-.99,.08,.89),(-.63,.23,.88),(-.20,.42,.85),(.28,.58,.85),
        (.72,.80,.76),(1.05,1.09,.49)],.081,bark)
    # Sparse low-profile patches, no grass cards or tiny scattered leaves.
    for i,(p,s) in enumerate([
        ((-.70,1.956,-.51),(.35,.023,.20)),
        ((-1.15,.515,.53),(.24,.024,.20)),
        ((1.10,.595,.52),(.26,.026,.17)),
        ((.83,top_y(.83,-.63)+.008,-.63),(.24,.018,.15))]):
        o=stone_box("Moss_"+str(i+1),p,s,moss,.006)
        # The same explicit UV map samples the copied moss material.
    root=bpy.data.objects.new("F1ThermalStone",None);MODEL.objects.link(root)
    for o in list(MODEL.objects):
        if o!=root:o.parent=root;o["scope"]="render only; original game collision unchanged"
    root["origin_godot"]=[0,0,0];root["world_bottom_origin"]=[-29,0,8]
    root["no_runtime_lights"]=True
    return root

def audit():
    bpy.context.view_layer.update()
    col=bpy.data.collections["F1ThermalStone_EDITABLE"];objects=[o for o in col.objects if o.type=="MESH"]
    pts=[];rows=[];bad=[]
    for o in objects:
        m=o.data;m.calc_loop_triangles();naked=0;edge_counts={}
        for p in m.polygons:
            for edge in p.edge_keys:edge_counts[edge]=edge_counts.get(edge,0)+1
        naked=sum(1 for count in edge_counts.values() if count!=2)
        area_min=min(t.area for t in m.loop_triangles)
        uv=m.uv_layers.get("PaintUV")
        if naked or area_min<=0 or uv is None:bad.append({"object":o.name,"open_or_nonmanifold_edges":naked,"min_triangle_area":area_min,"uv":uv is not None})
        for v in m.vertices:pts.append(gp(o.matrix_world@v.co))
        if uv and not all(math.isfinite(k) for d in uv.data for k in d.uv):bad.append({"object":o.name,"nonfinite_uv":True})
        rows.append({"name":o.name,"vertices":len(m.vertices),"triangles":len(m.loop_triangles),"materials":[a.name for a in m.materials],"open_or_nonmanifold_edges":naked,"min_triangle_area_m2":area_min})
    low=[min(p[k] for p in pts) for k in range(3)];high=[max(p[k] for p in pts) for k in range(3)]
    limits=[(-1.5,1.5),(0,2),(-1,1)]
    inside=all(low[k]>=limits[k][0]-1e-6 and high[k]<=limits[k][1]+1e-6 for k in range(3))
    root=bpy.data.objects["F1ThermalStone"]
    root_identity=all(abs(root.matrix_world[i][j]-(1 if i==j else 0))<1e-7 for i in range(4) for j in range(4))
    result={"bounds_godot":{"min":low,"max":high},"inside_original_box":inside,"root_identity":root_identity,
        "mesh_count":len(rows),"triangles":sum(r["triangles"] for r in rows),"objects":rows,"invalid":bad,
        "core_normal_godot":list(NORMAL),"normal_dot_game_camera":NORMAL.dot(CAMERA_G.normalized()),
        "model_lights":sum(o.type=="LIGHT" for o in col.objects),
        "no_runtime_export":True,"scope":"offline editable source; no game/collision/playthrough approval"}
    result["ok"]=inside and root_identity and not bad and result["model_lights"]==0
    return result

def studio():
    scene=bpy.context.scene
    scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=20;scene.cycles.use_denoising=True
    scene.render.threads_mode="FIXED";scene.render.threads=2
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format="PNG"
    scene.view_settings.view_transform="AgX"
    world=bpy.data.worlds.new("Neutral_studio");scene.world=world;world.use_nodes=True
    world.node_tree.nodes["Background"].inputs[0].default_value=(.40,.44,.46,1)
    world.node_tree.nodes["Background"].inputs[1].default_value=.55
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.018));o=bpy.context.object;o.name="STUDIO_floor";relink(o,STUDIO)
    m=bpy.data.materials.new("STUDIO_floor");m.diffuse_color=(.25,.27,.27,1);o.data.materials.append(m)
    for name,loc,energy,size in [("Key",(4,7,4),850,5),("Fill",(-4,4,2),480,5),("Back",(1,5,-5),600,4)]:
        d=bpy.data.lights.new("STUDIO_"+name,"AREA");d.energy=energy;d.shape="DISK";d.size=size
        o=bpy.data.objects.new(d.name,d);STUDIO.objects.link(o);o.location=bp(loc)
        o.rotation_euler=(bp((0,1,0))-o.location).to_track_quat("-Z","Y").to_euler()
    d=bpy.data.cameras.new("SourceReviewCamera");o=bpy.data.objects.new(d.name,d);STUDIO.objects.link(o)
    scene.camera=o;d.type="ORTHO";return o

def view(camera,offset,height,resolution):
    scene=bpy.context.scene;scene.render.resolution_x=resolution[0];scene.render.resolution_y=resolution[1]
    focus=bp((0,1,0));camera.location=focus+bp(offset)
    camera.rotation_euler=(focus-camera.location).to_track_quat("-Z","Y").to_euler()
    # Calibrate actual Blender frame height instead of assuming sensor-fit semantics.
    camera.data.ortho_scale=height
    frame=camera.data.view_frame(scene=scene);actual=max(v.y for v in frame)-min(v.y for v in frame)
    camera.data.ortho_scale*=height/actual
    frame=camera.data.view_frame(scene=scene)
    return {"godot_direction":list(offset),"vertical_span_m":max(v.y for v in frame)-min(v.y for v in frame),
        "resolution":list(resolution),"scope":"offline source projection, not Godot screenshot"}

def main():
    print('THERMAL_SOURCE_PID '+str(os.getpid()),flush=True)
    p=argparse.ArgumentParser();p.add_argument("--output",required=True);p.add_argument("--readback-only",action="store_true")
    args=p.parse_args(sys.argv[sys.argv.index("--")+1:]);out=Path(args.output).resolve()
    if ASSET.resolve() not in out.parents:raise RuntimeError("Output outside owned asset directory")
    if args.readback_only:
        bpy.ops.wm.open_mainfile(filepath=str(out/"f1_thermal_stone_editable.blend"))
        report=audit();(out/"readback.json").write_text(json.dumps(report,indent=2))
        if not report["ok"]:raise RuntimeError("Source reopen audit failed")
        print("THERMAL_SOURCE_READBACK_PASS",flush=True);return
    out.mkdir(exist_ok=False,parents=True)
    build();report=audit();(out/"geometry.json").write_text(json.dumps(report,indent=2))
    if not report["ok"]:raise RuntimeError("Source geometry audit failed: "+json.dumps(report))
    camera=studio();view(camera,CAMERA_G,3.5,(1100,900))
    bpy.ops.wm.save_as_mainfile(filepath=str(out/"f1_thermal_stone_editable.blend"))
    shots=[]
    for name,offset,height,res in [
        ("01-game-direction-close",CAMERA_G,3.5,(1100,900))]:
        shot=view(camera,offset,height,res);shot["file"]=name+".png"
        bpy.context.scene.render.filepath=str(out/shot["file"])
        bpy.ops.render.render(write_still=True);shots.append(shot)
        print("THERMAL_SOURCE_SHOT "+name,flush=True)
    (out/"shots.json").write_text(json.dumps(shots,indent=2))
    bpy.ops.wm.open_mainfile(filepath=str(out/"f1_thermal_stone_editable.blend"))
    readback=audit();(out/"readback.json").write_text(json.dumps(readback,indent=2))
    if readback!=report:raise RuntimeError("Saved editable source differs on reopen")
    print("THERMAL_SOURCE_PASS "+json.dumps({"meshes":report["mesh_count"],"triangles":report["triangles"],"bounds":report["bounds_godot"]}),flush=True)

if __name__=="__main__":main()

