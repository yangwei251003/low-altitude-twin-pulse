"""Prepare the exact final-story captions for offline speech production only."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / 'data/v3/content/final_story/voice_lines.json'
DEST = ROOT / 'data/v3/content/final_flow'


def main():
    source = json.loads(SOURCE.read_text(encoding='utf-8-sig'))
    lines = source['entries']
    clips = {}
    events = {}
    by_character = {}
    by_text = {}
    voices = ['Microsoft Huihui Desktop', 'Microsoft Kangkang', 'Microsoft Yaoyao']
    for line in lines:
        cue = line['voice_id']
        text = line['text'].strip()
        character = line.get('character_id', 'narrator:final')
        if not cue.startswith('final_') or not cue.replace('_', '').isalnum() or not text:
            raise ValueError('Invalid owned final voice caption')
        voice = voices[int(hashlib.sha256(character.encode()).hexdigest()[:8], 16) % len(voices)]
        key = hashlib.sha256((text + '\n' + voice + '\n0').encode()).hexdigest()[:20]
        filename = 'vofinal_' + key + '.wav'
        clips[filename] = {'file': filename, 'text': text, 'voice': voice, 'rate': 0}
        events[cue] = {'files': ['res://assets/v3/content/final_flow/voices/' + filename], 'bus': 'ui',
                       'gain_db': -5.0, 'range_m': 1.0, 'priority': 8, 'cooldown_ms': 100, 'voice': True}
        by_character[character + '\n' + text] = cue
        by_text.setdefault(text, cue)
    DEST.mkdir(parents=True, exist_ok=True)
    routes = {'schema_version': 1, 'voice_status': 'offline Chinese synthetic speech, not human performance',
              'events': events, 'by_character': by_character, 'by_text': by_text}
    (DEST / 'voice_routes.json').write_text(json.dumps(routes, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DEST / 'voice_production_manifest.json').write_text(json.dumps({'clips': list(clips.values())}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'captions': len(lines), 'files': len(clips)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
