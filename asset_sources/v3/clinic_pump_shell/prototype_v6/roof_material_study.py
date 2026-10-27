"""One bounded roof-material cause study; no vendor code, bake, GLB or runtime.
Actual frozen V5 node inspection, then A/B/C under the same lights/camera.
"""
from pathlib import Path
import bpy,json,hashlib,os,time,shutil,types
import numpy as np
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[3]
SOURCE=HERE.parent/'prototype_v5/pump_shell_prototype.blend'
SOURCE_SHA='91dac06d035d2895c78d1cc0b4069916534bed3d5fe245dcd6b72dd35ab98ca4'
GEOMETRY_SHA='9c4fdc581596935f022a111d46b340fcac8dab8417e92c19eb9551854ccc508b'
VENDOR=ROOT/'asset_sources/third_party/ambientCG/Metal012_1K-PNG'
MAPS={'Color':('3ee176198f3c3f20a4b328bbb3b5476811f17da5a76f2d8004139f080359265d','sRGB'),
      'Metalness':('a7a42ccdb662efc7af2fc7b96e190ff0aab22ca7038cc70b36dc28e0b80f22fe','Non-Color'),
      'Roughness':('9cd0739a076cf2ead6155adc4deeaa1e23c56216130dfa826316740dd5625114','Non-Color'),
      'NormalGL':('8c04eb729bdf675f23c37a90a141357129a975dd662cfbf8db29d5cd5ac69dcf','Non-Color')}
support=types.ModuleType('frozen_geometry_support'); support.__file__=str(HERE/'frozen_geometry_support.py')
exec(compile(Path(support.__file__).read_text(encoding='utf-8'),support.__file__,'exec'),support.__dict__)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def scalar(v):
    if isinstance(v,(bool,int,float,str)): return v
    try: return list(v)
    except TypeError: return str(v)
def material_graph(m):
    bs=m.node_tree.nodes['PumpPrincipled']; selected=['Base Color','Metallic','Roughness','Normal','Emission Strength']
    pending=[link.from_node for name in selected for link in bs.inputs[name].links]; active={bs.name}
    while pending:
        node=pending.pop()
        if node.name in active: continue
        active.add(node.name)
        pending.extend(link.from_node for sock in node.inputs for link in sock.links)
    nodes=[]
    for n in m.node_tree.nodes:
        if n.name not in active: continue
        row={'name':n.name,'type':n.bl_idname,'label':n.label,'inputs':[]}
        for sock in n.inputs:
            item={'name':sock.name,'identifier':sock.identifier,'links':[{'from_node':q.from_node.name,'from_socket':q.from_socket.name} for q in sock.links]}
            if hasattr(sock,'default_value'): item['default']=scalar(sock.default_value)
            row['inputs'].append(item)
        if hasattr(n,'operation'): row['operation']=n.operation
        if n.type=='TEX_IMAGE': row['image']={'path':n.image.filepath,'colorspace':n.image.colorspace_settings.name}
        if n.type=='UVMAP': row['uv_map']=n.uv_map
        nodes.append(row)
    return {'material':m.name,'actual_assigned_to':'RoofZincPanel_0','active_upstream_nodes_only':True,'nodes':nodes}
def image_stats(im):
    im.reload(); px=np.empty(len(im.pixels),dtype=np.float32); im.pixels.foreach_get(px); px=px.reshape(-1,4)[:,:3]
    return {'size':list(im.size),'colorspace':im.colorspace_settings.name,'min':px.min(axis=0).tolist(),'mean':px.mean(axis=0).tolist(),'max':px.max(axis=0).tolist(),'pixels_read':len(px)}

def pbr_nodes(m,images):
    n=m.node_tree.nodes; lk=m.node_tree.links; uv=n.new('ShaderNodeUVMap'); uv.uv_map='SteelUV'; nodes={}
    for key,im in images.items():
        tx=n.new('ShaderNodeTexImage'); tx.name='Metal012_'+key; tx.image=im; tx.extension='REPEAT'; tx.interpolation='Linear'; lk.new(uv.outputs['UV'],tx.inputs['Vector']); nodes[key]=tx
    bs=n['PumpPrincipled']; lk.new(nodes['Metalness'].outputs['Color'],bs.inputs['Metallic']); lk.new(nodes['Roughness'].outputs['Color'],bs.inputs['Roughness'])
    nm=n.new('ShaderNodeNormalMap'); nm.name='Metal012_NormalGL_Tangent'; nm.space='TANGENT'; nm.uv_map='SteelUV'; nm.inputs['Strength'].default_value=1
    lk.new(nodes['NormalGL'].outputs['Color'],nm.inputs['Color']); lk.new(nm.outputs['Normal'],bs.inputs['Normal'])
    return nodes

def sparse_edge_layer(m,images):
    nodes=pbr_nodes(m,images); n=m.node_tree.nodes; lk=m.node_tree.links
    def op(kind,a,b=0):
        q=n.new('ShaderNodeMath'); q.operation=kind
        for v,sock in [(a,q.inputs[0]),(b,q.inputs[1])]:
            if hasattr(v,'node'): lk.new(v,sock)
            else: sock.default_value=v
        return q.outputs[0]
    # Use the already-authored atlas solely to irregularize the 18cm edge band.
    atlas=n['UneditedAtlasV2']; gray=n.new('ShaderNodeRGBToBW'); lk.new(atlas.outputs['Color'],gray.inputs[0])
    uv=n.new('ShaderNodeUVMap'); uv.uv_map='PanelUV'; sep=n.new('ShaderNodeSeparateXYZ'); lk.new(uv.outputs['UV'],sep.inputs[0])
    size=n.new('ShaderNodeVertexColor'); size.layer_name='FaceSize'; ss=n.new('ShaderNodeSeparateColor'); lk.new(size.outputs['Color'],ss.inputs[0])
    edgeu=op('MULTIPLY',op('MINIMUM',sep.outputs['X'],op('SUBTRACT',1,sep.outputs['X'])),ss.outputs['Red'])
    edgev=op('MULTIPLY',op('MINIMUM',sep.outputs['Y'],op('SUBTRACT',1,sep.outputs['Y'])),ss.outputs['Green'])
    edge=op('MINIMUM',edgeu,edgev)
    band=op('MAXIMUM',0,op('SUBTRACT',1,op('DIVIDE',edge,.18)))
    broken=op('MINIMUM',1,op('MAXIMUM',0,op('DIVIDE',op('SUBTRACT',gray.outputs[0],.30),.16)))
    mask=op('MULTIPLY',.35,op('MULTIPLY',band,broken))
    color=n.new('ShaderNodeMixRGB'); color.name='SparseEdgeOxideOnly'; lk.new(mask,color.inputs[0]); lk.new(nodes['Color'].outputs['Color'],color.inputs[1]); color.inputs[2].default_value=(.18,.165,.135,1)
    bs=n['PumpPrincipled']; lk.new(color.outputs[0],bs.inputs['Base Color'])
    # Subpixel dirt/oxide mixture only near edges; bare panel uses original map.
    rough=op('ADD',op('MULTIPLY',nodes['Roughness'].outputs['Color'],op('SUBTRACT',1,mask)),op('MULTIPLY',.78,mask))
    metal=op('MULTIPLY',nodes['Metalness'].outputs['Color'],op('SUBTRACT',1,mask))
    lk.new(rough,bs.inputs['Roughness']); lk.new(metal,bs.inputs['Metallic'])
    return {'edge_band_m':.18,'maximum_mixture':.35,'center_atlas_influence':0,'normal':'Original NormalGL only, no atlas-derived bump/displacement'}

def main():
    start=time.time(); assert sha(SOURCE)==SOURCE_SHA; assert not (HERE/'roof_material_study.blend').exists()
    evidence=HERE/'evidence'; inputs=HERE/'source_inputs'; evidence.mkdir(exist_ok=True); inputs.mkdir(exist_ok=True)
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'study_only':True}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE)); bpy.context.view_layer.update()
    parts=[o for o in bpy.data.objects if o.get('editable_piece')]; before=support.geometry_digest(parts); assert before['sha256']==GEOMETRY_SHA
    roof=[bpy.data.objects['RoofZincPanel_'+str(i)] for i in range(3)]
    original=roof[0].data.materials[0]; graph=material_graph(original)
    (evidence/'actual_v5_assigned_nodes.json').write_text(json.dumps(graph,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    old_image_rows=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            src=Path(bpy.path.abspath(im.filepath)); digest=sha(src); assert digest in [support.OLD_SHA,support.NEW_SHA]
            dest=inputs/src.name; shutil.copyfile(src,dest); im.filepath=str(dest); old_image_rows.append({'path':str(dest),'sha256':digest})
    maps={}; provenance=json.loads((VENDOR/'provenance.json').read_text(encoding='utf-8')); stats={}
    for key,(digest,space) in MAPS.items():
        src=VENDOR/('Metal012_1K-PNG_'+key+'.png'); assert sha(src)==digest
        dest=inputs/src.name; shutil.copyfile(src,dest); im=bpy.data.images.load(str(dest),check_existing=False); im.colorspace_settings.name=space
        maps[key]=im; stats[key]={**image_stats(im),'sha256':digest,'original_path':str(src)}
    for i,o in enumerate(roof):
        me=o.data; me.uv_layers.new(name='SteelUV'); steel=me.uv_layers['SteelUV']; metric=me.uv_layers['MetricUV']
        # Explicit author test scale: 2m per tile, shared by color/rough/metal/normal.
        # Vendor source does not assert this represents a measured real-world scale.
        for li in range(len(me.loops)):
            u,v=tuple(metric.data[li].uv); steel.data[li].uv=(u/2+i*.173,v/2+i*.291)
    b=original.copy(); b.name='STUDY_B_AtlasColor_RealSteelResponse'; pbr_nodes(b,maps)
    c=original.copy(); c.name='STUDY_C_RealSteel_SparseEdge'; edge_contract=sparse_edge_layer(c,maps)
    bpy.context.view_layer.update(); assert support.geometry_digest(parts)['sha256']==GEOMETRY_SHA
    scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=8; scene.render.threads_mode='FIXED'; scene.render.threads=2
    scene.render.resolution_x=1024; scene.render.resolution_y=720; scene.render.resolution_percentage=100
    # Geometry, transforms, camera, light energies, view and exposure stay V5.
    # Hide lower body for this isolated roof study; all roof hardware stays.
    for o in parts: o.hide_render=o.get('runtime_group')!='RoofCover'
    world_nodes=[{'name':n.name,'type':n.bl_idname,'inputs':[{'name':s.name,'default':scalar(s.default_value)} for s in n.inputs if hasattr(s,'default_value')]} for n in scene.world.node_tree.nodes]
    lighting={'camera_location':list(scene.camera.location),'camera_rotation':list(scene.camera.rotation_euler),'ortho_scale':scene.camera.data.ortho_scale,
              'resolution':[1024,720],'view':scene.view_settings.view_transform,'exposure':scene.view_settings.exposure,'world_nodes':world_nodes,
              'lights':[{'name':o.name,'type':o.data.type,'energy':o.data.energy,'size':o.data.size,'color':list(o.data.color),'location':list(o.location),'rotation':list(o.rotation_euler)} for o in bpy.data.objects if o.type=='LIGHT']}
    report={'status':'READY_TO_RENDER_DIAGNOSTIC_ONLY','source_v5_sha256':SOURCE_SHA,'geometry_sha256':GEOMETRY_SHA,'triangles':before['triangles'],
            'actual_v5_graph':'actual_v5_assigned_nodes.json','map_stats':stats,'lighting':lighting,'edge_contract':edge_contract,'provider':provenance,
            'test_scale_m_per_tile':2,'cases':{'A':'Actual V5 atlas material unchanged','B':'Same actual V5 base color; only replace metal/rough/normal with Metal012','C':'Full Metal012 maps + sparse atlas edge mask, no whole-face white patches'},
            'limits':['Roof isolation, not full asset or game acceptance.','Same uniform world and two area lights; no new HDRI or lighting fix.','B isolates response bundle, not every response input independently.','No physical displacement, no vendor blend/code executed.']}
    outputs=[]
    for label,mat in [('A_atlas_v5',original),('B_atlas_color_steel_response',b),('C_steel_pbr_sparse_edge',c)]:
        for o in roof: o.data.materials.clear(); o.data.materials.append(mat)
        p=evidence/(label+'.png'); scene.render.filepath=str(p); bpy.ops.render.render(write_still=True); outputs.append({'case':label,'path':str(p),'sha256':sha(p)})
    # Final editable study keeps C and all original source geometry, lower body hidden.
    blend=HERE/'roof_material_study.blend'; bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath: im.filepath=bpy.path.relpath(im.filepath)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False); bpy.ops.wm.open_mainfile(filepath=str(blend))
    readback=[]
    known={support.OLD_SHA,support.NEW_SHA}|{v[0] for v in MAPS.values()}
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath)); digest=sha(p); assert digest in known
            im.reload(); pixel=tuple(im.pixels[:4]); assert len(pixel)==4 and im.has_data
            readback.append({'relative':im.filepath,'resolved':str(p),'sha256':digest,'colorspace':im.colorspace_settings.name,'size':list(im.size)})
    assert support.geometry_digest([o for o in bpy.data.objects if o.get('editable_piece')])['sha256']==GEOMETRY_SHA
    assert sha(SOURCE)==SOURCE_SHA
    report.update(status='RENDERED_PENDING_VISUAL_ANALYSIS',images=outputs,reopened_images=readback,blend_sha256=sha(blend),elapsed_seconds=time.time()-start)
    (evidence/'study_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'geometry_unchanged':True}),flush=True)
if __name__=='__main__':main()
