from pathlib import Path
import json,hashlib,urllib.request,concurrent.futures
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'asset_sources/third_party'
tasks=[]
for asset in ['island_tree_01','shrub_01','coast_rocks_01']:
    info=json.loads((CACHE/(asset+'.json')).read_text())['gltf']['1k']['gltf']
    folder=CACHE/asset
    tasks.append((folder/Path(info['url']).name,info))
    tasks.extend((folder/path,item) for path,item in info['include'].items())
def download(task):
    path,item=task;path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists() and hashlib.md5(path.read_bytes()).hexdigest()==item['md5']:return
    req=urllib.request.Request(item['url'],headers={'User-Agent':'LowAltitudeHangar-AssetPreparation/0.1'})
    with urllib.request.urlopen(req,timeout=100) as response:data=response.read()
    if len(data)!=item['size'] or hashlib.md5(data).hexdigest()!=item['md5']:raise ValueError('Download failed integrity: '+str(path))
    path.write_bytes(data);print('VERIFIED',path.name,len(data),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(download,tasks))
out=[]
for path,item in tasks:out.append({'path':str(path.relative_to(ROOT)),'url':item['url'],'md5':item['md5'],'license':'CC0-1.0'})
(ROOT/'docs/polyhaven_models.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('MODEL_FETCH_COMPLETE',flush=True)
