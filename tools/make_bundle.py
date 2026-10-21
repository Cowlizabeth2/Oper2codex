"""Produce a deterministic source archive; never include local databases or secrets."""
import hashlib
import json
from pathlib import Path
import zipfile


def make_bundle(root, output):
    root, output = Path(root), Path(output)
    files = []
    for name in ["main.py", "requirements.txt", "requirements-dev.txt", "README.md", ".gitignore"]:
        if (root / name).is_file():
            files.append(root / name)
    for directory in ["operational_center", "tools", "tests", "docs", ".github"]:
        files.extend(p for p in (root / directory).rglob("*") if p.is_file() and not any(part in {"__pycache__", ".pytest_cache"} for part in p.parts) and p.suffix not in {".pyc", ".log", ".sqlite"})
    entries = {str(p.relative_to(root)).replace("\\", "/"): p.read_bytes() for p in sorted(set(files))}
    entries["bundle-manifest.json"] = json.dumps({"format": 1, "sha256": {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()}}, sort_keys=True, indent=2).encode()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return output


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    print(make_bundle(root, root / "source_bundle.zip"))
