"""Bounded original-source acquisition only; does not invoke Blender or edit pixels."""
from pathlib import Path
import concurrent.futures, datetime, hashlib, json, urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCES = {
    'rocky_trail': ROOT/'asset_sources/v3/clinic_ground_transition/p10/vendor/polyhaven_rocky_trail',
    'sandy_gravel_02': ROOT/'asset_sources/v3/clinic_ground_transition/p9/vendor/polyhaven_sandy_gravel_02',
}

def fetch_one(asset, kind, record):
    url = record['url']
    dest = HERE/'inputs'/asset/url.rsplit('/', 1)[-1]
    if dest.exists():
        payload = dest.read_bytes()
    else:
        req = urllib.request.Request(url, headers={'User-Agent': 'LowAltitudeSquad-source-audit/1.0'})
        with urllib.request.urlopen(req, timeout=45) as response:
            payload = response.read(20_000_001)
        if len(payload) > 20_000_000:
            raise RuntimeError('Bounded acquisition exceeded 20MB per input')
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(payload)
    actual_md5 = hashlib.md5(payload).hexdigest()
    if len(payload) != record['size'] or actual_md5 != record['md5']:
        raise RuntimeError(f'Official size/MD5 mismatch: {asset}/{kind}')
    return {'asset': asset, 'kind': kind, 'url': url,
            'path': str(dest.relative_to(ROOT)).replace('\\', '/'),
            'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest(),
            'official_md5': actual_md5, 'official_size_and_md5_match': True,
            'license': 'CC0-1.0', 'license_url': 'https://polyhaven.com/license',
            'asset_url': f'https://polyhaven.com/a/{asset}',
            'pixels_modified': False, 'executed_as_code': False}

jobs = []
for asset, vendor in SOURCES.items():
    data = json.loads((vendor/'files.json').read_text(encoding='utf-8-sig'))
    for kind, entry in [('DisplacementPNG', data['Displacement']['2k']['png']),
                        ('MaterialXText', data['mtlx']['2k']['mtlx'])]:
        jobs.append((asset, kind, entry))
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    acquired = list(pool.map(lambda args: fetch_one(*args), jobs))
report = {'retrieved_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'scope': 'Two original 2K height PNGs and two small author MaterialX files only. No dependencies fetched; XML not executed.',
          'records': acquired}
(HERE/'acquisition.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
for row in acquired:
    print(row['asset'], row['kind'], row['bytes'], row['sha256'])
