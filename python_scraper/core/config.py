"""
core.config 兼容层

为 JavSP 爬虫代码提供统一的配置访问接口。
实际配置数据由 javsp_core.core.config_lite 模块管理。
"""

import sys
import os

# 调试：打印路径信息
_debug = os.environ.get('SCRAPER_DEBUG', '0') == '1'
if _debug:
    print(f"[DEBUG] core.config: __file__={__file__}", file=sys.stderr)
    print(f"[DEBUG] core.config: dirname={os.path.dirname(__file__)}", file=sys.stderr)

# 添加 javsp_core 到 Python 路径
_javsp_core_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'javsp_core'))
if _debug:
    print(f"[DEBUG] core.config: _javsp_core_path={_javsp_core_path}", file=sys.stderr)
    print(f"[DEBUG] core.config: exists={os.path.exists(_javsp_core_path)}", file=sys.stderr)

if _javsp_core_path not in sys.path:
    sys.path.insert(0, _javsp_core_path)

# 从轻量级配置模块导入（延迟导入以避免循环依赖）
_cfg = None
_ScraperConfig = None
_init_config = None
_config_lite_module = None

def _get_config():
    global _config_lite_module
    if _config_lite_module is None:
        # 尝试复用已加载的 javsp_core.core.config_lite 模块
        if 'javsp_core.core.config_lite' in sys.modules:
            _config_lite_module = sys.modules['javsp_core.core.config_lite']
        else:
            import importlib.util
            
            # 直接加载 javsp_core/core/config_lite.py 文件
            _config_lite_path = os.path.join(
                os.path.dirname(os.path.dirname(__file__)),  # python_scraper/
                'javsp_core',
                'core',
                'config_lite.py'
            )
            
            _spec = importlib.util.spec_from_file_location("javsp_core.core.config_lite", _config_lite_path)
            _config_lite_module = importlib.util.module_from_spec(_spec)
            _spec.loader.exec_module(_config_lite_module)
            
            # 注册到 sys.modules 以确保全局唯一
            sys.modules['javsp_core.core.config_lite'] = _config_lite_module
    
    # 每次都返回最新的 cfg 值（不缓存！）
    return _config_lite_module.cfg

class _ConfigProxy:
    """配置代理对象，提供延迟加载"""
    
    def __getattr__(self, name):
        cfg_obj = _get_config()
        # 如果配置还未初始化（cfg_obj 为 None），返回合理的默认值
        if cfg_obj is None:
            # 对于超时等数值属性，返回默认值
            if name in ('timeout', 'retry', 'max_workers'):
                return 10
            elif name in ('use_proxy', 'hardworking_mode', 'respect_site_avid',
                         'title_remove_actor', 'title_chinese_first',
                         'unify_actress_name', 'translate_title', 'translate_plot'):
                return False
            elif name in ('proxy', 'javdb_cookie', 'scan_dir'):
                return ''
            elif name == 'Network':
                return type('Network', (), {'timeout': 10, 'retry': 3, 'use_proxy': False, 'proxy': ''})()
            elif name == 'crawler':
                return type('Crawler', (), {
                    'required_keys': 'cover,title',
                    'javdb_cookie': '',
                    'hardworking_mode': True,
                    'sleep_after_scraping': 1
                })()
            else:
                raise AttributeError(f"Configuration not initialized. Cannot access '{name}' on None config")
        
        if hasattr(cfg_obj, name):
            return getattr(cfg_obj, name)
        raise AttributeError(f"'{type(cfg_obj).__name__}' object has no attribute '{name}'")
    
    def __repr__(self):
        cfg_obj = _get_config()
        if cfg_obj is None:
            return '<ConfigProxy (not initialized)>'
        return repr(cfg_obj)
    
    def __bool__(self):
        cfg_obj = _get_config()
        return bool(cfg_obj)

# 创建全局配置实例代理
cfg = _ConfigProxy()

# 向后兼容：提供 Config 类别名（延迟加载）
class _ConfigMeta(type):
    """元类 - 延迟加载 Config 类"""
    
    def __getattr__(cls, name):
        if name in ('__name__', '__doc__', '__module__'):
            raise AttributeError(name)
        # 触发配置模块的真正导入
        config_class = _get_config().__class__
        if hasattr(config_class, name):
            return getattr(config_class, name)
        raise AttributeError(f"'{config_class.__name__}' has no attribute '{name}'")

class Config(metaclass=_ConfigMeta):
    """Config 类的兼容别名（实际指向 ScraperConfig）"""
    pass

def __getattr__(name):
    """模块级别的属性访问（用于延迟加载）"""
    if name in ('ScraperConfig', 'init_config'):
        # 触发模块加载
        _get_config()
        if _config_lite_module:
            return getattr(_config_lite_module, name, None)
    raise AttributeError(f"module 'core.config' has no attribute '{name}'")

__all__ = ['cfg', 'Config', 'ScraperConfig', 'init_config']
