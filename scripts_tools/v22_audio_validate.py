"""Read/measure generated files and source hashes; never runs Godot or a device."""
from pathlib import Path
import hashlib,json,sys
from v22_audio_build import stats

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/audio/v22'
SRC=ROOT/'assets/source_audio/v22'

def main():
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
    failures=[];measured=[]
    for group in ['music','environment','voice']:
        for item in manifest[group]:
            path=OUT/item['file'];actual=stats(path)
            if actual['sha256']!=item['sha256']:failures.append(item['id']+': manifest hash mismatch')
            if actual['clipped_samples']:failures.append(item['id']+': clipped decoded samples')
            if actual['rms_dbfs']<-50:failures.append(item['id']+': unexpectedly silent')
            measured.append(dict(group=group,id=item['id'],**actual))
    for filename,folder in [('music_sources.json','music'),('environment_sources.json','environment')]:
        for item in json.loads((SRC/filename).read_text(encoding='utf8')):
            actual=hashlib.sha256((SRC/folder/item['original_file']).read_bytes()).hexdigest()
            if actual!=item['source_sha256']:failures.append(item['id']+': original source mismatch')
    total=sum(x['seconds'] for x in measured if x['group']=='music')
    if total<900 or len(manifest['music'])<6:failures.append('insufficient complete music')
    if len(manifest['voice'])<24:failures.append('missing Mandarin narration')
    if not (SRC/'.gdignore').exists():failures.append('source folder is not ignored by Godot')
    if not manifest.get('credits_text') or len(manifest.get('credits',[]))<6:failures.append('missing music credits')
    report=dict(kind='offline_decoded_file_validation_not_engine_or_listening_test',
        music_tracks=len(manifest['music']),music_seconds=round(total,6),environment_files=len(manifest['environment']),
        voice_files=len(manifest['voice']),voice_seconds=round(sum(x['seconds'] for x in measured if x['group']=='voice'),6),
        generated_bytes=sum(x['bytes'] for x in measured),failures=failures,files=measured)
    (SRC/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k!='files'},ensure_ascii=False))
    return bool(failures)

if __name__=='__main__':sys.stdout.reconfigure(encoding='utf8');sys.exit(main())
