"""
core.func 兼容层

为 JavSP 爬虫代码提供通用工具函数的统一访问接口。
实际实现由 javsp_core.core.func 模块提供。
"""

import sys
import os
import importlib.util

# 直接加载原始的 func.py 文件（避免循环导入）
_original_module_path = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),  # python_scraper/
    'javsp_core',
    'core',
    'func.py'
)

# 使用 spec_from_file_location 加载原始模块
_spec = importlib.util.spec_from_file_location("original_core_func", _original_module_path)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

# 导出所有公共名称
if hasattr(_module, '__all__'):
    __all__ = list(_module.__all__)
else:
    # 自动导出所有非私有属性
    __all__ = [name for name in dir(_module) if not name.startswith('_')]

# 将所有公共属性添加到当前模块命名空间
for _name in __all__:
    if hasattr(_module, _name):
        globals()[_name] = getattr(_module, _name)
