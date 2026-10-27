"""Native selected-to-active bake of an editable 380mm tread tile; CPU only."""
import hashlib
import json
import math
import bpy


def bp(p):return (p[0],-p[2],p[1])


def bake_tread_tile(scene,out):
    col=bpy.data.collections.new('SOURCE_TreadHighpoly_OfflineOnly');scene.collection.children.link(col)
    # One periodic 4x4 tile. All relief is inside its boundary, so repeated borders are flat.
    verts=[bp(p) for p in [(0,-.0018,0),(.38,-.0018,0),(.38,-.0018,.38),(0,-.0018,.38)]]
    faces=[(3,2,1,0)]
    for ix in range(4):
        for iz in range(4):
            angle=(1 if (ix+iz)%2 else -1)*math.pi/4
            co,si=math.cos(angle),math.sin(angle)
            for side in (-1,1):
                cx=(ix+.5)*.095-side*.0085*si;cz=(iz+.5)*.095+side*.0085*co
                start=len(verts)
                for height,scale in ((-.0018,1),(0,.72)):
                    for u,v in ((-.030,0),(0,-.004),(.030,0),(0,.004)):
                        verts.append(bp((cx+scale*(u*co-v*si),height,cz+scale*(u*si+v*co))))
                local=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
                faces.extend(tuple(start+i for i in f) for f in local)
    highmesh=bpy.data.meshes.new('TreadTile_EditableHighMesh');highmesh.from_pydata(verts,[],faces);highmesh.update()
    high=bpy.data.objects.new('TreadTile_High_16DoublePairs',highmesh);col.objects.link(high)
    lowmesh=bpy.data.meshes.new('TreadTile_BakeReceiverMesh');lowmesh.from_pydata(verts[:4],[],[(3,2,1,0)]);lowmesh.update()
    low=bpy.data.objects.new('TreadTile_LowBakeReceiver',lowmesh);col.objects.link(low)
    uv=lowmesh.uv_layers.new(name='TreadUV');uv.active_render=True
    for loop in lowmesh.loops:
        v=lowmesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=(v.x/.38,-v.y/.38)
    image=bpy.data.images.new('LandingTread_Normal',width=512,height=512,alpha=False,float_buffer=False)
    image.colorspace_settings.name='Non-Color';image.generated_color=(.5,.5,1,1)
    mat=bpy.data.materials.new('TreadTile_BakeOnly');mat.use_nodes=True;lowmesh.materials.append(mat)
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;mat.node_tree.nodes.active=tex
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.bake.use_selected_to_active=True;scene.render.bake.cage_extrusion=.006
    scene.render.bake.max_ray_distance=.012;scene.render.bake.margin=4;scene.render.bake.use_clear=True
    scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    bpy.ops.object.select_all(action='DESELECT');high.select_set(True);low.select_set(True);bpy.context.view_layer.objects.active=low
    bpy.ops.object.bake(type='NORMAL')
    path=out/'LandingTread_Normal.png';image.filepath_raw=str(path);image.file_format='PNG';image.save()
    # Reopen the saved bytes, force pixels resident, then verify non-flat content.
    loaded=bpy.data.images.load(str(path),check_existing=False);loaded.colorspace_settings.name='Non-Color'
    pixels=list(loaded.pixels);assert loaded.has_data and list(loaded.size)==[512,512]
    varying=sum(abs(pixels[i]-.5)>.035 or abs(pixels[i+1]-.5)>.035 for i in range(0,len(pixels),4))
    assert 1500<varying<512*512*.65,('unexpected baked relief coverage',varying)
    high['scope']='editable highpoly reference only, not runtime geometry'
    low['scope']='bake receiver only, not a second visible floor'
    high.hide_render=True;low.hide_render=True;high.hide_set(True);low.hide_set(True)
    high.select_set(False);low.select_set(False)
    loaded.pack()
    record={'native_bake':'selected_to_active_NORMAL','source_tile_m':[.38,.38],
            'pitch_m':.095,'short_bar_m':[.060,.008],'pair_center_spacing_m':.017,'relief_m':.0018,
            'tile_cells':[4,4],'bars':32,'pixels':[512,512],'normal_space':'TANGENT','uv_map':'TreadUV',
            'nonflat_pixels':varying,'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'source_collection_hidden':'SOURCE_TreadHighpoly_OfflineOnly','not_runtime_tread_geometry':True}
    (out/'normal_bake_report.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    return loaded,record
