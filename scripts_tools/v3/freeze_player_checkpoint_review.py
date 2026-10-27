"""Freeze a passed real F5/F9 run and retain the two earlier integration failures."""
from pathlib import Path
import argparse, hashlib, json, shutil
ROOT=Path(__file__).resolve().parents[2]
PRIOR=['canal-player-checkpoint-20261020_044243_700af1',
       'canal-player-checkpoint-20261020_045443_a19e9b',
       'canal-player-checkpoint-20261020_050050_41e6fb']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('run')
    args=parser.parse_args()
    assert args.run.startswith('canal-player-checkpoint-') and '/' not in args.run and '\\' not in args.run
    source=ROOT/'artifacts/v3/art'/args.run
    result=json.loads((source/'result.json').read_text(encoding='utf-8'))
    assert not result['failures'] and not result['engine_errors']
    after=json.loads((source/'inputs_after.json').read_text(encoding='utf-8'))
    assert after['unchanged']
    out=ROOT/'docs/v3/evidence/canal-player-checkpoint'/args.run
    assert not out.exists(), 'Preserve earlier frozen evidence.'
    out.mkdir(parents=True)
    (out/'.gdignore').write_text('',encoding='utf-8')
    (out/'.gitattributes').write_text('* -text -whitespace\n',encoding='utf-8')
    for path in source.rglob('*'):
        if path.is_file():
            target=out/'actual'/path.relative_to(source)
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(path,target)
    wanted=json.loads((source/'inputs.json').read_text(encoding='utf-8'))
    for relative,digest in wanted.items():
        current=ROOT/relative
        assert sha(current)==digest, relative
        saved=out/'actual/input_snapshot'/relative
        if saved.exists(): assert sha(saved)==digest
        else:
            saved.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(current,saved)
    for name in PRIOR:
        prior=ROOT/'artifacts/v3/art'/name
        for path in prior.iterdir():
            if path.is_file() and path.suffix in {'.json','.log'}:
                target=out/'prior_failures'/name/path.name
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(path,target)
    rows=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}
          for p in sorted(out.rglob('*')) if p.is_file()]
    manifest={'scope':'Fresh player action, original work, return traffic, public QA injury, F5/F9 whole-scene restore and next F5; no human, MAIN, LAN or performance claim.',
              'source':args.run,'checks':result['checks'],'files':rows,'bytes':sum(r['bytes'] for r in rows),
              'prior_failure_limit':'Earlier runs retain original results/logs/hash inventories, not full source snapshots.'}
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for row in rows: assert sha(ROOT/row['path'])==row['sha256']
    print(json.dumps({'files':len(rows),'bytes':manifest['bytes'],'path':str(out),'manifest_sha256':sha(out/'manifest.json')},ensure_ascii=False))

if __name__=='__main__': main()
