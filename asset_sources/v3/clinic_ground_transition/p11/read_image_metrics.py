"""Read-only image comparison numbers; no rendered-image editing or output."""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / 'source_review_01'
report = json.loads((OUT / 'study_report.json').read_text(encoding='utf-8'))
selected = json.loads((HERE / 'selected_stones.json').read_text(encoding='utf-8'))
arrays = [np.asarray(Image.open(OUT / row['file']).convert('RGB'), dtype=np.int16) for row in report['renders']]
height, width = arrays[0].shape[:2]
x, y, z = report['camera']['rotation']
cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
rx = np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])
ry = np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])
rz = np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])
rotation = rz @ ry @ rx
camera = np.array(report['camera']['location'])
pixels_per_m = width / report['camera']['ortho_scale_m']
projected = []
for row in selected['stones']:
    gx, gy, gz = row['ground_center']
    # This is only the reported ground-center marker, not silhouette/visibility.
    local = rotation.T @ (np.array([gx, -gz, gy]) - camera)
    projected.append({'object':row['name'], 'ground_center_pixel':[width / 2 + local[0] * pixels_per_m, height / 2 - local[1] * pixels_per_m], 'not_a_visibility_measure':True})
comparisons = []
for label, a, b in [('A_to_B', arrays[0], arrays[1]), ('B_to_C', arrays[1], arrays[2])]:
    difference = np.abs(a-b)
    changed = difference.max(axis=2) > 8
    yy, xx = np.where(changed)
    comparisons.append({'comparison':label, 'mean_absolute_rgb_8bit':float(difference.mean()), 'max_absolute_rgb_8bit':int(difference.max()), 'pixels_max_channel_gt8':int(changed.sum()), 'fraction_max_channel_gt8':float(changed.mean()), 'bounding_box_xyxy_gt8':[int(xx.min()),int(yy.min()),int(xx.max()),int(yy.max())] if len(xx) else None})
(OUT / 'image_difference_readback.json').write_text(json.dumps({'purpose':'Read-only differences aid locating the three study objects; neither differences nor pixel coverage prove art acceptance or true visibility.', 'image_size':[width,height], 'projected_ground_centers':projected, 'comparisons':comparisons}, ensure_ascii=False, indent=2),encoding='utf-8')
print(json.dumps({'projected':projected,'comparisons':comparisons},ensure_ascii=False))
