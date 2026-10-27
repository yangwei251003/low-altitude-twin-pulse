"""Freeze exactly the input bytes and five real camera views of the rack review."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tests_v3/candidates/canal_calibration_art/evidence/gpu_20261020'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    assert not OUT.exists(), 'Evidence is immutable; choose a new dated directory.'
    OUT.mkdir(parents=True)
    (OUT/'.gdignore').write_text('',encoding='utf-8')
    (OUT/'.gitattributes').write_text('* -text\n',encoding='utf-8')
    source=ROOT/'artifacts/v3/art/calibration-rack-probe-20261020_043005_63c444'
    wanted=json.loads((source/'inputs.json').read_text(encoding='utf-8'))
    for relative,digest in wanted.items():
        current=ROOT/relative
        assert sha(current)==digest,relative
        target=OUT/'inputs'/relative;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(current,target)
    for name in ['calibration-rack-import-20261020_042825_b3b245',source.name]:
        directory=ROOT/'artifacts/v3/art'/name
        for path in directory.iterdir():
            if path.is_file():
                target=OUT/'actual'/name/path.name;target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(path,target)
    rows=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}
          for p in sorted(OUT.rglob('*')) if p.is_file()]
    manifest={'scope':'31 real scripted player/work checks and 5 actual GPU views; no human/performance/MAIN/LAN claim',
              'files':rows,'file_count':len(rows),'bytes':sum(r['bytes'] for r in rows)}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'files':len(rows),'bytes':manifest['bytes'],'manifest_sha256':sha(OUT/'manifest.json')}))
if __name__=='__main__':main()
