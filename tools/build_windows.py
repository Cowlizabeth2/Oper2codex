"""Build and smoke-test a standalone Windows folder, then create one artifact ZIP."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))


def checked_run(command, logfile, timeout=None):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace", timeout=timeout)
    Path(logfile).write_text(result.stdout, encoding="utf-8")
    print(result.stdout, end="")
    result.check_returncode()


def resolve_commit(root):
    commit=os.environ.get('GITHUB_SHA')
    if not commit:
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    if not re.fullmatch(r'[0-9a-fA-F]{40}',commit):
        raise ValueError('Для сборки требуется полный 40-символьный SHA коммита')
    return commit


def build():
    if sys.platform != "win32":
        raise SystemExit("Windows packaging must run on Windows")
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    commit = resolve_commit(root)
    (root / "artifacts").mkdir(exist_ok=True)
    (root / "operational_center" / "build.json").write_text(json.dumps({"commit": commit}), encoding="utf-8")
    checked_run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--windowed", "--name", "OperationalCenter",
                    "--add-data", "operational_center/qml;operational_center/qml", "--add-data", "operational_center/build.json;operational_center",
                    "--hidden-import", "PySide6.QtQuick", "--hidden-import", "PySide6.QtQml", "main.py"], root / "artifacts" / "build-output.txt")
    folder = root / "dist" / "OperationalCenter"
    report = root / "artifacts" / "packaged-smoke.json"
    report.parent.mkdir(exist_ok=True)
    checked_run([str(folder / "OperationalCenter.exe"), "--smoke-test", "--smoke-report", str(report)], root / "artifacts" / "packaged-output.txt", timeout=60)
    result = json.loads(report.read_text(encoding="utf-8"))
    if not result["ok"] or len(result["checks"]) != 14 or len(result.get("service_checks", [])) != 9 or result["qml_errors"] or result.get('commit') != commit:
        raise RuntimeError("Packaged application failed functional QML smoke-test")
    # This database exists on disk BEFORE the EXE starts. The ordinary clean
    # smoke workspace cannot substitute for a real application upgrade check.
    from tools.prepare_exe_upgrade import prepare
    with tempfile.TemporaryDirectory(prefix='oper-exe-upgrade-') as temp:
        data=Path(temp)/'old-profile'
        manifest=prepare(data)
        for phase in ['apply','verify']:
            upgrade_report=root/'artifacts'/f'packaged-upgrade-{phase}.json'
            checked_run([str(folder/'OperationalCenter.exe'),'--upgrade-test','--data-dir',str(data),
                         '--upgrade-manifest',str(manifest),'--upgrade-phase',phase,
                         '--upgrade-output',str(root/'artifacts'/'exe-upgrade'),
                         '--smoke-report',str(upgrade_report)],root/'artifacts'/f'packaged-upgrade-{phase}.txt',timeout=120)
            upgraded=json.loads(upgrade_report.read_text(encoding='utf-8'))
            if not upgraded['ok'] or upgraded.get('commit')!=commit or not upgraded.get('upgrade',{}).get('ok'):
                raise RuntimeError('Packaged EXE could not upgrade and reopen the precreated legacy database')
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
