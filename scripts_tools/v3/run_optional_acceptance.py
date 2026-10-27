"""Play optional content only after this task's new current-build natural84."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import secrets
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import dev


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chain',type=Path,required=True)
    parser.add_argument('--region',choices=['I1','F1','I2','F2','I3','F3','I4','F4'],required=True)
    parser.add_argument('--mode',choices=['all','stories','combat','secrets','choices','presentation','panels','summary'],default='all')
    parser.add_argument('--rendering-driver',choices=['vulkan','d3d12'])
    args=parser.parse_args()
    chain=args.chain.resolve(strict=True)
    if not chain.is_relative_to(dev.POLICY.root/'evidence') or chain.name!='chain.json' or not chain.parent.name.startswith('normal-chain-20261022_'):
        raise SystemExit('Only the new managed current-task chain is allowed')
    source=json.loads(chain.read_text(encoding='utf-8'))
    version=re.search(r'^config/version="([^"]+)"$',(dev.ROOT/'project.godot').read_text(encoding='utf-8'),re.M)[1]
    if source.get('state')!='complete' or len(source.get('completed',[]))!=16 or source['target']['app_version']!=version or source['candidate']!=dev.POLICY._index()['current']:
        raise SystemExit('Current-build natural84 must actually complete before optional acceptance')
    stamp=datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3)
    folder=dev.POLICY.root/'evidence'/('optional-acceptance-'+args.region+'-'+stamp)
    dev.POLICY.preflight_qa(64*1024**2)
    folder.mkdir()
    output=folder/'result.json'
    args_native=['--headless','--script','res://scripts_tools/v3/acceptance_optional_runner.gd','--',
                 '--qa-profile='+source['profile'],'--source-chain='+str(chain),'--region='+args.region,'--mode='+args.mode,'--output='+str(output)]
    if args.mode in ('presentation','panels'):
        args_native.remove('--headless')
    if args.rendering_driver:
        if args.mode not in ('presentation','panels'):
            raise SystemExit('Rendering override is limited to actual GPU presentation')
        args_native[:0]=['--rendering-driver',args.rendering_driver]
    print('OPTIONAL_REPORT',output,flush=True)
    dev.execute(args_native,'optional-acceptance-'+args.region+'-'+stamp,timeout=1530)
    report=json.loads(output.read_text(encoding='utf-8'))
    if not report.get('passed') or not report.get('native_exit',{}).get('observed_scene_exit'):
        raise SystemExit('Optional acceptance did not pass; keep its real progress and report')
    print(json.dumps({'passed':True,'report':str(output),'outcomes':report['outcomes']},ensure_ascii=False))


if __name__=='__main__':
    main()
