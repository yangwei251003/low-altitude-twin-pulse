"""P11 three-stone source study, original CC0 maps only; no bake/export."""
from pathlib import Path
import math
import bpy

HERE=Path(__file__).resolve().parent
VENDOR=HERE.parent/'p10/vendor/polyhaven_rocky_trail'
UV_NAME='StoneSurfaceUV'
SOURCE_WIDTH_M=2.0
# UV centers were selected by looking at the original diffuse, inside larger
# brown/grey stone surfaces rather than deliberately sampling inter-stone gaps.
# The surface projection keeps the original 2 metre source scale.
PATCHES={
    'FallenConcreteFragment_00':(.560,.630),
    'SedimentBankStone_047':(.764,.952),
    'SedimentBankStone_020':(.666,.205),
}

def assign_uv(obj):
    mesh=obj.data
    assert UV_NAME not in mesh.uv_layers
    old_layers={layer.name:[tuple(row.uv) for row in layer.data] for layer in mesh.uv_layers}
    center=sum((v.co for v in mesh.vertices),mesh.vertices[0].co*0)/len(mesh.vertices)
    mesh.uv_layers.new(name=UV_NAME);uv=mesh.uv_layers[UV_NAME]
    offsets=PATCHES[obj.name]
    for face in mesh.polygons:
        dominant=max(range(3),key=lambda i:abs(face.normal[i]))
        u_axis=(dominant+1)%3;v_axis=(dominant+2)%3
        sign=1 if face.normal[dominant]>=0 else -1
        for li in face.loop_indices:
            delta=mesh.vertices[mesh.loops[li].vertex_index].co-center
            uv.data[li].uv=(offsets[0]+delta[u_axis]/SOURCE_WIDTH_M,
                            offsets[1]+sign*delta[v_axis]/SOURCE_WIDTH_M)
    assert all([tuple(row.uv) for row in mesh.uv_layers[name].data]==coords for name,coords in old_layers.items())
    # Source shader and tangent NormalMap explicitly use the same named UV.
    mesh.calc_loop_triangles();mesh.calc_tangents(uvmap=UV_NAME)
    rows=[tuple(row.uv) for row in uv.data]
    assert all(0<=u<=1 and 0<=v<=1 for u,v in rows)
    assert all(all(math.isfinite(x) for x in loop.tangent) for loop in mesh.loops)
    return {'object':obj.name,'uv':UV_NAME,'source_width_m':SOURCE_WIDTH_M,
            'patch_center_uv':offsets,'uv_min':[min(v[i] for v in rows) for i in range(2)],
            'uv_max':[max(v[i] for v in rows) for i in range(2)],
            'old_source_uv_unchanged':True,'tangent_count':len(mesh.loops),
            'coordinate_mode':'Signed dominant-face metric projection; UV seams do not split physical vertices.'}

def material():
    mat=bpy.data.materials.new('STUDY_P11_RockSurface');mat.use_nodes=True
    nodes,links=mat.node_tree.nodes,mat.node_tree.links;nodes.clear()
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map=UV_NAME
    maps={}
    for role,suffix,space in [('base','diff','sRGB'),('normal','nor_gl','Non-Color'),('rough','rough','Non-Color')]:
        node=nodes.new('ShaderNodeTexImage');node.name='RockyTrail_'+role
        node.image=bpy.data.images.load(str(VENDOR/('rocky_trail_'+suffix+'_2k.png')),check_existing=True)
        node.image.colorspace_settings.name=space;node.extension='EXTEND';node.interpolation='Linear'
        links.new(uv.outputs['UV'],node.inputs['Vector']);maps[role]=node
    # Preserve scanned rock information. No color-to-height / arbitrary hole bump.
    tone=nodes.new('ShaderNodeHueSaturation');tone.name='Small palette integration'
    tone.inputs['Saturation'].default_value=.90;tone.inputs['Value'].default_value=.96
    tone.inputs['Hue'].default_value=.5;tone.inputs['Fac'].default_value=1
    links.new(maps['base'].outputs['Color'],tone.inputs['Color'])
    rough=nodes.new('ShaderNodeClamp');rough.inputs['Min'].default_value=.60;rough.inputs['Max'].default_value=.95
    links.new(maps['rough'].outputs['Color'],rough.inputs['Value'])
    normal=nodes.new('ShaderNodeNormalMap');normal.name='Explicit scanned tangent normal'
    normal.space='TANGENT';normal.uv_map=UV_NAME;normal.inputs['Strength'].default_value=.60
    links.new(maps['normal'].outputs['Color'],normal.inputs['Color'])
    bs=nodes.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=0
    bs.inputs['Emission Strength'].default_value=0;bs.inputs['Roughness'].default_value=.80
    links.new(tone.outputs['Color'],bs.inputs['Base Color']);links.new(rough.outputs['Result'],bs.inputs['Roughness'])
    links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    out=nodes.new('ShaderNodeOutputMaterial');links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    mat['source']='https://polyhaven.com/a/rocky_trail'
    mat['author_license']='Amal Kumar / CC0; unchanged original 2K images'
    mat['scope']='Three representative stones only. No geometry displacement, no new collision.'
    return mat

def concrete_fragment_material(source_concrete):
    """Retain the actual slab material as the fragment's dominant identity.
    Rocky surface information only contributes limited exposed aggregate grain;
    the broken slab is not converted into a natural grey boulder.
    """
    mat=source_concrete.copy();mat.name='STUDY_P11_FracturedConcrete'
    nodes,links=mat.node_tree.nodes,mat.node_tree.links
    bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    def preserve_input(socket):
        return socket.links[0].from_socket if socket.is_linked else tuple(socket.default_value) if hasattr(socket.default_value,'__len__') else socket.default_value
    base=preserve_input(bs.inputs['Base Color']);rough=preserve_input(bs.inputs['Roughness'])
    old_normal=preserve_input(bs.inputs['Normal'])
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map=UV_NAME
    images={}
    for role,suffix,space in [('base','diff','sRGB'),('normal','nor_gl','Non-Color'),('rough','rough','Non-Color')]:
        node=nodes.new('ShaderNodeTexImage');node.name='LimitedAggregate_'+role
        node.image=bpy.data.images.load(str(VENDOR/('rocky_trail_'+suffix+'_2k.png')),check_existing=True)
        node.image.colorspace_settings.name=space;node.extension='EXTEND'
        links.new(uv.outputs['UV'],node.inputs['Vector']);images[role]=node
    def mix(a,b,factor):
        node=nodes.new('ShaderNodeMixRGB');node.inputs[0].default_value=factor
        for value,slot in [(a,node.inputs[1]),(b,node.inputs[2])]:
            if hasattr(value,'node'):links.new(value,slot)
            elif isinstance(value,(int,float)):slot.default_value=(value,value,value,1)
            else:slot.default_value=tuple(value)+(1,) if len(value)==3 else value
        return node.outputs['Color']
    links.new(mix(base,images['base'].outputs['Color'],.15),bs.inputs['Base Color'])
    links.new(mix(rough,images['rough'].outputs['Color'],.15),bs.inputs['Roughness'])
    normal=nodes.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map=UV_NAME
    normal.inputs['Strength'].default_value=.35;links.new(images['normal'].outputs['Color'],normal.inputs['Color'])
    combined=mix(old_normal,normal.outputs['Normal'],.20)
    normalized=nodes.new('ShaderNodeVectorMath');normalized.operation='NORMALIZE'
    links.new(combined,normalized.inputs[0]);links.new(normalized.outputs['Vector'],bs.inputs['Normal'])
    mat['identity']='Broken concrete: 85% original P10 slab color/roughness, 15% exposed aggregate contribution.'
    mat['source_concrete_material']=source_concrete.name
    mat['no_geometry_or_height_change']=True
    return mat

def smooth_by_actual_angle(obj,angle_degrees=50):
    mesh=obj.data
    assert not mesh.has_custom_normals,'Unexpected pre-existing custom normals'
    assert hasattr(mesh,'set_sharp_from_angle'),'Validate Blender API before proceeding'
    for face in mesh.polygons:face.use_smooth=True
    mesh.set_sharp_from_angle(angle=math.radians(angle_degrees));mesh.update()
    sharp=mesh.attributes.get('sharp_edge')
    count=sum(bool(v.value) for v in sharp.data) if sharp else 0
    normals=[tuple(row.vector) for row in mesh.corner_normals]
    assert normals and all(all(math.isfinite(v) for v in row) for row in normals)
    return {'object':obj.name,'angle_degrees':angle_degrees,'edges':len(mesh.edges),
            'sharp_edges':count,'smooth_faces':sum(f.use_smooth for f in mesh.polygons),
            'corner_normals_count':len(normals),'changes_collision':False,
            'method':'Face smooth flags plus actual-angle sharp_edge; no subdivision or vertex displacement.'}
