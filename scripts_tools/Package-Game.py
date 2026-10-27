"""Package an already exported Windows game and verify the ZIP byte-for-byte."""
from pathlib import Path
import datetime, hashlib, json, shutil, struct, zipfile

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'build' / 'LowAltitude'
EXE = RELEASE / '低空小队.exe'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    data = EXE.read_bytes()
    pe_offset = struct.unpack_from('<I', data, 0x3C)[0]
    if data[:2] != b'MZ' or data[pe_offset:pe_offset+4] != b'PE\0\0' or struct.unpack_from('<H',data,pe_offset+4)[0] != 0x8664:
        raise RuntimeError('The game is not a valid Windows x86_64 PE executable')
    sources = [ROOT/'project.godot', ROOT/'export_presets.cfg', *sorted((ROOT/'scripts').glob('*.gd')), *sorted((ROOT/'scenes').glob('*.tscn'))]
    if any(path.stat().st_mtime > EXE.stat().st_mtime for path in sources):
        raise RuntimeError('Game source changed after export; run Export-Game.ps1 again')
    native = json.loads((ROOT/'artifacts/release-native-checks.json').read_text(encoding='utf-8-sig'))
    if native.get('exe_sha256','').lower()!=digest(EXE) or native.get('status')!='PASS':
        raise RuntimeError('Record native launch verification for this exact executable before packaging')
    for source, target in [('README.md','游玩说明.md'),('docs/VERIFICATION.md','验证说明.md'),('docs/CONTROLLER_TEST.md','控制器测试步骤.md'),('toolchain.lock.json','toolchain.lock.json'),('THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md')]:
        shutil.copy2(ROOT/source, RELEASE/target)
    manifest = {
        'version':'0.1.0',
        'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'platform':'Windows x86_64',
        'entry':'低空小队.exe',
        'engine':'4.7.2.stable.official.ed1daf0bf',
        'native_launch_verified':True,
        'native_evidence':'artifacts/release-native-checks.json',
        'sources':{path.relative_to(ROOT).as_posix():digest(path) for path in sources},
        'files':{path.relative_to(RELEASE).as_posix():{'bytes':path.stat().st_size,'sha256':digest(path)} for path in sorted(RELEASE.rglob('*')) if path.is_file() and path.name!='build-manifest.json'},
    }
    (RELEASE/'build-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    archive=ROOT/'build'/'低空小队-v0.1-Windows.zip'
    temporary=archive.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temporary,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as output:
        for path in sorted(RELEASE.rglob('*')):
            if path.is_file():output.write(path,Path('低空小队-v0.1')/path.relative_to(RELEASE))
    with zipfile.ZipFile(temporary) as package:
        failure=package.testzip()
        if failure:raise RuntimeError('ZIP CRC check failed: '+failure)
        extracted=package.read('低空小队-v0.1/低空小队.exe')
        if hashlib.sha256(extracted).hexdigest()!=digest(EXE):raise RuntimeError('Packaged executable checksum mismatch')
        count=len(package.infolist())
    temporary.replace(archive)
    checksum=digest(archive)
    archive.with_suffix('.zip.sha256').write_text(checksum+'  '+archive.name+'\n',encoding='utf8')
    evidence={'archive':str(archive),'bytes':archive.stat().st_size,'sha256':checksum,'entries':count,'crc':'PASS','executable_sha256_matches':'PASS','architecture':'AMD64'}
    (ROOT/'artifacts/package-verification.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(evidence))

if __name__=='__main__':main()
