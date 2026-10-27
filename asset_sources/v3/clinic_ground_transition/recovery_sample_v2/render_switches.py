"""Four original-camera low-model views; only two explicit material links vary."""
import sys,time,os
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import common as C

def main():
    started=time.monotonic();scene=C.open_source();before=C.fingerprints();lock=C.scene_lock(scene);C.show_low()
    mat=bpy.data.materials['Study_BakedLow_ExplicitPBR'];n=mat.node_tree.nodes;l=mat.node_tree.links
    bs=next(q for q in n if q.type=='BSDF_PRINCIPLED')
    normal=bs.inputs['Normal'].links[0].from_socket
    multiplied=bs.inputs['Base Color'].links[0].from_socket
    assert normal.node.type=='NORMAL_MAP' and multiplied.node.type=='MIX_RGB'
    base=next(q for q in n if q.type=='TEX_IMAGE' and q.image.name=='Study1K_BaseColor').outputs['Color']
    results=[]
    for use_n,use_ao,name in [(True,True,'01_N1_A1_baseline'),(False,True,'02_N0_A1'),(True,False,'03_N1_A0'),(False,False,'04_N0_A0')]:
        for link in list(bs.inputs['Normal'].links):l.remove(link)
        if use_n:l.new(normal,bs.inputs['Normal'])
        else:bs.inputs['Normal'].default_value=(0,0,0)
        l.new(multiplied if use_ao else base,bs.inputs['Base Color'])
        assert C.scene_lock(scene)==lock and C.fingerprints()==before
        scene.render.filepath=str(C.OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
        p=C.OUT/(name+'.png');results.append({'file':p.name,'sha256':C.sha(p),'bytes':p.stat().st_size,'normal_enabled':use_n,'AO_multiply_enabled':use_ao})
        C.write('render_checkpoint.json',{'renders':results,'scene_lock':lock,'mesh_digests':before})
    l.new(normal,bs.inputs['Normal']);l.new(multiplied,bs.inputs['Base Color'])
    assert C.fingerprints()==before;C.check_inputs()
    C.write('render_result.json',{'status':'DIAGNOSTIC_VIEWS_PENDING_REVIEW_NOT_REPAIR','pid':os.getpid(),'seconds':time.monotonic()-started,'renders':results,'scene_lock':lock,'mesh_digests':before,'source_saved_or_modified':False,'baked':False})

if __name__=='__main__':main()
