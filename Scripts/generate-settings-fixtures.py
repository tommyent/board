"""Print JSON fixtures encoded by historical Models.swift, without reading any preferences.

Run from the checkout; the output maps fixture filenames to their JSON contents.
"""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
fixtures = {}
for version, revision in [("0.4.1", "2debb8c"), ("0.4.7", "9dd875c")]:
    source = subprocess.check_output(
        ["git", "show", f"{revision}:Board/Models.swift"], cwd=root, text=True
    )
    with tempfile.TemporaryDirectory(prefix="board-settings-fixture-") as directory:
        main = Path(directory) / "main.swift"
        main.write_text(source + '\nlet encoder = JSONEncoder()\n'
                        'encoder.outputFormatting = [.prettyPrinted, .sortedKeys]\n'
                        'print(String(data:try encoder.encode(AppSettings()),encoding:.utf8)!)\n')
        executable = Path(directory) / "encode"
        subprocess.run(["xcrun", "swiftc", str(main), "-o", str(executable)], check=True)
        encoded = subprocess.check_output([str(executable)], text=True)
        assert json.loads(encoded)["version"] == 1
        fixtures[f"settings-{version}.json"] = encoded
print(json.dumps(fixtures))
