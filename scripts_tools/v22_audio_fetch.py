"""Fetch only author-hosted, redistributable V2.2 audio and offline TTS tools.

No authentication. Downloads are retained with URLs, licences and SHA256.
Run with --model for the offline-only MeloTTS package, or --music for music.
"""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, sys, tarfile, time
from urllib.parse import quote
import requests

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source_audio/v22'
TOOLS = ROOT / '.tools/v22_audio'
BASE = 'https://incompetech.com/music/royalty-free/'
TRACKS = {
    'USUAN1400037': ('carefree', ['explore', 'action']),
    'USUAN1200076': ('easy_lemon', ['explore', 'hangar']),
    'USUAN1400013': ('montauk_point', ['explore', 'action']),
    'USUAN1900022': ('wholesome', ['explore', 'hangar']),
    'USUAN2300003': ('morning', ['hangar', 'explore']),
    'USUAN1100207': ('heartwarming', ['hangar', 'explore']),
}

def fetch(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.stat().st_size > 0:
        return path
    temporary = path.with_suffix(path.suffix + '.part')
    for attempt in range(3):
        try:
            with requests.get(url, stream=True, timeout=(30, 90)) as response:
                response.raise_for_status()
                with temporary.open('wb') as out:
                    for chunk in response.iter_content(1024 * 1024):
                        out.write(chunk)
            temporary.replace(path)
            print('downloaded', path.name, path.stat().st_size, flush=True)
            return path
        except requests.RequestException:
            if attempt == 2: raise
            time.sleep(2)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fetch_range(url,path,size):
    """Bounded HTTP byte ranges avoid long stalled CDN responses on this network."""
    if path.exists() and path.stat().st_size==size: return path
    path.parent.mkdir(parents=True,exist_ok=True)
    block=4*1024*1024
    chunks=list(range((size+block-1)//block))
    def part(index):
        start=index*block;end=min(size,start+block)-1
        target=path.with_suffix('.part.%03d'%index)
        if target.exists() and target.stat().st_size==end-start+1:return target
        for attempt in range(3):
            try:
                r=requests.get(url+'?download=true',headers={'Range':f'bytes={start}-{end}'},timeout=(20,45))
                r.raise_for_status()
                assert r.status_code==206 and len(r.content)==end-start+1,(r.status_code,len(r.content),start,end)
                target.write_bytes(r.content)
                print('model chunk',index+1,len(chunks),flush=True)
                return target
            except (requests.RequestException,AssertionError):
                if attempt==2:raise
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: parts=list(pool.map(part,chunks))
    with path.open('wb') as out:
        for item in parts:out.write(item.read_bytes())
    return path

def music():
    catalog = fetch(BASE + 'pieces.json', SOURCE / 'incompetech-pieces.json')
    data = json.loads(catalog.read_text(encoding='utf8'))
    pieces = data if isinstance(data, list) else data.get('pieces', data.get('tracks', []))
    print('catalog type', type(data).__name__, 'entries', len(pieces), flush=True)
    if not pieces and isinstance(data, dict): pieces = list(data.values())
    selected = []
    for piece in pieces:
        isrc = str(piece.get('isrc', piece.get('ISRC', '')))
        if isrc not in TRACKS: continue
        key, contexts = TRACKS[isrc]
        filename = piece['filename']
        selected.append(dict(id=key, title=piece['title'], author='Kevin MacLeod',
            isrc=isrc, contexts=contexts, source_page=BASE+'index.html?isrc='+isrc,
            download_url=BASE+'mp3-royaltyfree/'+quote(filename), original_file=filename,
            license='CC-BY-4.0', license_url='https://creativecommons.org/licenses/by/4.0/',
            author_metadata=piece))
    assert len(selected) == 6, [p.get('isrc') for p in selected]
    def one(item):
        audio = fetch(item['download_url'], SOURCE / 'music' / item['original_file'])
        page = fetch(item['source_page'], SOURCE / 'licenses' / (item['id']+'.html'))
        item.update(source_sha256=sha(audio), license_page_sha256=sha(page))
        # The current author detail-page template explicitly applies CC BY 4.0.
        assert b'creativecommons.org/licenses/by/4.0' in page.read_bytes(), item['source_page']
        return item
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        selected = list(executor.map(one, selected))
    (SOURCE/'music_sources.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2),encoding='utf8')
    print('MUSIC SOURCES READY', [(x['id'],x['author_metadata'].get('length')) for x in selected],flush=True)

def model():
    url='https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-melo-tts-zh_en.tar.bz2'
    package=fetch(url,TOOLS/'vits-melo-tts-zh_en.tar.bz2')
    with tarfile.open(package) as archive:
        archive.extractall(TOOLS,filter='data')
    model_dir=TOOLS/'vits-melo-tts-zh_en'
    license_path=model_dir/'LICENSE'
    (SOURCE/'licenses').mkdir(parents=True,exist_ok=True)
    (SOURCE/'licenses/MeloTTS-LICENSE.txt').write_bytes(license_path.read_bytes())
    metadata=dict(source_url=url, documentation='https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html',
        upstream='https://huggingface.co/myshell-ai/MeloTTS-Chinese', license='MIT',
        archive_sha256=sha(package), model_sha256=sha(model_dir/'model.onnx'),
        model_bytes=(model_dir/'model.onnx').stat().st_size, runtime_in_game=False)
    (SOURCE/'tts_model.json').write_text(json.dumps(metadata,indent=2),encoding='utf8')
    print('TTS MODEL READY',metadata['model_bytes'],flush=True)

def environment():
    from bs4 import BeautifulSoup
    choices=[('rain','Ylmir','rain-loopable','Rain OGG.zip'),
             ('vehicle_start','looneybits','car-engine-start-up-02','engine_start_up_01.wav'),
             ('vehicle_loop','domasx2','racing-car-engine-sound-loops','loop_0.wav'),
             ('traffic','IgnasD','high-traffic-road-sounds','gatve Varniu.ogg')]
    collected=[]
    for key,author,slug,filename in choices:
        page_url='https://opengameart.org/content/'+slug
        page=fetch(page_url,SOURCE/'licenses'/(key+'.html'))
        doc=BeautifulSoup(page.read_text(encoding='utf8'),'html.parser')
        assert 'CC0' in doc.get_text(), page_url
        links=[a.get('href') for a in doc.select('a[href]') if a.get_text(strip=True)==filename]
        assert links,(page_url,filename)
        audio=fetch(links[0],SOURCE/'environment'/filename)
        collected.append(dict(id=key,author=author,source_page=page_url,download_url=links[0],
            original_file=filename,license='CC0-1.0',license_url='https://creativecommons.org/publicdomain/zero/1.0/',
            source_sha256=sha(audio),license_page_sha256=sha(page)))
    (SOURCE/'environment_sources.json').write_text(json.dumps(collected,ensure_ascii=False,indent=2),encoding='utf8')
    print('ENVIRONMENT SOURCES READY',flush=True)

def model_hf():
    # Maintainer mirror, linked to the same MeloTTS conversion as the official docs.
    repo='csukuangfj/vits-melo-tts-zh_en'
    info=requests.get('https://huggingface.co/api/models/'+repo,timeout=30);info.raise_for_status()
    revision=info.json()['sha']
    tree=requests.get('https://huggingface.co/api/models/'+repo+'/tree/'+revision+'?recursive=true',timeout=30)
    tree.raise_for_status()
    files=[x for x in tree.json() if x['type']=='file' and x['path'] not in ['model.int8.onnx','.gitattributes']]
    destination=TOOLS/'vits-melo-tts-zh_en'
    def one(item):
        url='https://huggingface.co/'+repo+'/resolve/'+revision+'/'+item['path']
        path=fetch_range(url,destination/item['path'],item['size']) if item['size']>32*1024*1024 else fetch(url,destination/item['path'])
        assert path.stat().st_size==item['size'],item
        if item.get('lfs',{}).get('oid'):assert sha(path)==item['lfs']['oid'],item['path']
        return dict(path=item['path'],bytes=item['size'],sha256=sha(path))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        records=list(pool.map(one,files))
    (SOURCE/'licenses').mkdir(parents=True,exist_ok=True)
    (SOURCE/'licenses/MeloTTS-LICENSE.txt').write_bytes((destination/'LICENSE').read_bytes())
    metadata=dict(source_url='https://huggingface.co/'+repo,revision=revision,files=records,
        documentation='https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html',
        upstream='https://huggingface.co/myshell-ai/MeloTTS-Chinese',license='MIT',runtime_in_game=False,
        model_sha256=sha(destination/'model.onnx'),model_bytes=(destination/'model.onnx').stat().st_size)
    (SOURCE/'tts_model.json').write_text(json.dumps(metadata,indent=2),encoding='utf8')
    print('TTS MODEL READY',metadata['model_bytes'],flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    parser=argparse.ArgumentParser();parser.add_argument('--music',action='store_true');parser.add_argument('--model',action='store_true');parser.add_argument('--model-hf',action='store_true');parser.add_argument('--environment',action='store_true');args=parser.parse_args()
    SOURCE.mkdir(parents=True,exist_ok=True)
    if args.music: music()
    if args.model: model()
    if args.environment: environment()
    if args.model_hf: model_hf()
