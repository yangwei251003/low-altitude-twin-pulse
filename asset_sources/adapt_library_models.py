"""Retain CC0 originals; normalize and simplify game-ready GLBs in Blender."""
import bpy,math
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
for asset,name,height,budget in [('island_tree_01','garden_tree',5.0,120000),('shrub_01','garden_shrub',.85,7000),('coast_rocks_01','coast_rock',3.5,6000)]:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'asset_sources/third_party'/asset/(asset+'_1k.gltf')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    print('IMPORTED',asset,[(o.name,len(o.data.polygons)) for o in meshes],flush=True)
    # Source native file preserves all original geometry and material connections.
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'asset_sources/blend'/(name+'_source.blend')))
    vertices=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
    minimum=Vector([min(v[i] for v in vertices) for i in range(3)])
    maximum=Vector([max(v[i] for v in vertices) for i in range(3)])
    center=Vector(((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2,minimum.z))
    span=maximum-minimum
    factor=height/max(.01,max(span.x,span.y) if name=='coast_rock' else span.z)
    print('SOURCE_BOUNDS',name,list(span),'scale',factor,flush=True)
    total=sum(len(o.data.polygons) for o in meshes)
    for o in meshes:
        matrix=o.matrix_world.copy();o.parent=None
        for v in o.data.vertices:v.co=(matrix@v.co-center)*factor
        o.matrix_world=Matrix.Identity(4)
        bpy.context.view_layer.objects.active=o
        if total>budget:
            mod=o.modifiers.new('Game silhouette preservation','DECIMATE');mod.ratio=budget/total
            bpy.ops.object.modifier_apply(modifier=mod.name)
        for polygon in o.data.polygons:polygon.use_smooth=True
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'asset_sources/blend'/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models'/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    print('ADAPTED',name,'original polys',total,'export polys',sum(len(o.data.polygons) for o in meshes),flush=True)
