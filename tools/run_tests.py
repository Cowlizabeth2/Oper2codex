"""Keep the runner's exit code and retain output even after a native Qt crash."""
from pathlib import Path
import subprocess
import sys


if __name__ == "__main__":
    Path("artifacts").mkdir(exist_ok=True)
    result = subprocess.run([sys.executable, "-m", "pytest", "-q", "--junitxml=artifacts/tests.xml"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace", timeout=300)
    Path("artifacts/test-output.txt").write_text(result.stdout, encoding="utf-8")
    Path("artifacts/test-exit-code.txt").write_text(str(result.returncode), encoding="utf-8")
    print(result.stdout, end="")
    raise SystemExit(result.returncode)
