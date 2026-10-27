from pathlib import Path
import json,urllib.request,hashlib
HERE=Path(__file__).resolve().parent
for asset in ['rock_face_01','rock_face_02']:
 folder=HERE/'vendor'/asset;folder.mkdir(parents=True,exist_ok=True)
 for kind in ['info','files']:
  url=f'https://api.polyhaven.com/{kind}/{asset}'
  request=urllib.request.Request(url,headers={'User-Agent':'LowAltitudeTwinPulseAssetStudy/1.0 (CC0 geometry source research)'})
  data=urllib.request.urlopen(request,timeout=30).read();(folder/f'{kind}.json').write_bytes(data)
  j=json.loads(data)
  if kind=='info':print(asset,json.dumps({'name':j.get('name'),'authors':j.get('authors'),'type':j.get('type')}))
  else:print(asset,json.dumps(j.get('gltf',{}).get('1k',{}),indent=2))
