"""Original synthesized game audio, reproducible without external packages."""
from pathlib import Path
import math, random, wave, struct, urllib.request
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/audio';OUT.mkdir(parents=True,exist_ok=True)
RATE=22050
random.seed(4)

def wav(name,seconds,fn):
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
        data=bytearray()
        for i in range(int(seconds*RATE)):
            t=i/RATE;value=max(-1,min(1,fn(t,i)))
            data.extend(struct.pack('<h',int(value*23000)))
        f.writeframes(data)

wav('shot',.14,lambda t,i:math.sin(2*math.pi*(650*t-950*t*t))*math.exp(-32*t)*.26)
wav('hit',.22,lambda t,i:(random.uniform(-1,1)*.4+math.sin(160*t))*math.exp(-20*t)*.40)
wav('destroy',.48,lambda t,i:(random.uniform(-1,1)*.4+math.sin(2*math.pi*(150*t-70*t*t))*.4)*math.exp(-9*t)*.52)
wav('ui',.12,lambda t,i:math.sin(2*math.pi*720*t)*math.exp(-40*t)*.2)
wav('shield',.7,lambda t,i:math.sin(2*math.pi*(220*t+210*t*t))*math.sin(math.pi*t/.7)*.18)
wav('complete',1.6,lambda t,i:sum(math.sin(2*math.pi*f*t)*math.exp(-4*max(0,t-k*.12))*(t>=k*.12) for k,f in enumerate([329.63,415.3,493.88,659.25]))*.08)
wav('interact',.4,lambda t,i:math.sin(2*math.pi*(440*t+200*t*t))*math.exp(-9*t)*.20)

def music(t,i):
    # 32-second ambient phrase, no harsh rotor or mandatory sonic cues.
    chords=[[130.81,196,261.63,329.63],[110,164.81,220,293.66],[87.31,130.81,174.61,261.63],[98,146.83,196,293.66]]
    chord=chords[int(t//8)%4];phase=t%8
    pad=sum(math.sin(2*math.pi*f*t+math.sin(t*.28)*.15) for f in chord)*.022
    note=chord[int((t%8)//.5)%4]*2
    pluck=math.sin(2*math.pi*note*t)*math.exp(-7*(t%.5))*.026
    pulse=math.sin(2*math.pi*55*t)*math.exp(-18*(t%1.0))*.035
    fade=min(1,t/1.5,(32-t)/1.5)
    return (pad+pluck+pulse)*max(0,fade)

wav('harbor',32,music)
print('Original audio generated.')

fontdir=ROOT/'assets/fonts';fontdir.mkdir(exist_ok=True)
for name,url in [
    ('NotoSansSC.ttf','https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf'),
    ('OFL.txt','https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt')]:
    dest=fontdir/name
    if not dest.exists():
        req=urllib.request.Request(url,headers={'User-Agent':'LowAltitudeDev/0.1'})
        with urllib.request.urlopen(req,timeout=60) as r:dest.write_bytes(r.read())
    print('Font: '+name+' '+str(dest.stat().st_size),flush=True)
