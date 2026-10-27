"""One checkpointed native PBR channel; bake function reused from approved bridge delivery."""
from pathlib import Path
import argparse
import hashlib
import json
import sys
import time
sys.dont_write_bytecode=True
import bpy
OUT=Path(__file__).resolve().parent
SIZE=2048
PREFIX='SharedLandings_Deck'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False;obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
def shader(material):
    ps=[n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED']
    assert len(ps)==1
    return ps[0]

def bake(proxy, channel):
    print('BAKE_BEGIN '+channel, flush=True)
    (OUT/'textures').mkdir(exist_ok=True)
    image = bpy.data.images.new(PREFIX+'_'+channel, width=SIZE, height=SIZE, alpha=False, float_buffer=False)
    image.colorspace_settings.name = 'sRGB' if channel == 'BaseColor' else 'Non-Color'
    restore = []
    try:
        for material in proxy.data.materials:
            nodes, links = material.node_tree.nodes, material.node_tree.links
            p = shader(material)
            output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output)
            old = output.inputs['Surface'].links[0].from_socket
            temporary = []
            restore.append((material, output, old, temporary))
            if channel != 'Normal':
                emission = nodes.new('ShaderNodeEmission')
                emission.inputs['Strength'].default_value = 1
                temporary.append(emission)
                if channel == 'BaseColor':
                    socket = p.inputs['Base Color']
                    if socket.is_linked:
                        links.new(socket.links[0].from_socket, emission.inputs['Color'])
                    else:
                        emission.inputs['Color'].default_value = socket.default_value
                else:
                    combine = nodes.new('ShaderNodeCombineColor')
                    combine.mode = 'RGB'
                    combine.inputs['Red'].default_value = 1
                    temporary.append(combine)
                    for name, key in [('Green','Roughness'), ('Blue','Metallic')]:
                        socket = p.inputs[key]
                        if socket.is_linked:
                            links.new(socket.links[0].from_socket, combine.inputs[name])
                        else:
                            combine.inputs[name].default_value = socket.default_value
                    links.new(combine.outputs[0], emission.inputs['Color'])
                links.new(emission.outputs[0], output.inputs['Surface'])
            target = nodes.new('ShaderNodeTexImage')
            target.image = image
            temporary.append(target)
            for node in nodes:
                node.select = False
            target.select = True
            nodes.active = target
        select([proxy])
        scene = bpy.context.scene
        scene.render.bake.normal_space = 'TANGENT'
        scene.render.bake.normal_r = 'POS_X'
        scene.render.bake.normal_g = 'POS_Y'
        scene.render.bake.normal_b = 'POS_Z'
        bpy.ops.object.bake(type='NORMAL' if channel == 'Normal' else 'EMIT', use_clear=True, margin=8, use_selected_to_active=False)
        image.filepath_raw = str(OUT/'textures'/(PREFIX+'_'+channel+'.png'))
        image.file_format = 'PNG'
        image.save()
    finally:
        for material, output, old, temporary in restore:
            material.node_tree.links.new(old, output.inputs['Surface'])
            for node in temporary:
                material.node_tree.nodes.remove(node)
    loaded = bpy.data.images.load(image.filepath_raw, check_existing=False)
    loaded.colorspace_settings.name = image.colorspace_settings.name
    assert len(tuple(loaded.pixels[:4])) == 4
    assert list(loaded.size) == [SIZE,SIZE] and loaded.has_data
    print('BAKE_DONE '+channel, flush=True)
    return {'channel': channel, 'path': image.filepath_raw, 'sha256': sha(image.filepath_raw),
            'bytes': Path(image.filepath_raw).stat().st_size, 'colorspace': loaded.colorspace_settings.name, 'size': list(loaded.size)}

def main():
    global SIZE,PREFIX
    started=time.monotonic();ap=argparse.ArgumentParser();ap.add_argument('--group',choices=['Deck','Coating'],required=True)
    ap.add_argument('--channel',choices=['BaseColor','ORM','Normal'],required=True)
    opts=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);SIZE=2048 if opts.group=='Deck' else 1024
    PREFIX='SharedLandings_'+opts.group
    report_path=OUT/'bake_report.json';report=json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {'stage':'BAKING','textures':{}}
    key=opts.group+'/'+opts.channel
    if key in report['textures']:
        r=report['textures'][key];assert sha(r['path'])==r['sha256'];print('CHANNEL_ALREADY_COMPLETE '+key,flush=True);return
    assert not (OUT/'textures'/(PREFIX+'_'+opts.channel+'.png')).exists(), 'Uncheckpointed earlier output: preserve failure before retry.'
    prep=json.loads((OUT/'atlas_preparation_report.json').read_text(encoding='utf-8'))
    assert sha(OUT/'uv_checkpoint.blend')==prep['checkpoint_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'uv_checkpoint.blend'))
    for row in prep['source_images_resolved_before_save']:
        assert Path(row['path']).is_file() and sha(row['path'])==row['sha256']
    for image in bpy.data.images:
        if image.source!='FILE':continue
        assert Path(bpy.path.abspath(image.filepath)).is_file(), ('Missing source image',image.name,image.filepath)
        _=tuple(image.pixels[:4]);assert image.has_data and min(image.size)>0
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
    scene.render.threads_mode='FIXED';scene.render.threads=2
    proxy=bpy.data.objects[opts.group+'BakeProxy']
    result=bake(proxy,opts.channel);result['group']=opts.group;result['seconds']=time.monotonic()-started
    report['textures'][key]=result;report['stage']='BAKE_COMPLETE' if len(report['textures'])==6 else 'BAKING'
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('LANDING_CHANNEL '+json.dumps(result),flush=True)
if __name__=='__main__':main()
