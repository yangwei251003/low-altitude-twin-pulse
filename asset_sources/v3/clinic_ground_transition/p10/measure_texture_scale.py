"""Read-only image/sampling analysis; no image manipulation or material edits."""
from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parent
section=json.loads((P/'p9_cross_sections.json').read_text())
bake_density=section['baked_effective_texels_per_meter_quantiles'][1]
rows=[]
for name,width,folder in [('sandy_gravel_02',2.5,P.parent/'p9/vendor/polyhaven_sandy_gravel_02'),('rocky_trail',2.0,P/'vendor/polyhaven_rocky_trail')]:
    normal=folder/(name+'_nor_gl_2k.png')
    a=np.asarray(Image.open(normal).convert('RGB'),dtype=np.float64)/255
    n=a.shape[0];fx=np.fft.rfftfreq(n,d=width/n);fy=np.fft.fftfreq(n,d=width/n)
    radial=np.hypot(fx[None,:],fy[:,None]);wavelength=np.divide(1,radial,out=np.full_like(radial,np.inf),where=radial!=0)
    power=np.zeros_like(radial)
    for channel in (0,1):
        values=a[:,:,channel]-np.mean(a[:,:,channel]);fft=np.fft.rfft2(values);power+=np.abs(fft)**2
    power[:,1:-1]*=2;power[0,0]=0;total=float(power.sum())
    ranges=[(0,.01),(.01,.05),(.05,.15),(.15,float('inf'))]
    bands=[{'wavelength_m':[lo,None if not np.isfinite(hi) else hi],'normal_xy_power_percent':float(power[(wavelength>=lo)&(wavelength<hi)].sum()/total*100)} for lo,hi in ranges]
    row={'material':name,'source_width_m':width,'source_resolution':list(a.shape[:2]),'source_pixel_pitch_m':width/n,'normal_sha256':hashlib.sha256(normal.read_bytes()).hexdigest(),'normal_xy_radial_power':bands,'normal_xy_power_below_p9_two_texel_wavelength_percent':float(power[wavelength<2/bake_density].sum()/total*100),'two_baked_texels_m':2/bake_density}
    rows.append(row)
out={'method':'Read-only FFT of original NormalGL R/G after subtracting channel means; radial wavelength uses official physical width. This is a surface-detail frequency statistic, not stone segmentation, pebble size, or camera visibility. Tile-edge energy and source compression/bit conversion can contribute. Native images remain unchanged.','p9_actual_baked_density_px_per_m':bake_density,'p9_baked_pixel_pitch_m':1/bake_density,'materials':rows,'limits':['P9 source scan UV really is 2.5m. Its single 2K asset atlas allocates only about 198 pixels per meter to soil. Much of the source fine detail therefore lies below two baked texels; this is a sampling limitation, not proof that every small feature disappears.','Rocky Trail is a static comparison only. No new P10 shader, bake or render was run.']}
(P/'texture_world_scale.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))
