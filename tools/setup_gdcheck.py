"""按需安装本地 Godot 静态检查工具 gdtoolkit。

依赖树含数百个文件、约 5MB，不入版本库。需要 gdlint / gdformat 时运行：

    python tools/setup_gdcheck.py

安装到 tools/gdcheck/（已 gitignore）。之后可用：

    tools/gdcheck/bin/gdlint.exe scripts
    tools/gdcheck/bin/gdformat.exe scripts
"""

import subprocess
import sys
from pathlib import Path

VERSION = 'gdtoolkit==4.5.0'
TARGET = Path(__file__).resolve().parent / 'gdcheck'


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, '-m', 'pip', 'install', '--target', str(TARGET), VERSION]
    print(' '.join(command))
    raise SystemExit(subprocess.call(command))


if __name__ == '__main__':
    main()
