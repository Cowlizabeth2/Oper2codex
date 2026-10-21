"""Build and smoke-test a standalone Windows folder, then create one artifact ZIP."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def build():
    if sys.platform != "win32":
        raise SystemExit("Windows packaging must run on Windows")
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    commit = os.environ.get("GITHUB_SHA", "local")
    (root / "operational_center" / "build.json").write_text(json.dumps({"commit": commit}), encoding="utf-8")
    subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--windowed", "--name", "OperationalCenter",
                    "--add-data", "operational_center/qml;operational_center/qml", "--add-data", "operational_center/build.json;operational_center",
                    "--hidden-import", "PySide6.QtQuick", "--hidden-import", "PySide6.QtQml", "main.py"], check=True)
    folder = root / "dist" / "OperationalCenter"
    report = root / "artifacts" / "packaged-smoke.json"
    report.parent.mkdir(exist_ok=True)
    subprocess.run([str(folder / "OperationalCenter.exe"), "--smoke-test", "--smoke-report", str(report)], check=True, timeout=60)
    result = json.loads(report.read_text(encoding="utf-8"))
    if not result["ok"] or len(result["checks"]) != 9 or result["qml_errors"]:
        raise RuntimeError("Packaged application failed functional QML smoke-test")
    scripts = {
        "ЗАПУСТИТЬ.bat": '@echo off\r\ncd /d "%~dp0"\r\nstart "" "OperationalCenter.exe"\r\n',
        "ДИАГНОСТИКА.bat": '@echo off\r\nchcp 65001 >nul\r\ncd /d "%~dp0"\r\nstart "" /wait "OperationalCenter.exe"\r\necho Код выхода: %errorlevel%\r\necho Логи: %LOCALAPPDATA%\\OperationalCenter\\startup.log\r\npause\r\n',
        "ОТКРЫТЬ_ЛОГИ.bat": '@echo off\r\nexplorer "%LOCALAPPDATA%\\OperationalCenter"\r\n',
    }
    for name, content in scripts.items():
        (folder / name).write_bytes(content.encode("utf-8"))
    shutil.copy2(root / "docs" / "USER_GUIDE.md", folder / "ИНСТРУКЦИЯ.md")
    shutil.copy2(report, folder / "build-smoke.json")
    shutil.make_archive(str(root / "artifacts" / "OperationalCenter-Windows"), "zip", folder.parent, folder.name)


if __name__ == "__main__":
    build()
