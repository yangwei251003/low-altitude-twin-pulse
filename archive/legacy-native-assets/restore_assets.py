"""Verify and restore the additional, SHA-pinned legacy editable asset parts."""
from __future__ import annotations
import argparse,hashlib,json,os,stat,tempfile,urllib.request,zipfile
from pathlib import Path,PurePosixPath

HERE=Path(__file__).resolve().parent
PROJECT_ROOT=HERE.parents[1]
RELEASE_PREFIX='https://github.com/yangwei251003/low-altitude-twin-pulse/releases/download/'

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def target_path(root,name):
    path=PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(p in ('','..','.') for p in path.parts) or '\\' in name or ':' in name:
        raise ValueError('unsafe archive path')
    target=root.joinpath(*path.parts)
    for parent in (target,*target.parents):
        if parent==root.parent:break
        if parent.is_symlink() or (hasattr(parent,'is_junction') and parent.is_junction()):raise ValueError('link or reparse destination refused')
    if not target.resolve().is_relative_to(root.resolve()):raise ValueError('destination escaped selected directory')
    return target

def obtain(package,args):
    if args.local_dir:
        file=args.local_dir/package['file']
        if not file.is_file():raise FileNotFoundError('missing local part: '+package['file'])
        return file
    if not args.download:raise ValueError('provide --local-dir, or explicitly use --download')
    url=package['url']
    if not url.startswith(RELEASE_PREFIX):raise ValueError('unexpected download repository')
    cache=HERE/'.cache';cache.mkdir(exist_ok=True);file=cache/package['file']
    if file.exists():return file
    fd,name=tempfile.mkstemp(prefix='asset-',suffix='.part',dir=cache);os.close(fd);temporary=Path(name)
    try:
        with urllib.request.urlopen(url,timeout=90) as response,temporary.open('wb') as output:
            size=0
            while data:=response.read(1024*1024):
                size+=len(data)
                if size>package['bytes']:raise ValueError('download exceeds pinned size')
                output.write(data)
        if temporary.stat().st_size!=package['bytes'] or digest(temporary)!=package['sha256']:raise ValueError('download size or SHA mismatch')
        temporary.rename(file)
    finally:
        if temporary.exists():temporary.unlink()
    return file

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    source=parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--local-dir',type=Path,help='directory containing all four downloaded parts')
    source.add_argument('--download',action='store_true',help='explicitly download the pinned public GitHub parts')
    parser.add_argument('--destination',type=Path,default=PROJECT_ROOT)
    parser.add_argument('--verify-only',action='store_true',help='verify every entry without writing destination files')
    args=parser.parse_args(argv);spec=json.loads((HERE/'release-assets.json').read_text(encoding='utf-8'));root=args.destination.resolve()
    if args.destination.is_symlink() or (hasattr(args.destination,'is_junction') and args.destination.is_junction()):raise ValueError('destination must be an ordinary directory')
    packages=[];planned=[];seen=set();unchanged=0
    # Verify every archive, every entry, and every existing destination before any extraction.
    for package in spec['packages']:
        file=obtain(package,args)
        if file.stat().st_size!=package['bytes'] or digest(file)!=package['sha256']:raise ValueError('part size or SHA mismatch: '+package['file'])
        expected={row['path']:row for row in package['files']}
        if len(expected)!=len(package['files']):raise ValueError('duplicate manifest entry')
        with zipfile.ZipFile(file) as archive:
            infos=archive.infolist()
            if len(infos)!=len(expected) or {x.filename for x in infos}!=set(expected):raise ValueError('ZIP entry set differs from pinned manifest')
            for info in infos:
                row=expected[info.filename];target=target_path(root,info.filename)
                if info.filename in seen or info.is_dir() or stat.S_ISLNK(info.external_attr>>16) or info.file_size!=row['bytes']:raise ValueError('unexpected entry type, duplicate, or size')
                seen.add(info.filename)
                with archive.open(info) as stream:sha=hashlib.file_digest(stream,'sha256').hexdigest()
                if sha!=row['sha256']:raise ValueError('asset SHA mismatch: '+info.filename)
                if target.exists():
                    if not target.is_file() or target.stat().st_size!=row['bytes'] or digest(target)!=row['sha256']:raise FileExistsError('modified destination is protected: '+info.filename)
                    unchanged+=1
                else:planned.append((file,info.filename,target,row))
        packages.append(package)
    restored=0
    if not args.verify_only:
        for file,name,target,row in planned:
            target.parent.mkdir(parents=True,exist_ok=True);target_path(root,name)
            # Exclusive creation prevents an intervening user file from being replaced.
            with zipfile.ZipFile(file) as archive,archive.open(name) as incoming,target.open('xb') as output:
                while data:=incoming.read(1024*1024):output.write(data)
            if target.stat().st_size!=row['bytes'] or digest(target)!=row['sha256']:raise ValueError('restored file verification failed')
            restored+=1
    result={'parts_verified':len(packages),'entries_verified':len(seen),'restored_files':restored,'existing_identical_files':unchanged,'verify_only':args.verify_only,'old_release_parts_modified':False,'source_programs_or_game_executed':False}
    print(json.dumps(result))
    return 0

if __name__=='__main__':raise SystemExit(main())
