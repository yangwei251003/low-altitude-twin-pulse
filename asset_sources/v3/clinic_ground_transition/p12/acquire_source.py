"""Bounded official input acquisition. No Blender, image edits or model edits."""
from pathlib import Path
import urllib.request, json, hashlib, concurrent.futures
from PIL import Image

HERE=Path(__file__).resolve().parent
OUT=HERE/'inputs/polyhaven_rock_07_1k'
HEAD={'User-Agent':'LowAltitudeSquadAssetAudit/1.0 (Powered by Poly Haven; single-rock study)'}
def get(url,cap):
    with urllib.request.urlopen(urllib.request.Request(url,headers=HEAD),timeout=30) as response:
        data=response.read(cap+1)
        assert len(data)<=cap,(url,len(data))
        return data
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    info_raw=get('https://api.polyhaven.com/info/rock_07',100_000)
    files_raw=get('https://api.polyhaven.com/files/rock_07',200_000)
    info=json.loads(info_raw);files=json.loads(files_raw)
    chosen=[('editable_source',files['blend']['1k']['blend'])]+[(role,files[key]['1k']['png']) for role,key in [('base_color','Diffuse'),('tangent_normal_gl','nor_gl'),('ambient_rough_metal','arm')]]
    def acquire(item):
        role,record=item;name=record['url'].split('/')[-1];path=OUT/name
        data=path.read_bytes() if path.exists() else get(record['url'],5_000_000)
        assert len(data)==record['size'] and hashlib.md5(data).hexdigest()==record['md5'],name
        if not path.exists():path.write_bytes(data)
        row={'role':role,'file':name,'url':record['url'],'bytes':len(data),'sha256':sha(data),'official_md5':record['md5'],'official_md5_match':True}
        if path.suffix=='.png':
            with Image.open(path) as image:
                row.update(pixel_size=list(image.size),image_mode=image.mode,first_pixel=list(image.getpixel((0,0))) if isinstance(image.getpixel((0,0)),tuple) else image.getpixel((0,0)))
                assert image.size==(1024,1024)
        return row
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:records=list(pool.map(acquire,chosen))
    for name,data in [('official_info.json',info_raw),('official_files.json',files_raw)]:
        path=OUT/name
        assert not path.exists() or path.read_bytes()==data,'Do not overwrite prior metadata snapshot'
        path.write_bytes(data)
    report={'asset':'Rock 07','author':'Jenelle van Heerden','asset_url':'https://polyhaven.com/a/rock_07','license':'CC0','license_url':'https://polyhaven.com/license','api_terms_url':'https://github.com/Poly-Haven/Public-API/blob/master/ToS.md','scope':'One native LOD3 natural stone only; not concrete; no model execution at acquisition.','format_choice':'Unchanged official lossless 1K PNG maps chosen instead of smaller JPEG downloads; avoids adding normal-map JPEG compression. These are not upscaled images.','actual_files':records,'total_asset_bytes':sum(r['bytes'] for r in records),'api_metadata_sha256':{'info':sha(info_raw),'files':sha(files_raw)},'native_source_note':'Native material relative EXR references are preserved in original blend. Study appends only chosen mesh and creates standard material using the three authorized PNG maps; roughness from ARM G. Original blend is never rewritten.'}
    (OUT/'provenance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
