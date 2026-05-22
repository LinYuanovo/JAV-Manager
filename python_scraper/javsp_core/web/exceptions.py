"""
统一的异常处理和重试策略管理系统

提供：
1. 分层的异常类型体系
2. 可配置的重试策略
3. 统一的错误日志记录格式
4. 异常上下文信息捕获
"""

import time
import functools
import logging
from typing import Any, Callable, Dict, List, Optional, Type, Union
from dataclasses import dataclass, field


logger = logging.getLogger(__name__)


# ============================================================
# 异常分类常量（用于策略匹配）
# ============================================================

class ExceptionCategory:
    """异常类别标识"""
    NOT_FOUND = 'not_found'           # 资源未找到（不重试）
    DUPLICATE = 'duplicate'           # 重复数据（不重试）
    PERMISSION = 'permission'         # 权限不足（不重试）
    BLOCKED = 'blocked'               # 被封锁/限制（不重试）
    NETWORK_TRANSIENT = 'network_transient'  # 临时网络错误（应重试）
    NETWORK_PERMANENT = 'network_permanent'  # 永久网络错误（有限重试）
    SERVER_ERROR = 'server_error'     # 服务端错误（应重试）
    UNKNOWN = 'unknown'               # 未知错误（谨慎重试）


# ============================================================
# 增强的异常类（带上下文信息）
# ============================================================

@dataclass
class ErrorContext:
    """
    错误上下文信息
    
    用于捕获异常发生时的环境信息，便于调试和分析。
    """
    timestamp: float = field(default_factory=time.time)
    module: str = ''
    function: str = ''
    url: str = ''
    retry_count: int = 0
    extra_data: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'timestamp': self.timestamp,
            'module': self.module,
            'function': self.function,
            'url': self.url[:100] if self.url else '',
            'retry_count': self.retry_count,
            'extra_data': self.extra_data
        }


class CrawlerError(Exception):
    """
    所有站点抓取器相关异常的基类（增强版）
    
    现在支持：
    - 错误上下文自动捕获
    - 结构化的错误信息
    - 类别标识用于策略匹配
    """
    
    category = ExceptionCategory.UNKNOWN
    should_retry = False
    default_log_level = logging.ERROR
    
    def __init__(self, message: str, *args, **kwargs) -> None:
        super().__init__(message, *args)
        
        # 提取可选的上下文参数
        self.context = ErrorContext(
            module=kwargs.pop('module', ''),
            function=kwargs.pop('function', ''),
            url=kwargs.pop('url', ''),
            extra_data=kwargs.get('extra_data', {})
        )
        
        # 存储原始参数（保持向后兼容）
        self._raw_args = args if args else None
    
    @property
    def user_friendly_message(self) -> str:
        """面向用户的友好错误消息"""
        return str(self.args[0]) if self.args else "未知错误"
    
    @property
    def technical_details(self) -> str:
        """技术细节消息（包含上下文）"""
        details = [self.user_friendly_message]
        
        if self.context.module:
            details.append(f"模块: {self.context.module}")
        if self.context.function:
            details.append(f"函数: {self.context.function}")
        if self.context.url:
            details.append(f"URL: {self.context.url}")
            
        return " | ".join(details)
    
    def log(self, log_level: Optional[int] = None) -> None:
        """
        使用统一格式记录此异常
        
        Args:
            log_level: 日志级别，默认使用类的 default_log_level
        """
        level = log_level or self.default_log_level
        logger.log(level, f"[{type(self).__name__}] {self.technical_details}", exc_info=True)
    
    def __str__(self) -> str:
        return self.user_friendly_message
    
    def __repr__(self) -> str:
        return f"{type(self).__name__}('{self.user_friendly_message}', category='{self.category}')"


class MovieNotFoundError(CrawlerError):
    """表示某个站点没有抓取到某部影片"""
    category = ExceptionCategory.NOT_FOUND
    should_retry = False
    default_log_level = logging.DEBUG  # 这是正常情况，不需要ERROR级别
    
    def __init__(self, mod: str, avid: str, *suggestions) -> None:
        msg = f"{mod}: 未找到影片: '{avid}'"
        if suggestions:
            sug_str = ', '.join(str(s) for s in suggestions[:5])
            msg += f" (相似结果: {sug_str})"
        super().__init__(
            msg,
            module=mod,
            extra_data={'avid': avid, 'suggestions_count': len(suggestions)}
        )
        self.suggestions = suggestions


class MovieDuplicateError(CrawlerError):
    """影片重复"""
    category = ExceptionCategory.DUPLICATE
    should_retry = False
    default_log_level = logging.WARNING
    
    def __init__(self, mod: str, avid: str, dup_count: int, *args) -> None:
        msg = f"{mod}: '{avid}': 存在{dup_count}个完全匹配目标番号的搜索结果"
        super().__init__(
            msg,
            module=mod,
            extra_data={'avid': avid, 'duplicate_count': dup_count}
        )
        self.duplicate_count = dup_count


class SiteBlocked(CrawlerError):
    """由于IP段或者触发反爬机制等原因导致用户被站点封锁"""
    category = ExceptionCategory.BLOCKED
    should_retry = False
    default_log_level = logging.ERROR
    
    def __init__(self, message: str, url: str = '', status_code: int = 0) -> None:
        super().__init__(
            message,
            url=url,
            extra_data={'status_code': status_code}
        )
        self.status_code = status_code


class SitePermissionError(CrawlerError):
    """由于缺少权限而无法访问影片资源"""
    category = ExceptionCategory.PERMISSION
    should_retry = False
    default_log_level = logging.WARNING
    
    def __init__(self, message: str, url: str = '') -> None:
        super().__init__(message, url=url)


class CredentialError(CrawlerError):
    """由于缺少Cookies等凭据而无法访问影片资源"""
    category = ExceptionCategory.PERMISSION
    should_retry = False
    default_log_level = logging.WARNING
    
    def __init__(self, message: str, site: str = '') -> None:
        super().__init__(message, extra_data={'site': site})


class WebsiteError(CrawlerError):
    """非预期的状态码等网页故障"""
    category = ExceptionCategory.SERVER_ERROR
    should_retry = True
    default_log_level = logging.ERROR
    
    def __init__(self, message: str, url: str = '', status_code: int = 0) -> None:
        super().__init__(
            message,
            url=url,
            extra_data={'status_code': status_code}
        )
        self.status_code = status_code


class NetworkTransientError(CrawlerError):
    """临时性网络错误（超时、连接中断等）"""
    category = ExceptionCategory.NETWORK_TRANSIENT
    should_retry = True
    default_log_level = logging.WARNING
    
    def __init__(self, message: str, url: str = '', original_error: Exception = None) -> None:
        super().__init__(
            message,
            url=url,
            extra_data={
                'original_error_type': type(original_error).__name__ if original_error else None
            }
        )
        self.original_error = original_error


class OtherError(CrawlerError):
    """其他尚未分类的错误"""
    category = ExceptionCategory.UNKNOWN
    should_retry = False
    default_log_level = logging.ERROR


# ============================================================
# 重试策略配置
# ============================================================

@dataclass
class RetryPolicy:
    """
    重试策略配置
    
    Attributes:
        max_retries: 最大重试次数
        base_delay: 基础延迟时间（秒）
        max_delay: 最大延迟时间（秒）
        exponential_base: 指数退避底数 (delay = base_delay * exponential_base^attempt)
        jitter: 是否添加随机抖动（避免惊群效应）
        retryable_exceptions: 可重试的异常类型集合
    """
    max_retries: int = 3
    base_delay: float = 1.0
    max_delay: float = 30.0
    exponential_base: float = 2.0
    jitter: bool = True
    retryable_exceptions: tuple = (
        NetworkTransientError,
        WebsiteError,
    )
    
    def get_delay(self, attempt: int) -> float:
        """
        计算第N次重试的等待时间
        
        Args:
            attempt: 当前尝试次数（从0开始）
            
        Returns:
            float: 应等待的秒数
        """
        import random
        
        delay = min(
            self.base_delay * (self.exponential_base ** attempt),
            self.max_delay
        )
        
        if self.jitter:
            delay *= (0.5 + random.random())
            
        return delay
    
    def should_retry_exception(self, exception: Exception) -> bool:
        """
        判断某个异常是否应该触发重试
        
        Args:
            exception: 发生的异常
            
        Returns:
            bool: 是否应该重试
        """
        if isinstance(exception, CrawlerError):
            return exception.should_retry
            
        return isinstance(exception, self.retryable_exceptions)


# 默认重试策略实例
DEFAULT_RETRY_POLICY = RetryPolicy()


# ============================================================
# 重试装饰器和工具函数
# ============================================================

def with_retry(
    policy: Optional[RetryPolicy] = None,
    on_failure: Optional[Callable] = None,
    context_extractor: Optional[Callable] = None
):
    """
    自动重试装饰器
    
    为函数添加自动重试功能，支持自定义的重试策略和失败回调。
    
    Args:
        policy: 重试策略，默认使用 DEFAULT_RETRY_POLICY
        on_failure: 每次失败时的回调函数 signature: (exception, attempt, delay) -> None
        context_extractor: 从异常中提取额外上下文的函数
        
    Example:
        >>> @with_retry()
        ... def fetch_data(url):
        ...     ...
        
        >>> custom_policy = RetryPolicy(max_retries=5, base_delay=2.0)
        >>> @with_retry(policy=custom_policy)
        ... def critical_operation():
        ...     ...
    """
    _policy = policy or DEFAULT_RETRY_POLICY
    
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            last_exception = None
            
            for attempt in range(_policy.max_retries + 1):
                try:
                    result = func(*args, **kwargs)
                    
                    if attempt > 0:
                        logger.info(
                            f"[Retry] ✅ 函数 '{func.__name__}' 在第 "
                            f"{attempt + 1} 次尝试成功"
                        )
                    
                    return result
                    
                except Exception as e:
                    last_exception = e
                    
                    if not _policy.should_retry_exception(e):
                        logger.debug(
                            f"[Retry] 函数 '{func.__name__}' 遇到不可重试异常: "
                            f"{type(e).__name__}: {e}"
                        )
                        raise
                    
                    if attempt < _policy.max_retries:
                        delay = _policy.get_delay(attempt)
                        
                        logger.warning(
                            f"[Retry] ⚠️  函数 '{func.__name__}' 第 "
                            f"{attempt + 1}/{_policy.max_retries} 次失败: "
                            f"{type(e).__name__}: {str(e)[:100]}... "
                            f"(等待 {delay:.1f}s 后重试)"
                        )
                        
                        if on_failure:
                            try:
                                on_failure(e, attempt, delay)
                            except Exception as callback_err:
                                logger.error(
                                    f"[Retry] 失败回调执行出错: {callback_err}"
                                )
                        
                        time.sleep(delay)
                    else:
                        logger.error(
                            f"[Retry] ❌ 函数 '{func.__name__}' 在 "
                            f"{_policy.max_retries + 1} 次尝试后仍然失败"
                        )
            
            raise last_exception
            
        return wrapper
    return decorator


def handle_crawler_exception(
    exception: Exception,
    crawler_name: str = '',
    movie_id: str = '',
    reraise: bool = True
) -> bool:
    """
    统一的爬虫异常处理函数
    
    根据异常类型进行分类处理，记录结构化日志，
    并决定是否重新抛出异常。
    
    Args:
        exception: 捕获到的异常
        crawler_name: 当前爬虫名称（用于日志）
        movie_id: 正在处理的影片ID
        reraise: 是否重新抛出异常
        
    Returns:
        bool: 是否为可恢复的错误（True表示可以继续）
        
    Example:
        >>> try:
        ...     parse_data(movie)
        ... except Exception as e:
        ...     if handle_crawler_exception(e, crawler_name='javdb', movie_id='ABP-123'):
        ...         continue  # 可恢复，继续下一个
        ...     else:
        ...         break     # 不可恢复，停止处理
    """
    prefix = f"[{crawler_name}] " if crawler_name else ""
    id_info = f" (ID: '{movie_id}')" if movie_id else ""
    
    if isinstance(exception, CrawlerError):
        enhanced_exc = exception
        enhanced_exc.context.module = crawler_name
        enhanced_exc.log()
        
    elif isinstance(exception, ConnectionError):
        logger.warning(
            f"{prefix}⚠️  连接错误{id_info}: "
            f"{type(exception).__name__}: {str(exception)[:150]}"
        )
        enhanced_exc = NetworkTransientError(
            f"网络连接失败{id_info}",
            original_error=exception
        )
        
    elif isinstance(exception, TimeoutError):
        logger.warning(
            f"{prefix}⏰ 请求超时{id_info}: "
            f"{str(exception)[:150]}"
        )
        enhanced_exc = NetworkTransientError(
            f"请求超时{id_info}",
            original_error=exception
        )
        
    else:
        logger.error(
            f"{prefix}💥 未预期异常{id_info}: "
            f"{type(exception).__name__}: {str(exception)[:200]}",
            exc_info=True
        )
        enhanced_exc = OtherError(
            f"未预期的错误{id_info}: {str(exception)[:100]}"
        )
    
    should_continue = enhanced_exc.should_retry
    
    if reraise and not should_continue:
        raise enhanced_exc
        
    return should_continue


def classify_exception(exception: Exception) -> str:
    """
    将普通异常分类为CrawlerError类别
    
    用于将第三方库的异常映射到我们的异常体系中。
    
    Args:
        exception: 要分类的异常
        
    Returns:
        str: ExceptionCategory 常量值
    """
    if isinstance(exception, CrawlerError):
        return exception.category
        
    exc_type = type(exception).__name__
    
    if 'Timeout' in exc_type or 'Connection' in exc_type:
        return ExceptionCategory.NETWORK_TRANSIENT
    elif 'HTTP' in exc_type and hasattr(exception, 'code'):
        code = getattr(exception, 'code', 0)
        if code in (403, 503):
            return ExceptionCategory.BLOCKED
        elif code == 404:
            return ExceptionCategory.NOT_FOUND
        elif code >= 500:
            return ExceptionCategory.SERVER_ERROR
        elif code == 401 or code == 403:
            return ExceptionCategory.PERMISSION
    elif 'NotFound' in exc_type:
        return ExceptionCategory.NOT_FOUND
        
    return ExceptionCategory.UNKNOWN


# ============================================================
# 便捷别名（向后兼容）
# ============================================================

__all__ = [
    'CrawlerError',
    'MovieNotFoundError',
    'MovieDuplicateError',
    'SiteBlocked',
    'SitePermissionError',
    'CredentialError',
    'WebsiteError',
    'OtherError',
    'NetworkTransientError',
    'ExceptionCategory',
    'RetryPolicy',
    'DEFAULT_RETRY_POLICY',
    'with_retry',
    'handle_crawler_exception',
    'classify_exception',
]
