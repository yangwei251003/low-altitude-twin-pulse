"""Render the saved editable source without rebuilding or overwriting GLB bytes."""
import bpy,sys,json,hashlib,time
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/overpass';EVID=ROOT/'artifacts/v3/art/overpass'
revision=sys.argv[sys.argv.index('--revision')+1] if '--revision' in sys.argv else '3'
samples=int(sys.argv[sys.argv.index('--samples')+1]) if '--samples' in sys.argv else 20
selected=sys.argv[sys.argv.index('--views')+1].split(',') if '--views' in sys.argv else ['front','back','under']
source=SRC/'maintenance_overpass.blend';glb=ROOT/'assets/v3/overpass/maintenance_overpass.glb'
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=samples
def pos(p):return Vector((p[0],-p[2],p[1]))
views={'front':((33,23,40),(0,-2,0)),'back':((-32,20,-40),(0,-2,0)),'under':((0,-2.5,36),(0,-2.5,0))}
records=[]
for name in selected:
 at,target=views[name];scene.camera.location=pos(at);scene.camera.rotation_euler=(pos(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler()
 p=EVID/f'overpass_{name}_v{revision}.png';scene.render.filepath=str(p);start=time.perf_counter();bpy.ops.render.render(write_still=True)
 records.append({'view':name,'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'render_seconds':time.perf_counter()-start,'camera_godot':at,'target_godot':target})
report={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'samples':samples,'cpu_threads':2,'resolution':[scene.render.resolution_x,scene.render.resolution_y],'views':records,'scope':'Blender source renders; no asset mutation, no Godot or performance evidence'}
(EVID/f'renders_v{revision}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('OVERPASS_SAVED_SOURCE_RENDERS_COMPLETE',flush=True)
