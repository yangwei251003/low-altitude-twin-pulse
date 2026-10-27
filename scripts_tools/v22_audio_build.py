"""Reproducible offline preparation: full music, separate nature, recorded weather,
and Mandarin tutorial voice. No runtime TTS and no network in this build script.
"""
from pathlib import Path
import argparse, hashlib, json, math, subprocess, sys, wave, zipfile
import numpy as np
from scipy import signal
import imageio_ffmpeg

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/source_audio/v22'
OUT=ROOT/'assets/audio/v22'
OLD=ROOT/'asset_sources/v2/audio'
RATE=48000
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
VOICE_TEXTS={
 'lobby_welcome':'欢迎来到低空小队。先熟悉机库，再开始你的第一次飞行。',
 'lobby_profile':'这里是驾驶员档案。查看你的飞行记录和获得的奖励。',
 'lobby_fleet':'打开机队，选择一架无人机。不同机型有不同的飞行特点。',
 'lobby_loadout':'打开装配，查看飞机的模块。选好装备，再去执行任务。',
 'lobby_mission':'打开任务板，选择基础飞行训练。每一步都有提示。',
 'lobby_prepare':'准备起飞。先看看操作提示，你可以随时暂停和调整设置。',
 'lobby_complete':'做得好，机库导览完成了。现在可以选择任务，继续探索。',
 'lobby_device':'点击设备，查看操控连接。手机可以稍后再配对。',
 'lobby_settings':'点击设置，调整声音、字号和飞行方式。',
 'lobby_tutorial':'点击教学，真实飞行课程会按你的操作逐步引导。',
 'training_complete':'做得好，这项训练已经完成。你可以继续练习，也可以选择下一个任务。',
 'flight_lift':'轻轻增加升力，把飞机升到离地约三米，然后松开。',
 'flight_hover':'让飞机稳定悬停，保持两秒。小幅调整就好。',
 'flight_yaw':'原地转动机头，大约九十度。注意机头朝向的变化。',
 'flight_forward':'轻轻向前飞，移动大约四米。留意前方的空间。',
 'flight_strafe':'保持机头朝向，向一侧平移大约三米。',
 'flight_brake':'先向前飞起来，再按住刹车，直到飞机稳稳停下。',
 'flight_land':'慢慢降低高度，在标记区域轻轻着陆。',
 'flight_zoom':'调整一下视野大小，找到看得清飞机和周围环境的距离。',
 'cargo_pickup':'靠近货物并稳定悬停，再使用互动操作挂上货物。',
 'cargo_swing':'轻推轻停，让货物摆角回到十五度内，并稳定两秒。',
 'cargo_delivery':'把货物带到交付区，稳住飞机，再按提示完成交付。',
 'cargo_wind':'风会影响飞机和货物。小幅修正，留出足够的安全距离。',
 'scan':'靠近扫描目标，使用扫描工具，并保持稳定。',
 'route':'沿着任务标记完成一段取货和交付。观察路口，选择宽敞的通道。',
 'interference':'靠近分流塔，观察干扰提示。然后离开，让信号恢复。',
 'cover':'警报出现后，利用建筑挡住敌机的视线，保持至少一秒。',
}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def run(args,**kwargs): return subprocess.run([FFMPEG,'-hide_banner','-y',*args],check=True,capture_output=True,**kwargs)
def decode(path,channels=1, data=None):
    args=['-v','error','-i','pipe:0' if data is not None else str(path),'-ac',str(channels),'-ar',str(RATE),'-f','f32le','pipe:1']
    return np.frombuffer(run(args,input=data).stdout,dtype='<f4').reshape(-1,channels).astype(np.float64)
def rms(x):return float(np.sqrt(np.mean(x*x)))
def normalize(x,target,ceiling):
    x=x-x.mean(axis=0)
    return x*min(10**(target/20)/max(rms(x),1e-10),10**(ceiling/20)/max(float(np.abs(x).max()),1e-10))
def cyclic(x,seconds,overlap=.5):
    n=round(seconds*RATE);k=min(round(overlap*RATE),n//4)
    x=x[np.arange(n+k)%len(x)].copy();w=(.5-.5*np.cos(np.linspace(0,math.pi,k)))[:,None]
    x[:k]=x[n:n+k]*(1-w)+x[:k]*w
    return x[:n]
def noise(seconds,seed,high=2400,low=60):
    n=round(seconds*RATE);freq=np.fft.rfftfreq(n,1/RATE)
    spectrum=np.fft.rfft(np.random.default_rng(seed).normal(size=n))
    spectrum*=np.exp(-(freq/high)**4)*(1-np.exp(-(freq/low)**4))
    return np.fft.irfft(spectrum,n=n)[:,None]
def stats(path,channels=None):
    if path.suffix=='.wav':
        with wave.open(str(path)) as w:
            channels=w.getnchannels();rate=w.getframerate();frames=w.getnframes()
            x=np.frombuffer(w.readframes(frames),dtype='<i2').astype(np.float64).reshape(-1,channels)/32768
    else:
        channels=channels or 2;rate=RATE;x=decode(path,channels);frames=len(x)
    return dict(seconds=round(frames/rate,6),channels=channels,sample_rate=rate,
        rms_dbfs=round(20*math.log10(max(rms(x),1e-12)),3),
        peak_dbfs=round(20*math.log10(max(float(np.abs(x).max()),1e-12)),3),
        clipped_samples=int(np.sum(np.abs(x)>=.99997)),sha256=sha(path),bytes=path.stat().st_size)
def write_wav(key,x,target=-24,ceiling=-6,loop=False,source_ids=None):
    x=normalize(x,target,ceiling)
    if not loop:
        n=min(round(.012*RATE),len(x)//4)
        x[:n]*=np.linspace(0,1,n)[:,None];x[-n:]*=np.linspace(1,0,n)[:,None]
    path=OUT/(key+'.wav');path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as w:
        w.setnchannels(x.shape[1]);w.setsampwidth(2);w.setframerate(RATE)
        w.writeframes(np.round(x*32767).astype('<i2').tobytes())
    return dict(id=key,file=key+'.wav',loop=loop,source_ids=source_ids or ['project_original_synthesis'],**stats(path))

def music(manifest):
    sources=json.loads((SRC/'music_sources.json').read_text(encoding='utf8'))
    tracks=[]
    for source in sources:
        original=SRC/'music'/source['original_file'];key='music/'+source['id'];path=OUT/(key+'.ogg')
        path.parent.mkdir(parents=True,exist_ok=True)
        analysis=run(['-i',str(original),'-af','loudnorm=I=-20:TP=-3:LRA=11:print_format=json','-f','null','-']).stderr.decode('utf8',errors='replace')
        values=json.JSONDecoder().raw_decode(analysis[analysis.rfind('{'):])[0]
        filt='loudnorm=I=-20:TP=-3:LRA=11:measured_I={input_i}:measured_TP={input_tp}:measured_LRA={input_lra}:measured_thresh={input_thresh}:offset={target_offset}:linear=true'.format(**values)
        run(['-v','error','-i',str(original),'-af',filt,'-ar',str(RATE),'-ac','2','-c:a','libvorbis','-q:a','5',str(path)])
        item=dict(id=source['id'],file=key+'.ogg',title=source['title'],author=source['author'],
            author_url='https://incompetech.com/',license_url='https://creativecommons.org/licenses/by/4.0/',
            contexts=source['contexts'],license=source['license'],source_page=source['source_page'],
            original_sha256=source['source_sha256'],normalization=values,**stats(path))
        assert item['clipped_samples']==0,item
        tracks.append(item);print('music',item['id'],item['seconds'],flush=True)
    assert len(tracks)>=6 and sum(x['seconds'] for x in tracks)>=900
    manifest['music']=tracks
    credits=['V2.2 Music Credits','All six compositions and recordings by Kevin MacLeod (incompetech.com).',
             'Licensed under Creative Commons Attribution 4.0: https://creativecommons.org/licenses/by/4.0/',
             'Changes: loudness normalization and Ogg encoding; complete compositions retained.','']
    credits += [f"{x['title']} — Kevin MacLeod — {x['source_page']}" for x in sources]
    (OUT/'CREDITS.txt').write_text('\n'.join(credits),encoding='utf8')
    manifest['credits_text']='\n'.join(credits)
    manifest['credits']=[dict(title=x['title'],author=x['author'],author_url='https://incompetech.com/',
        source_url=x['source_page'],license=x['license'],license_url=x['license_url'],
        changes='Loudness normalization and Ogg encoding; complete composition retained.') for x in sources]

def environment(manifest):
    sources=json.loads((SRC/'environment_sources.json').read_text(encoding='utf8'))
    records=[]
    birds=decode(OLD/'downloads/birds-isaiah658.ogg')
    birds=signal.sosfiltfilt(signal.butter(2,[400,8500],btype='bandpass',fs=RATE,output='sos'),birds,axis=0)
    for i in range(8):
        clip=birds[round((i*3.45+.5)*RATE):round((i*3.45+2.55)*RATE)]
        # Gentle transient shaping only on isolated chirps, never a dense loop.
        clip=np.tanh(normalize(clip,-17,-1)*2.5)
        records.append(write_wav('environment/bird_%02d'%i,clip,-27.5,-8,False,['birds']))
    sea=decode(OLD/'downloads/wave_01.flac')
    for region in range(1,5):
        air=normalize(noise(32,2200+region),-29,-12)
        water=normalize(cyclic(sea,32),-28,-10)
        bed=air+water*({1:.08,2:.03,3:.6,4:.15}[region])
        records.append(write_wav('environment/bed_R%d'%region,cyclic(bed,32),-30,-11,True,['waves','project_original_synthesis']))
    records.append(write_wav('environment/wind',noise(32,7799,3500),-25,-10,True))
    rain_source=next(x for x in sources if x['id']=='rain')
    with zipfile.ZipFile(SRC/'environment'/rain_source['original_file']) as z:
        members=[x for x in z.namelist() if x.lower().endswith('.ogg')]
        assert members
        for i,member in enumerate(members):
            rain=decode(None,1,z.read(member))
            records.append(write_wav('environment/rain_%02d'%i,cyclic(rain,len(rain)/RATE),-26,-9,True,['rain']))
    car=decode(SRC/'environment'/'engine_start_up_01.wav')
    records.append(write_wav('environment/vehicle_start',car,-24,-7,False,['vehicle_start']))
    engine=decode(SRC/'environment'/'loop_0.wav')
    for i in range(3):
        n=round((5+i)*RATE);t=np.linspace(0,1,n)[:,None]
        motor=cyclic(engine,(5+i))*(np.sin(np.pi*t)**1.7)
        motor += normalize(noise(5+i,337+i,2200),-32,-15)*np.sin(np.pi*t)
        records.append(write_wav('environment/vehicle_pass_%d'%i,motor,-26,-9,False,['vehicle_loop','project_original_synthesis']))
    traffic_source=next((x for x in sources if x['id']=='traffic'),None)
    assert traffic_source,'Run fetch --environment again for traffic source'
    traffic=decode(SRC/'environment'/traffic_source['original_file'])
    records.append(write_wav('environment/traffic',cyclic(traffic,min(40,len(traffic)/RATE)),-29,-10,True,['traffic']))
    seconds=24;n=round(seconds*RATE);t=np.arange(n)/RATE
    hum=(.04*np.sin(math.tau*90*t)+.013*np.sin(math.tau*180*t)+.008*np.sin(math.tau*270*t))[:,None]
    hum+=normalize(noise(seconds,992,1200),-34,-15)
    records.append(write_wav('environment/machinery',hum,-28,-10,True))
    impact=decode(ROOT/'assets/v2/audio/collision_1.wav')
    for i in range(3):
        shifted=signal.resample_poly(impact,10,9+i)
        records.append(write_wav('environment/mechanical_%d'%i,shifted,-27,-10,False,['kenney_impacts']))
    manifest['environment']=records
    manifest['bird_gain_policy']={'source_target_rms_dbfs':-27.5,'bus_default':.5,'player_db':-2,
        'interval_seconds':[12,30],'old_baked_birds_removed':True,'old_source_target_rms_dbfs':-20,
        'source_rms_reduction_db':7.5,'reference_mix_reduction_db_approx':9,'spatial_max_distance_m':75,
        'note':'Reference unit-distance gain target; real attenuation varies with source distance. Human listening still required.'}
    old=json.loads((OLD/'sources.json').read_text(encoding='utf8'))
    (SRC/'legacy_sources.json').write_text(json.dumps(old,ensure_ascii=False,indent=2),encoding='utf8')
    print('environment',len(records),'files',flush=True)

def voice(manifest, selected_ids=None):
    selected=set(selected_ids or VOICE_TEXTS)
    unknown=selected-set(VOICE_TEXTS)
    if unknown: raise ValueError('Unknown voice IDs: '+', '.join(sorted(unknown)))
    sys.path.insert(0,str(ROOT/'.tools/v22_audio/python'))
    import sherpa_onnx
    model_dir=ROOT/'.tools/v22_audio/vits-melo-tts-zh_en'
    config=sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=str(model_dir/'model.onnx'),
            lexicon=str(model_dir/'lexicon.txt'),tokens=str(model_dir/'tokens.txt')),
        num_threads=2,provider='cpu'),max_num_sentences=1)
    assert config.validate()
    tts=sherpa_onnx.OfflineTts(config)
    # Incremental voice production retains all unselected audio and its metadata.
    records=[item for item in manifest.get('voice',[]) if item['id'] not in selected]
    (SRC/'voice_texts.json').write_text(json.dumps(VOICE_TEXTS,ensure_ascii=False,indent=2),encoding='utf8')
    for key,text in VOICE_TEXTS.items():
        if key not in selected: continue
        audio=tts.generate(text,sid=0,speed=.96)
        x=np.asarray(audio.samples,dtype=np.float64)[:,None]
        x=signal.resample_poly(x,RATE,audio.sample_rate,axis=0)
        # Keep modest leading/trailing space, preserving consonants and natural phrase endings.
        active=np.flatnonzero(np.abs(x[:,0])>.003)
        if len(active):x=x[max(0,active[0]-round(.08*RATE)):min(len(x),active[-1]+round(.15*RATE))]
        item=write_wav('voice/'+key,x,-20,-4,False,['melotts_zh_en'])
        item.update(id=key,text=text,synthesizer='sherpa-onnx '+sherpa_onnx.__version__,model='MeloTTS-Chinese ONNX',speaker_id=0,speed=.96)
        records.append(item);print('voice',key,item['seconds'],flush=True)
    order={key:index for index,key in enumerate(VOICE_TEXTS)}
    manifest['voice']=sorted(records,key=lambda item:order.get(item['id'],len(order)))

def write_credits(manifest):
    sources=json.loads((SRC/'music_sources.json').read_text(encoding='utf8'))
    credits=[dict(title=x['title'],author=x['author'],author_url='https://incompetech.com/',
        source_url=x['source_page'],license=x['license'],license_url=x['license_url'],
        changes='Loudness normalization and Ogg encoding; complete composition retained.') for x in sources]
    titles={'rain':'Rain (loopable)','vehicle_start':'Car engine Start Up 02',
            'vehicle_loop':'Racing car engine sound loops','traffic':'High traffic road sounds'}
    for x in json.loads((SRC/'environment_sources.json').read_text(encoding='utf8')):
        credits.append(dict(title=titles[x['id']],author=x['author'],author_url=x['source_page'],
            source_url=x['source_page'],license=x['license'],license_url=x['license_url'],
            changes='Selected, leveled, converted to mono PCM; engine loop used in designed vehicle passes.'))
    for x in json.loads((SRC/'legacy_sources.json').read_text(encoding='utf8')):
        if x['id']=='music':continue # Sherwood is no longer loaded by V2.2.
        credits.append(dict(title=x['title'],author=x['author'],author_url=x['source_page'],
            source_url=x['source_page'],license=x['license'],license_url=x['license_url'],
            changes='Retained V2 flight/UI/contact sounds; birds split into quiet spatial one-shots; water reused in bird-free beds.'))
    credits += [dict(title='MeloTTS-Chinese (offline Mandarin voice generation)',author='MyShell.ai',
        author_url='https://github.com/myshell-ai',source_url='https://huggingface.co/myshell-ai/MeloTTS-Chinese',
        license='MIT',license_url='https://github.com/myshell-ai/MeloTTS/blob/main/LICENSE',
        changes='Project-written Mandarin text rendered offline ('+str(len(manifest.get('voice',[])))+' clips); model is not part of the game runtime.'),
        dict(title='sherpa-onnx (offline voice tool)',author='k2-fsa contributors',author_url='https://github.com/k2-fsa',
        source_url='https://github.com/k2-fsa/sherpa-onnx',license='Apache-2.0',
        license_url='https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE',changes='Used only during audio production; no inference in the game.')]
    manifest['credits']=credits
    lines=['V2.2 Audio Credits','Music compositions/recordings: Kevin MacLeod (incompetech.com), CC BY 4.0.',
           'https://creativecommons.org/licenses/by/4.0/','Complete works retained; loudness normalization and Ogg encoding applied.','']
    for x in credits:lines.extend([x['title']+' — '+x['author'],x['source_url'],x['license']+' — '+x['license_url'],x['changes'],''])
    manifest['credits_text']='\n'.join(lines)
    (OUT/'CREDITS.txt').write_text(manifest['credits_text'],encoding='utf8')

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    p=argparse.ArgumentParser();p.add_argument('--music',action='store_true');p.add_argument('--environment',action='store_true');p.add_argument('--voice',action='store_true');p.add_argument('--voice-id',action='append',default=[],help='Generate only this voice ID; may be repeated.');a=p.parse_args()
    if a.voice and a.voice_id: p.error('Choose --voice (all) or --voice-id (incremental), not both')
    OUT.mkdir(parents=True,exist_ok=True)
    path=OUT/'manifest.json'
    manifest=json.loads(path.read_text(encoding='utf8')) if path.exists() else {'version':'2.2','music':[],'environment':[],'voice':[]}
    for key,enabled in [('music',a.music),('environment',a.environment),('voice',a.voice)]:
        if enabled:
            globals()[key](manifest)
            path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    if a.voice_id:
        voice(manifest,a.voice_id)
        path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    if all((SRC/name).exists() for name in ['music_sources.json','environment_sources.json','legacy_sources.json']):
        write_credits(manifest)
        path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
