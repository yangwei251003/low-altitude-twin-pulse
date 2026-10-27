"""Same GLB; no geometry, material, bake or export mutation. Quantized normals measured in double angle."""
from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from export_asset import triangles
from verify_glb import verify,compare,NAMES
def main():
    start=time.monotonic();print(json.dumps({'stage':'same_byte_readback','pid':os.getpid()}),flush=True)
    glb=HERE/'west_service_room.glb';before=sha(glb);failure=json.loads((HERE/'failed_reimport_normal_component/failure.json').read_text(encoding='utf-8'));assert before==failure['glb_sha256']
    source=HERE/'west_service_room_editable.blend';bake=json.loads((HERE/'bake_report.json').read_text(encoding='utf-8'));assert sha(source)==bake['source_sha256']
    expected=json.loads((HERE/'expected_runtime_triangles.json').read_text(encoding='utf-8'));raw=verify(glb,expected,bake['textures']);write('raw_glb_verified_final.json',raw)
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'west_service_room_delivery.blend'));images=image_audit()
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(glb));actual={o.name:triangles(o) for o in bpy.data.objects if o.type=='MESH'};assert set(actual)==set(NAMES);errors=compare(expected,actual,reimport=True)
    assert sha(glb)==before and sha(source)==bake['source_sha256']
    write('export_report.json',{'status':'EXPORT_AND_SAME_BYTE_NUMERIC_REIMPORT_PASS_NOT_GAME_VERIFIED','pid':os.getpid(),'seconds':time.monotonic()-start,'glb':str(glb),'sha256':before,'bytes':glb.stat().st_size,'raw_report':'raw_glb_verified_final.json','source_unchanged':True,'source_sha256':sha(source),'delivery_blend_sha256':sha(HERE/'west_service_room_delivery.blend'),'reopened_images':images,'reimport_errors':errors,'reimport_triangles':{k:len(v) for k,v in actual.items()},'origin_world':[-14,0,-8],'no_collision_lights_cameras':True,'readback_rule':'Raw exporter quantization mapping retained; Blender second INT16 custom-normal storage checked by double atan2, <=0.1 degrees. No GLB mutation.'})
    print(json.dumps({'stage':'readback_end','pid':os.getpid(),'seconds':time.monotonic()-start,'normal_angle_degrees':errors['normal_angle_degrees'],'glb_sha256':before}),flush=True)
if __name__=='__main__':main()
