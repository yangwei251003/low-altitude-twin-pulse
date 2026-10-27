"""Stage C: reopen actual baked repair and render two locked-camera views."""
import os,time,json
import bpy
import repair_common as R


def main():
    started=time.monotonic();R.verify_frozen();prev,result,blend=R.source_stage_result('bake')
    bpy.ops.wm.open_mainfile(filepath=str(blend));R.write('reopened_images.json',R.images())
    semantics=json.loads((prev/'semantics.json').read_text(encoding='utf-8'))
    for row in result['maps']:
        p=prev/row['file'];assert p.is_file() and R.sha(p)==row['sha256']
    low=bpy.data.objects['RepairLowFull'];high=bpy.data.objects['RepairHighFull']
    assert R.digest(low.data)==semantics['low_geometry_bakeuv'] and R.digest(high.data)==semantics['high_geometry']
    mat=low.data.materials[0];bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    assert bs.inputs['Normal'].links[0].from_node.type=='NORMAL_MAP'
    assert bs.inputs['Base Color'].links[0].from_node.type=='MIX_RGB'
    renders=[];scene=bpy.context.scene;scene.cycles.device='CPU';scene.cycles.samples=24
    for ob,name in [(high,'01_high_source.png'),(low,'02_low_baked.png')]:
        assert R.scene_lock(scene)==semantics['camera'];R.show([ob]);scene.render.filepath=str(R.OUT/name)
        bpy.ops.render.render(write_still=True)
        p=R.OUT/name;renders.append({'file':name,'bytes':p.stat().st_size,'sha256':R.sha(p)})
        R.write('render_checkpoint.json',renders)
    R.verify_frozen();assert R.sha(blend)==result['blend_sha256']
    R.write('result.json',{'stage':'render','status':'PASS','pid':os.getpid(),'seconds':time.monotonic()-started,
                         'source':str(blend),'source_sha256':R.sha(blend),'renders':renders,'same_camera':semantics['camera'],
                         'Normal_and_AO_enabled':True,'geometry_changed':False,'visual_status':'PENDING_ACTUAL_REVIEW',
                         'not_whole_asset_not_game_export':True})


if __name__=='__main__':main()
