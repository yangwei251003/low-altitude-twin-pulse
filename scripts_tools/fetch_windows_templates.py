from pathlib import Path
import io, urllib.request, zipfile, hashlib, json, os, time

URL = 'https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
ROOT = Path(__file__).resolve().parents[1]

def get_range(start, end):
    for attempt in range(3):
        try:
            req = urllib.request.Request(URL, headers={'User-Agent':'LowAltitudeDev/0.1','Range':f'bytes={start}-{end}'})
            with urllib.request.urlopen(req, timeout=60) as r:
                if r.status != 206: raise RuntimeError('Server did not honor range')
                data = r.read()
                if len(data) != end-start+1: raise RuntimeError('Incomplete range')
                return data, r.headers['Content-Range']
        except Exception:
            if attempt == 2: raise
            time.sleep(2)

class RemoteZip(io.RawIOBase):
    def __init__(self):
        _, content_range = get_range(0,0)
        self.length = int(content_range.split('/')[-1])
        self.pos = 0
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos+offset if whence == 1 else self.length+offset)
        return self.pos
    def read(self, size=-1):
        size = self.length-self.pos if size < 0 else min(size,self.length-self.pos)
        parts = []
        while size > 0:
            count = min(size, 4*1024*1024)
            part,_ = get_range(self.pos, self.pos+count-1)
            parts.append(part)
            self.pos += count
            size -= count
        return b''.join(parts)

def install_templates():
    dest = Path(os.environ['APPDATA'])/'Godot/export_templates/4.7.2.stable'
    dest.mkdir(parents=True,exist_ok=True)
    expected = {
        'windows_release_x86_64.exe':'d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562',
        'windows_debug_x86_64.exe':'51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107',
        'version.txt':'38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e',
    }
    evidence = []
    missing = []
    for name, digest in expected.items():
        path = dest/name
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == digest:
            evidence.append({'name':name,'bytes':path.stat().st_size,'sha256':digest,'verified_existing':True})
        else:
            missing.append(name)
    if missing:
      with zipfile.ZipFile(RemoteZip()) as z:
        for name in missing:
            matches = [i for i in z.infolist() if Path(i.filename).name == name]
            if len(matches)!=1: raise RuntimeError('Missing '+name)
            info = matches[0]
            print(f'Fetching {name}: {info.compress_size} compressed bytes',flush=True)
            data = z.read(info)
            if hashlib.sha256(data).hexdigest() != expected[name]: raise RuntimeError('Template checksum mismatch: '+name)
            (dest/name).write_bytes(data)
            item = {'name':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'zip_crc_verified':True}
            evidence.append(item)
            print(json.dumps(item),flush=True)
    result={'source':URL,'files':evidence}
    (ROOT/'artifacts').mkdir(exist_ok=True)
    (ROOT/'artifacts/windows_templates.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    return result

if __name__ == '__main__':
    print(json.dumps(install_templates()),flush=True)
