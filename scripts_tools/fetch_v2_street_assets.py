"""Download selected CC0 Kenney packs into the V2 street source archive."""
from pathlib import Path
import concurrent.futures, hashlib, json, urllib.request, zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'asset_sources/v2/streets/third_party'
PACKS = {
    'kenney_car_kit': ('https://kenney.nl/assets/car-kit', 'https://kenney.nl/media/pages/assets/car-kit/1a312ec241-1775131960/kenney_car-kit.zip'),
    'kenney_commercial': ('https://kenney.nl/assets/city-kit-commercial', 'https://kenney.nl/media/pages/assets/city-kit-commercial/a742d900eb-1753115042/kenney_city-kit-commercial_2.1.zip'),
    'kenney_roads': ('https://kenney.nl/assets/city-kit-roads', 'https://kenney.nl/media/pages/assets/city-kit-roads/74288c9459-1791628607/kenney_city-kit-roads.zip'),
}

def fetch(item):
    name, (page, url) = item
    DEST.mkdir(parents=True, exist_ok=True)
    dest = DEST / (name + '.zip')
    if not dest.exists():
        req = urllib.request.Request(url, headers={'User-Agent': 'LowAltitudeSquad-V2-AssetPreparation/2.0'})
        with urllib.request.urlopen(req, timeout=120) as response:
            dest.write_bytes(response.read())
    folder = DEST / name
    folder.mkdir(exist_ok=True)
    with zipfile.ZipFile(dest) as archive:
        for entry in archive.infolist():
            if not (folder / entry.filename).resolve().is_relative_to(folder.resolve()):
                raise ValueError('Archive path outside destination')
        archive.extractall(folder)
    record = dict(name=name, author='Kenney', page=page, download=url, license='CC0-1.0',
        license_url='https://creativecommons.org/publicdomain/zero/1.0/',
        sha256=hashlib.sha256(dest.read_bytes()).hexdigest(), bytes=dest.stat().st_size,
        retrieved='2026-10-14', archive=str(dest.relative_to(ROOT)).replace('\\', '/'))
    print('FETCHED', name, record['bytes'], flush=True)
    return record

if __name__ == '__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        records = list(pool.map(fetch, PACKS.items()))
    (DEST / 'provenance.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
