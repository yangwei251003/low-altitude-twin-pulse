"""Read-only image/author metadata statistics, local source audit, and frozen-P13 check."""
from pathlib import Path
import hashlib, json, struct, xml.etree.ElementTree as ET
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FROZEN = HERE.parent/'p13'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

assets = []
for name, vendor, width_m, author in [
    ('rocky_trail', HERE.parent/'p10/vendor/polyhaven_rocky_trail', 2.0, 'Amal Kumar'),
    ('sandy_gravel_02', HERE.parent/'p9/vendor/polyhaven_sandy_gravel_02', 2.5, 'Dario Barresi')]:
    height = HERE/'inputs'/name/(name+'_disp_2k.png')
    raw = height.read_bytes()
    w,h,bits,color,_,_,_ = struct.unpack('>IIBBBBB', raw[16:29])
    with Image.open(height) as image:
        values = np.asarray(image)
    assert values.dtype == np.uint16 and values.ndim == 2
    norm = values.astype(np.float64)/65535.0
    qs = np.percentile(norm, [0,1,5,25,50,75,95,99,100])
    keys = ['min','p01','p05','p25','p50','p75','p95','p99','max']
    mtlx = HERE/'inputs'/name/(name+'_2k.mtlx')
    tree = ET.parse(mtlx).getroot()
    displacement = tree.find('displacement')
    scale = float(next(x.attrib['value'] for x in displacement if x.attrib['name']=='scale'))
    info = json.loads((vendor/'info.json').read_text(encoding='utf-8-sig'))
    assets.append({
        'asset':name, 'author':author, 'published_width_m':width_m,
        'api_dimensions_raw':info.get('dimensions'),
        'horizontal_scale_note':'Published asset page meter width used. Raw API dimensions preserved, unit not inferred as a new hard constraint.',
        'texture_pixels_per_m_at_published_width':w/width_m,
        'height_path':str(height.relative_to(ROOT)).replace('\\','/'),
        'height_sha256':sha(height), 'size':[w,h], 'bit_depth':bits,
        'png_color_type':color, 'decoded_dtype':str(values.dtype),
        'unique_height_values':int(len(np.unique(values))),
        'normalized_height_quantiles':dict(zip(keys, map(float,qs))),
        'normalized_height_std':float(norm.std()),
        'author_materialx_path':str(mtlx.relative_to(ROOT)).replace('\\','/'),
        'author_materialx_displacement_scale':scale,
        'author_materialx_units_declared':tree.attrib.get('unit'),
        'scale_caution':'0.01 is the delivered author shader preset. No metric unit or measured vertical-depth field is declared here; not proof of physical scan height.',
        'if_one_scene_unit_is_one_meter_at_author_preset':{
            'min_max_mm':float((qs[-1]-qs[0])*scale*1000),
            'p01_p99_mm':float((qs[-2]-qs[1])*scale*1000)},
        'previous_vendor_filenames':[p.name for p in sorted(vendor.iterdir()) if p.is_file()],
        'previously_downloaded_height':any(p.stem.endswith('_disp_2k') for p in vendor.iterdir()),
        'input_pixels_unchanged':True,
    })

inputs = []
for rel in ['p10/scan_soil_material.py','p13/build_preview.py','p13/terrain_design.py']:
    p=HERE.parent/rel
    inputs.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(p)})
report = {'scope':'Static only. No Blender, geometry construction, image modification or GPU.',
          'assets':assets,'audited_source_files':inputs,
          'frozen_p13_manifest_sha256':sha(FROZEN/'manifest.json'),
          'frozen_p13_expected_manifest_sha256':'d799fbafc0b4d7b46c2e190586dd927d6512d73910acbe29f76235d0f9065a89'}
assert report['frozen_p13_manifest_sha256']==report['frozen_p13_expected_manifest_sha256']
(HERE/'height_diagnosis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for a in assets:
    print(a['asset'], 'quantiles', a['normalized_height_quantiles'])
    print('conditional_preset_mm',a['if_one_scene_unit_is_one_meter_at_author_preset'])
print('P13 manifest unchanged',report['frozen_p13_manifest_sha256'])
