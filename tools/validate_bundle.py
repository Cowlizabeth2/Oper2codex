"""Validate source ZIP before extracting it into a new, isolated build directory."""
import hashlib
import json
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

REQUIRED = {"main.py", "requirements.txt", "requirements-dev.txt", "operational_center/app.py", "operational_center/qml/Main.qml", "tools/build_windows.py", "bundle-manifest.json"}


def extract(source, destination):
    destination = Path(destination)
    if destination.exists():
        raise ValueError("Build destination must not exist")
    with zipfile.ZipFile(source) as archive:
        entries = archive.infolist()
        if len(entries) > 10000 or sum(e.file_size for e in entries) > 200 * 1024 * 1024:
            raise ValueError("Source bundle exceeds size limit")
        seen, names = set(), set()
        for entry in entries:
            name = entry.filename
            path = PurePosixPath(name)
            if (not name or "\\" in name or ":" in name or path.is_absolute() or ".." in path.parts
                    or any(p.endswith((" ", ".")) for p in path.parts)
                    or any(p.split(".")[0].upper() in {"CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"} for p in path.parts)
                    or stat.S_ISLNK(entry.external_attr >> 16) or entry.flag_bits & 1):
                raise ValueError("Unsafe source bundle entry")
            canonical = str(path).casefold()
            if canonical in seen:
                raise ValueError("Duplicate source bundle entry")
            seen.add(canonical)
            if not entry.is_dir():
                names.add(name)
        if not REQUIRED <= names:
            raise ValueError("Source bundle is missing required files")
        manifest = json.loads(archive.read("bundle-manifest.json"))
        if manifest.get("format") != 1 or set(manifest.get("sha256", {})) != names - {"bundle-manifest.json"}:
            raise ValueError("Invalid source bundle manifest")
        for name, digest in manifest["sha256"].items():
            if hashlib.sha256(archive.read(name)).hexdigest() != digest:
                raise ValueError("Source bundle checksum mismatch: " + name)
        destination.mkdir(parents=True)
        for entry in entries:
            if entry.is_dir():
                continue
            target = destination.joinpath(*PurePosixPath(entry.filename).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as stream:
                stream.write(archive.read(entry))
    return destination


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
