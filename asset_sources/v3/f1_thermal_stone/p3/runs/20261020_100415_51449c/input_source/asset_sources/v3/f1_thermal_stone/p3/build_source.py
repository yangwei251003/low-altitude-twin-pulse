"""P3 source-only edits. Preserve P2 stone/collar and frozen camera/light helpers."""
import importlib.util,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('thermal_p2_frozen',HERE.parent/'p2/build_source.py')
p2=importlib.util.module_from_spec(spec);spec.loader.exec_module(p2)
base=p2.base
spec=importlib.util.spec_from_file_location('thermal_p3_root_geometry',HERE/'root_geometry.py')
roots=importlib.util.module_from_spec(spec);spec.loader.exec_module(roots)
ROOT_REPORTS={}

def color_attribute(mesh,name,values):
    attr=mesh.color_attributes.get(name)
    if attr:mesh.color_attributes.remove(attr)
    attr=mesh.color_attributes.new(name=name,type='FLOAT_COLOR',domain='CORNER')
    if len(values)!=len(mesh.loops):raise RuntimeError('Incorrect color corners: '+name)
    for row,value in zip(attr.data,values):row.color=value
    return attr

def root_mesh(name,unused_controls,unused_radius,unused_sides,mat):
    spec=next(row for row in roots.authored_roots() if row[0]==name)
    controls,radius,sides,offset=spec[1:]
    verts,faces,distance,report=roots.make_root(controls,radius,sides,offset)
    obj=base.mesh_object(name,verts,faces,mat);mesh=obj.data
    uv=mesh.uv_layers.new(name='PaintUV');uv.active_render=True
    for polygon in mesh.polygons:
        js=[mesh.loops[li].vertex_index%sides for li in polygon.loop_indices]
        seam=0 in js and sides-1 in js
        for li in polygon.loop_indices:
            vi=mesh.loops[li].vertex_index;j=vi%sides
            uv.data[li].uv=((1 if seam and j==0 else j/sides),distance[vi//sides]/1.8) if len(polygon.vertices)==4 else (
                .5+.45*math.cos(j*math.tau/sides),.5+.45*math.sin(j*math.tau/sides))
        polygon.use_smooth=len(polygon.vertices)==4
    obj['frame']='minimal-rotation parallel transport; smooth low-foot alignment'
    obj['upper_ellipse_ratio']=[report['min_upper_aspect'],report['max_upper_aspect']]
    obj['max_adjacent_frame_angle_deg']=report['max_adjacent_frame_angle_deg']
    ROOT_REPORTS[name]=report
    return obj

def crystal(mat):
    n=18;c=base.CENTER;normal=base.NORMAL;u=base.U;v=normal.cross(u).normalized()
    angles=[i*math.tau/n+.031*math.sin(i*2.13) for i in range(n)]
    vs=[]
    for ring in range(3):
        for i,a in enumerate(angles):
            aa=a+(0 if ring<2 else .075*math.sin(i*1.7))
            radius=[.371,.350,.215][ring]*(1+(.014 if ring<2 else .10)*math.sin(i*2.4+.6))
            h=[-.065,-.012,.045+.016*math.sin(i*1.8)+.009*math.cos(i*3.1)][ring]
            center=c+(u*.019-v*.012 if ring==2 else Vector((0,0,0)))
            vs.append(center+normal*h+radius*(math.cos(aa)*u+math.sin(aa)*v))
    vs.extend([c+u*.031-v*.022+normal*.074,c-normal*.065]);faces=[]
    for ring in range(2):
        for i in range(n):
            j=(i+1)%n;a=ring*n+i;b=ring*n+j;cc=(ring+1)*n+j;d=(ring+1)*n+i
            faces.extend([(a,b,d),(b,cc,d)] if i%2 else [(a,b,cc),(a,cc,d)])
    for i in range(n):
        j=(i+1)%n;faces.extend([(2*n+i,2*n+j,3*n),(i,3*n+1,j)])
    obj=base.mesh_object('TemperatureCore',vs,faces,mat);base.uv_project(obj)
    values=[]
    for polygon in obj.data.polygons:
        # Neutral per-facet value, independent from any temperature or light.
        value=.91+.085*math.sin(polygon.index*1.71)+.025*math.cos(polygon.index*.63)
        values.extend([(value,value,value,1)]*len(polygon.loop_indices))
    color_attribute(obj.data,'CoreFacet',values)
    obj['display_only_temperature']=20;obj['neutral_facets_not_temperature_state']=True
    return obj

def stone_paint(obj):
    mesh=obj.data;uv=mesh.uv_layers['PaintUV'];uv.active_render=True
    bounds=[(min(v.co[k] for v in mesh.vertices),max(v.co[k] for v in mesh.vertices)) for k in range(3)]
    tone=[None]*len(mesh.loops);wear=[None]*len(mesh.loops)
    phase=(sum(obj.name.encode())%29)/29
    for polygon in mesh.polygons:
        axis=max(range(3),key=lambda k:abs(polygon.normal[k]));axes=[k for k in range(3) if k!=axis]
        # The source PNG is one painted material, not a 4x4 atlas. A fixed
        # 0.52 UV/m scale yields a 1.923m brush field on every stone part.
        scale=.34 if obj.name=='StoneFoundation' else .52
        spans=[(bounds[k][1]-bounds[k][0])*scale for k in axes]
        offsets=[.04+(1-.08-s)*(.25+.5*phase) for s in spans]
        if min(offsets)<0:raise RuntimeError('Stone exceeds authored metric texture sheet: '+obj.name)
        up=roots.smooth(.12,.84,polygon.normal.z)
        warm=(1.10,.86,.56);cool=(.67,.78,.88)
        variation=.96+.06*math.sin(phase*5+polygon.center.x*2+polygon.center.y*.7)
        rgb=[(cool[k]*(1-up)+warm[k]*up)*variation for k in range(3)]
        bevel=.12<polygon.normal.z<.90 and polygon.area<.08 and polygon.center.z>.40
        for li in polygon.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=tuple(offsets[q]+(co[k]-bounds[k][0])*scale for q,k in enumerate(axes))
            tone[li]=(*rgb,1)
            # Only small actual bevel faces: a broken, subdued warm edge.
            amount=(.20+.12*math.sin(co.x*5.1+co.y*3.7+phase*6)) if bevel else 0
            wear[li]=(amount,amount,amount,1)
    color_attribute(mesh,'StoneTone',tone);color_attribute(mesh,'StoneWear',wear)
    obj['paint_scale_uv_per_meter']=.34 if obj.name=='StoneFoundation' else .52
    obj['source_png_is_not_atlas']=True

def stone_material(mat):
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
    output=nodes.new('ShaderNodeOutputMaterial');p=nodes.new('ShaderNodeBsdfPrincipled')
    links.new(p.outputs['BSDF'],output.inputs['Surface']);p.inputs['Metallic'].default_value=0
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='PaintUV'
    textures={}
    for channel in ('BaseColor','Roughness','Normal'):
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(base.TEX/('FB_stone_'+channel+'.png')),check_existing=True)
        if channel!='BaseColor':tex.image.colorspace_settings.name='Non-Color'
        tex.image.pack();tex.extension='EXTEND';links.new(uv.outputs['UV'],tex.inputs['Vector']);textures[channel]=tex
    contrast=nodes.new('ShaderNodeVectorMath');contrast.operation='SUBTRACT';contrast.inputs[1].default_value=(.18,.18,.18)
    links.new(textures['BaseColor'].outputs['Color'],contrast.inputs[0])
    gain=nodes.new('ShaderNodeVectorMath');gain.operation='SCALE';gain.inputs['Scale'].default_value=1.55
    links.new(contrast.outputs['Vector'],gain.inputs[0])
    offset=nodes.new('ShaderNodeVectorMath');offset.operation='ADD';offset.inputs[1].default_value=(.24,.24,.24)
    links.new(gain.outputs['Vector'],offset.inputs[0])
    tone=nodes.new('ShaderNodeVertexColor');tone.layer_name='StoneTone'
    tint=nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1
    links.new(offset.outputs['Vector'],tint.inputs[1]);links.new(tone.outputs['Color'],tint.inputs[2])
    edge=nodes.new('ShaderNodeVertexColor');edge.layer_name='StoneWear'
    polish=nodes.new('ShaderNodeMixRGB');polish.blend_type='MIX';polish.inputs[2].default_value=(.48,.39,.25,1)
    links.new(edge.outputs['Color'],polish.inputs[0]);links.new(tint.outputs[0],polish.inputs[1]);links.new(polish.outputs[0],p.inputs['Base Color'])
    links.new(textures['Roughness'].outputs['Color'],p.inputs['Roughness'])
    normal=nodes.new('ShaderNodeNormalMap');normal.uv_map='PaintUV';normal.inputs['Strength'].default_value=.28
    links.new(textures['Normal'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],p.inputs['Normal'])
    mat['source_coordinate_contract']='explicit PaintUV + CORNER StoneTone/StoneWear; retain in bake proxy'
    mat['no_lighting_baked']=True

def core_material_facets(mat):
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes.get('Principled BSDF')
    existing=p.inputs['Base Color'].links[0].from_socket
    attr=nodes.new('ShaderNodeVertexColor');attr.layer_name='CoreFacet'
    mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
    links.new(existing,mix.inputs[1]);links.new(attr.outputs['Color'],mix.inputs[2])
    links.new(mix.outputs[0],p.inputs['Base Color']);links.new(mix.outputs[0],p.inputs['Emission Color'])
    p.inputs['Roughness'].default_value=.41
    mat['delivery_neutral_facets']=True

_build_p2=p2.build
def build():
    root=_build_p2()
    # P3 pure root vertices already include the approved 50mm front shift.
    bpy.data.objects['RootBindings_Front'].location=(0,0,0)
    for obj in base.MODEL.objects:
        if obj.type=='MESH' and obj.data.materials[0].name=='FT_WarmFacetedStone':stone_paint(obj)
    stone_material(bpy.data.materials['FT_WarmFacetedStone'])
    core_material_facets(bpy.data.materials['FT_TemperatureCore'])
    (base.OUTPUT/'root_frames.json').write_text(json.dumps(ROOT_REPORTS,indent=2),encoding='utf-8')
    return root

_audit_p2=p2.audit
def audit():
    result=_audit_p2();attributes=[]
    for obj in bpy.data.collections['F1ThermalStone_EDITABLE'].objects:
        if obj.type!='MESH':continue
        expected=['StoneTone','StoneWear'] if obj.data.materials[0].name=='FT_WarmFacetedStone' else ['CoreFacet'] if obj.name=='TemperatureCore' else []
        for name in expected:
            attr=obj.data.color_attributes.get(name)
            valid=bool(attr and attr.domain=='CORNER' and len(attr.data)==len(obj.data.loops) and all(math.isfinite(v) for item in attr.data for v in item.color))
            attributes.append({'object':obj.name,'attribute':name,'valid':valid,'corners':len(attr.data) if attr else 0})
    result['explicit_source_attributes']=attributes
    result['ok']=result['ok'] and all(row['valid'] for row in attributes)
    return result

p2.sculpted_root=root_mesh;p2.crystal=crystal
base.build=build;base.audit=audit
if __name__=='__main__':base.main()
