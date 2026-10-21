"""Record source smoke-test output and its actual process exit status."""
from pathlib import Path
import subprocess
import sys

if __name__ == "__main__":
    Path("artifacts").mkdir(exist_ok=True)
    result = subprocess.run([sys.executable, "main.py", "--smoke-test", "--smoke-report", "artifacts/source-smoke.json"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace", timeout=60)
    Path("artifacts/source-output.txt").write_text(result.stdout, encoding="utf-8")
    Path("artifacts/source-exit-code.txt").write_text(str(result.returncode), encoding="utf-8")
    print(result.stdout, end="")
    raise SystemExit(result.returncode)
