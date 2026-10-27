"""One bounded source study. Imported only by its explicitly authorized Blender stages."""
from pathlib import Path
import hashlib, json, math, os, sys
sys.dont_write_bytecode = True
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
OUT=Path(os.environ['RECOVERY_SAMPLE_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
CFG=json.loads((HERE/'fixed_config.json').read_text(encoding='utf-8'))

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,data): (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def bp(x,y,z): return (x,-z,y)
def gp(v): return [float(v[0]),float(v[2]),float(-v[1])]
def clamp(v): return max(0.,min(1.,v))
def smooth(v): v=clamp(v);return v*v*(3-2*v)
def select(obs,active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.hide_set(False);o.hide_viewport=False;o.select_set(True)
    bpy.context.view_layer.objects.active=active or obs[0]
def show(obs):
    names={o.name for o in obs}
    for o in bpy.data.objects:
        if o.type=='MESH' and o.get('study_part'):o.hide_render=o.name not in names

def load_image(rel,space):
    p=(ROOT/rel).resolve();expected=CFG['inputs'][rel]
    assert sha(p)==expected['sha256'] and p.stat().st_size==expected['bytes'],str(p)
    im=bpy.data.images.load(str(p),check_existing=True);im.colorspace_settings.name=space
    im.filepath=str(p)
    pixel=tuple(im.pixels[:4]);assert pixel and im.has_data and all(math.isfinite(x) for x in pixel)
    return im

def images_report():
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE':continue
        p=Path(bpy.path.abspath(im.filepath)).resolve()
        assert p.is_file(),(im.name,im.filepath,str(p))
        first=tuple(im.pixels[:4]);assert im.has_data and first and all(math.isfinite(x) for x in first),(im.name,first,im.has_data)
        rows.append({'name':im.name,'absolute_path':str(p),'sha256':sha(p),'bytes':p.stat().st_size,'size':list(im.size),'space':im.colorspace_settings.name,'first_pixel':first})
    return rows

def mesh(name,verts,faces,mat=None):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
    bm.to_mesh(me);bm.free();me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob);ob['study_part']=True
    if mat:me.materials.append(mat)
    source_uv(ob);return ob

def source_uv(ob):
    me=ob.data
    for name in ('MetricUV','RockScanUV','SoilScanUV'):
        if name not in me.uv_layers:me.uv_layers.new(name=name)
    if 'SurfaceControl' not in me.color_attributes:me.color_attributes.new(name='SurfaceControl',type='FLOAT_COLOR',domain='CORNER')
    layers={n:me.uv_layers[n] for n in ('MetricUV','RockScanUV','SoilScanUV')}
    for face in me.polygons:
        axis=max(range(3),key=lambda k:abs(face.normal[k]))
        for li in face.loop_indices:
            x,y,z=gp(me.vertices[me.loops[li].vertex_index].co)
            pair=(z,y) if axis==0 else ((x,y) if axis==1 else (x,z))
            layers['MetricUV'].data[li].uv=(pair[0]/1.5,pair[1]/1.5)
            # Horizontal soil UV; separate metric projection on mineral solids.
            rockpair=(x,z) if ob.get('soil') else pair
            layers['RockScanUV'].data[li].uv=(rockpair[0]/2+.31,rockpair[1]/2+.09)
            layers['SoilScanUV'].data[li].uv=(x/2.5+.13,z/2.5+.27)
            wet,deposit=controls(x,z)
            me.color_attributes['SurfaceControl'].data[li].color=(wet,deposit,1. if axis==2 else 0.,1.)

def edge(x):
    # Unequal large fracture setbacks, not a row of equally spaced teeth.
    points=[(-.45,.285),(-.32,.298),(-.19,.253),(-.07,.227),(.045,.276),(.16,.312),(.29,.268),(.38,.294),(.45,.286)]
    for (a,b),(c,d) in zip(points,points[1:]):
        if x<=c:return b+(d-b)*clamp((x-a)/(c-a))
    return points[-1][1]

def channel_x(z):return -.055+.09*math.sin((z-.24)*3.4)
def controls(x,z):
    t=clamp((z-.24)/.66);dx=x-channel_x(z);bed_half=.082+.043*t
    wet=math.exp(-1.5*(dx/(bed_half+.04))**2)*(1-.38*t)
    side=(1-smooth((abs(dx)-bed_half-.10)/.12))*smooth((abs(dx)-bed_half+.015)/.10)
    # One broader left apron, weaker outer right shoulder. No hard-band mask.
    apron=math.exp(-((x+.23)/.29)**2-((z-.43)/.25)**2)
    deposit=clamp(max(side*(.80 if dx<0 else .40),apron*.85))
    boundary=smooth(min(x+.45,.45-x)/.065)*smooth((.9-z)/.07)
    return wet,deposit*boundary

def ground_height(x,z):
    t=clamp((z-edge(x))/(.9-edge(x)));dx=x-channel_x(z)
    width=.082+.043*t
    bed=math.exp(-1.7*(dx/width)**2)
    shoulder=.012*math.exp(-((dx+.155)/.09)**2)-.002*math.exp(-((dx-.13)/.10)**2)
    h=-.027-.043*bed+shoulder+.005*math.sin(t*2.1)
    boundary=smooth(min(x+.45,.45-x)/.05)*smooth((.9-z)/.06)
    return h*boundary

def actual_tree(ob):
    me=ob.data;me.calc_loop_triangles()
    return BVHTree.FromPolygons([v.co for v in me.vertices],[tuple(t.vertices) for t in me.loop_triangles],all_triangles=True)
def ray_height(tree,x,z):
    p,normal,index,d=tree.ray_cast(Vector(bp(x,.4,z)),Vector((0,0,-1)),1.)
    assert p is not None,(x,z,'inside sample ray miss')
    return float(p.z)

def evaluated(ob,name):
    deps=bpy.context.evaluated_depsgraph_get();ev=ob.evaluated_get(deps)
    me=bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=deps)
    out=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(out);out['study_part']=True
    return out

def joined_copy(obs,name):
    copies=[]
    for ob in obs:
        cp=ob.copy();cp.data=ob.data.copy();bpy.context.scene.collection.objects.link(cp);cp.hide_render=False;cp.hide_set(False);copies.append(cp)
    select(copies);bpy.ops.object.join();out=bpy.context.object;out.name=name;out['study_part']=True;return out

def geometry(ob):
    me=ob.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me)
    row={'name':ob.name,'triangles':len(me.loop_triangles),'vertices':len(me.vertices),
         'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'volume_m3':bm.calc_volume(signed=True)}
    bm.free();points=[gp(v.co) for v in me.vertices]
    row['bounds']={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
    row['minimum_triangle_area_m2']=min(t.area for t in me.loop_triangles)
    return row

def add_ao(mat):
    n=mat.node_tree.nodes;l=mat.node_tree.links;bs=next(x for x in n if x.type=='BSDF_PRINCIPLED')
    for name,key in [('DIAG_Base','Base Color'),('DIAG_Rough','Roughness')]:
        rr=n.new('NodeReroute');rr.name=name
        if bs.inputs[key].links:l.new(bs.inputs[key].links[0].from_socket,rr.inputs[0])
        else:
            value=n.new('ShaderNodeRGB' if key=='Base Color' else 'ShaderNodeValue');value.outputs[0].default_value=bs.inputs[key].default_value;l.new(value.outputs[0],rr.inputs[0])
    ao=n.new('ShaderNodeAmbientOcclusion');ao.name='DIAG_AO';ao.only_local=True;ao.samples=16;ao.inputs['Distance'].default_value=.035
    mult=n.new('ShaderNodeMixRGB');mult.blend_type='MULTIPLY';mult.inputs[0].default_value=1
    l.new(n['DIAG_Base'].outputs[0],mult.inputs[1]);l.new(ao.outputs['AO'],mult.inputs[2]);l.new(mult.outputs[0],bs.inputs['Base Color'])
    # No full scanned macro normal atop the matching displaced relief.
    for link in list(bs.inputs['Normal'].links):l.remove(link)
    mat['macro_normal_disabled_for_displacement_diagnostic']=True

def make_scan_material(mineral=False):
    m=bpy.data.materials.new('RockyMineral' if mineral else 'MatchedHeightSediment');m.use_nodes=True
    n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
    def texture(prefix,role,uvname):
        rel=CFG['texture_paths'][prefix][role];im=load_image(rel,'sRGB' if role=='diff' else 'Non-Color')
        uv=n.new('ShaderNodeUVMap');uv.uv_map=uvname
        tex=n.new('ShaderNodeTexImage');tex.image=im;tex.extension='REPEAT';l.new(uv.outputs[0],tex.inputs[0]);return tex.outputs[0]
    rb=texture('rocky','diff','RockScanUV');rr=texture('rocky','rough','RockScanUV')
    bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=0;bs.inputs['IOR'].default_value=1.45
    if mineral:base,rough=rb,rr
    else:
        sb=texture('sandy','diff','SoilScanUV');sr=texture('sandy','rough','SoilScanUV')
        attr=n.new('ShaderNodeVertexColor');attr.layer_name='SurfaceControl';sep=n.new('ShaderNodeSeparateColor');l.new(attr.outputs[0],sep.inputs[0])
        def mix(a,b):
            q=n.new('ShaderNodeMixRGB');l.new(sep.outputs['Green'],q.inputs[0]);l.new(a,q.inputs[1]);l.new(b,q.inputs[2]);return q.outputs[0]
        base=mix(sb,rb);rough=mix(sr,rr)
        wet=n.new('ShaderNodeMath');wet.operation='MULTIPLY_ADD';l.new(sep.outputs['Red'],wet.inputs[0]);wet.inputs[1].default_value=-.16;wet.inputs[2].default_value=1
        mul=n.new('ShaderNodeMixRGB');mul.blend_type='MULTIPLY';mul.inputs[0].default_value=1;l.new(base,mul.inputs[1]);l.new(wet.outputs[0],mul.inputs[2]);base=mul.outputs[0]
        rm=n.new('ShaderNodeMath');rm.operation='MULTIPLY';l.new(rough,rm.inputs[0]);l.new(wet.outputs[0],rm.inputs[1]);rough=rm.outputs[0]
    l.new(base,bs.inputs['Base Color']);l.new(rough,bs.inputs['Roughness'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);add_ao(m);return m

def unwrap(ob,u0,u1):
    select([ob]);me=ob.data
    if 'BakeUV' not in me.uv_layers:me.uv_layers.new(name='BakeUV')
    me.uv_layers.active_index=me.uv_layers.find('BakeUV')
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.018);bpy.ops.object.mode_set(mode='OBJECT')
    layer=me.uv_layers['BakeUV']
    for v in layer.data:v.uv=(u0+v.uv.x*(u1-u0),.015+v.uv.y*.97)
    for v in me.uv_layers:v.active_render=v.name=='BakeUV'
    me.calc_loop_triangles();areas=[]
    for t in me.loop_triangles:
        a,b,c=[Vector(layer.data[li].uv) for li in t.loops]
        areas.append(abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2)
    assert min(areas)>1e-14,(ob.name,'zero BakeUV area',min(areas))
    return {'object':ob.name,'triangles':len(areas),'min_uv_area':min(areas),'atlas_u_interval':[u0,u1]}

def studio():
    s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=24;s.cycles.use_denoising=True
    s.render.threads_mode='FIXED';s.render.threads=2;s.render.resolution_x=1280;s.render.resolution_y=1100;s.render.resolution_percentage=100
    s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=0;s.view_settings.gamma=1
    w=bpy.data.worlds.new('NeutralReview');w.use_nodes=True;w.node_tree.nodes['Background'].inputs[0].default_value=(.32,.35,.39,1);w.node_tree.nodes['Background'].inputs[1].default_value=.4;s.world=w
    for name,loc,power,size in [('Key',(-1.6,-2.1,3.2),350,2.2),('Fill',(2.,.5,1.8),120,2.)]:
        d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,-.43,-.03))-o.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('OneFixedStudyCamera');o=bpy.data.objects.new(d.name,d);s.collection.objects.link(o);o.location=(-1.10,-1.80,1.25);o.rotation_euler=(Vector((0,-.44,-.05))-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=1.28;s.camera=o
    s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.film_transparent=False

def verify_frozen():
    for rel,row in CFG['inputs'].items():
        p=ROOT/rel;assert sha(p)==row['sha256'] and p.stat().st_size==row['bytes'],rel
    assert sha(HERE.parent/'p13/manifest.json')==CFG['p13_manifest_sha256']
    assert sha(HERE.parent/'recovery_study/manifest.json')==CFG['research_manifest_sha256']
