from pathlib import Path
import sys,os,time,json,math
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
def main():
    start=time.monotonic();print(json.dumps({'stage':'source','pid':os.getpid(),'threads':2}),flush=True)
    assert not (HERE/'west_service_room_editable.blend').exists(),'Freeze existing source before a new bounded revision.'
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    images,input_rows=load_inputs();m=materials(images)
    B=lambda n,a,b,f='Teal',v=.008:box(n,a,b,m['Concrete' if f=='Concrete' else 'Steel' if f=='Steel' else 'Paint'],f,v)
    # Solid inset core closes panel/louver gaps. Surface assemblies stay inside the original box.
    B('ClosedCore_NoEntrance',[-1.90,.43,-1.90],[1.90,2.38,1.90],'Seal',.005)
    # Four cast plinth quadrants create real construction seams, backed by the solid inner core.
    for ix,(x0,x1) in enumerate([(-2,-.003),(.003,2)]):
        for iz,(z0,z1) in enumerate([(-2,-.003),(.003,2)]):B(f'ConcretePlinth_{ix}_{iz}',[x0,0,z0],[x1,.46,z1],'Concrete',.010)
    B('PlinthJointBacking',[-1.985,.012,-1.985],[1.985,.45,1.985],'Concrete',.005)
    for sx in (-1,1):
        for sz in (-1,1):
            x0,x1=(-2,-1.79) if sx<0 else (1.79,2);z0,z1=(-2,-1.79) if sz<0 else (1.79,2)
            B(f'CornerPost_{sx}_{sz}',[x0,.45,z0],[x1,2.32,z1],'Teal',.014)
            B(f'CornerCap_{sx}_{sz}',[x0,2.32,z0],[x1,2.5,z1],'Teal',.009)
    # Four closed framed walls; south/north paired bolted panels, west continuous service panel.
    for side in ('South','North','West','East'):
        axis=2 if side in ('South','North') else 0;sign=1 if side in ('South','East') else -1;long=0 if axis==2 else 2
        def facebox(name,u0,u1,y0,y1,depth0,depth1,finish,bev=.006):
            a=[0,y0,0];b=[0,y1,0];a[long]=u0;b[long]=u1
            a[axis],b[axis]=((depth0,depth1) if sign>0 else (-depth1,-depth0))
            return B(side+'_'+name,a,b,finish,bev)
        facebox('HeadBeam',-1.79,1.79,2.24,2.49,1.84,1.996,'Teal',.012)
        facebox('Sill',-1.79,1.79,.45,.55,1.84,1.985,'Teal',.007)
        if side!='East':
            facebox('CentreMullion',-.10,.10,.55,2.24,1.87,1.991,'Teal',.010)
            for p,(u0,u1) in enumerate([(-1.785,-.105),(.105,1.785)]):
                for q,(y0,y1) in enumerate([(.555,1.315),(1.322,2.235)]):
                    facebox(f'InspectionPanel_{p}_{q}',u0,u1,y0,y1,1.884,1.949,'Wall',.007)
                for k,(u,y) in enumerate([(u0+.065,.625),(u1-.065,.625),(u0+.065,2.155),(u1-.065,2.155)]):
                    c=[0,y,0];c[long]=u;c[axis]=sign*1.961;axisv=[0,0,0];axisv[axis]=sign;bolt(side+f'_PanelHex_{p}_{k}',c,axisv,m['Steel'])
        else:
            # Backed recess: no fictitious traversable vent. 8 coarse formed slats.
            facebox('VentLowerPanel',-1.785,1.785,.555,1.02,1.884,1.949,'Wall')
            facebox('VentUpperPanel',-1.785,1.785,2.04,2.235,1.884,1.949,'Wall')
            facebox('VentLeftPanel',-1.785,-1.31,1.02,2.04,1.884,1.949,'Wall')
            facebox('VentRightPanel',1.31,1.785,1.02,2.04,1.884,1.949,'Wall')
            facebox('SolidVentBacking',-1.31,1.31,1.02,2.04,1.89,1.915,'Seal',.002)
            for k,(u0,u1,y0,y1) in enumerate([(-1.35,-1.29,1.00,2.06),(1.29,1.35,1.00,2.06),(-1.29,1.29,1.00,1.06),(-1.29,1.29,2.,2.06)]):facebox('VentRim_'+str(k),u0,u1,y0,y1,1.912,1.971,'Teal',.004)
            for i in range(8):
                y=1.085+i*.113;slat=facebox('Louver_'+str(i),-1.285,1.285,y,y+.087,1.916,1.966,'Teal',.003)
                # Outer bottom edge is inset: real sloping closed section, not alpha holes.
                for v in slat.data.vertices:
                    p=gp(v.co)
                    if p[1]<y+.04:p[0]-=.028;v.co=bp(p)
                slat.data.update();
            for i,(u,y) in enumerate([(-1.32,1.03),(1.32,1.03),(-1.32,2.03),(1.32,2.03)]):bolt('East_VentHex_'+str(i),(1.979,y,u),(1,0,0),m['Steel'])
        for i,u in enumerate((-1.68,1.68)):
            c=[0,2.37,0];c[long]=u;c[axis]=sign*1.982;d=[0,0,0];d[axis]=sign;bolt(side+'_BeamHex_'+str(i),c,d,m['Steel'])
    # Low roof panels sit 60mm under the rim; two unequal sampling phases, no white oxide atlas.
    B('RoofSealedUnderlay',[-1.80,2.28,-1.80],[1.80,2.39,1.80],'Teal',.006)
    for i,(x0,x1) in enumerate([(-1.79,-.025),(.025,1.79)]):B('RoofSteel_'+str(i),[x0,2.385,-1.79],[x1,2.432,1.79],'Steel',.004)
    B('RoofCentralStandingSeam',[-.035,2.39,-1.79],[.035,2.462,1.79],'Steel',.003)
    for i,x in enumerate((-1.69,1.69)):
        for j,z in enumerate((-1.69,1.69)):
            B(f'RoofJointPlate_{i}_{j}',[x-.115,2.431,z-.115],[x+.115,2.455,z+.115],'Teal',.004)
            for k,dx in enumerate((-.06,.06)):bolt(f'RoofJointHex_{i}_{j}_{k}',(x+dx,2.465,z),(0,1,0),m['Steel'])
    parts=[o for o in bpy.data.objects if o.get('editable_piece')];bpy.context.view_layer.update();report=geometry(parts)
    # The back plate is real, and its eastmost face covers the entire louver rectangle.
    vent=bpy.data.objects['East_SolidVentBacking'];assert len(vent.data.polygons)==6
    report.update(input_images=input_rows,origin_world=[-14,0,-8],root_name='WestServiceRoom',front='+Z',louver='Eight physical slats with opaque closed backing; no passage',collision='No collision export; Root keeps original WestLowRoof Box',reference=str(ROOT/'references/v3/production/west_service_room/west_service_room_reference_v1.png'))
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
    world=bpy.data.worlds.new('NeutralStudio');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.44,.47,.50,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55;scene.world=world
    groundmat=bpy.data.materials.new('ReviewGround_NotAsset');groundmat.diffuse_color=(.23,.24,.25,1)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012));ground=bpy.context.object;ground.name='ReviewGround_NOT_ASSET';ground.data.materials.append(groundmat)
    for name,loc,energy,size in [('Key',(-4,-6,10),1250,7),('Fill',(6,-1,6),450,6)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.objects.new('SourceReviewCamera',bpy.data.cameras.new('SourceReviewCamera'));scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO';camera.location=(8,-10,8);target=Vector((0,0,1.15));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=7.4
    image_audit();path=HERE/'west_service_room_editable.blend';save_relative(path);bpy.ops.wm.open_mainfile(filepath=str(path));parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert geometry(parts)['geometry_sha256']==report['geometry_sha256'];report['reopened_images']=image_audit()
    scene=bpy.context.scene;outputs=[]
    for name,scale in [('01-single-object-repaired',7.4)]:
        scene.camera.data.ortho_scale=scale;scene.render.filepath=str(HERE/(name+'.png'));bpy.ops.render.render(write_still=True)
        outputs.append({'path':scene.render.filepath,'sha256':sha(scene.render.filepath),'ortho_metres':scale,'scope':'Offline source-only view; 26m approximates scale, not actual game lighting or screenshot'})
    report.update(status='SOURCE_PREVIEW_COMPLETE_PENDING_ART_REVIEW',images=outputs,source_sha256=sha(path),seconds=time.monotonic()-start,pid=os.getpid(),source_materials=3)
    write('source_report.json',report);print(json.dumps({'stage':'source_end','pid':os.getpid(),'seconds':report['seconds'],'objects':report['objects'],'triangles':report['triangles']}),flush=True)
if __name__=='__main__':main()
