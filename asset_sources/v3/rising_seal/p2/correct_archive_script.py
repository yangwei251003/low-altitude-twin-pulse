"""Correct archival ordering: data was original, script copy occurred after edit."""
from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent;DEST=HERE/'envelope_reject_v1'
p=DEST/'build_rising_seal_p2.py';text=p.read_text(encoding='utf-8')
text=text.replace(' # Measured first trial exceeded front envelope by 6.74mm. Translate only the\n # exposed front centreline 12mm inward; retain its full rounded cross-section.\n controls=[(u,v,t-.012 if t>.10 else t,r) for u,v,t,r in controls]\n','')
text='\n'.join(line for line in text.split('\n') if not line.startswith('part_bounds='))
text=text.replace("'part_bounds_blender':part_bounds,",'')
p.write_text(text,encoding='utf-8')
manifest=json.loads((DEST/'archive.json').read_text(encoding='utf-8'))
for item in manifest['files']:
 path=DEST/item['name'];item['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();item['bytes']=path.stat().st_size
 item['provenance']='original source/log/report copied and hash-compared before rerun' if path!=p else 'pre-fix script restored by reversing the recorded 12mm/part-bounds patch; no independently captured original script hash'
manifest['archival_correction']='Initial script copy was made after the edit, unlike the three original data files. Corrected the script using the exact inverse edit; do not describe all four as independently verified pre-edit byte copies.'
(DEST/'archive.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Historical script restored; provenance distinguishes 3 original data files and inverse-patch script')
