"""Download and reassemble independently SHA-256 pinned release segments.

The original ZIP is reconstructed exactly and may then be passed to the
existing asset restore scripts with --local-dir. No game executable is run.
"""
from pathlib import Path
import argparse, hashlib, json, os, tempfile, urllib.request

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'https://github.com/yangwei251003/low-altitude-twin-pulse/releases/download/'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def safe_name(name):
    if not name or Path(name).name != name or '/' in name or '\\' in name or ':' in name or name in ('.', '..'):
        raise ValueError('unsafe filename')
    return name

def validate_file(path, size, sha):
    return path.is_file() and path.stat().st_size == size and digest(path) == sha

def assemble(package, output_dir, cache, local_parts=None):
    name = safe_name(package['file'])
    output_dir.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    destination = output_dir / name
    if destination.exists():
        if not validate_file(destination, package['bytes'], package['sha256']):
            raise FileExistsError('existing output differs; preserved: ' + name)
        return destination
    fd, temp_name = tempfile.mkstemp(prefix='.assemble-', dir=output_dir)
    os.close(fd)
    temporary = Path(temp_name)
    whole, total = hashlib.sha256(), 0
    try:
        with temporary.open('wb') as out:
            for part in package['parts']:
                part_name = safe_name(part['file'])
                path = (local_parts / part_name) if local_parts else cache / part_name
                if not path.exists():
                    if local_parts:
                        raise FileNotFoundError('missing local segment: ' + part_name)
                    url = part['url']
                    if not url.startswith(PREFIX) or url.rsplit('/', 1)[-1] != part_name:
                        raise ValueError('unexpected segment URL')
                    fd, name_tmp = tempfile.mkstemp(prefix='.download-', dir=cache)
                    os.close(fd)
                    download = Path(name_tmp)
                    try:
                        with urllib.request.urlopen(url, timeout=120) as response, download.open('wb') as stream:
                            size = 0
                            while block := response.read(1024 * 1024):
                                size += len(block)
                                if size > part['bytes']:
                                    raise ValueError('segment exceeds pinned size')
                                stream.write(block)
                        if not validate_file(download, part['bytes'], part['sha256']):
                            raise ValueError('segment checksum mismatch')
                        os.replace(download, path)
                    finally:
                        if download.exists(): download.unlink()
                if not validate_file(path, part['bytes'], part['sha256']):
                    raise ValueError('segment checksum mismatch: ' + part_name)
                with path.open('rb') as incoming:
                    while block := incoming.read(1024 * 1024):
                        total += len(block)
                        if total > package['bytes']:
                            raise ValueError('assembled ZIP exceeds pinned size')
                        whole.update(block)
                        out.write(block)
        if total != package['bytes'] or whole.hexdigest() != package['sha256']:
            raise ValueError('assembled ZIP checksum mismatch')
        # Exclusive creation prevents replacing a file appearing during assembly.
        with destination.open('xb') as out, temporary.open('rb') as incoming:
            while block := incoming.read(1024 * 1024): out.write(block)
        if not validate_file(destination, package['bytes'], package['sha256']):
            raise ValueError('output verification failed')
        return destination
    finally:
        if temporary.exists(): temporary.unlink()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', action='append', default=[], help='exact ZIP filename; repeat to select')
    parser.add_argument('--group', action='append', choices=['runtime', 'editable', 'windows', 'legacy'], default=[], help='release group; repeat to select')
    parser.add_argument('--output-dir', type=Path, default=ROOT / '.runtime/asset-zips')
    parser.add_argument('--local-parts', type=Path, help='use already downloaded segments instead of network')
    args = parser.parse_args()
    spec = json.loads((ROOT / 'release-segments.json').read_text(encoding='utf8'))
    packages = [p for p in spec['packages'] if (not args.only and not args.group) or p['file'] in args.only or p['group'] in args.group]
    if args.only and set(args.only) != {p['file'] for p in packages}: raise ValueError('unknown ZIP selection')
    for package in packages:
        result = assemble(package, args.output_dir, ROOT / '.runtime/segments', args.local_parts)
        print('Verified ZIP:', result, flush=True)

if __name__ == '__main__': main()
