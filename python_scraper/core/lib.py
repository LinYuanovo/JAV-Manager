"""
core.lib 兼容层

为 JavSP 爬虫代码提供工具函数的统一访问接口。
实际实现由 javsp_core.core.lib 模块提供。
"""

import sys
import os
import importlib.util

# 直接加载原始的 lib.py 文件（避免循环导入）
_original_lib_path = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),  # python_scraper/
    'javsp_core',
    'core',
    'lib.py'
)

# 使用 spec_from_file_location 加载原始模块
_spec = importlib.util.spec_from_file_location("original_core_lib", _original_lib_path)
_lib_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_lib_module)

# 导出所有公共函数
re_escape = _lib_module.re_escape
mei_path = _lib_module.mei_path
strftime_to_minutes = _lib_module.strftime_to_minutes
detect_special_attr = _lib_module.detect_special_attr

__all__ = [
    're_escape',
    'mei_path',
    'strftime_to_minutes',
    'detect_special_attr'
]
