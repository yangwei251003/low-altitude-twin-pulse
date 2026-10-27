"""Preserve complete leaves instead of collapsing away their silhouettes."""
import bpy,bmesh,random
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'asset_sources/blend/garden_tree_source.blend'))
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active=next(o for o in bpy.context.scene.objects if o.type=='MESH')
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='MATERIAL');bpy.ops.object.mode_set(mode='OBJECT')
random.seed(871)
for o in list(bpy.context.scene.objects):
    if o.type!='MESH':continue
    names=' '.join(o.data.materials[i].name for i in {p.material_index for p in o.data.polygons})
    bpy.context.view_layer.objects.active=o
    if 'leaves' in names:
        bm=bmesh.new();bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        visited=set();remove=[];components=[]
        for v in bm.verts:
            if v in visited:continue
            group=[];stack=[v];visited.add(v)
            while stack:
                at=stack.pop();group.append(at)
                for edge in at.link_edges:
                    nxt=edge.other_vert(at)
                    if nxt not in visited:visited.add(nxt);stack.append(nxt)
            components.append(len(group))
            if len(group)<300 and random.random()>.12:remove.extend(group)
            else:
                center=sum((v.co for v in group),Vector())/len(group)
                for v in group:v.co=center+(v.co-center)*1.7
        bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(o.data);bm.free()
        print('LEAF_COMPONENTS',len(components),'largest',max(components),'kept_polys',len(o.data.polygons),flush=True)
    else:
        target=5000 if 'branches' in names else 5500
        mod=o.modifiers.new('Branch silhouette optimization','DECIMATE');mod.ratio=min(1,target/max(1,len(o.data.polygons)))
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in o.data.polygons:p.use_smooth=True
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'asset_sources/blend/garden_tree.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/garden_tree.glb'),export_format='GLB',export_apply=True,export_yup=True)
print('CANOPY_ADAPTED',flush=True)
