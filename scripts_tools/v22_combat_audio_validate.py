"""Independent WAV/header/hash validation; writes only combat source evidence."""
from pathlib import Path
import collections,hashlib,json,math,wave,array
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/audio/v22_combat'
SRC=ROOT/'assets/source_audio/v22_combat'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    m=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
    failures=[];groups=collections.defaultdict(list);seconds=0.;size=0
    for item in m['files']:
        p=OUT/item['file'];groups[item['family']].append(item['sha256'])
        with wave.open(str(p)) as w:
            data=array.array('h',w.readframes(w.getnframes()))
            duration=w.getnframes()/w.getframerate()
            ok=w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==48000
        if not ok or sha(p)!=item['sha256'] or abs(duration-item['seconds'])>1e-6:failures.append(item['id']+': format/hash/duration')
        peak=max(abs(v) for v in data);rms=math.sqrt(sum(v*v for v in data)/len(data))/32768
        if peak>round(32768*10**(-6.9/20)) or rms<.001 or data[0]!=0 or data[-1]!=0:failures.append(item['id']+': waveform/headroom/fade')
        seconds+=duration;size+=p.stat().st_size
    for family,hashes in groups.items():
        if len(hashes)<2 or len(set(hashes))!=len(hashes):failures.append(family+': variation')
    sources=json.loads((SRC/'sources.json').read_text(encoding='utf8'))
    for name,record in sources['selected_files'].items():
        if sha(SRC/record['file'])!=record['sha256']:failures.append(name+': source hash')
    if (OUT/'CREDITS.txt').read_text(encoding='utf8')!=m['credits_text']:failures.append('credits mismatch')
    result={'scope':'Independent offline WAV decode/hash/source/fade/headroom validation; not engine or listening','files':len(m['files']),'families':len(groups),'seconds':seconds,'bytes':size,'failures':failures,'manifest_sha256':sha(OUT/'manifest.json')}
    (SRC/'independent_validation.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print(json.dumps(result));return 1 if failures else 0
if __name__=='__main__':raise SystemExit(main())
