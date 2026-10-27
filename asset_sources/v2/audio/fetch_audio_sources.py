"""Fetch only six approved, public CC0 source files; validate SHA256 before use."""
from pathlib import Path
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parent
SOURCES = json.loads((ROOT / 'sources.json').read_text(encoding='utf8'))


def main():
    directory = ROOT / 'downloads'
    directory.mkdir(parents=True, exist_ok=True)
    for source in SOURCES:
        destination = directory / source['source_file']
        if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == source['sha256']:
            print('Verified existing: ' + destination.name)
            continue
        request = urllib.request.Request(source['download_url'], headers={'User-Agent': 'LowAltitudeSquad-AssetFetch/2.1'})
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read(20 * 1024 * 1024)
        if hashlib.sha256(data).hexdigest() != source['sha256']:
            raise ValueError('Downloaded source differs from audited checksum: ' + destination.name)
        destination.write_bytes(data)
        print('Downloaded and verified: ' + destination.name)


if __name__ == '__main__':
    main()
