"""
core.chromium 兼容层

为 JavSP 爬虫代码提供浏览器 Cookie 获取功能的统一访问接口。
实际实现由 javsp_core.core.chromium 模块提供。
"""

import sys
import os
import importlib.util

# 直接加载原始的 chromium.py 文件（避免循环导入）
_original_module_path = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),  # python_scraper/
    'javsp_core',
    'core',
    'chromium.py'
)

# 使用 spec_from_file_location 加载原始模块
_spec = importlib.util.spec_from_file_location("original_core_chromium", _original_module_path)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

# 导出主要函数
get_browsers_cookies = _module.get_browsers_cookies

# 导出所有公共名称
if hasattr(_module, '__all__'):
    __all__ = list(_module.__all__)
else:
    __all__ = ['get_browsers_cookies']
