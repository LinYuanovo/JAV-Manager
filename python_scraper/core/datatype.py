"""
core.datatype 兼容层

为 JavSP 爬虫代码提供数据类型定义的统一访问接口。
通过 sys.modules 共享同一个模块实例，确保 isinstance 检查正常工作。
"""

import sys
import os

# 确保原始模块已加载（__main__.py 先通过 javsp_core.core.datatype 导入）
_original_module_name = 'javsp_core.core.datatype'
if _original_module_name not in sys.modules:
    # 如果还未加载，手动加载（兼容某些边缘情况）
    import importlib
    importlib.import_module(_original_module_name)

_module = sys.modules[_original_module_name]

# 导出主要类
Movie = _module.Movie
MovieInfo = _module.MovieInfo
GenreMap = _module.GenreMap if hasattr(_module, 'GenreMap') else None

# 导出所有公共名称
if hasattr(_module, '__all__'):
    __all__ = list(_module.__all__)
else:
    __all__ = ['Movie', 'MovieInfo', 'GenreMap']
