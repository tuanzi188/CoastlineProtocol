"""按需安装本地 Godot 静态检查工具 gdtoolkit。

依赖树含数百个文件、约 5MB，且带平台相关的编译扩展（.pyd），不适合入库。
此前 vendor 进仓库的那份副本正因为 *.pyd 被忽略而缺 regex / pyyaml 扩展，
gdlint 实际跑不起来（ImportError: regex module must be installed）。

改为装进本地虚拟环境 tools/gdcheck/（已 gitignore）：

    python tools/setup_gdcheck.py

之后：

    tools\\gdcheck\\Scripts\\gdlint.exe scripts
    tools\\gdcheck\\Scripts\\gdformat.exe scripts
"""

import subprocess
import sys
from pathlib import Path

VERSION = 'gdtoolkit==4.5.0'
TARGET = Path(__file__).resolve().parent / 'gdcheck'


def run(command):
    command = [str(part) for part in command]
    print(' '.join(command))
    subprocess.check_call(command)


def main():
    scripts = TARGET / ('Scripts' if sys.platform == 'win32' else 'bin')
    python = scripts / ('python.exe' if sys.platform == 'win32' else 'python')
    if not python.exists():
        run([sys.executable, '-m', 'venv', str(TARGET)])
    run([python, '-m', 'pip', 'install', '--quiet', '--upgrade', 'pip'])
    run([python, '-m', 'pip', 'install', VERSION])
    print('done. try: %s scripts' % (scripts / 'gdlint'))


if __name__ == '__main__':
    main()
