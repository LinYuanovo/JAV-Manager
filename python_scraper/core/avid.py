"""
core.avid 兼容层

为 JavSP 爬虫代码提供番号识别功能的统一访问接口。
实际实现由 javsp_core.core.avid 模块提供。
"""

import sys
import os
import importlib.util

# 直接加载原始的 avid.py 文件（避免循环导入）
_original_module_path = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),  # python_scraper/
    'javsp_core',
    'core',
    'avid.py'
)

# 使用 spec_from_file_location 加载原始模块
_spec = importlib.util.spec_from_file_location("original_core_avid", _original_module_path)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

# 导出所有公共函数和类
get_id = _module.get_id
get_cid = _module.get_cid
guess_av_type = _module.guess_av_type

# 别名（向后兼容）
extract_id = get_id  # extract_id 是 get_id 的别名

# 导出所有公共名称（如果有 __all__ 的话）
if hasattr(_module, '__all__'):
    __all__ = list(_module.__all__)
else:
    __all__ = ['get_id', 'get_cid', 'guess_av_type', 'extract_id']
