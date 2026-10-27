"""Offline combat sound design; deterministic seed, selected CC0 foley + original DSP.
No network, Godot, or device access. Requires numpy/scipy/imageio_ffmpeg.
"""
from pathlib import Path
import hashlib, json, math, subprocess, wave, zipfile
import numpy as np
from scipy import signal
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'assets/source_audio/v22_combat'
OUT = ROOT / 'assets/audio/v22_combat'
ARCHIVE = ROOT / 'asset_sources/v2/audio/downloads/kenney_impact-sounds.zip'
RATE = 48000
ARCHIVE_SHA = '029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8'
SOURCE_URL = 'https://kenney.nl/assets/impact-sounds'
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
used = {}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def foley(name):
    with zipfile.ZipFile(ARCHIVE) as z:
        data = z.read('Audio/' + name + '.ogg')
    p = SRC / 'originals' / (name + '.ogg')
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    used[name] = {'file':str(p.relative_to(SRC)).replace('\\','/'), 'sha256':sha(p), 'archive_member':'Audio/'+name+'.ogg'}
    raw = subprocess.run([FFMPEG,'-v','error','-i','pipe:0','-ac','1','-ar',str(RATE),'-f','f32le','pipe:1'],input=data,capture_output=True,check=True).stdout
    x = np.frombuffer(raw,dtype='<f4').astype(float)
    nonzero = np.flatnonzero(np.abs(x) > .001)
    if len(nonzero): x = x[max(0,nonzero[0]-96):min(len(x),nonzero[-1]+481)]
    return x / max(np.max(np.abs(x)), 1e-8)

def pad(x,n): return np.pad(x[:n],(0,max(0,n-len(x))))
def tint(x,cut): return signal.sosfilt(signal.butter(2,cut,fs=RATE,output='sos'),x)
def add(x,y,at=0.,gain=1.):
    i=round(at*RATE); n=min(len(y),len(x)-i)
    if n>0: x[i:i+n] += y[:n]*gain

def synth(family,v):
    seed = 220000 + sum(ord(c) for c in family)*13 + v
    rng = np.random.default_rng(seed)
    duration = {'shot_light':.42,'shot_heavy':.68,'near_pass':.6,'impact_metal':.88,'impact_ground':.62,'impact_water':1.15,'shield':.85,'component':.8,'destroyed':1.8,'wreck':1.55,'approach':1.5,'warning':.75,'critical':1.1}[family]
    n=round((duration+v*.035)*RATE); t=np.arange(n)/RATE
    noise=rng.normal(0,1,n); sources=[]
    def sample(stem):
        name=f'{stem}_{v:03d}'; sources.append(name); return foley(name)
    x=np.zeros(n)
    if family in ['shot_light','shot_heavy']:
        heavy=family=='shot_heavy'
        x = tint(noise,5600 if not heavy else 3600)*np.exp(-t/(.023 if not heavy else .065))*.5
        freq=(330 if not heavy else 175)*(1+v*.07)*np.exp(-t*12)+65
        x += np.sin(2*np.pi*np.cumsum(freq)/RATE)*np.exp(-t/.07)*.55
        add(x,sample('impactPlate_light'),.008,.18)
        add(x,x.copy(),.048,.09)
    elif family=='near_pass':
        env=np.exp(-((t-.19)/.085)**2)
        x=tint(noise,8000)*env*.7+signal.chirp(t,1500+v*140,t[-1],380)*env*.12
    elif family=='impact_metal':
        add(x,sample('impactMetal_medium'),0,.75)
        x+=tint(noise,6500)*np.exp(-t/.024)*.2
    elif family=='impact_ground':
        add(x,sample('impactSoft_heavy'),0,.6)
        add(x,sample('footstep_concrete'),.023,.35)
        x+=tint(noise,2900)*np.exp(-t/.06)*.3
    elif family=='impact_water':
        x=tint(noise,4200)*np.exp(-t/.23)*(1-np.exp(-t*210))*.55
        for j in range(13):
            delay=rng.uniform(.025,.55);tt=np.maximum(t-delay,0)
            x+=np.sin(2*np.pi*(350+rng.uniform(0,1100))*tt/(1+tt*5))*np.exp(-tt*50)*(t>=delay)*.05
        x+=np.sin(2*np.pi*(80*t+20*(1-np.exp(-t*20))))*np.exp(-t/.045)*.22
    elif family=='shield':
        x=tint(noise,2300)*np.exp(-t/.055)*.18
        for f in [260,390,660]:x+=np.sin(2*np.pi*f*(1+v*.025)*t+np.sin(2*np.pi*8*t)*.2)*np.exp(-t/.18)*.12
    elif family=='component':
        add(x,sample('impactMetal_light'),0,.55)
        for j in range(5):
            delay=.025+j*.04;tt=np.maximum(t-delay,0)
            x+=tint(noise,6500)*np.exp(-tt/.007)*(t>=delay)*(.1-j*.012)
        x+=signal.chirp(t,1500,t[-1],70)*np.exp(-t/.16)*.08
    elif family=='destroyed':
        x=tint(noise,1900)*np.exp(-t/.32)*(1-np.exp(-t*160))*.5
        x+=np.sin(2*np.pi*(80*t+3*(1-np.exp(-t*25))))*np.exp(-t/.2)*.4
        add(x,sample('impactMetal_heavy'),.045,.45)
        for j in range(3):add(x,sample('impactPlate_light'),.16+j*.19,.12/(j+1))
    elif family=='wreck':
        add(x,sample('impactMetal_heavy'),0,.65)
        for j in range(4):add(x,sample('impactMetal_light'),.12+j*.17,.3/(j+1))
        x+=tint(noise,2800)*np.exp(-t/.2)*.16
    elif family=='approach':
        env=np.sin(np.pi*np.minimum(t/t[-1],1))**2
        for h in [1,2,4,7]:x+=np.sin(2*np.pi*np.cumsum((90+v*12+20*np.cos(np.pi*t/t[-1]))*h)/RATE)*env*.1/h
        x+=tint(noise,2600)*env*.1
    else:
        # Two soft, descending instrument tones, not a piercing siren.
        for j,f in enumerate([750,580] if family=='warning' else [660,520,660]):
            start=.02+j*.22;tt=np.maximum(t-start,0)
            env=np.minimum(tt/.012,1)*np.exp(-tt/.09)*(t>=start)
            x+=(np.sin(2*np.pi*(f+v*24)*tt)+.18*np.sin(2*np.pi*f*2*tt))*env*.25
    x-=x.mean()
    # Preserve attacks while suppressing edits and subsonic DC.
    x=signal.sosfilt(signal.butter(2,35,btype='highpass',fs=RATE,output='sos'),x)
    k=min(96,len(x)//4);x[:k]*=np.linspace(0,1,k);x[-480:]*=np.linspace(1,0,480)
    target=-25 if family in ['warning','critical','approach','near_pass'] else -22
    x*=min(10**(target/20)/max(np.sqrt(np.mean(x*x)),1e-9),10**(-7/20)/max(np.max(np.abs(x)),1e-9))
    return x,sorted(set(sources)),seed

def build():
    assert sha(ARCHIVE)==ARCHIVE_SHA,'Archived Kenney source changed'
    SRC.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    (SRC/'.gdignore').write_text('',encoding='utf8')
    with zipfile.ZipFile(ARCHIVE) as z:(SRC/'Kenney-License.txt').write_bytes(z.read('License.txt'))
    records=[]
    for family in ['shot_light','shot_heavy','near_pass','impact_metal','impact_ground','impact_water','shield','component','destroyed','wreck','approach','warning','critical']:
        for v in range(2 if family in ['warning','critical'] else 3):
            x,sources,seed=synth(family,v);name=f'{family}_{v:02d}';p=OUT/(name+'.wav')
            with wave.open(str(p),'wb') as w:
                w.setparams((1,2,RATE,len(x),'NONE','not compressed'));w.writeframes(np.round(x*32767).astype('<i2').tobytes())
            decoded=np.frombuffer(p.read_bytes()[44:],dtype='<i2').astype(float)/32768
            records.append({'id':name,'family':family,'file':p.name,'seconds':len(x)/RATE,'channels':1,'sample_rate':RATE,'bytes':p.stat().st_size,'sha256':sha(p),'rms_dbfs':20*math.log10(np.sqrt(np.mean(decoded**2))),'peak_dbfs':20*math.log10(max(abs(decoded))),'clipped_samples':int(np.sum(abs(decoded)>=.99997)),'sources':sources,'seed':seed,'loop':False})
    credits=[{'title':'Impact Sounds','author':'Kenney','source_url':SOURCE_URL,'license':'CC0-1.0','license_url':'https://creativecommons.org/publicdomain/zero/1.0/','changes':'Selected metal, plate, soft impact and concrete foley; layered, filtered, edited, leveled and converted to 48 kHz mono PCM.'}, {'title':'Combat electronic, air and water layers','author':'Low Altitude Squad project','source_url':'scripts_tools/v22_combat_audio_build.py','license':'Project-original','license_url':'','changes':'Deterministic procedural sound design, no third-party recordings in these synthesis layers.'}]
    text='V2.2 Combat Audio Credits\n\nKenney — Impact Sounds\n'+SOURCE_URL+'\nCC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/\n'+credits[0]['changes']+'\n\nOriginal layers: project procedural sound design. Editable Python generator and deterministic seeds supplied.\n'
    manifest={'schema':1,'sample_rate':RATE,'positional_format':'mono sources; real AudioStreamPlayer3D stereo rendering','files':records,'credits':credits,'credits_text':text,'generator_sha256':sha(Path(__file__))}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'CREDITS.txt').write_text(text,encoding='utf8')
    (SRC/'sources.json').write_text(json.dumps({'archive_sha256':ARCHIVE_SHA,'original_archive':str(ARCHIVE.relative_to(ROOT)).replace('\\','/'),'source_page':SOURCE_URL,'license':'CC0-1.0','license_verified':'2026-10-14 official Kenney asset page and bundled License.txt','selected_files':used},indent=2),encoding='utf8')
    report={'scope':'offline PCM validation; no Godot or human listening','count':len(records),'seconds':sum(v['seconds'] for v in records),'bytes':sum(v['bytes'] for v in records),'failures':[v['id'] for v in records if v['clipped_samples'] or v['rms_dbfs'] < -40],'files':records}
    (SRC/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k!='files'}))
    assert not report['failures']

if __name__=='__main__':build()
