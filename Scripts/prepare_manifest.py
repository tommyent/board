"""Create synthesized toggle cues and an exhaustive source inventory. No external dependencies."""
import math, wave, struct, json, hashlib, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
res=ROOT/'Board/Resources'; cues=res/'Cues'; cues.mkdir(parents=True,exist_ok=True)
for name,frequencies in [('enable',(523.25,783.99)),('disable',(783.99,523.25))]:
    frames=[]
    for i in range(14400):
        t=i/48000; freq=frequencies[0] if t<.12 else frequencies[1]; local=t if t<.12 else t-.12
        envelope=min(1,local/.006)*math.exp(-local*24)*min(1,(.3-t)/.015)
        frames.append(struct.pack('<h',int(math.sin(2*math.pi*freq*t)*envelope*10000)))
    with wave.open(str(cues/(name+'.wav')),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(48000);f.writeframes(b''.join(frames))
notice=(ROOT/'Docs/References/kbsim-LICENSE.md').read_text()
(res/'THIRD-PARTY-NOTICES.txt').write_text('Mechanical recordings from tplai/kbsim\nRevision ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4\n\n'+notice+'\n\nTypewriter keystrokes by Cassie-OrbitGames (CC0 1.0)\nhttps://opengameart.org/content/typewriter-sounds\nhttps://creativecommons.org/publicdomain/zero/1.0/\nComplete strokes play on press only; no separate release recordings.\n')
source=json.loads((ROOT/'Docs/imported-assets.json').read_text())+json.loads((ROOT/'Docs/typewriter-assets.json').read_text())
manifest=[a for a in source if a['path'].startswith('Board/Resources/Audio/')]
for asset in sorted(list(cues.glob('*'))+list((ROOT/'Assets').rglob('*.png'))+list((ROOT/'Assets/Source').glob('*.svg'))):
    if asset.exists(): manifest.append({'path':str(asset.relative_to(ROOT)),'author':'Original project artwork / synthesis','source':'Scripts/render_previews.swift, prepare_manifest.py','date':'2026-09-10','license':'Original; available for personal use with this project','processing':'Procedural geometry / PCM synthesis; see editable sources','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()})
# Brand package files (app icons, menu glyph) are recorded by hand; keep their entries across regeneration.
manifest+=[a for a in json.loads((ROOT/'Docs/asset-manifest.json').read_text())['assets'] if a['author']=='Board Keycap brand package']
manifest_data={'version':1,'assets':manifest,'mapping':'GENERIC_R0 through R4 are physical rows; Space/Enter/Backspace have dedicated press/release; Tab/Shift/modifiers fall back to corresponding row press and generic release. bluealps/release/GENERIC_long.mp3 is preserved but unused, matching upstream.'}
(ROOT/'Docs/asset-manifest.json').write_text(json.dumps(manifest_data,indent=2))
print('Inventoried',len(manifest),'shipped and source assets')
