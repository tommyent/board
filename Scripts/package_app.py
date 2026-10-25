"""Copy the Release app into dist; preserve any previous package in build/PreviousBuilds."""
from pathlib import Path
import datetime, plistlib, shutil
root=Path(__file__).resolve().parents[1]
source=root/'build/DerivedData/Build/Products/Release/Board.app'
with (source/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
assert info['CFBundleIdentifier']=='com.tommyent.Board', 'Unexpected package identity'
destination=root/'dist/Board.app'
destination.parent.mkdir(exist_ok=True)
if destination.exists():
    with (destination/'Contents/Info.plist').open('rb') as f:
        assert plistlib.load(f)['CFBundleIdentifier']=='com.tommyent.Board', 'Unexpected previous package identity'
    previous=root/'build/PreviousBuilds'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    previous.mkdir(parents=True)
    destination.rename(previous/destination.name)
shutil.copytree(source,destination,symlinks=True)
print(destination)
