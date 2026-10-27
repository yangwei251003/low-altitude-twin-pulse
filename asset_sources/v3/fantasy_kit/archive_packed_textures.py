"""Extract each locked .blend's authoritative packed PNG bytes to its own texture folder.
No model save, export, render or GPU. Avoids same-name maps from different builds colliding.
"""
import bpy,hashlib,json
from pathlib import Path
SOURCE=Path(__file__).resolve().parent
manifest={}
for asset in ('rootstone_terrace','photosensitive_roots'):
    source=SOURCE/(asset+'.blend');before=hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    target=SOURCE/'textures'/asset;target.mkdir(parents=True,exist_ok=True)
    records=[]
    for img in bpy.data.images:
        if not img.name.startswith('FKit_') or not img.packed_file:continue
        data=bytes(img.packed_file.data)
        assert data.startswith(b'\x89PNG\r\n\x1a\n'),img.name
        path=target/(img.name+'.png');path.write_bytes(data)
        records.append({'file':str(path.relative_to(SOURCE)),'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
    assert len(records)==12,(asset,len(records))
    assert before==hashlib.sha256(source.read_bytes()).hexdigest()
    manifest[asset]={'source_sha256':before,'maps':records,'source_unchanged':True}
(SOURCE/'textures'/'packed_texture_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(manifest))
