"""网络请求的统一接口"""
import os
import sys
import time
import shutil
import logging
import requests
import contextlib
try:
    from curl_cffi import requests as curl_requests
    HAS_CURL_CFFI = True
except ImportError:
    HAS_CURL_CFFI = False
import lxml.html
from tqdm import tqdm
from lxml import etree
from lxml.html.clean import Cleaner
from requests.models import Response


sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
from core.config import cfg
from web.exceptions import *


__all__ = ['Request', 'get_html', 'post_html', 'request_get', 'resp2html', 'is_connectable', 'download', 'get_resp_text']


headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'}

logger = logging.getLogger(__name__)
# 删除js脚本相关的tag，避免网页检测到没有js运行环境时强行跳转，影响调试
cleaner = Cleaner(kill_tags=['script', 'noscript'])


def _normalize_proxies(proxies):
    """将字符串格式的代理转换为 dict 格式（兼容新版 requests 库）
    
    新版 requests 库要求 proxies 参数必须是 dict（如 {'http': '...', 'https': '...'}），
    而旧版接受字符串。此函数做兼容转换。
    
    注意：返回 None 会让 requests 使用 trust_env 默认值（会读取系统代理），
    因此当代理未启用时，返回 {'http': None, 'https': None} 以显式禁用。
    """
    if isinstance(proxies, str) and proxies.strip():
        return {'http': proxies, 'https': proxies}
    # 显式禁用代理，防止 requests 使用系统代理（trust_env=True）
    return {'http': None, 'https': None}


# 与网络请求相关的功能汇总到一个模块中以方便处理，但是不同站点的抓取器又有自己的需求（针对不同网站
# 需要使用不同的UA、语言等）。每次都传递参数很麻烦，而且会面临函数参数越加越多的问题。因此添加这个
# 处理网络请求的类，它带有默认的属性，但是也可以在各个抓取器模块里进行进行定制
class Request():
    """作为网络请求出口并支持各个模块定制功能"""
    def __init__(self, use_scraper=False) -> None:
        # 必须使用copy()，否则各个模块对headers的修改都将会指向本模块中定义的headers变量，导致只有最后一个对headers的修改生效
        self.headers = headers.copy()
        self.cookies = {}
        if cfg.Network.use_proxy and cfg.Network.proxy:
            self.proxies = _normalize_proxies(cfg.Network.proxy)
        else:
            # 明确禁用代理，覆盖系统代理设置（requests trust_env=True 会读取系统代理）
            self.proxies = {'http': None, 'https': None}
        self.timeout = cfg.Network.timeout
        if not use_scraper:
            self.scraper = None
            self.__get = requests.get
            self.__post = requests.post
            self.__head = requests.head
        else:
            if HAS_CURL_CFFI:
                try:
                    # curl_cffi 的 Session 需要在创建时指定 impersonate
                    self.scraper = curl_requests.Session(impersonate="chrome110")
                    self.__get = self._scraper_monitor(self.scraper.get)
                    self.__post = self._scraper_monitor(self.scraper.post)
                    self.__head = self._scraper_monitor(self.scraper.head)
                    logger.info("成功初始化 curl_cffi Session (impersonate=chrome110)")
                except Exception as e:
                    logger.warning(f"curl_cffi 初始化失败: {e}，回退到常规 requests")
                    self.scraper = None
                    self.__get = requests.get
                    self.__post = requests.post
                    self.__head = requests.head
            else:
                logger.warning("curl_cffi 未安装，回退到常规 requests")
                self.scraper = None
                self.__get = requests.get
                self.__post = requests.post
                self.__head = requests.head

    def _scraper_monitor(self, func):
        """监控curl_cffi的工作状态，遇到挑战时尝试退回常规的requests请求"""
        def wrapper(*args, **kw):
            try:
                return func(*args, **kw)
            except Exception as e:
                logger.debug(f"scraper 请求失败: '{e}', 尝试退回常规的requests请求")
                if func == self.scraper.get:
                    return requests.get(*args, **kw)
                else:
                    return requests.post(*args, **kw)
        return wrapper

    def get(self, url, delay_raise=False):
        r = self.__get(url,
                      headers=self.headers,
                      proxies=self.proxies,
                      cookies=self.cookies,
                      timeout=self.timeout)
        if not delay_raise:
            r.raise_for_status()
        return r

    def post(self, url, data, delay_raise=False):
        r = self.__post(url,
                      data=data,
                      headers=self.headers,
                      proxies=self.proxies,
                      cookies=self.cookies,
                      timeout=self.timeout)
        if not delay_raise:
            r.raise_for_status()
        return r

    def head(self, url, delay_raise=True):
        r = self.__head(url,
                      headers=self.headers,
                      proxies=self.proxies,
                      cookies=self.cookies,
                      timeout=self.timeout)
        if not delay_raise:
            r.raise_for_status()
        return r

    def get_html(self, url):
        r = self.get(url)
        html = resp2html(r)
        return html


class DownloadProgressBar(tqdm):
    def update_to(self, b=1, bsize=1, tsize=None):
        if tsize is not None:
            self.total = tsize
        self.update(b * bsize - self.n)


def request_get(url, cookies={}, timeout=cfg.Network.timeout, delay_raise=False):
    """获取指定url的原始请求"""
    r = requests.get(url, headers=headers, proxies=_normalize_proxies(cfg.Network.proxy), cookies=cookies, timeout=timeout)
    if not delay_raise:
        if r.status_code == 403 and b'>Just a moment...<' in r.content:
            raise SiteBlocked(f"403 Forbidden: 无法通过CloudFlare检测: {url}")
        else:
            r.raise_for_status()
    return r


def request_post(url, data, cookies={}, timeout=cfg.Network.timeout, delay_raise=False):
    """向指定url发送post请求"""
    r = requests.post(url, data=data, headers=headers, proxies=_normalize_proxies(cfg.Network.proxy), cookies=cookies, timeout=timeout)
    if not delay_raise:
        r.raise_for_status()
    return r


def get_resp_text(resp: Response, encoding=None):
    """提取Response的文本"""
    if encoding:
        resp.encoding = encoding
    else:
        # curl_cffi 和 requests 的 apparent_encoding 行为可能不同
        # 优先使用 resp.encoding，如果为空则使用 apparent_encoding
        if hasattr(resp, 'apparent_encoding') and resp.apparent_encoding:
            resp.encoding = resp.apparent_encoding
        elif not resp.encoding:
            resp.encoding = 'utf-8'
    return resp.text


def get_html(url, encoding='utf-8'):
    """使用get方法访问指定网页并返回经lxml解析后的document"""
    resp = request_get(url)
    text = get_resp_text(resp, encoding=encoding)
    html = lxml.html.fromstring(text)
    html.make_links_absolute(url, resolve_base_href=True)
    # 清理功能仅应在需要的时候用来调试网页（如prestige），否则可能反过来影响调试（如JavBus）
    # html = cleaner.clean_html(html)
    if hasattr(sys, 'javsp_debug_mode'):
        lxml.html.open_in_browser(html, encoding=encoding)  # for develop and debug
    return html


def resp2html(resp, encoding='utf-8') -> lxml.html.HtmlComment:
    """将request返回的response转换为经lxml解析后的document"""
    text = get_resp_text(resp, encoding=encoding)
    html = lxml.html.fromstring(text)
    html.make_links_absolute(resp.url, resolve_base_href=True)
    # html = cleaner.clean_html(html)
    if hasattr(sys, 'javsp_debug_mode'):
        lxml.html.open_in_browser(html, encoding=encoding)  # for develop and debug
    return html


def post_html(url, data, encoding='utf-8', cookies={}):
    """使用post方法访问指定网页并返回经lxml解析后的document"""
    resp = request_post(url, data, cookies=cookies)
    text = get_resp_text(resp, encoding=encoding)
    html = lxml.html.fromstring(text)
    # jav321提供ed2k形式的资源链接，其中的非ASCII字符可能导致转换失败，因此要先进行处理
    ed2k_tags = html.xpath("//a[starts-with(@href,'ed2k://')]")
    for tag in ed2k_tags:
        tag.attrib['ed2k'], tag.attrib['href'] = tag.attrib['href'], ''
    html.make_links_absolute(url, resolve_base_href=True)
    for tag in ed2k_tags:
        tag.attrib['href'] = tag.attrib['ed2k']
        tag.attrib.pop('ed2k')
    # html = cleaner.clean_html(html)
    # lxml.html.open_in_browser(html, encoding=encoding)  # for develop and debug
    return html


def dump_xpath_node(node, filename=None):
    """将xpath节点dump到文件"""
    if not filename:
        filename = node.tag + '.html'
    with open(filename, 'wt', encoding='utf-8') as f:
        content = etree.tostring(node, pretty_print=True).decode('utf-8')
        f.write(content)


def is_connectable(url, timeout=3):
    """测试与指定url的连接"""
    try:
        r = requests.get(url, headers=headers, timeout=timeout)
        return True
    except requests.exceptions.RequestException as e:
        logger.debug(f"Not connectable: {url}\n" + repr(e))
        return False


def urlretrieve(url, filename=None, reporthook=None, headers=None):
    """
    使用requests实现urlretrieve（资源安全版本）
    
    使用上下文管理器确保网络连接和文件句柄都能正确关闭，
    即使在下载过程中发生异常也不会泄漏资源。
    
    Args:
        url: 要下载的URL
        filename: 保存路径
        reporthook: 进度回调函数
        headers: 请求头字典
        
    Raises:
        IOError: 文件写入失败时
        requests.RequestException: 网络请求失败时
    """
    logger.debug(f"[Download] 开始下载: '{url[:80]}...' → '{filename}'")
    
    response = None
    file_handle = None
    
    try:
        response = requests.get(
            url,
            headers=headers,
            proxies=_normalize_proxies(cfg.Network.proxy),
            stream=True,
            timeout=cfg.Network.timeout * 10  # 下载超时应更长
        )
        response.raise_for_status()
        
        file_handle = open(filename, 'wb+')
        
        bs = 1024
        size = int(response.headers.get("Content-Length", -1))
        blocknum = 0
        
        if reporthook:
            reporthook(blocknum, bs, size)
            
        for chunk in response.iter_content(chunk_size=bs):
            if chunk:
                file_handle.write(chunk)
                file_handle.flush()
                blocknum += 1
                
                if reporthook:
                    reporthook(blocknum, bs, size)
                    
        logger.info(
            f"[Download] ✅ 下载完成: "
            f"'{os.path.basename(filename)}' "
            f"({blocknum * bs / 1024:.1f} KB)"
        )
        
    except Exception as e:
        logger.error(
            f"[Download] ❌ 下载失败: {type(e).__name__}: {str(e)[:150]}",
            exc_info=True
        )
        
        if file_handle and not file_handle.closed:
            file_handle.close()
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                    logger.debug(f"[Download] 已清理不完整的文件: '{filename}'")
                except OSError as cleanup_err:
                    logger.warning(f"[Download] 清理文件失败: {cleanup_err}")
                    
        raise
        
    finally:
        if response:
            response.close()
        if file_handle and not file_handle.closed:
            file_handle.close()


class DownloadContext:
    """
    文件下载上下文管理器（批量下载场景）
    
    自动管理多个文件的下载过程，提供统一的错误处理和资源清理。
    
    Example:
        >>> with DownloadContext() as dl_ctx:
        ...     dl_ctx.download(url1, 'file1.jpg')
        ...     dl_ctx.download(url2, 'file2.jpg')
        ...     # 所有下载完成后自动统计和日志记录
    """
    
    def __init__(self, base_dir: str = '', max_concurrent: int = 3):
        """
        初始化下载上下文
        
        Args:
            base_dir: 基础保存目录
            max_concurrent: 最大并发下载数（预留）
        """
        self.base_dir = base_dir
        self.max_concurrent = max_concurrent
        self.downloaded_files: list = []
        self.failed_urls: list = []
        self._start_time = time.time()
        
        logger.debug(f"[DownloadContext] 初始化 (base_dir='{base_dir}')")
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        elapsed = time.time() - self._start_time
        
        summary = (
            f"[DownloadContext] 会话结束:\n"
            f"  ✅ 成功: {len(self.downloaded_files)} 个文件\n"
            f"  ❌ 失败: {len(self.failed_urls)} 个URL\n"
            f"  ⏱️  总耗时: {elapsed:.1f}s"
        )
        
        if exc_type:
            logger.error(summary)
        else:
            logger.info(summary)
            
        return False  # 不抑制异常
    
    def download(self, url: str, output_path: str, desc: str = None) -> dict:
        """
        在此上下文中下载单个文件
        
        Args:
            url: URL地址
            output_path: 输出路径
            desc: 描述信息
            
        Returns:
            dict: 下载结果信息 {total, elapsed, rate}
            
        Raises:
            Exception: 下载失败时抛出
        """
        if self.base_dir and not os.path.isabs(output_path):
            output_path = os.path.join(self.base_dir, output_path)
            
        try:
            info = download(url, output_path, desc)
            self.downloaded_files.append(output_path)
            return info
            
        except Exception as e:
            self.failed_urls.append({'url': url, 'path': output_path, 'error': str(e)})
            raise


def download(url, output_path, desc=None):
    """
    下载指定url的资源（带进度显示）
    
    Args:
        url: 资源URL（支持http/https，也支持本地文件复制）
        output_path: 保存路径
        desc: 进度条描述文字
        
    Returns:
        dict: 下载统计信息 {total, elapsed, rate}
        
    Example:
        >>> info = download('https://example.com/image.jpg', 'image.jpg')
        >>> print(f"下载速度: {info['rate']:.2f} bytes/s")
    """
    # 支持"下载"本地资源，以供fc2fan的本地镜像所使用
    if not url.startswith('http'):
        start_time = time.time()
        shutil.copyfile(url, output_path)
        filesize = os.path.getsize(url)
        elapsed = time.time() - start_time
        info = {'total': filesize, 'elapsed': elapsed, 'rate': filesize / (elapsed + 0.001)}
        logger.info(f"[Download] 本地复制完成: '{output_path}' ({filesize} bytes)")
        return info
        
    if not desc:
        desc = url.split('/')[-1]
        
    referrer = headers.copy()
    referrer['referer'] = url[:url.find('/', 8) + 1]  # 提取base_url部分
    
    with DownloadProgressBar(unit='B', unit_scale=True,
                             miniters=1, desc=desc, leave=False) as t:
        urlretrieve(url, filename=output_path, reporthook=t.update_to, headers=referrer)
        info = {k: t.format_dict[k] for k in ('total', 'elapsed', 'rate')}
        
        logger.info(
            f"[Download] ✅ 下载成功: '{desc}' "
            f"({info['total']/1024:.1f} KB, "
            f"{info['rate']/1024:.1f} KB/s)"
        )
        
        return info


def open_in_chrome(url, new=0, autoraise=True):
    """使用指定的Chrome Profile打开url，便于调试"""
    import subprocess
    chrome = R'C:\Program Files\Google\Chrome\Application\chrome.exe'
    subprocess.run(f'"{chrome}" --profile-directory="Profile 2" {url}', shell=True)

import webbrowser
webbrowser.open = open_in_chrome


if __name__ == "__main__":
    import pretty_errors
    pretty_errors.configure(display_link=True)
    download('https://www.javbus.com/pics/cover/6n54_b.jpg', 'cover.jpg')
