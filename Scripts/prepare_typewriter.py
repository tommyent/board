"""Trim leading silence from the preserved CC0 keystrokes; retain their complete decay."""
from pathlib import Path
import hashlib, json, struct, wave

root = Path(__file__).resolve().parents[1]
records = json.loads((root/'Docs/typewriter-assets.json').read_text())
for record in records:
    destination = root/record['path']
    source = root/'Docs/References/typewriter'/destination.name
    with wave.open(str(source), 'rb') as audio:
        params = audio.getparams()
        assert params.sampwidth == 2
        data = audio.readframes(params.nframes)
    samples = struct.unpack('<'+'h'*(len(data)//2), data)
    threshold = max(abs(value) for value in samples)*0.01
    onset = next(i for i, value in enumerate(samples) if abs(value) > threshold)//params.nchannels
    start = max(0, onset-round(params.framerate*0.002))
    with wave.open(str(destination), 'wb') as audio:
        audio.setparams(params)
        audio.writeframes(data[start*params.nchannels*params.sampwidth:])
    record.update(originalPath=str(source.relative_to(root)), originalSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
                  processing=f'Leading silence trimmed by {start} frames, retaining 2 ms before the 1%-peak onset and the full decay. Complete keystroke plays on press only. Runtime mono PCM conversion, DC removal, and 1 ms boundary fades.')
(root/'Docs/typewriter-assets.json').write_text(json.dumps(records, indent=2)+'\n')
print('Prepared four typewriter variations from preserved CC0 source recordings')
