"""Independent 3x5x4.1 m service cabin; never scale the frozen low cabin."""
from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *

def main():
    start=time.monotonic();print(json.dumps({'stage':'source','pid':os.getpid(),'threads':2}),flush=True)
    assert not (HERE/'west_offset_room_editable.blend').exists()
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    images,input_rows=load_inputs();m=materials(images)
    B=lambda n,a,b,f='Teal',v=.008:box(n,a,b,m['Concrete' if f=='Concrete' else 'Steel' if f=='Steel' else 'Paint'],f,v)
    B('ClosedCore_NoEntrance',[-1.40,.43,-2.40],[1.40,3.98,2.40],'Seal',.005)
    for ix,(x0,x1) in enumerate([(-1.5,-.003),(.003,1.5)]):
        for iz,(z0,z1) in enumerate([(-2.5,-.003),(.003,2.5)]):
            B(f'ConcretePlinth_{ix}_{iz}',[x0,0,z0],[x1,.46,z1],'Concrete',.010)
    B('PlinthJointBacking',[-1.485,.012,-2.485],[1.485,.45,2.485],'Concrete',.005)
    for sx in (-1,1):
        for sz in (-1,1):
            x0,x1=(-1.5,-1.29) if sx<0 else (1.29,1.5)
            z0,z1=(-2.5,-2.29) if sz<0 else (2.29,2.5)
            # End-abut caps; the frozen low cabin's coplanar overlap must not recur.
            B(f'CornerPost_{sx}_{sz}',[x0,.45,z0],[x1,3.92,z1],'Teal',.014)
            B(f'CornerCap_{sx}_{sz}',[x0,3.92,z0],[x1,4.1,z1],'Teal',.009)
    backings=[]
    for side in ('South','North','West','East'):
        axis=2 if side in ('South','North') else 0
        sign=1 if side in ('South','East') else -1
        long=0 if axis==2 else 2
        half=1.29 if axis==2 else 2.29
        outer=2.5 if axis==2 else 1.5
        def facebox(name,u0,u1,y0,y1,inset0,inset1,finish,bev=.006):
            a=[0,y0,0];b=[0,y1,0];a[long]=u0;b[long]=u1
            d0,d1=outer-inset0,outer-inset1
            a[axis],b[axis]=((d0,d1) if sign>0 else (-d1,-d0))
            return B(side+'_'+name,a,b,finish,bev)
        def hexhead(name,u,y,inset=.021):
            c=[0,y,0];c[long]=u;c[axis]=sign*(outer-inset)
            d=[0,0,0];d[axis]=sign;return bolt(side+'_'+name,c,d,m['Steel'])
        facebox('HeadBeam',-half,half,3.84,4.09,.16,.004,'Teal',.012)
        facebox('MidBand',-half,half,2.05,2.23,.16,.009,'Teal',.010)
        facebox('Sill',-half,half,.45,.55,.16,.015,'Teal',.007)
        bays=[(-half+.005,-.105),(.105,half-.005)] if axis==2 else [(-2.285,-.805),(-.795,.795),(.805,2.285)]
        for i,(u0,u1) in enumerate(bays):
            facebox(f'LowerInspectionPanel_{i}',u0,u1,.555,2.045,.116,.051,'Wall',.007)
            for k,(u,y) in enumerate([(u0+.065,.625),(u1-.065,.625),(u0+.065,1.975),(u1-.065,1.975)]):hexhead(f'LowerHex_{i}_{k}',u,y,.039)
        if axis==2:
            facebox('CentreMullionLower',-.10,.10,.55,2.05,.13,.009,'Teal',.010)
            facebox('CentreMullionUpper',-.10,.10,2.23,3.84,.13,.009,'Teal',.010)
        if side!='East':
            for i,(u0,u1) in enumerate(bays):
                facebox(f'UpperInspectionPanel_{i}',u0,u1,2.235,3.835,.116,.051,'Wall',.007)
                for k,(u,y) in enumerate([(u0+.065,2.305),(u1-.065,2.305),(u0+.065,3.765),(u1-.065,3.765)]):hexhead(f'UpperHex_{i}_{k}',u,y,.039)
        else:
            # Two upper vent banks, opaque backs. Fixed coarse slats, not imaginary doors.
            facebox('VentCentreMullion',-.075,.075,2.23,3.84,.13,.009,'Teal',.009)
            for bank,(u0,u1) in enumerate([(-2.285,-.085),(.085,2.285)]):
                backings.append(facebox(f'SolidVentBacking_{bank}',u0,u1,2.235,3.835,.11,.085,'Seal',.002))
                for k,(a,b,y0,y1) in enumerate([(u0,u0+.06,2.235,3.835),(u1-.06,u1,2.235,3.835),(u0+.06,u1-.06,2.235,2.295),(u0+.06,u1-.06,3.775,3.835)]):
                    facebox(f'VentRim_{bank}_{k}',a,b,y0,y1,.088,.029,'Teal',.004)
                for i in range(8):
                    y=2.315+i*.18
                    slat=facebox(f'Louver_{bank}_{i}',u0+.065,u1-.065,y,y+.142,.084,.034,'Teal',.003)
                    for v in slat.data.vertices:
                        p=gp(v.co)
                        if p[1]<y+.06:p[0]-=.028;v.co=bp(p)
                    slat.data.update()
                for k,(u,y) in enumerate([(u0+.03,2.265),(u1-.03,2.265),(u0+.03,3.805),(u1-.03,3.805)]):hexhead(f'VentHex_{bank}_{k}',u,y)
        for level,y in [('Head',3.97),('Band',2.14)]:
            for i,u in enumerate((-half+.11,half-.11)):hexhead(level+'_BeamHex_'+str(i),u,y,.018)
    # Intentionally three quiet roof panels rather than the reference's many thin lines.
    B('RoofSealedUnderlay',[-1.30,3.88,-2.30],[1.30,3.99,2.30],'Teal',.006)
    for i,(z0,z1) in enumerate([(-2.285,-.787),(-.737,.737),(.787,2.285)]):
        B('RoofSteel_'+str(i),[-1.285,3.985,z0],[1.285,4.032,z1],'Steel',.004)
    for i,z in enumerate((-.762,.762)):
        B('RoofStandingSeam_'+str(i),[-1.285,3.99,z-.035],[1.285,4.062,z+.035],'Steel',.003)
    for i,x in enumerate((-1.16,1.16)):
        for j,z in enumerate((-2.16,2.16)):
            B(f'RoofJointPlate_{i}_{j}',[x-.115,4.031,z-.115],[x+.115,4.055,z+.115],'Teal',.004)
            for k,dx in enumerate((-.06,.06)):bolt(f'RoofJointHex_{i}_{j}_{k}',(x+dx,4.065,z),(0,1,0),m['Steel'])
    parts=[o for o in bpy.data.objects if o.get('editable_piece')];bpy.context.view_layer.update();report=geometry(parts)
    assert len(backings)==2 and all(len(o.data.polygons)==6 for o in backings)
    report.update(input_images=input_rows,origin_world=[-12.5,0,-2.5],root_name='WestOffsetRoom',front='+Z',louver='Two banks of eight physical slats; opaque closed backs; no passage',collision='No collision export; Root retains original WestOffsetRoof Box',reference=str(ROOT/'references/v3/production/west_offset_room/west_offset_room_reference_v1.png'),intentional_simplification='Three large low-reflection roof panels replace the reference many thin seams',construction='New dimensions and band layout; no nonuniform scaling of low room',cap_joint='CornerPost ends at 3.92m; CornerCap begins at 3.92m, no coplanar exterior overlap')
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
    world=bpy.data.worlds.new('NeutralStudio');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.44,.47,.50,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55;scene.world=world
    groundmat=bpy.data.materials.new('ReviewGround_NotAsset');groundmat.diffuse_color=(.23,.24,.25,1)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012));ground=bpy.context.object;ground.name='ReviewGround_NOT_ASSET';ground.data.materials.append(groundmat)
    for name,loc,energy,size in [('Key',(-4,-6,10),1250,7),('Fill',(6,-1,6),450,6)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.objects.new('SourceReviewCamera',bpy.data.cameras.new('SourceReviewCamera'));scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO';camera.location=(8,-10,9);target=Vector((0,0,1.95));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=8.4
    image_audit();path=HERE/'west_offset_room_editable.blend';save_relative(path);bpy.ops.wm.open_mainfile(filepath=str(path));parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert geometry(parts)['geometry_sha256']==report['geometry_sha256'];report['reopened_images']=image_audit()
    scene=bpy.context.scene;scene.render.filepath=str(HERE/'01-single-object.png');bpy.ops.render.render(write_still=True)
    report.update(status='SOURCE_PREVIEW_COMPLETE_PENDING_ART_REVIEW',images=[{'path':scene.render.filepath,'sha256':sha(scene.render.filepath),'ortho_metres':8.4,'scope':'Offline single-object source review, south/east faces; not game screenshot'}],source_sha256=sha(path),seconds=time.monotonic()-start,pid=os.getpid(),source_materials=3)
    write('source_report.json',report);print(json.dumps({'stage':'source_end','pid':os.getpid(),'seconds':report['seconds'],'objects':report['objects'],'triangles':report['triangles']}),flush=True)

if __name__=='__main__':main()
