"""Fetch pinned public recordings; only writes inside this checkout."""
import hashlib, io, json, pathlib, urllib.request, zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
REVISION = "ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4"
PACKS = {"alpaca", "blackink", "redink", "turquoise", "cream", "holypanda", "boxnavy", "buckling", "topre", "bluealps"}
url = f"https://codeload.github.com/tplai/kbsim/zip/{REVISION}"
data = urllib.request.urlopen(url, timeout=60).read()
archive = zipfile.ZipFile(io.BytesIO(data))
manifest = []
for item in archive.infolist():
    path = pathlib.PurePosixPath(item.filename)
    parts = path.parts
    if item.is_dir(): continue
    if "audio" in parts:
        rel = parts[parts.index("audio")+1:]
        if not rel or rel[0] not in PACKS: continue
        dest = ROOT / "Board/Resources/Audio" / pathlib.Path(*rel)
    elif path.name.lower() in {"license.md", "readme.md"}:
        dest = ROOT / "Docs/References" / ("kbsim-" + path.name)
    elif "src" in parts and path.suffix in {".ts", ".js", ".json"}:
        dest = ROOT / "Docs/References/kbsim-source" / pathlib.Path(*parts[parts.index("src")+1:])
    else: continue
    content = archive.read(item)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(content)
    manifest.append({"path": str(dest.relative_to(ROOT)), "source": f"https://github.com/tplai/kbsim/blob/{REVISION}/" + "/".join(parts[1:]), "author": "tplai/kbsim contributors; see preserved README and notices", "license": "MIT (repository notice)", "revision": REVISION, "sha256": hashlib.sha256(content).hexdigest(), "processing": "Unmodified source file"})
(ROOT / "Docs/imported-assets.json").write_text(json.dumps(manifest, indent=2))
print(f"Saved {len(manifest)} source files at {REVISION}")
