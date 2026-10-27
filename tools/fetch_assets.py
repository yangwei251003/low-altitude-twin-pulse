"""Restore versioned project assets from public, SHA-256 pinned release archives."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, os, stat, tempfile, urllib.request, zipfile

ROOT=Path(__file__).resolve().parents[1]
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def target_path(root,name):
    p=PurePosixPath(name)
    if p.is_absolute() or not p.parts or any(x in ('','..','.') for x in p.parts) or '\\' in name or ':' in name:raise ValueError('unsafe archive path')
    target=root.joinpath(*p.parts)
    for parent in (target,*target.parents):
        if parent==root.parent:break
        if parent.is_symlink() or parent.is_junction():raise ValueError('link/reparse target refused')
    if not target.resolve().is_relative_to(root.resolve()):raise ValueError('target escaped destination')
    return target
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--runtime-only',action='store_true',help='restore only playable runtime assets')
    group.add_argument('--editable-only',action='store_true',help='restore only editable source assets')
    parser.add_argument('--local-dir',type=Path,help='directory containing the exact downloaded ZIPs')
    parser.add_argument('--destination',type=Path,default=ROOT,help='explicit destination project directory')
    parser.add_argument('--verify-only',action='store_true',help='verify every ZIP entry without extracting files')
    parser.add_argument('--force',action='store_true',help='explicitly replace modified asset files after verification')
    args=parser.parse_args()
    spec=json.loads((ROOT/'release-assets.json').read_text(encoding='utf-8'))
    dest=args.destination.resolve();dest.mkdir(parents=True,exist_ok=True)
    if dest.is_symlink() or dest.is_junction():raise ValueError('destination must be an ordinary directory')
    packages=[p for p in spec['packages'] if not (args.runtime_only and p['id']!='runtime') and not (args.editable_only and p['id']!='editable')]
    cache=ROOT/'.runtime/asset-downloads';cache.mkdir(parents=True,exist_ok=True)
    for package in packages:
        archive=(args.local_dir/package['file']) if args.local_dir else cache/package['file']
        if not archive.exists():
            if args.local_dir:raise FileNotFoundError('missing local asset ZIP: '+package['file'])
            url=package['url']
            if not url.startswith('https://github.com/yangwei251003/low-altitude-twin-pulse/releases/download/'):raise ValueError('unexpected release source')
            print('Downloading',package['file'],flush=True)
            fd,temp=tempfile.mkstemp(prefix='download-',suffix='.part',dir=cache);os.close(fd);temp=Path(temp)
            try:
                with urllib.request.urlopen(url,timeout=90) as response,temp.open('wb') as f:
                    total=0
                    for block in iter(lambda:response.read(1024*1024),b''):
                        total+=len(block)
                        if total>package['bytes']:raise ValueError('download exceeds pinned size')
                        f.write(block)
                if temp.stat().st_size!=package['bytes'] or digest(temp)!=package['sha256']:raise ValueError('download checksum mismatch')
                os.replace(temp,archive)
            finally:
                if temp.exists():temp.unlink()
        if archive.stat().st_size!=package['bytes'] or digest(archive)!=package['sha256']:raise ValueError('archive SHA-256/size mismatch: '+package['file'])
        expected={r['path']:r for r in package['files']}
        verified=restored=0
        with zipfile.ZipFile(archive) as z:
            names=z.namelist()
            if len(names)!=len(set(names)) or set(names)!=set(expected):raise ValueError('archive paths do not exactly match the manifest')
            for info in z.infolist():
                row=expected[info.filename];target=target_path(dest,info.filename)
                if info.is_dir() or stat.S_ISLNK(info.external_attr>>16) or info.file_size!=row['bytes']:raise ValueError('unsupported entry or incorrect size')
                keep=False
                if not args.verify_only and target.exists():
                    if not target.is_file():raise ValueError('existing target is not a file')
                    keep=target.stat().st_size==row['bytes'] and digest(target)==row['sha256']
                    if not keep and not args.force:raise ValueError('modified asset preserved; review before using --force: '+info.filename)
                output=None;temp=None
                if not args.verify_only and not keep:
                    target.parent.mkdir(parents=True,exist_ok=True)
                    fd,name=tempfile.mkstemp(prefix='.restore-',dir=target.parent);output=os.fdopen(fd,'wb');temp=Path(name)
                h=hashlib.sha256();size=0
                try:
                    with z.open(info) as stream:
                        for block in iter(lambda:stream.read(1024*1024),b''):
                            size+=len(block)
                            if size>row['bytes']:raise ValueError('entry exceeds pinned size')
                            h.update(block)
                            if output:output.write(block)
                    if output:output.close();output=None
                    if size!=row['bytes'] or h.hexdigest()!=row['sha256']:raise ValueError('asset checksum mismatch')
                    if temp:os.replace(temp,target);temp=None;restored+=1
                    verified+=1
                finally:
                    if output:output.close()
                    if temp and temp.exists():temp.unlink()
        print(f'{package["id"]}: verified {verified}, restored {restored}',flush=True)
    print('Asset verification complete. Preserve original local projects; this public snapshot has documented omissions.')
if __name__=='__main__':main()
