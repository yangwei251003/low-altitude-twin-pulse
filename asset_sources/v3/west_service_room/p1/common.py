"""WestLowRoof isolated source. Approved pump materials reused; no runtime writes."""
from pathlib import Path
import bpy,bmesh,json,hashlib,math,shutil,struct
from mathutils import Vector,Matrix
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
UVS=('MetricUV','FinishUV','PanelUV')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,value): (HERE/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return [float(p[0]),float(p[2]),float(-p[1])]
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.hide_set(False);o.hide_viewport=False;o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
def image_audit():
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath or not im.users:continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();assert p.is_file(),str(p)
        im.reload();pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and all(math.isfinite(v) for v in pixel),im.name
        rows.append({'image':im.name,'relative':im.filepath,'resolved':str(p),'sha256':sha(p),'size':list(im.size),'space':im.colorspace_settings.name,'actual_pixel':pixel})
    return rows
def save_relative(path):
    absolute={im.name:str(Path(bpy.path.abspath(im.filepath)).resolve()) for im in bpy.data.images if im.source=='FILE' and im.filepath}
    for name,p in absolute.items():bpy.data.images[name].filepath=p
    bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
    for name,p in absolute.items():bpy.data.images[name].filepath=bpy.path.relpath(p)
    bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
def load_inputs():
    dst=HERE/'source_inputs';dst.mkdir(exist_ok=True)
    inputs={'Atlas':ROOT/'references/v3/production/clinic_pump_shell/material_atlas_v2.png'}
    for ch in ('Color','Roughness','Metalness','NormalGL'):
        inputs[ch]=ROOT/'asset_sources/third_party/ambientCG/Metal012_1K-PNG'/('Metal012_1K-PNG_'+ch+'.png')
    result={};rows=[]
    for key,p in inputs.items():
        d=dst/p.name;shutil.copyfile(p,d);assert sha(d)==sha(p)
        im=bpy.data.images.load(str(d),check_existing=False);im.colorspace_settings.name='sRGB' if key in ('Atlas','Color') else 'Non-Color';result[key]=im
        rows.append({'key':key,'source':str(p),'copy':str(d),'sha256':sha(d),'colorspace':im.colorspace_settings.name})
    return result,rows
def materials(images):
    result={}
    for kind in ('Paint','Concrete','Steel'):
        m=bpy.data.materials.new('WestService_'+kind);m.use_nodes=True;m.use_backface_culling=True
        n,l=m.node_tree.nodes,m.node_tree.links;n.clear()
        bs=n.new('ShaderNodeBsdfPrincipled');bs.name='Principled';out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);bs.inputs['Emission Strength'].default_value=0
        def put(value,s):
            if hasattr(value,'node'):l.new(value,s)
            else:s.default_value=value
        def op(kind,a,b=0):
            q=n.new('ShaderNodeMath');q.operation=kind;put(a,q.inputs[0]);put(b,q.inputs[1]);return q.outputs[0]
        def mix(f,a,b,mode='MIX'):
            q=n.new('ShaderNodeMixRGB');q.blend_type=mode;put(f,q.inputs[0]);put(a,q.inputs[1]);put(b,q.inputs[2]);return q.outputs[0]
        def tex(image,uvname):
            uv=n.new('ShaderNodeUVMap');uv.uv_map=uvname;t=n.new('ShaderNodeTexImage');t.image=image;l.new(uv.outputs[0],t.inputs['Vector']);return t
        if kind=='Steel':
            ts={key:tex(images[key],'MetricUV') for key in ('Color','Roughness','Metalness','NormalGL')}
            # Same physical steel as approved pump; dimmer/rougher to subordinate to cistern.
            put(mix(1,ts['Color'].outputs['Color'],(.57,.59,.61,1),'MULTIPLY'),bs.inputs['Base Color'])
            put(op('MINIMUM',.88,op('ADD',.28,op('MULTIPLY',.65,ts['Roughness'].outputs['Color']))),bs.inputs['Roughness'])
            put(ts['Metalness'].outputs['Color'],bs.inputs['Metallic'])
            normal=n.new('ShaderNodeNormalMap');normal.uv_map='MetricUV';normal.space='TANGENT';normal.inputs['Strength'].default_value=.25
            l.new(ts['NormalGL'].outputs['Color'],normal.inputs['Color']);l.new(normal.outputs[0],bs.inputs['Normal'])
        else:
            t=tex(images['Atlas'],'FinishUV');t.extension='EXTEND'
            gray=n.new('ShaderNodeRGBToBW');l.new(t.outputs['Color'],gray.inputs[0])
            if kind=='Paint':
                # Authored wall/teal crops share one source material; source atlas remains unedited.
                put(mix(1,t.outputs['Color'],(.68,.74,.77,1),'MULTIPLY'),bs.inputs['Base Color'])
                bs.inputs['Roughness'].default_value=.75;bs.inputs['Metallic'].default_value=.04
                # Only submillimetre paint relief, not image lighting interpreted as large holes.
                bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.045;bump.inputs['Distance'].default_value=.00025
                l.new(gray.outputs[0],bump.inputs['Height']);l.new(bump.outputs[0],bs.inputs['Normal'])
            else:
                put(mix(.78,(.29,.275,.245,1),t.outputs['Color']),bs.inputs['Base Color'])
                put(op('MINIMUM',.94,op('ADD',.64,op('MULTIPLY',.55,gray.outputs[0]))),bs.inputs['Roughness']);bs.inputs['Metallic'].default_value=0
                uv=n.new('ShaderNodeUVMap');uv.uv_map='MetricUV';noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=95;noise.inputs['Detail'].default_value=1.5;l.new(uv.outputs[0],noise.inputs['Vector'])
                bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.075;bump.inputs['Distance'].default_value=.001
                l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],bs.inputs['Normal'])
        m['source_semantics']='Reuse approved pump original color regions and physical Metal012. No baked lighting; no invented measured height.'
        result[kind]=m
    return result
def uv_source(o,finish):
    me=o.data;me.update();coords=[gp(v.co) for v in me.vertices];lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
    for name in UVS:me.uv_layers.new(name=name)
    # Reacquire named handles after all UV layers are created (RNA reallocation).
    metric,atlas,panel=[me.uv_layers[k] for k in UVS];seed=int(hashlib.sha256(o.name.encode()).hexdigest()[:8],16)
    for face in me.polygons:
        ng=gp(face.normal);axis=max(range(3),key=lambda a:abs(ng[a]));a,b=(0,2) if axis==1 else ((2,1) if axis==0 else (0,1))
        sx=max(1e-7,hi[a]-lo[a]);sy=max(1e-7,hi[b]-lo[b])
        for li in face.loop_indices:
            p=coords[me.loops[li].vertex_index];u=(p[a]-lo[a])/sx;v=(p[b]-lo[b])/sy;panel.data[li].uv=(u,v)
            metric.data[li].uv=(p[a]/2.0+(seed%17)*.071,p[b]/2.0+(seed%11)*.083)
            if finish=='Wall':au,av=.02+.46*u,.52+.46*v
            elif finish=='Teal':
                along,across=(u,v) if sx>=sy else (v,u)
                span=min(.94,max(sx,sy)/8.5);band=min(.94,max(.035,min(sx,sy)/.8))
                start=.02+((seed%101)/100)*(.96-span)
                au=.502+(start+span*along)*.496;av=.003+(.02+band*across)*.494
            elif finish=='Seal':au,av=.82+.015*u,.22+.015*v
            elif finish=='Concrete':
                au=.008+.482*(u if seed%2 else 1-u)
                av=.008+.475*(v if axis!=1 else .9)
            else:au,av=.75,.75
            atlas.data[li].uv=(au,av)
    me.uv_layers.active_index=me.uv_layers.find('MetricUV')
    for uv in me.uv_layers:uv.active_render=uv.name=='MetricUV'
def box(name,lo,hi,mat,finish,bevel=.008):
    c=[(a+b)/2 for a,b in zip(lo,hi)];size=[b-a for a,b in zip(lo,hi)]
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp(c));o=bpy.context.object;o.name=name;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    uv_source(o,finish);o.data.materials.append(mat);o['editable_piece']=True;o['finish']=finish
    if bevel:
        mod=o.modifiers.new('ManufacturedEdge','BEVEL');mod.width=bevel;mod.segments=1
        mod.affect='EDGES';mod.use_clamp_overlap=True
        mod=o.modifiers.new('WeightedPlanarNormals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=40
    return o
def bolt(name,centre,axis,mat):
    # True sunk 70mm hex heads; all centres keep 12mm clearance from outer box.
    bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=.035,depth=.018,location=bp(centre));o=bpy.context.object;o.name=name
    direction=bp(axis);o.rotation_euler=Vector((0,0,1)).rotation_difference(direction).to_euler()
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);uv_source(o,'Steel');o.data.materials.append(mat);o['editable_piece']=True;o['finish']='Steel'
    return o
def geometry(parts):
    dg=bpy.context.evaluated_depsgraph_get();rows=[];allpoints=[];digest=hashlib.sha256()
    for o in sorted(parts,key=lambda o:o.name):
        assert o.matrix_world==Matrix.Identity(4),o.name
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.calc_loop_triangles()
        coords=[gp(v.co) for v in me.vertices];allpoints+=coords
        bm=bmesh.new();bm.from_mesh(me);bad=sum(not e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True);bm.free()
        assert not bad and volume>0,(o.name,bad,volume)
        for tri in me.loop_triangles:
            for vi in tri.vertices:digest.update(struct.pack('<3f',*coords[vi]))
        rows.append({'name':o.name,'triangles':len(me.loop_triangles),'nonmanifold':bad,'signed_volume':volume,'finish':o['finish']});bpy.data.meshes.remove(me)
    bounds=[[min(p[i] for p in allpoints) for i in range(3)],[max(p[i] for p in allpoints) for i in range(3)]]
    assert all(bounds[0][i]>=(-2,0,-2)[i]-1e-5 and bounds[1][i]<=(2,2.5,2)[i]+1e-5 for i in range(3)),bounds
    assert max(abs(a-b) for row,goal in zip(bounds,[[-2,0,-2],[2,2.5,2]]) for a,b in zip(row,goal))<1e-5,bounds
    total=sum(r['triangles'] for r in rows);assert total<20000
    return {'parts':rows,'objects':len(rows),'triangles':total,'AABB_local_godot':bounds,'geometry_sha256':digest.hexdigest(),'all_parts_closed_outward':True,'limits':'Independent closed components; engineered intersections are intentional. Existing whole box collision stays authoritative.'}
