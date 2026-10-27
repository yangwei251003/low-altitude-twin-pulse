"""Fetch a small licensed selection, preserving sources and hashes."""
from pathlib import Path
import urllib.request, json, zipfile, hashlib, concurrent.futures
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'asset_sources/third_party'; CACHE.mkdir(parents=True,exist_ok=True)
def get(url):
    req=urllib.request.Request(url,headers={'User-Agent':'LowAltitudeHangar-AssetPreparation/0.1'})
    with urllib.request.urlopen(req,timeout=90) as r: return r.read()
def archive(name,url):
    dest=CACHE/(name+'.zip')
    if not dest.exists():dest.write_bytes(get(url))
    folder=CACHE/name; folder.mkdir(exist_ok=True)
    with zipfile.ZipFile(dest) as z:
        for i in z.infolist():
            if not (folder/i.filename).resolve().is_relative_to(folder.resolve()):raise ValueError('Unsafe archive path')
        z.extractall(folder)
    return {'asset':name,'url':url,'license':'CC0-1.0','sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
urls={
 'kenney_industrial':'https://kenney.nl/media/pages/assets/city-kit-industrial/0ec35b139d-1788171848/kenney_city-kit-industrial_2.0.zip',
 'kenney_nature':'https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip',
 'kenney_particles':'https://kenney.nl/media/pages/assets/particle-pack/f8fe0f8cb8-1677578741/kenney_particle-pack.zip'}
records=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for r in pool.map(lambda item:archive(*item),urls.items()):
        records.append(r);print('FETCHED',r['asset'],flush=True)
for asset in ['sandstone_blocks_04','aerial_grass_rock','rock_boulder_dry']:
    try:
        info=json.loads(get('https://api.polyhaven.com/files/'+asset))
        (CACHE/(asset+'.json')).write_text(json.dumps(info,indent=2),encoding='utf-8')
        print('POLYHAVEN',asset,list(info),flush=True)
        for channel in ['Diffuse','nor_gl','Rough']:
            if channel not in info or '1k' not in info[channel]:continue
            options=info[channel]['1k'];entry=options.get('jpg',options.get('png'))
            if not entry:continue
            url=entry['url'];dest=ROOT/'assets/textures'/asset/Path(url).name;dest.parent.mkdir(parents=True,exist_ok=True)
            if not dest.exists():dest.write_bytes(get(url))
            records.append({'asset':asset+'/'+channel,'url':url,'license':'CC0-1.0','sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'path':str(dest.relative_to(ROOT))})
    except Exception as e:print('OPTIONAL_TEXTURE_FAILED',asset,str(e),flush=True)
(ROOT/'docs/asset_sources.json').write_text(json.dumps(records,indent=2,ensure_ascii=False),encoding='utf-8')
print('RESOURCE_FETCH_COMPLETE',flush=True)
