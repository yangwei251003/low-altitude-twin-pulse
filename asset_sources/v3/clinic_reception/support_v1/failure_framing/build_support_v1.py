"""PREPARED ONLY. Blender CPU2, source-only, root-approved window required.

blender.exe -b -t 2 --python-exit-code 2 --python this_file.py -- --render
The parent process must bound its own process tree. No engine or GLB export.
"""
from pathlib import Path
import hashlib
import itertools
import json
import math
import shutil
import sys

import bpy
import bmesh
from mathutils import Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
PLAN=json.loads((HERE/'support_plan.json').read_text(encoding='utf-8'))
ORIGIN=PLAN['origin_world']
PARTS=[]


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def bp(world):return Vector((world[0]-ORIGIN[0],-(world[2]-ORIGIN[2]),world[1]-ORIGIN[1]))
def wp(local):return [local.x+ORIGIN[0],local.z+ORIGIN[1],-local.y+ORIGIN[2]]


def standard_material():
    mat=bpy.data.materials.new('ReceptionSupport_GravityV4_PBR');mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
    shader=nodes.new('ShaderNodeBsdfPrincipled');shader.name='SupportPrincipled'
    out=nodes.new('ShaderNodeOutputMaterial');links.new(shader.outputs['BSDF'],out.inputs['Surface'])
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
    dest=HERE/'source_inputs';dest.mkdir(exist_ok=True)
    for role,row in PLAN['textures'].items():
        source=ROOT/row['path'];assert sha(source)==row['sha256'],source
        target=dest/source.name
        if target.exists():assert sha(target)==row['sha256']
        else:shutil.copy2(source,target)
        image=bpy.data.images.load(str(target),check_existing=True)
        image.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
        tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.extension='EXTEND';tex.label=role
        links.new(uv.outputs['UV'],tex.inputs['Vector'])
        if role=='Normal':
            normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=1
            links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],shader.inputs['Normal'])
        else:links.new(tex.outputs['Color'],shader.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
    return mat


def mapped_uv(obj,kind):
    layer=obj.data.uv_layers.get('SurfaceUV') or obj.data.uv_layers.new(name='SurfaceUV')
    for old in list(obj.data.uv_layers):
        if old!=layer:obj.data.uv_layers.remove(old)
    obj.data.uv_layers.active=layer;layer.active_render=True
    a,b,c,d=PLAN['material_regions'][kind];pad=6/2048
    points=[wp(obj.matrix_world@v.co) for v in obj.data.vertices]
    lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
    major=max(range(3),key=lambda i:hi[i]-lo[i])
    for face in obj.data.polygons:
        bn=obj.matrix_world.to_3x3()@face.normal;n=(bn.x,bn.z,-bn.y)
        normal_axis=max(range(3),key=lambda i:abs(n[i]));axes=[i for i in range(3) if i!=normal_axis]
        if kind=='post' and 1 in axes:axes=[next(i for i in axes if i!=1),1]
        elif kind=='beam' and major in axes:axes=[major,next(i for i in axes if i!=major)]
        for index in face.loop_indices:
            p=points[obj.data.loops[index].vertex_index]
            u=(p[axes[0]]-lo[axes[0]])/max(hi[axes[0]]-lo[axes[0]],1e-9)
            v=(p[axes[1]]-lo[axes[1]])/max(hi[axes[1]]-lo[axes[1]],1e-9)
            layer.data[index].uv=(a+pad+u*(c-a-2*pad),b+pad+v*(d-b-2*pad))


def register(obj,parent,material,kind):
    matrix=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=matrix
    obj.data.materials.append(material);obj['material_region']=kind
    obj['collision_role']='actual_structure' if parent.name=='SupportStructure' else 'visual_fastener'
    mapped_uv(obj,kind);PARTS.append(obj)


def box(row,parent,material):
    lo,hi=row['min'],row['max']
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp([(a+b)/2 for a,b in zip(lo,hi)]))
    obj=bpy.context.object;obj.name=row['name'];obj.dimensions=(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    # Small shoulders are exact mating pieces, without bevel-induced visual gaps.
    if not row['name'].startswith('PostShoulder'):
        bevel=obj.modifiers.new('ManufacturedEdge','BEVEL');bevel.width=min(.008,min(hi[i]-lo[i] for i in range(3))*.15);bevel.segments=2
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    register(obj,parent,material,row['material_region'])


def cylinder(name,a,b,radius,sides,parent,material):
    start,end=bp(a),bp(b);axis=end-start
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides,radius=radius,depth=axis.length,location=(start+end)/2)
    obj=bpy.context.object;obj.name=name;obj.rotation_euler=axis.to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    register(obj,parent,material,'steel')


def bounds(obj):
    points=[wp(obj.matrix_world@v.co) for v in obj.data.vertices]
    return {'name':obj.name,'min':[min(v[i] for v in points) for i in range(3)],'max':[max(v[i] for v in points) for i in range(3)]}


def root_node(name,parent=None):
    obj=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(obj);obj.parent=parent;return obj


def reference_building():
    # Optional read-only context. Neither source file nor GLB is saved/changed.
    path=HERE.parent/'delivery_v5/clinic_reception_v5_delivery.blend'
    assert sha(path)=='4ed0b50326786349d1f2774208e0bee57c25704dbedd8f3555ee8ab4d77d63a6'
    report=json.loads((HERE.parent/'delivery_v5/delivery_report.json').read_text(encoding='utf-8'))
    names=set(report['nodes'])
    with bpy.data.libraries.load(str(path),link=False) as (available,loaded):
        assert names.issubset(set(available.objects));loaded.objects=sorted(names)
    collection=bpy.data.collections.new('REFERENCE_frozen_V5_NOT_EXPORT');bpy.context.scene.collection.children.link(collection)
    refroot=None
    for obj in loaded.objects:
        if obj is None:continue
        if obj.name=='ClinicReception':refroot=obj
        collection.objects.link(obj);obj['exclude_export']=True;obj.name='REF_'+obj.name
    assert refroot is not None
    refroot.location=bp([7,5,-6])
    for image in bpy.data.images:
        if image.source!='FILE':continue
        if Path(bpy.path.abspath(image.filepath)).is_file():continue
        basename=Path(image.filepath).name
        matches=[p for folder in ['textures','source_inputs'] if (p:=path.parent/folder/basename).is_file()]
        assert len(matches)==1,basename;image.filepath=str(matches[0])
    return collection


def checks():
    rows=[bounds(obj) for obj in PARTS];topology=[];triangles=0
    for obj in PARTS:
        bm=bmesh.new();bm.from_mesh(obj.data)
        row={'name':obj.name,'open_or_nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'signed_volume':bm.calc_volume(signed=True)}
        bm.free();obj.data.calc_loop_triangles()
        row['zero_area_triangles']=sum((obj.data.vertices[t.vertices[1]].co-obj.data.vertices[t.vertices[0]].co).cross(obj.data.vertices[t.vertices[2]].co-obj.data.vertices[t.vertices[0]].co).length<1e-12 for t in obj.data.loop_triangles)
        triangles+=len(obj.data.loop_triangles);topology.append(row)
    overlaps=[]
    for a,b in itertools.combinations(rows,2):
        if all(min(a['max'][i],b['max'][i])-max(a['min'][i],b['min'][i])>1e-6 for i in range(3)):overlaps.append([a['name'],b['name']])
    expected=PLAN['world_aabb'];actual={'min':[min(r['min'][i] for r in rows) for i in range(3)],'max':[max(r['max'][i] for r in rows) for i in range(3)]}
    result={'status':'actual_source_candidate_not_runtime','mesh_count':len(PARTS),'triangle_count':triangles,'world_aabb':actual,'topology':topology,'positive_volume_aabb_pairs':overlaps,'parts':rows,
            'checks':{'within_original_envelope':all(abs(actual[k][i]-expected[k][i])<1e-5 for k in ('min','max') for i in range(3)),
                      'positive_closed_nonzero_meshes':all(r['open_or_nonmanifold_edges']==0 and r['signed_volume']>0 and r['zero_area_triangles']==0 for r in topology),
                      'no_component_positive_volume_overlap':not overlaps,'triangle_budget':triangles<=PLAN['triangle_budget'],
                      'all_expected_source_parts':len(PARTS)==PLAN['structure_count']+PLAN['detail_count']},
            'limits':['No runtime sweeps or structural stress proof','AABB disjointness does not test arbitrary internal self-intersection','Old EastLandingLeg must be removed by root','Frozen building reference excluded from support mesh checks and future export']}
    (HERE/'support_geometry.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    assert all(result['checks'].values()),result['checks']


def main():
    target=HERE/'clinic_reception_support_v1.blend';assert not target.exists(),'Preserve previous candidate before rerun'
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    root=root_node('ClinicReceptionSupport');root['world_placement']=ORIGIN
    structure=root_node('SupportStructure',root);details=root_node('SupportDetails',root)
    material=standard_material()
    for row in PLAN['parts']:box(row,structure,material)
    for bolt in PLAN['bolts']:
        a=bolt['base'];axis=bolt['axis'];b=[a[i]+axis[i]*bolt['washer_depth'] for i in range(3)];c=[b[i]+axis[i]*bolt['head_depth'] for i in range(3)]
        cylinder(bolt['name']+'_Washer',a,b,bolt['washer_radius'],12,details,material)
        cylinder(bolt['name']+'_Hex',b,c,bolt['hex_radius'],6,details,material)
    bpy.context.view_layer.update();checks();reference_building()
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    world=bpy.data.worlds.new('SupportPreviewWorld');world.use_nodes=True;world.node_tree.nodes.clear()
    background=world.node_tree.nodes.new('ShaderNodeBackground');output=world.node_tree.nodes.new('ShaderNodeOutputWorld')
    background.inputs[0].default_value=(.14,.18,.19,1);background.inputs[1].default_value=.5
    world.node_tree.links.new(background.outputs[0],output.inputs['Surface']);scene.world=world
    for name,position,energy,size in [('Key',[15,17,5],2100,9),('Fill',[-2,10,-3],1200,7)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
        light=bpy.data.objects.new(name,data);scene.collection.objects.link(light);light.location=bp(position);light.rotation_euler=(bp([7,3,-6])-light.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('SupportAssemblyCamera');camera=bpy.data.objects.new('SupportAssemblyCamera',data);scene.collection.objects.link(camera)
    # Same default azimuth/elevation family as V5, target lowered to include feet.
    target_point=Vector([7,3.7,-6]);camera.location=bp(target_point+Vector([19,21.85,19]));camera.rotation_euler=(bp(target_point)-camera.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=23;scene.camera=camera
    scene.render.filepath=str(HERE/'support_v1_assembly.png')
    # Local source images are portable; read-only frozen reference images remain absolute.
    for image in bpy.data.images:
        if image.source=='FILE' and Path(image.filepath).parent==HERE/'source_inputs':image.filepath='//source_inputs/'+Path(image.filepath).name
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'clinic_reception_support_v1.blend'),relative_remap=False)
    if '--render' in sys.argv:bpy.ops.render.render(write_still=True)
    print('SUPPORT_V1_SOURCE_COMPLETE_NO_GLB',flush=True)


if __name__=='__main__':main()
