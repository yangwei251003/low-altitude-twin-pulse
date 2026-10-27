"""Download pinned, official development dependencies. Does not modify PATH."""
from pathlib import Path
import concurrent.futures, hashlib, json, os, urllib.request, zipfile, shutil

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.tools' / 'downloads'
CACHE.mkdir(parents=True, exist_ok=True)
(ROOT / '.tools' / '.gdignore').touch()
(ROOT / 'artifacts').mkdir(exist_ok=True)

def fetch(url, filename):
    path = CACHE / filename
    if not path.exists():
        temp = path.with_suffix(path.suffix + '.part')
        req = urllib.request.Request(url, headers={'User-Agent': 'LowAltitudeDev/0.1'})
        with urllib.request.urlopen(req, timeout=90) as response, temp.open('wb') as output:
            shutil.copyfileobj(response, output, 1024 * 1024)
        temp.replace(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(json.dumps({'download': filename, 'bytes': path.stat().st_size, 'sha256': digest}), flush=True)
    return path, digest

def gut():
    url = 'https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip'
    archive, digest = fetch(url, 'gut-9.7.1.zip')
    if digest != '14969aa46adc84aa08cdd21b9f6d1a64addd92ae60b36f02d0521ed305aa4086':
        raise RuntimeError('GUT 9.7.1 checksum mismatch')
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            marker = '/addons/gut/'
            if marker not in info.filename or info.is_dir():
                continue
            relative = info.filename.split(marker, 1)[1]
            dest = ROOT / 'addons' / 'gut' / relative
            if not dest.resolve().is_relative_to((ROOT / 'addons' / 'gut').resolve()):
                raise ValueError('Unsafe archive path')
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(z.read(info))
    return {'name': 'GUT', 'version': '9.7.1', 'source': url, 'sha256': digest}

def templates():
    from fetch_windows_templates import install_templates
    result = install_templates()
    return {'name':'Godot Windows templates','version':'4.7.2.stable',**result}

if __name__ == '__main__':
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(fn): fn.__name__ for fn in (gut, templates)}
        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result()
                results.append(result)
                print(json.dumps(result), flush=True)
            except Exception as error:
                results.append({'name': futures[future], 'error': str(error)})
                print(str(error), flush=True)
    (ROOT / 'artifacts' / 'dependencies.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    raise SystemExit(1 if any('error' in result for result in results) else 0)
