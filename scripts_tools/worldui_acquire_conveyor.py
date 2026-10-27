"""Download the free CC0 author distribution; never logs temporary download tokens."""
from pathlib import Path
import requests, re, html, zipfile, io, json, hashlib
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/source/worldui/conveyor_kenney';DEST.mkdir(parents=True,exist_ok=True)
base='https://kenney-assets.itch.io/conveyor-kit'
session=requests.Session()
def token(page):
 match=re.search(r'<meta\s+name="csrf_token"\s+value="([^"]+)"',page)
 if not match:match=re.search(r'<meta\s+name="csrf_token"\s+content="([^"]+)"',page)
 if not match:raise ValueError('Author page did not expose a CSRF token')
 return html.unescape(match.group(1))
page=session.get(base+'/purchase',timeout=30);page.raise_for_status()
r=session.post(base+'/download_url',data={'csrf_token':token(page.text)},timeout=30);r.raise_for_status()
url=r.json()['url'];page=session.get(url,timeout=30);page.raise_for_status()
file_id=re.search(r'data-upload_id="(\d+)"',page.text)
if not file_id:raise ValueError('Author download file ID missing')
r=session.post(base+'/file/'+file_id.group(1),data={'csrf_token':token(page.text)},timeout=30);r.raise_for_status()
r=session.get(r.json()['url'],timeout=60);r.raise_for_status();data=r.content
(DEST/'kenney_conveyor-kit.zip').write_bytes(data)
archive=zipfile.ZipFile(io.BytesIO(data))
for entry in archive.infolist():
 target=(DEST/entry.filename).resolve()
 if not target.is_relative_to(DEST.resolve()):raise ValueError('Unsafe archive path')
archive.extractall(DEST)
(DEST/'SOURCE.json').write_text(json.dumps({'author':'Kenney','source':base,'license':'CC0-1.0','retrieved':'2026-10-16','sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)},indent=2),encoding='utf-8')
print(json.dumps({'downloaded_bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'glb_count':len(list(DEST.rglob('*.glb')))}))
