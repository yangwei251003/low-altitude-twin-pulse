"""Prepare only the pinned MIT-licensed GUT development addon in this project."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,urllib.request,zipfile,stat
ROOT=Path(__file__).resolve().parents[1]
URL='https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip'
SHA='14969aa46adc84aa08cdd21b9f6d1a64addd92ae60b36f02d0521ed305aa4086'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--archive',type=Path);p.add_argument('--verify-only',action='store_true');args=p.parse_args()
 archive=args.archive or ROOT/'.runtime/dependencies/gut-9.7.1.zip'
 if not archive.exists():
  if args.archive:raise FileNotFoundError(archive)
  archive.parent.mkdir(parents=True,exist_ok=True)
  with urllib.request.urlopen(URL,timeout=90) as response:
   data=response.read(20*1024*1024+1)
  if len(data)>20*1024*1024 or hashlib.sha256(data).hexdigest()!=SHA:raise ValueError('GUT archive checksum mismatch')
  archive.write_bytes(data)
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA:raise ValueError('GUT archive checksum mismatch')
 count=0
 with zipfile.ZipFile(archive) as z:
  for item in z.infolist():
   q=PurePosixPath(item.filename)
   if '..' in q.parts or q.is_absolute() or stat.S_ISLNK(item.external_attr>>16):raise ValueError('unsafe archive member')
   parts=q.parts
   if len(parts)<4 or parts[1:3]!=('addons','gut') or item.is_dir():continue
   rel=Path(*parts[1:]);dest=ROOT/rel
   for ancestor in (dest,*dest.parents):
    if ancestor==ROOT.parent:break
    if ancestor.is_symlink() or ancestor.is_junction():raise ValueError('link target refused')
   data=z.read(item)
   if dest.exists() and dest.read_bytes()!=data:
    try:same_text=dest.read_bytes().decode('utf-8').replace('\r\n','\n')==data.decode('utf-8').replace('\r\n','\n')
    except UnicodeDecodeError:same_text=False
    if not same_text:raise ValueError('existing addon differs; preserve/review before replacing: '+str(rel))
   if not args.verify_only and not dest.exists():dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
   count+=1
 if count<100:raise ValueError('GUT archive structure not recognized')
 print(f'GUT 9.7.1: pinned archive verified, {count} addon files checked; '+('not installed' if args.verify_only else 'ready'))
if __name__=='__main__':main()
