"""One Rock07 LOD3 source sample, original P10 ground unchanged. No bake/GLB.
Requires an explicit serial CPU2 window before execution.
"""
from pathlib import Path
import bpy, json, hashlib, struct, math, time, os, collections
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[3]
INPUT=HERE/'inputs/polyhaven_rock_07_1k'
OLD=HERE.parent/'p10/repair_01'
OUT=HERE/'sample_review_01'
TARGET='SedimentBankStone_047'
SAMPLE='Study_Rock07_LOD3_Sediment047'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
def signature(obj):
    b=bytearray()
    for v in obj.data.vertices:b.extend(struct.pack('<3f',*v.co))
    for p in obj.data.polygons:
        b.extend(struct.pack('<I',len(p.vertices)))
        b.extend(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
    return hashlib.sha256(b).hexdigest()
def mesh_record(obj):
    obj.data.calc_loop_triangles()
    return {'geometry':signature(obj),'triangles':len(obj.data.loop_triangles),'matrix':[[float(v) for v in row] for row in obj.matrix_world], 'materials':[m.name for m in obj.data.materials]}
def uv_signature(mesh):
    b=bytearray()
    for layer in mesh.uv_layers:
        b.extend(layer.name.encode());b.extend(b'\0')
        for row in layer.data:b.extend(struct.pack('<2f',*row.uv))
    return hashlib.sha256(b).hexdigest()

def material(uvname):
    m=bpy.data.materials.new('STUDY_Rock07_OriginalPBR');m.use_nodes=True
    nodes,links=m.node_tree.nodes,m.node_tree.links;nodes.clear()
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map=uvname
    textures={}
    for role,file,space in [('base','rock_07_diff_1k.png','sRGB'),('normal','rock_07_nor_gl_1k.png','Non-Color'),('arm','rock_07_arm_1k.png','Non-Color')]:
        n=nodes.new('ShaderNodeTexImage');n.name='Official_'+role
        n.image=bpy.data.images.load(str(INPUT/file),check_existing=True);n.image.colorspace_settings.name=space
        n.extension='EXTEND';links.new(uv.outputs['UV'],n.inputs['Vector']);textures[role]=n
    split=nodes.new('ShaderNodeSeparateColor');split.mode='RGB';links.new(textures['arm'].outputs['Color'],split.inputs['Color'])
    normal=nodes.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map=uvname;normal.inputs['Strength'].default_value=1
    links.new(textures['normal'].outputs['Color'],normal.inputs['Color'])
    bs=nodes.new('ShaderNodeBsdfPrincipled');bs.inputs['Emission Strength'].default_value=0
    links.new(textures['base'].outputs['Color'],bs.inputs['Base Color'])
    links.new(split.outputs['Green'],bs.inputs['Roughness']);links.new(split.outputs['Blue'],bs.inputs['Metallic'])
    links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    out=nodes.new('ShaderNodeOutputMaterial');links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    m['source']='https://polyhaven.com/a/rock_07';m['license']='CC0 / Jenelle van Heerden'
    m['AO_note']='Original ARM R retained as source data. This first source preview uses real Cycles geometry shadows, without multiplying authored AO into the albedo.'
    return m

def image_readback():
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath or im.users==0:continue
        p=Path(bpy.path.abspath(im.filepath));r={'name':im.name,'stored_path':im.filepath,'absolute_path':str(p),'exists':p.exists()};rows.append(r)
        write('image_readback.json',rows);assert p.exists(),r
        r['sha256']=sha(p);im.reload();r['first_pixel']=list(im.pixels[:4]);r['has_data_after_pixel_read']=bool(im.has_data);r['size']=list(im.size);r['colorspace']=im.colorspace_settings.name
        assert im.has_data and len(r['first_pixel'])==4 and all(math.isfinite(v) for v in r['first_pixel']),r
    write('image_readback.json',rows)
    return rows

def main():
    started=time.time();assert not OUT.exists(),'Preserve previous attempt'
    contract=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))
    for row in contract['files']:assert sha(PROJECT/row['path'])==row['sha256'],row['path']
    OUT.mkdir();bpy.ops.wm.open_mainfile(filepath=str(OLD/'editable_source.blend'))
    objects=[o for o in bpy.data.objects if o.type=='MESH' and o.get('editable_piece',False)]
    baseline={o.name:mesh_record(o) for o in objects};assert len(baseline)==144
    assert sum(r['triangles'] for r in baseline.values())==7456
    expected=json.loads((OLD/'minimal_repair.json').read_text(encoding='utf-8'))['geometry_signatures']
    assert all(r['geometry']==expected[n] for n,r in baseline.items())
    old=bpy.data.objects[TARGET];assert baseline[TARGET]['triangles']==20
    old_points=np.array([list(old.matrix_world@v.co) for v in old.data.vertices])
    cov=np.cov(old_points[:,:2].T);eigen,axes=np.linalg.eigh(cov);axis=axes[:,int(eigen.argmax())]
    old_yaw=math.atan2(float(axis[1]),float(axis[0]))
    target_row=next(r for r in json.loads((OLD/'sediment_distribution.json').read_text(encoding='utf-8'))['low_stones'] if r['name']==TARGET)
    gx,gy,gz=target_row['ground_center'];destination_xy=(gx,-gz)
    before_materials=set(bpy.data.materials);before_images=set(bpy.data.images)
    with bpy.data.libraries.load(str(INPUT/'rock_07_1k.blend'),link=False) as (src,dst):
        assert 'rock_07_LOD3' in src.objects
        dst.objects=['rock_07_LOD3']
    sample=dst.objects[0];assert sample is not None and len(sample.modifiers)==0
    old.users_collection[0].objects.link(sample);sample.name=SAMPLE;sample.hide_render=False;sample.hide_viewport=False;sample.hide_set(False)
    sample['editable_piece']=True;sample['replaces_only']=TARGET;sample['source_asset']='Poly Haven Rock 07 / LOD3 / CC0'
    sample.data.calc_loop_triangles();assert len(sample.data.loop_triangles)==1854
    original_uv=uv_signature(sample.data);assert len(sample.data.uv_layers)>0
    source_matrix=sample.matrix_world.copy()
    pts=[source_matrix@v.co for v in sample.data.vertices]
    lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    dims=hi-lo;assert dims.z<max(dims.x,dims.y),'Expected native source Z up'
    long_axis=0 if dims.x>=dims.y else 1;source_yaw=0 if long_axis==0 else math.pi/2
    scale=.12/max(dims.x,dims.y);assert scale>0
    center=Vector(((lo.x+hi.x)*.5,(lo.y+hi.y)*.5,lo.z))
    placement=Matrix.Translation(Vector((destination_xy[0],destination_xy[1],0))) @ Matrix.Rotation(old_yaw-source_yaw,4,'Z') @ Matrix.Scale(scale,4) @ Matrix.Translation(-center)
    sample.data.transform(placement@source_matrix);sample.matrix_world=Matrix.Identity(4);sample.data.update()
    assert uv_signature(sample.data)==original_uv
    soil=bpy.data.objects['CompactedSoil_ContinuousSupport'];soil.data.calc_loop_triangles()
    ground=BVHTree.FromPolygons([soil.matrix_world@v.co for v in soil.data.vertices],[tuple(t.vertices) for t in soil.data.loop_triangles],all_triangles=True)
    def height_at(x,y):
        hit,normal,_,_=ground.ray_cast(Vector((x,y,1)),Vector((0,0,-1)),3)
        assert hit is not None and normal.z>.10,(x,y)
        return float(hit.z)
    # First true vertical contact against actual soil triangles, followed by
    # 12 mm burial. No squashing, vertex warping or ground editing.
    offsets=[height_at(v.co.x,v.co.y)-float(v.co.z) for v in sample.data.vertices]
    first_contact=max(offsets);burial=.012
    sample.data.transform(Matrix.Translation(Vector((0,0,first_contact-burial))));sample.data.update()
    clearances=[float(v.co.z)-height_at(v.co.x,v.co.y) for v in sample.data.vertices]
    pts=[v.co.copy() for v in sample.data.vertices]
    lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    contact={'target':TARGET,'sample':SAMPLE,'original_source_dimensions_blender_m':list(dims),'uniform_scale':scale,'unrotated_long_axis_after_scale_m':max(dims.x,dims.y)*scale,'rotation_z_radians':old_yaw-source_yaw,'target_ground_center_godot':target_row['ground_center'],'first_vertical_contact_offset_m':first_contact,'burial_m':burial,'surface_clearance_min_max_m':[min(clearances),max(clearances)],'buried_vertices':sum(v<-.0001 for v in clearances),'exposed_vertices':sum(v>.0001 for v in clearances),'bounds_godot_min':[lo.x,lo.z,-hi.y],'bounds_godot_max':[hi.x,hi.z,-lo.y],'native_uv_before':original_uv,'native_uv_after':uv_signature(sample.data),'scope':'Actual soil triangle rays; no game collider or complete triangle self-intersection verification.'}
    write('contact_report.json',contact)
    assert contact['buried_vertices']>0 and contact['exposed_vertices']>0
    assert abs(min(clearances)+burial)<2e-6
    assert lo.x>=-3 and hi.x<=3 and -hi.y>=0 and -lo.y<=2.4 and lo.z>=-.18 and hi.z<=.03+1e-6,contact
    sample.data.materials.clear();sample.data.materials.append(material(sample.data.uv_layers.active.name))
    for p in sample.data.polygons:p.material_index=0
    # Keep the author normals/smooth flags; no new angle smoothing or remesh.
    sample.data.calc_tangents(uvmap=sample.data.uv_layers.active.name)
    assert all(all(math.isfinite(c) for c in loop.tangent) for loop in sample.data.loops)
    sample.data.calc_loop_triangles();edge=collections.Counter()
    for t in sample.data.loop_triangles:
        a,b,c=t.vertices
        for u,v in [(a,b),(b,c),(c,a)]:edge[tuple(sorted((int(u),int(v))))]+=1
    volume=sum(sample.data.vertices[t.vertices[0]].co.dot(sample.data.vertices[t.vertices[1]].co.cross(sample.data.vertices[t.vertices[2]].co))/6 for t in sample.data.loop_triangles)
    topology={'triangles':len(sample.data.loop_triangles),'vertices':len(sample.data.vertices),'boundary_edges':sum(n==1 for n in edge.values()),'nonmanifold_edges':sum(n>2 for n in edge.values()),'signed_volume_m3':volume,'source_smooth_faces':sum(p.use_smooth for p in sample.data.polygons),'has_custom_normals':sample.data.has_custom_normals,'tangents_finite':True,'native_uv_preserved':uv_signature(sample.data)==original_uv}
    write('sample_topology.json',topology)
    assert topology['boundary_edges']==0 and topology['nonmanifold_edges']==0 and volume>0,topology
    bpy.data.objects.remove(old,do_unlink=True)
    for m in list(bpy.data.materials):
        if m not in before_materials and m!=sample.data.materials[0] and m.users==0:bpy.data.materials.remove(m)
    for im in list(bpy.data.images):
        if im not in before_images and im.users==0:bpy.data.images.remove(im)
    def unchanged_check():
        assert all(mesh_record(bpy.data.objects[n])==r for n,r in baseline.items() if n!=TARGET)
        current=[o for o in bpy.data.objects if o.type=='MESH' and o.get('editable_piece',False)]
        assert len(current)==144
        assert {o.name for o in current}==set(baseline)-{TARGET}|{SAMPLE}
        assert sum(mesh_record(o)['triangles'] for o in current)==9290
    unchanged_check();images=image_readback()
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.render.threads_mode='FIXED';scene.render.threads=2
    full_camera={'location':list(scene.camera.location),'rotation':list(scene.camera.rotation_euler),'ortho_scale':scene.camera.data.ortho_scale,'resolution':[scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage]}
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath and im.users>0:
            absolute=bpy.path.abspath(im.filepath);im.filepath=bpy.path.relpath(absolute,start=str(OUT))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_sample.blend'),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'editable_sample.blend'));images=image_readback();unchanged_check()
    scene=bpy.context.scene
    scene.render.filepath=str(OUT/'01_full_source.png');bpy.ops.render.render(write_still=True)
    close=json.loads((HERE.parent/'p11/source_review_01/study_report.json').read_text(encoding='utf-8'))['camera']
    scene.camera.location=close['location'];scene.camera.rotation_euler=close['rotation'];scene.camera.data.ortho_scale=close['ortho_scale_m']
    scene.render.resolution_x=1440;scene.render.resolution_y=860;scene.render.resolution_percentage=100
    scene.render.filepath=str(OUT/'02_same_three_stone_close.png');bpy.ops.render.render(write_still=True)
    unchanged_check()
    assert all(sha(PROJECT/r['path'])==r['sha256'] for r in contract['files'])
    write('study_report.json',{'status':'SOURCE_SAMPLE_PENDING_ACTUAL_IMAGE_REVIEW','pid':os.getpid(),'elapsed_seconds':time.time()-started,'changed_only':{'removed':TARGET,'added':SAMPLE},'other_143_objects_geometry_transforms_materials_unchanged':True,'source_inputs_unchanged':True,'editable_parts':144,'actual_triangles':9290,'full_camera':full_camera,'close_camera':close,'contact':contact,'topology':topology,'images':images,'renders':[{'path':p.name,'bytes':p.stat().st_size,'sha256':sha(p)} for p in [OUT/'01_full_source.png',OUT/'02_same_three_stone_close.png']],'baked':False,'glb_exported':False,'engine_tested':False})
    print(json.dumps({'pid':os.getpid(),'seconds':time.time()-started,'triangles':9290,'status':'completed_source_study'}),flush=True)

if __name__=='__main__':main()
