# -*- mode: python ; coding: utf-8 -*-
import sys
from pathlib import Path

block_cipher = None

# 获取当前 spec 文件所在目录（即 python_scraper）
scraper_dir = Path(SPECPATH)

a = Analysis(
    [str(scraper_dir / '__main__.py')],
    pathex=[str(scraper_dir)],
    binaries=[],
    datas=[
        # 包含 javsp_core 整个包
        (str(scraper_dir / 'javsp_core'), 'javsp_core'),
        (str(scraper_dir / 'core'), 'core'),
    ],
    hiddenimports=[
        'requests',
        'lxml',
        'lxml.etree',
        'bs4',
        'PIL',
        'Pillow',
        'json',
        'sys',
        'os',
        'pathlib',
        'threading',
        'concurrent.futures',
        'urllib.request',
        'urllib.parse',
        'urllib.error',
        're',
        'datetime',
        'hashlib',
        'shutil',
        'copy',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'tkinter',
        'matplotlib',
        'numpy',
        'pandas',
        'scipy',
        # 排除 Qt 绑定（避免冲突）
        'PyQt5',
        'PyQt6',
        'PySide2',
        'PySide6',
        # 其他不常用的库
        'IPython',
        'jupyter',
        'notebook',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='javsp_scraper',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,  # 使用 UPX 压缩（可选）
    console=True,  # 保持控制台窗口（用于 stdin/stdout 通信）
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
