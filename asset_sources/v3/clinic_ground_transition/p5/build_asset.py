"""P5 source-only: edge aggregate, sediment-channel zones, original frozen helper reuse.
Requires an explicit serial Blender window. Does not export GLB or modify runtime.
"""
from pathlib import Path
import sys, importlib.util, math, random, json, time, os, shutil
sys.dont_write_bytecode = True
import bpy

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
spec = importlib.util.spec_from_file_location('transition_p3_frozen', OUT.parent/'p3/build_asset.py')
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)
H.OUT = OUT
OLD_MESH, OLD_AUTHOR, OLD_GEOMETRY = H.mesh, H.author, H.geometry_report
SURFACE = ROOT/'references/v3/production/clinic_ground_transition/surface_atlas_v2.png'
SURFACE_SHA = '4cb682cc931a667c2bacaf06bb0c7cdb17fb05aadd227520af3e5f870af72d67'
EMBEDDED = []

def smooth(t):
    t = H.clamp(t)
    return t*t*(3-2*t)

def channel_data(x, z):
    """One geometry-defined coordinate field for silt, groove and wetness.
    Returns silt coverage, local cross/along UV, physical groove and bank weights.
    Does not add a second surface over the terrain.
    """
    result = (0.0, (.5, .5), 0.0, 0.0)
    for ri, (points, amplitude) in enumerate(H.ROUTES):
        lengths = [math.hypot(c-a, d-b) for (a,b),(c,d) in zip(points, points[1:])]
        total, walk, best = sum(lengths), 0.0, None
        for ((a,b),(c,d)), length in zip(zip(points, points[1:]), lengths):
            q = H.clamp(((x-a)*(c-a)+(z-b)*(d-b))/(length*length))
            dx, dz = x-(a+q*(c-a)), z-(b+q*(d-b))
            distance = math.hypot(dx,dz)
            if best is None or distance < best[0]:
                signed = ((c-a)*dz-(d-b)*dx)/length
                best = (distance, (walk+q*length)/total, signed)
            walk += length
        distance, t, signed = best
        main = ri in (0,2,4)
        width = ((.105+.085*t) if main else (.065+.035*t)) * (1 if ri != 2 else .86)
        tail = smooth((1-t)/.18)
        silt = smooth((1-distance/width)*1.45)*tail
        groove = math.exp(-2.4*(distance/(width*.70))**2)*tail*amplitude
        bank = math.exp(-5*((distance-width)/max(.035,width*.45))**2)*tail
        if silt > result[0]:
            result = (silt, (.5+signed/.65, .12+(t*total)/1.5), groove, bank)
        elif groove > result[2]:
            result = (result[0],result[1],groove,max(bank,result[3]))
    return result

def soil_y(x,z):
    front, outer = H.front(x), H.outer(x)
    s = H.clamp((z-front)/(outer-front))
    side = math.sin(math.pi*H.clamp((x+3)/6))**.45
    _,_,groove,bank = channel_data(x,z)
    base = -.048*(1-s) - .025*groove + .0045*bank
    broad = .003*math.sin(x*2.3+s*5)*math.sin(math.pi*s)
    return (base+broad)*side*min(1,(1-s)*10)

H.soil_y = soil_y

def mesh(name,vs,fs,mat,group,kind):
    ob = OLD_MESH(name,vs,fs,mat,group,kind)
    if kind == 'soil':
        ob.data.uv_layers.new(name='ChannelUV')
        # Reacquire RNA handles after creating the new UV layer.
        channel_uv = ob.data.uv_layers['ChannelUV']
        controls = ob.data.color_attributes['SurfaceControl']
        for poly in ob.data.polygons:
            top = poly.normal.z > .15
            for li in poly.loop_indices:
                p = ob.data.vertices[ob.data.loops[li].vertex_index].co
                x,y,z = H.gp(p)
                silt,uv,_,_ = channel_data(x,z)
                channel_uv.data[li].uv = uv
                controls.data[li].color = (H.wet(x,z),silt if top else 0,1 if top else 0,1)
        ob.data.uv_layers.active_index = ob.data.uv_layers.find('MetricUV')
        for layer in ob.data.uv_layers:
            layer.active_render = layer.name == 'MetricUV'
    return ob

H.mesh = mesh

def author(kind,old_atlas):
    if kind != 'soil':
        return OLD_AUTHOR(kind,old_atlas)
    g = H.Graph('SOURCE_soil_P5_silt_and_banks')
    n,l = g.n,g.l
    atlas = bpy.data.images.load(str(OUT/'source_inputs/surface_atlas_v2_UNEDITED.png'),check_existing=True)
    atlas.colorspace_settings.name = 'sRGB'
    metric = n.new('ShaderNodeUVMap'); metric.uv_map='MetricUV'
    channel = n.new('ShaderNodeUVMap'); channel.uv_map='ChannelUV'
    attr=n.new('ShaderNodeVertexColor');attr.layer_name='SurfaceControl'
    control=n.new('ShaderNodeSeparateColor');l.new(attr.outputs[0],control.inputs[0])

    def atlas_region(socket,left,scale):
        split=n.new('ShaderNodeSeparateXYZ');l.new(socket,split.inputs[0])
        xy=n.new('ShaderNodeCombineXYZ')
        for name in ['X','Y']:
            q=g.op('PINGPONG',g.op('MULTIPLY',split.outputs[name],scale),1)
            if name=='X': q=g.op('ADD',.004 if left else .504,g.op('MULTIPLY',q,.492))
            else: q=g.op('ADD',.008,g.op('MULTIPLY',q,.984))
            l.new(q,xy.inputs[name])
        image=n.new('ShaderNodeTexImage');image.image=atlas;image.extension='EXTEND'
        image.label='Fine sediment along channel' if left else 'Sparse gravel bank, 0.5m metric coverage'
        l.new(xy.outputs[0],image.inputs[0]);return image.outputs[0]

    bank=g.mix((.15,.13,.105,1),atlas_region(metric.outputs[0],False,3.0),.82)
    silt=g.mix((.155,.128,.098,1),atlas_region(channel.outputs[0],True,1.0),.94)
    base=g.mix(bank,silt,control.outputs['Green'])
    damp=g.op('SUBTRACT',1,g.op('MULTIPLY',control.outputs['Red'],.24))
    mult=n.new('ShaderNodeMixRGB');mult.blend_type='MULTIPLY';mult.inputs[0].default_value=1
    l.new(base,mult.inputs[1]);l.new(damp,mult.inputs[2])
    rough=g.op('SUBTRACT',.86,g.op('ADD',g.op('MULTIPLY',control.outputs['Green'],.11),g.op('MULTIPLY',control.outputs['Red'],.18)))
    bs=n.new('ShaderNodeBsdfPrincipled');l.new(mult.outputs[0],bs.inputs['Base Color']);l.new(rough,bs.inputs['Roughness'])
    bs.inputs['Metallic'].default_value=0;bs.inputs['Emission Strength'].default_value=0
    # Source color is never used as a height field. Only sub-mm micro texture here;
    # the actual broad rills and sediment shoulders are already in the shared mesh.
    noise=n.new('ShaderNodeTexNoise');l.new(metric.outputs[0],noise.inputs['Vector'])
    noise.inputs['Scale'].default_value=48;noise.inputs['Detail'].default_value=1
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.18
    distance=g.op('SUBTRACT',.0012,g.op('MULTIPLY',control.outputs['Green'],.00095))
    l.new(distance,bump.inputs['Distance']);l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0])
    return g.m

H.author = author

def fragment(name,cx,cz,diameter,height,embedded,rng,mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1 if embedded else 2,radius=1)
    temp=bpy.context.object
    originals=[tuple(v.co) for v in temp.data.vertices]
    faces=[list(p.vertices) for p in temp.data.polygons]
    bpy.data.objects.remove(temp,do_unlink=True)
    angle=rng.random()*math.tau
    cy=H.edge_y(cx)-height*.62 if embedded else soil_y(cx,cz)-.003
    vertices=[]
    for vx,vy,vz in originals:
        radial=1+rng.uniform(-.12,.12)
        xx=(vx*math.cos(angle)-vy*math.sin(angle))*diameter*.5*radial
        zz=(vx*math.sin(angle)+vy*math.cos(angle))*diameter*(.26 if embedded else .36)*radial
        yy=cy+vz*height*.5*(1+rng.uniform(-.10,.10))
        vertices.append(H.bp(cx+xx,yy,cz+zz))
    if name == 'EmbeddedAggregate_09':
        # Actual first-attempt vertices had only 2 mm insertion at this sloping
        # fracture. Move this one part 3.966 mm along the measured inward normal.
        # Size, rotation, height, all other pieces and the exposure check remain.
        dx, dz = .00041869300437443846, -.003944048719505284
        vertices = [(x+dx,y-dz,z) for x,y,z in vertices]
        cx += dx; cz += dz
    if max(v[2] for v in vertices)>.027:
        shift=max(v[2] for v in vertices)-.027
        vertices=[(x,y,z-shift) for x,y,z in vertices]
    ob=mesh(name,vertices,faces,mat,H.GROUPS[1],'chip')
    ys=[v[2] for v in vertices];surface=soil_y(cx,cz)
    row={'name':name,'ground_center':[cx,surface,cz],'min_y':min(ys),'max_y':max(ys),'protrusion_m':max(ys)-surface,'diameter_m':diameter,'embedded_below_ground_m':surface-min(ys)}
    if embedded:
        exposed=0;inserted=0
        for p in vertices:
            x,y,z=H.gp(p)
            exposed+=z>H.front(x)+.003 and y>soil_y(x,z)+.003
            inserted+=z<H.front(x)-.003 and y<H.edge_y(x)
        row.update(exposed_vertices=exposed,inserted_vertices=inserted)
        EMBEDDED.append(row)
    else:
        H.CHIPS.append(row)
    return ob

def build(mats):
    for k,(a,b) in enumerate([(-3,-1.17),(-1.15,.83),(.85,3)]):
        xs=sorted(set([a,b]+[x for x in H.X if a<x<b]));top=[]
        for row in range(4):
            for x in xs:
                f=H.front(x);z=[.01,.18,f-.025,f][row]
                top.append(H.bp(x,[0,0,0,H.edge_y(x)][row],z))
        H.grid_solid('ConcreteResidual_%02d'%k,top,4,len(xs),mats['concrete'],H.GROUPS[0],'concrete')
    for k,(a,b) in enumerate([(-1.17,-1.15),(.83,.85)]):
        end=min(H.front(a),H.front(b))-.002
        H.grid_solid('RecessedCrossSeal_%02d'%k,[H.bp(a,-.012,.01),H.bp(b,-.012,.01),H.bp(a,-.012,end),H.bp(b,-.012,end)],2,2,mats['seal'],H.GROUPS[0],'seal')
    H.grid_solid('JoinSeal_10mm',[H.bp(-3,-.012,0),H.bp(3,-.012,0),H.bp(-3,-.012,.01),H.bp(3,-.012,.01)],2,2,mats['seal'],H.GROUPS[0],'seal')
    top=[]
    for row in range(21):
        for x in H.X:
            z=H.front(x)+(H.outer(x)-H.front(x))*row/20
            top.append(H.bp(x,soil_y(x,z),z))
    H.grid_solid('CompactedSoil_ContinuousSupport',top,21,len(H.X),mats['soil'],H.GROUPS[1],'soil')
    rng=random.Random(521731)
    # Unequal clusters attached to the real fracture, not an even all-surface scatter.
    clusters=[(-2.35,.25,6),(-1.18,.30,10),(.43,.27,7),(1.75,.32,9)]
    item=0
    for center,spread,count in clusters:
        for i in range(count):
            x=center+((i+.25+rng.random()*.5)/count*2-1)*spread
            z=H.front(x)+rng.uniform(-.003,.008)
            fragment('EmbeddedAggregate_%02d'%item,x,z,rng.uniform(.035,.070),rng.uniform(.028,.045),True,rng,mats['chip']);item+=1
    for i in range(16):
        center,spread,_=clusters[i%4]
        x=center+rng.uniform(-spread*.9,spread*.9)
        z=H.front(x)+rng.uniform(.13,.45)
        # Keep the continuous silt bed readable; place blocks on its actual banks.
        if channel_data(x,z)[0]>.65:
            x+=.17 if i%2 else -.17
            z=max(z,H.front(x)+.13)
        fragment('FallenFracture_%02d'%i,x,z,rng.uniform(.08,.155),rng.uniform(.040,.065),False,rng,mats['chip'])

H.build = build

def geometry_report():
    report=OLD_GEOMETRY()
    checks=report['checks']
    checks.append({'name':'embedded_aggregate_attached_and_exposed','pass':all(r['exposed_vertices']>0 and r['inserted_vertices']>0 for r in EMBEDDED)})
    checks.append({'name':'visual_budget_8000','pass':report['triangles']<=8000})
    report.update(embedded_aggregate=EMBEDDED,source_method='P5 distinct silt bed / gravel bank and fracture clusters; shared original footprint',collision_status='NOT_EXPORTED; requires new actual coarse surface and >=3cm-protrusion fragment caps; P2 collision is not reused')
    (OUT/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    assert all(c['pass'] for c in checks),[c for c in checks if not c['pass']]
    return report

H.geometry_report=geometry_report

def main():
    started=time.time()
    assert not (OUT/'editable_source.blend').exists(),'Preserve prior attempt before any rerun'
    assert H.sha(H.ATLAS)==H.ATLAS_SHA and H.sha(SURFACE)==SURFACE_SHA
    frozen={str(p):H.sha(p) for p in [OUT.parent/'p3/build_asset.py',OUT.parent/'p4/manifest.json']}
    for sub in ['textures','evidence','source_inputs']:(OUT/sub).mkdir(exist_ok=True)
    shutil.copyfile(H.ATLAS,OUT/'source_inputs/material_atlas_v1_UNEDITED.png')
    shutil.copyfile(SURFACE,OUT/'source_inputs/surface_atlas_v2_UNEDITED.png')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    atlas=bpy.data.images.load(str(OUT/'source_inputs/material_atlas_v1_UNEDITED.png'))
    atlas.colorspace_settings.name='sRGB'
    materials={k:author(k,atlas) for k in ['concrete','soil','chip','seal']}
    build(materials)
    # Save every attempted mesh before numeric assertions; failures remain reviewable.
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'geometry_attempt.blend'),relative_remap=False)
    report=geometry_report();H.studio()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_source.blend'),relative_remap=False)
    report['editable_sha256']=H.sha(OUT/'editable_source.blend')
    proxy=H.proxy_and_uv();H.attribute_audit(proxy)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False)
    maps=[]
    for role in ['BaseColor','ORM','Normal']:
        maps.append(H.bake(proxy,role))
        (OUT/'bake_report.json').write_text(json.dumps({'status':'CHECKPOINT_'+role,'maps':maps},indent=2),encoding='utf-8')
    material=H.final_mat(maps);proxy.data.materials.clear();proxy.data.materials.append(material)
    for poly in proxy.data.polygons:poly.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'baked_source.blend'))
    images=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            path=Path(bpy.path.abspath(im.filepath));assert path.exists()
            im.reload();first=tuple(im.pixels[:4]);assert len(first)==4 and im.has_data
            images.append({'path':str(path),'sha256':H.sha(path),'colorspace':im.colorspace_settings.name})
    scene=bpy.context.scene;scene.cycles.samples=24
    path=OUT/'evidence/transition_source_p5.png';scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    assert all(H.sha(p)==digest for p,digest in frozen.items())
    report.update(status='P5_SOURCE_RENDERED_PENDING_ACTUAL_REVIEW_NO_GLB',maps=maps,reopened_images=images,render_sha256=H.sha(path),source_unchanged=H.sha(OUT/'editable_source.blend')==report['editable_sha256'],frozen_inputs_unchanged=True,seconds=time.time()-started)
    (OUT/'production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-started,'triangles':report['triangles'],'render':str(path)}),flush=True)

if __name__=='__main__':main()
