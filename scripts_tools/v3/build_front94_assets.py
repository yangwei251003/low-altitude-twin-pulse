"""Editable original UI icon and short sound sources; no image manipulation."""
from pathlib import Path
import math
import struct
import wave

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui/front/dev94'
PATHS = {
    'assist': '<circle cx="12" cy="12" r="9"/><path d="m8 17 4-11 4 11-4-3ZM3 12H1M23 12h-2M12 1v2M12 21v2"/>',
    'home': '<path d="M3 11 12 4l9 7v9H3Z"/><path d="M8 20v-7h8v7M7 8V4"/>',
    'modes': '<path d="m4 20 5-16 3 9 8 3-16 4ZM9 4l11 12M12 13 4 20"/>',
    'room': '<rect x="3" y="4" width="7" height="10" rx="2"/><rect x="14" y="4" width="7" height="10" rx="2"/><path d="M6 14v5h12v-5M10 9h4M12 19v3"/>',
    'map': '<path d="m3 5 6-2 6 3 6-2v15l-6 2-6-3-6 2ZM9 3v15M15 6v15"/><circle cx="15" cy="11" r="2"/>',
    'missions': '<rect x="5" y="4" width="15" height="17" rx="2"/><path d="M9 2h7v5H9ZM8 12l2 2 3-4M15 12h3M8 18h10"/>',
    'base': '<path d="m2 12 10-9 10 9M5 10v11h14V10M9 21v-7h6v7M9 8h6"/>',
    'hangar': '<path d="M3 20V8l9-5 9 5v12H3ZM7 20v-9h10v9M7 14h10M7 17h10"/>',
    'inventory': '<path d="m3 7 9-4 9 4-9 5ZM3 7v11l9 4 9-4V7M12 12v10M7 5l9 4v5"/>',
    'workshop': '<path d="m14 3-3 3 1 5 5 1 4-4v5l-4 3-5-1-7 7-3-3 7-7-1-5 3-4Z"/>',
    'shop': '<path d="M3 7h18l-2 14H5ZM8 8V5a4 4 0 0 1 8 0v3M9 14h6M12 11v6"/>',
    'events': '<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3ZM4 3v4M2 5h4M20 18v4M18 20h4"/>',
    'friends': '<circle cx="9" cy="8" r="4"/><path d="M2 21v-3a7 7 0 0 1 14 0v3M16 4a4 4 0 0 1 0 8M18 15a6 6 0 0 1 4 6"/>',
    'profile': '<path d="m12 2 9 4v7c0 5-9 9-9 9S3 18 3 13V6Z"/><circle cx="12" cy="9" r="3"/><path d="M7 17a5 5 0 0 1 10 0"/>',
    'results': '<path d="M7 3h10v7a5 5 0 0 1-10 0ZM7 5H3v3a4 4 0 0 0 4 4M17 5h4v3a4 4 0 0 1-4 4M12 15v6M7 21h10"/>',
    'settings': '<circle cx="12" cy="12" r="4"/><path d="M10 2h4l1 3 3 1 3-1 2 4-3 2v2l3 2-2 4-3-1-3 1-1 3h-4l-1-3-3-1-3 1-2-4 3-2v-2L1 9l2-4 3 1 3-1Z"/>',
}


def sound(kind, seconds, frequencies):
    rate = 44100
    samples = bytearray()
    for i in range(int(rate * seconds)):
        t = i / rate
        x = t / seconds
        envelope = min(1.0, t / .003) * math.exp(-5.2 * x) * min(1.0, (1-x) * 20)
        tone = sum(math.sin(math.tau * (f*t + 0.5*80*t*t)) * weight for f, weight in frequencies)
        tone += math.sin(math.tau * 160*t) * .12 * math.exp(-28*x)
        samples.extend(struct.pack('<h', int(max(-1, min(1, tone*envelope*.45))*32767)))
    with wave.open(str(OUT / ('ui_'+kind+'.wav')), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(samples)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, shape in PATHS.items():
        (OUT/('nav_'+key+'.svg')).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#9ee6db" stroke-width="1.45" stroke-linecap="round" stroke-linejoin="round">'+shape+'</g></svg>\n', encoding='utf-8')
    sound('hover', .045, [(1250,.44),(1875,.13)])
    sound('press', .105, [(740,.50),(1110,.18),(1480,.1)])
    sound('engage', .16, [(523.25,.48),(784.88,.21),(1046.5,.1)])
    print('Original front-end assets authored:', len(PATHS), 'icons, 3 short audio cues')


if __name__=='__main__':
    main()
