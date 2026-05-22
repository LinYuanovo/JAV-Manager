"""
爬虫上下文管理器 - 提供线程安全的依赖注入机制

使用方式:
    with CrawlerContext() as ctx:
        request = ctx.get_request()
        html = request.get(url)
"""

import threading
import logging
from typing import Dict, Optional, Any
from contextlib import contextmanager

from .base import Request


logger = logging.getLogger(__name__)


class CrawlerContext:
    """
    爬虫运行时上下文
    
    封装所有爬虫需要的共享资源（如Request实例、Cookie池等），
    通过依赖注入的方式提供给各个模块，避免全局可变状态。
    
    Features:
        - 线程安全的资源管理
        - 自动清理资源
        - 支持嵌套上下文
        - 详细的日志记录
    """
    
    _instance_lock = threading.Lock()
    _current_context = threading.local()  # 线程本地存储
    
    def __init__(
        self,
        use_scraper: bool = False,
        cookies: Optional[Dict[str, str]] = None,
        custom_headers: Optional[Dict[str, str]] = None
    ):
        """
        初始化爬虫上下文
        
        Args:
            use_scraper: 是否使用反检测浏览器模拟
            cookies: 初始Cookie字典
            custom_headers: 自定义请求头
        """
        self._lock = threading.RLock()
        self._resources: Dict[str, Any] = {}
        self._cookies_pool: list = []
        
        logger.debug(f"[Context] 创建新的CrawlerContext实例 (use_scraper={use_scraper})")
        
        with self._lock:
            self._initialize_request(use_scraper, cookies, custom_headers)
    
    def _initialize_request(
        self,
        use_scraper: bool,
        cookies: Optional[Dict[str, str]],
        headers: Optional[Dict[str, str]]
    ) -> None:
        """初始化HTTP请求对象"""
        try:
            self._resources['request'] = Request(
                use_scraper=use_scraper
            )
            
            if cookies:
                self.set_cookies(cookies)
                
            if headers:
                self.update_headers(headers)
                
            logger.info(
                f"[Context] ✅ Request对象初始化成功 "
                f"(scraper={'启用' if use_scraper else '禁用'})"
            )
            
        except Exception as e:
            logger.error(f"[Context] ❌ Request对象初始化失败: {e}", exc_info=True)
            raise
    
    @property
    def request(self) -> Request:
        """获取当前上下文的Request对象（线程安全）"""
        with self._lock:
            if 'request' not in self._resources:
                raise RuntimeError("Request对象未初始化")
            return self._resources['request']
    
    def get_request(self) -> Request:
        """
        获取Request对象的显式方法
        
        Returns:
            Request: HTTP请求对象
            
        Raises:
            RuntimeError: 如果Request未初始化
        """
        return self.request
    
    def set_cookies(self, cookies: Dict[str, str]) -> None:
        """
        设置请求Cookies
        
        Args:
            cookies: Cookie字典 {name: value}
        """
        with self._lock:
            if 'request' in self._resources:
                req = self._resources['request']
                req.cookies.update(cookies)
                
                # 同步到scraper（如果存在）
                if hasattr(req, 'scraper') and req.scraper:
                    req.scraper.cookies.update(cookies)
                    
                logger.debug(f"[Context] 已更新Cookies ({len(cookies)}个)")
    
    def update_headers(self, headers: Dict[str, str]) -> None:
        """
        更新请求头
        
        Args:
            headers: 要添加/更新的头部字典
        """
        with self._lock:
            if 'request' in self._resources:
                req = self._resources['request']
                req.headers.update(headers)
                logger.debug(f"[Context] 已更新请求头 ({len(headers)}个)")
    
    def add_to_cookies_pool(self, profile_info: Dict[str, Any]) -> None:
        """
        添加一组Cookies到池中
        
        Args:
            profile_info: Cookie信息字典，应包含:
                - profile: 来源标识 (如 'chrome', 'config')
                - site: 目标站点域名
                - cookies: Cookie字典
        """
        with self._lock:
            required_keys = {'profile', 'site', 'cookies'}
            if not all(k in profile_info for k in required_keys):
                logger.error(f"[Context] 无效的Cookie信息: 缺少必要字段 {required_keys - set(profile_info.keys())}")
                return
                
            self._cookies_pool.append(profile_info)
            logger.info(
                f"[Context] 添加Cookies到池: "
                f"source='{profile_info['profile']}', "
                f"site='{profile_info['site']}' "
                f"(池大小: {len(self._cookies_pool)})"
            )
    
    def get_next_cookies(self) -> Optional[Dict[str, str]]:
        """
        从池中获取下一组Cookies（FIFO）
        
        Returns:
            Cookie字典，如果池为空则返回None
        """
        with self._lock:
            if self._cookies_pool:
                cookie_info = self._cookies_pool.pop(0)
                logger.info(
                    f"[Context] 从池中取出Cookies: "
                    f"source='{cookie_info['profile']}' "
                    f"(剩余: {len(self._cookies_pool)})"
                )
                return cookie_info['cookies']
            else:
                logger.warning("[Context] Cookies池已空")
                return None
    
    def reset_request(self, use_scraper: bool = False) -> None:
        """
        重置Request对象（用于切换Cookies后）
        
        Args:
            use_scraper: 是否使用反检测
        """
        with self._lock:
            old_scraper = getattr(
                self._resources.get('request', {}),
                'scraper',
                None
            ) is not None
            
            logger.info(
                f"[Context] 重置Request对象 "
                f"(旧scraper={'有' if old_scraper else '无'} → "
                f"新scraper={'启用' if use_scraper else '禁用'})"
            )
            
            self._resources['request'] = Request(use_scraper=use_scraper)
    
    def __enter__(self):
        """进入上下文管理器"""
        logger.debug("[Context] 进入上下文")
        CrawlerContext._current_context.context = self
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """退出上下文管理器，自动清理资源"""
        try:
            if exc_type:
                logger.error(
                    f"[Context] ❌ 退出上下文 (异常: {exc_type.__name__}: {exc_val})"
                )
            else:
                logger.info("[Context] ✅ 正常退出上下文")
                
            with self._lock:
                resource_count = len(self._resources)
                self._resources.clear()
                cookies_count = len(self._cookies_pool)
                self._cookies_pool.clear()
                
                logger.debug(
                    f"[Context] 清理完成: "
                    f"释放{resource_count}个资源, "
                    f"清除{cookies_count}组缓存Cookies"
                )
                
        except Exception as e:
            logger.error(f"[Context] 清理资源时出错: {e}", exc_info=True)
        finally:
            CrawlerContext._current_context.context = None
        return False  # 不抑制异常
    
    @classmethod
    @contextmanager
    def get_current(cls):
        """
        获取当前线程的上下文（如果存在）
        
        Yields:
            CrawlerContext or None: 当前上下文
            
        Example:
            with CrawlerContext.get_current() as ctx:
                if ctx:
                    request = ctx.request
        """
        context = getattr(cls._current_context, 'context', None)
        yield context
    
    @classmethod
    def create_for_crawler(
        cls,
        crawler_name: str,
        use_scraper: bool = False,
        **kwargs
    ) -> 'CrawlerContext':
        """
        工厂方法：为特定爬虫创建专用上下文
        
        Args:
            crawler_name: 爬虫名称（用于日志）
            use_scraper: 是否使用反检测
            **kwargs: 其他初始化参数
            
        Returns:
            CrawlerContext: 配置好的上下文实例
        """
        logger.info(f"[Factory] 为爬虫 '{crawler_name}' 创建专用上下文")
        return cls(use_scraper=use_scraper, **kwargs)


# 全局默认上下文（向后兼容）
_default_context: Optional[CrawlerContext] = None
_context_lock = threading.Lock()


def get_global_context() -> CrawlerContext:
    """
    获取全局默认上下文（懒加载）
    
    Returns:
        CrawlerContext: 全局上下文实例
    """
    global _default_context
    
    with _context_lock:
        if _default_context is None:
            logger.info("[Global] 初始化全局默认CrawlerContext")
            _default_context = CrawlerContext()
        return _default_context


def reset_global_context() -> None:
    """重置全局上下文（主要用于测试）"""
    global _default_context
    
    with _context_lock:
        if _default_context:
            logger.warning("[Global] 重置全局CrawlerContext")
            _default_context = None
