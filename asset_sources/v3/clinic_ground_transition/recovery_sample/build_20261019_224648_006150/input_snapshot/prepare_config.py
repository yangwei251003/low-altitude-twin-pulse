"""Static input hashing and fixed original-height crop analysis. No image edits/engine."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
rock='asset_sources/v3/clinic_ground_transition/p10/vendor/polyhaven_rocky_trail/'
sand='asset_sources/v3/clinic_ground_transition/p9/vendor/polyhaven_sandy_gravel_02/'
height='asset_sources/v3/clinic_ground_transition/recovery_study/inputs/rocky_trail/rocky_trail_disp_2k.png'
atlas='references/v3/production/clinic_ground_transition/material_atlas_v1.png'
paths={'rocky':{'diff':rock+'rocky_trail_diff_2k.png','rough':rock+'rocky_trail_rough_2k.png'},'sandy':{'diff':sand+'sandy_gravel_02_diff_2k.png','rough':sand+'sandy_gravel_02_rough_2k.png'}}
files=[height,atlas,'asset_sources/v3/clinic_ground_transition/p3/build_asset.py']+[p for rows in paths.values() for p in rows.values()]
im=np.asarray(Image.open(ROOT/height)).astype(np.float64)/65535
# Fixed UV rectangle bounding the proposed0.9m soil sample. PNG origin is top-left.
u0,u1=.085,.535;v0,v1=.1975,.54
crop=im[int((1-v1)*2048):int((1-v0)*2048),int(u0*2048):int(u1*2048)]
q=np.percentile(crop,[0,1,50,99,100]);strength=.020/(q[3]-q[1])
out={'status':'STATIC_ONE_FIXED_CHOICE_NOT_EXECUTED','footprint_m':[.9,.9],'structural_bottom_y_m':-.18,'height_path':height,'concrete_atlas':atlas,'texture_paths':paths,
     'fixed_height_median':float(q[2]),'fixed_strength_m':float(strength),'strength_is_authored_amplification_not_measured_scan_depth':True,
     'height_crop_uv_rectangle':[u0,v0,u1,v1],'crop_min_p01_median_p99_max':q.tolist(),'crop_raw_unweighted_height_range_m':((q-q[2])*strength).tolist(),
     'displacement_axis':'Blender local Z = Godot local Y; preserves XY heightfield, no XZ channel fold','high_source_macro_normal':'disabled','rocky_width_m':2.,'sandy_width_m':2.5,
     'high_subdivision':{'base_grid':64,'simple_levels':2,'effective_top_grid':256},'low_grid':64,
     'inputs':{rel:{'bytes':(ROOT/rel).stat().st_size,'sha256':sha(ROOT/rel)} for rel in files},
     'p13_manifest_sha256':sha(HERE.parent/'p13/manifest.json'),'research_manifest_sha256':sha(HERE.parent/'recovery_study/manifest.json')}
(HERE/'fixed_config.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:out[k] for k in ('fixed_height_median','fixed_strength_m','crop_min_p01_median_p99_max','crop_raw_unweighted_height_range_m')}))
