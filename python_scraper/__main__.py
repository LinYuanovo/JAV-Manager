#!/usr/bin/env python3
"""
JavSP 刮削服务 - JSON-RPC 接口
通过 stdin/stdout 与 Flutter 应用通信

协议格式:
- 输入: JSON 命令行 (以换行符结束)
- 输出: JSON 结果或进度事件 (以换行符结束)

命令类型:
1. init - 初始化配置
2. scan - 扫描影片
3. start_scrape - 开始刮削
4. stop_scrape - 停止刮削
5. ping - 心跳检测

事件类型:
- progress - 刮削进度更新
- result - 命令执行结果
- error - 错误信息
"""

import sys
import os
import json
import logging
import shutil
import threading
from typing import Dict, Any, List, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeoutError
from dataclasses import dataclass, asdict
from datetime import datetime

# ============================================================
# 强制设置 UTF-8 编码（解决 Windows GBK/GB2312 兼容问题）
# ============================================================

# 方法1: 设置环境变量（影响 Python 的 I/O 层）
os.environ['PYTHONIOENCODING'] = 'utf-8'

# 方法2: 直接重新配置 stdout/stderr 为 UTF-8（Windows 关键步骤）
if sys.platform == 'win32':
    # 对于 Windows，使用 utf-8-sig 或 utf-8 模式重新打开流
    if hasattr(sys.stdout, 'buffer'):
        sys.stdout = open(sys.stdout.buffer.fileno(), mode='w', encoding='utf-8', buffering=1)
    if hasattr(sys.stderr, 'buffer'):
        sys.stderr = open(sys.stderr.buffer.fileno(), mode='w', encoding='utf-8', buffering=1)

# 方法3: 确保 stdin 也是 UTF-8（用于读取 Dart 端发送的命令）
if hasattr(sys.stdin, 'buffer'):
    sys.stdin = open(sys.stdin.buffer.fileno(), mode='r', encoding='utf-8', errors='replace')

# 添加必要目录到 Python 路径
_script_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_script_dir)
_javsp_core_dir = os.path.join(_script_dir, 'javsp_core')

# 添加 python_scraper/ 目录（用于导入 core 兼容包和 javsp_core 顶级包）
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)

# 关键：在添加 javsp_core/ 到 sys.path 之前，预加载 core 兼容包
# 这样 Python 会将 core 包缓存到 sys.modules，避免后续导入时被 javsp_core/core 遮蔽
_ = __import__('core.config', fromlist=['cfg'])

# 添加 python_scraper/javsp_core/ 目录
# 爬虫文件内 from web.base / from web.exceptions 等绝对导入需要从此目录查找
if _javsp_core_dir not in sys.path:
    sys.path.insert(0, _javsp_core_dir)

# 添加项目根目录（备用）
if _parent_dir not in sys.path:
    sys.path.insert(1, _parent_dir)

# 配置日志（输出到 stderr，避免干扰 stdout 的 JSON 通信）
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    stream=sys.stderr
)
logger = logging.getLogger('scraper_rpc')

# 导入 JavSP 核心模块
try:
    import javsp_core.core.config_lite as config_lite_module
    from javsp_core.core.config_lite import ScraperConfig, init_config
    from javsp_core.core.datatype import Movie, MovieInfo
    from javsp_core.core.file import scan_movies, get_fmt_size
    from javsp_core.core.avid import guess_av_type, get_id as extract_id
    
    # 导入爬虫模块（延迟导入，避免启动时加载所有依赖）
    _crawlers_imported = False
    
    def ensure_crawlers_imported():
        global _crawlers_imported
        if not _crawlers_imported:
            logger.info("正在导入爬虫模块...")
            # 导入基础模块
            from javsp_core.web.base import Request, download
            from javsp_core.web.crawler_context import CrawlerContext
            from javsp_core.web.exceptions import (
                CrawlerError, MovieNotFoundError, MovieDuplicateError,
                SiteBlocked, SitePermissionError, CredentialError,
                WebsiteError, NetworkTransientError, OtherError
            )
            
            # 导入指定的爬虫
            import importlib
            
            crawler_modules = [
                'javsp_core.web.javdb',
                'javsp_core.web.javbus',
                'javsp_core.web.jav321',
                'javsp_core.web.fc2',
                'javsp_core.web.javmenu',
                'javsp_core.web.fc2ppvdb',
                'javsp_core.web.fanza',
                'javsp_core.web.dl_getchu',
                'javsp_core.web.gyutto'
            ]
            
            for mod_name in crawler_modules:
                try:
                    importlib.import_module(mod_name)
                    logger.info(f"✅ 已导入: {mod_name}")
                except Exception as e:
                    logger.warning(f"⚠️ 导入失败: {mod_name} - {e}")
            
            _crawlers_imported = True
            logger.info("所有爬虫模块导入完成")
    
except ImportError as e:
    logger.error(f"❌ 无法导入 JavSP 核心模块: {e}")
    sys.exit(1)


# ============================================================
# 文件输出功能：NFO 生成、封面下载、文件整理
# ============================================================

def _output_organized_files(movie: Movie, info: MovieInfo):
    """刮削成功后整理文件到目标目录结构
    
    目标结构: 扫描目录/#整理完成/演员名/[番号] 标题/
      - fanart.jpg      # 海报墙（完整封面，无番号前缀）
      - poster.jpg      # 海报图（从 fanart.jpg 切割，比例 378:高度）
      - movie.nfo       # Kodi/Emby 元数据
      - 番号.mp4        # 视频文件（从原位置移动）
    """
    avid = info.dvdid or info.cid or movie.dvdid or movie.cid
    if not avid or not movie.files:
        logger.warning(f"[{avid}] 无法整理：缺少番号或文件路径")
        return
    
    base_output_dir = getattr(config_lite_module.cfg.file_config, 'output_folder', None) or ''
    if not base_output_dir:
        scan_dir = config_lite_module.cfg.file_config.scan_dir
        base_output_dir = os.path.join(scan_dir, '#整理完成')
    
    actresses = info.actress if info.actress else ['未知演员']
    actress_dir = ','.join(actresses[:3]) if len(actresses) > 3 else ','.join(actresses)
    actress_dir = _sanitize_filename(actress_dir)
    
    title_str = info.title or avid
    folder_name = f'[{avid}] {_sanitize_filename(title_str[:60])}'
    
    target_dir = os.path.join(base_output_dir, actress_dir, folder_name)
    os.makedirs(target_dir, exist_ok=True)
    
    _generate_nfo_kodi(info, target_dir, avid)
    
    cover_url = info.cover or ''
    
    fanart_path = os.path.join(target_dir, 'fanart.jpg')
    poster_path = os.path.join(target_dir, 'poster.jpg')
    
    fanart_data = _download_image_bytes(cover_url, avid)
    
    if fanart_data:
        with open(fanart_path, 'wb') as f:
            f.write(fanart_data)
        
        _generate_poster_from_fanart(fanart_data, poster_path, avid)
        
        size_kb = len(fanart_data) // 1024
        logger.info(f"[{avid}] ✅ fanart.jpg 已保存 ({size_kb}KB)")
    else:
        logger.warning(f"[{avid}] ⚠️ 封面下载失败，跳过 fanart/poster 生成")
    
    for i, src_file in enumerate(movie.files):
        ext = os.path.splitext(src_file)[1]
        if len(movie.files) == 1:
            dst_name = f'{avid}{ext}'
        else:
            dst_name = f'{avid}-CD{i+1}{ext}'
        dst_path = os.path.join(target_dir, dst_name)
        try:
            if os.path.exists(dst_path):
                logger.warning(f"[{avid}] 目标文件已存在，跳过: {dst_name}")
                continue
            shutil.move(src_file, dst_path)
            logger.info(f"[{avid}] 文件已整理: {os.path.basename(src_file)} -> {dst_name}")
        except Exception as e:
            logger.warning(f"[{avid}] 文件移动失败: {e}")
            try:
                shutil.copy2(src_file, dst_path)
                logger.info(f"[{avid}] 文件已复制: {dst_name}")
            except Exception as copy_err:
                logger.error(f"[{avid}] 文件复制也失败: {copy_err}")
    
    movie.save_dir = target_dir
    movie.nfo_file = os.path.join(target_dir, 'movie.nfo')
    movie.poster_file = poster_path
    movie.fanart_file = fanart_path
    
    logger.info(f"[{avid}] ✅ 整理完成: {target_dir}")


def _download_image_bytes(url: str, avid: str):
    """下载图片并返回字节数据"""
    if not url:
        return None
    try:
        import requests as _req
        
        proxies = _get_proxies_for_download()
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.javbus.com/'
        }
        
        resp = _req.get(url, timeout=30, proxies=proxies, headers=headers)
        resp.raise_for_status()
        return resp.content
    except Exception as e:
        logger.warning(f"[{avid}] 图片下载失败: {e}")
        return None


def _generate_poster_from_fanart(fanart_bytes: bytes, poster_path: str, avid: str):
    """从 fanart 数据切割生成 poster.jpg（宽度 378px，保持原比例高度）"""
    try:
        from PIL import Image
        from io import BytesIO
        
        img = Image.open(BytesIO(fanart_bytes))
        
        orig_w, orig_h = img.size
        logger.info(f"[{avid}] 原始封面尺寸: {orig_w}x{orig_h}")
        
        if orig_w == 0 or orig_h == 0:
            logger.warning(f"[{avid}] 封面尺寸异常 ({orig_w}x{orig_h})，直接保存")
            with open(poster_path, 'wb') as f:
                f.write(fanart_bytes)
            return
        
        poster_w = 378
        
        if img.mode in ('RGBA', 'P', 'LA'):
            img = img.convert('RGB')
        
        left = max(0, orig_w - poster_w)
        poster_img = img.crop((left, 0, orig_w, orig_h))
        poster_img.save(poster_path, 'JPEG', quality=97, optimize=True)
        
        file_size = os.path.getsize(poster_path) if os.path.exists(poster_path) else 0
        logger.info(f"[{avid}] ✅ poster.jpg 已生成 ({poster_w}x{orig_h}, {file_size//1024}KB)")
    except ImportError:
        logger.warning(f"[{avid}] Pillow 未安装，无法生成 poster.jpg，直接复制 fanart")
        try:
            with open(poster_path, 'wb') as f:
                f.write(fanart_bytes)
        except Exception as copy_e:
            logger.warning(f"[{avid}] poster.jpg 复制失败: {copy_e}")
    except Exception as e:
        logger.warning(f"[{avid}] poster.jpg 生成失败: {e}")
        try:
            with open(poster_path, 'wb') as f:
                f.write(fanart_bytes)
        except Exception:
            pass


def _generate_nfo_kodi(info, target_dir: str, avid: str):
    """生成 Kodi/Emby 标准 NFO 文件"""
    nfo_path = os.path.join(target_dir, 'movie.nfo')

    # 时长转分钟（runtime 单位是 minutes）
    duration_sec = 0
    if info.duration:
        try:
            duration_sec = int(info.duration)
        except (ValueError, TypeError):
            pass
    runtime_min = duration_sec // 60

    # 评分
    rating = '0'
    if info.score:
        try:
            rating = str(float(info.score))
        except (ValueError, TypeError):
            rating = info.score

    # 类型列表
    genres = info.genre if info.genre else []
    genre_tags = '\n  '.join(f'<genre>{_xml_escape(g)}</genre>' for g in genres)
    tag_tags = '\n  '.join(f'<tag>{_xml_escape(g)}</tag>' for g in genres)

    # 演员列表
    actors = info.actress if info.actress else []
    actor_tags = '\n'.join(f'  <actor>\n    <name>{_xml_escape(a)}</name>\n  </actor>' for a in actors)

    # 预告片
    trailer = info.preview_video if hasattr(info, 'preview_video') and info.preview_video else ''

    # 牌商/制作商
    studio = info.producer or info.publisher or ''

    nfo_content = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<movie>
  <title>{_xml_escape(f'{avid} {info.title or ""}'.strip())}</title>
  <originaltitle>{_xml_escape(info.ori_title or info.title or avid)}</originaltitle>
  <rating>{rating}</rating>
  <runtime>{runtime_min}</runtime>
  <mpaa>NC-17</mpaa>
  <uniqueid type="num" default="true">{avid}</uniqueid>
{genre_tags if genre_tags else '  <genre/>'}
{tag_tags if tag_tags else '  <tag/>'}
  <country>JP</country>
  <director>{_xml_escape(info.director or '')}</director>
  <premiered>{info.publish_date or ''}</premiered>
  <studio>{_xml_escape(studio)}</studio>
{_make_trailer_tag(trailer)}
{actor_tags if actor_tags else '  <actor><name/></actor>'}
</movie>'''

    try:
        with open(nfo_path, 'w', encoding='utf-8') as f:
            f.write(nfo_content)
        logger.info(f"[{avid}] ✅ NFO 已生成: {nfo_path}")
    except Exception as e:
        logger.warning(f"[{avid}] ⚠️ NFO 生成失败: {e}")


def _make_trailer_tag(url: str) -> str:
    if not url:
        return '  <trailer/>'
    return f'  <trailer>{_xml_escape(url)}</trailer>'


def _get_proxies_for_download():
    """获取下载用的代理设置"""
    cfg = config_lite_module.cfg
    if hasattr(cfg, 'network') and cfg.network:
        nw = cfg.network
        if getattr(nw, 'use_proxy', False) and getattr(nw, 'proxy', ''):
            return {'http': nw.proxy, 'https': nw.proxy}
        else:
            return {'http': None, 'https': None}
    return None


def _sanitize_filename(name: str) -> str:
    """清理文件名中的非法字符"""
    if not name:
        return 'unknown'
    # Windows 非法字符
    for ch in '<>:"/\\|?*':
        name = name.replace(ch, '')
    # 去除首尾空格和点
    name = name.strip(' .')
    # 限制长度
    if len(name) > 80:
        name = name[:80]
    return name or 'unknown'


def _xml_escape(text: str) -> str:
    """转义 XML 特殊字符"""
    if not text:
        return ''
    return (text
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace("'", '&apos;'))


@dataclass
class ScrapeProgress:
    """刮削进度事件"""
    movie_id: str
    avid: str
    status: str  # pending, scraping, success, failed
    progress: float = 0.0
    crawler_name: Optional[str] = None
    info: Optional[Dict] = None
    error: Optional[str] = None


@dataclass 
class ScrapeResult:
    """刮削结果"""
    success: bool
    message: str
    data: Optional[Any] = None


class ScraperRPCServer:
    """基于 stdin/stdout 的 JSON-RPC 服务器"""
    
    def __init__(self):
        self._config: Optional[ScraperConfig] = None
        self._movies: List[Movie] = []
        self._executor: Optional[ThreadPoolExecutor] = None
        self._stop_event = threading.Event()
        self._is_running = False
        self._lock = threading.Lock()
        self._write_lock = threading.Lock()
        self._current_cmd_id: Optional[str] = None  # 当前命令 ID，用于回传
        
        # 统计信息
        self._stats = {
            'total': 0,
            'pending': 0,
            'scraping': 0,
            'success': 0,
            'failed': 0
        }
    
    def _send_json(self, data: dict):
        """发送 JSON 数据到 Dart 端（线程安全）"""
        try:
            json_str = json.dumps(data, ensure_ascii=False)
            with self._write_lock:
                sys.stdout.buffer.write((json_str + '\n').encode('utf-8'))
                sys.stdout.buffer.flush()
        except Exception as e:
            logger.error(f"发送JSON失败: {e}")
    
    def _send_progress(self, progress: ScrapeProgress):
        """发送进度事件"""
        try:
            self._send_json({
                'type': 'progress',
                'id': self._current_cmd_id,
                'data': asdict(progress)
            })
        except Exception as e:
            logger.error(f"发送progress失败: {e}")
    
    def _send_result(self, result: ScrapeResult):
        """发送命令结果"""
        self._send_json({
            'type': 'result',
            'id': self._current_cmd_id,
            'data': {
                'success': result.success,
                'message': result.message,
                'data': result.data
            }
        })
    
    def _send_error(self, message: str):
        """发送错误信息"""
        self._send_json({
            'type': 'error',
            'id': self._current_cmd_id,
            'data': {'message': message}
        })
    
    def handle_command(self, command: Dict[str, Any]) -> bool:
        """
        处理来自 Dart 端的命令
        
        Returns:
            bool: 是否应该继续运行（False 表示退出）
        """
        cmd_type = command.get('type', '')
        cmd_id = command.get('id', '')
        self._current_cmd_id = cmd_id
        
        logger.info(f"📥 收到命令: {cmd_type} (id={cmd_id})")
        
        try:
            if cmd_type == 'init':
                return self._cmd_init(command.get('config', {}))
            
            elif cmd_type == 'scan':
                return self._cmd_scan()
            
            elif cmd_type == 'start_scrape':
                return self._cmd_start_scrape(
                    movie_ids=command.get('movie_ids', []),
                    thread_count=command.get('thread_count', 4)
                )
            
            elif cmd_type == 'stop_scrape':
                return self._cmd_stop_scrape()
            
            elif cmd_type == 'ping':
                self._send_result(ScrapeResult(success=True, message='pong'))
                return True
            
            elif cmd_type == 'exit':
                logger.info("收到退出命令")
                self._cleanup()
                return False
            
            else:
                self._send_error(f"未知命令类型: {cmd_type}")
                return True
                
        except Exception as e:
            logger.exception(f"处理命令时发生错误: {cmd_type}")
            self._send_error(str(e))
            return True
    
    def _cmd_init(self, config_data: dict) -> bool:
        """初始化配置"""
        try:
            logger.info(f"[INIT] 收到配置数据: {list(config_data.keys())}")
            # 打印网络配置细节
            network_cfg = config_data.get('network', {})
            logger.info(f"[INIT] 网络配置: use_proxy={network_cfg.get('use_proxy')}, proxy='{network_cfg.get('proxy')}'")
            
            init_config(config_data)
            
            # 验证是否成功设置
            logger.info(f"[INIT] 验证全局 cfg: {config_lite_module.cfg}, type={type(config_lite_module.cfg)}")
            
            if not config_lite_module.cfg:
                raise Exception("init_config 执行后 cfg 仍为 None")
            
            if not hasattr(config_lite_module.cfg, 'file_config') or not config_lite_module.cfg.file_config:
                raise Exception(f"cfg.file_config 无效: {getattr(config_lite_module.cfg, 'file_config', 'N/A')}")
                
            if not config_lite_module.cfg.file_config.scan_dir:
                raise Exception(f"scan_dir 为空: file_config={config_lite_module.cfg.file_config}")
            
            self._config = config_lite_module.cfg
            self._send_result(ScrapeResult(
                success=True,
                message='配置初始化成功',
                data=config_lite_module.cfg.to_dict() if config_lite_module.cfg else {}
            ))
            
            logger.info(f"[INIT] 配置验证通过: scan_dir='{config_lite_module.cfg.file_config.scan_dir}'")
            return True
            
        except Exception as e:
            logger.exception(f"[INIT] 配置初始化失败")
            self._send_result(ScrapeResult(
                success=False,
                message=f'配置初始化失败: {e}'
            ))
            return True
    
    def _cmd_scan(self) -> bool:
        """扫描指定目录下的影片"""
        # 诊断日志
        logger.info(f"[SCAN] 检查配置状态: cfg={config_lite_module.cfg}, type={type(config_lite_module.cfg)}")
        if config_lite_module.cfg:
            logger.info(f"[SCAN] cfg.file_config={config_lite_module.cfg.file_config}, scan_dir='{config_lite_module.cfg.file_config.scan_dir}'")
            logger.info(f"[SCAN] cfg.File={config_lite_module.cfg.File}, hasattr File: {hasattr(config_lite_module.cfg, 'File')}")
        
        if not config_lite_module.cfg or not config_lite_module.cfg.file_config or not config_lite_module.cfg.file_config.scan_dir:
            error_msg = '未配置扫描目录，请先调用 init 命令'
            if not config_lite_module.cfg:
                error_msg = '全局配置对象 cfg 为 None'
            elif not config_lite_module.cfg.file_config:
                error_msg = 'file_config 为 None'
            elif not config_lite_module.cfg.file_config.scan_dir:
                error_msg = f'scan_dir 为空 (file_config={config_lite_module.cfg.file_config})'
            
            logger.error(f"[SCAN] 配置检查失败: {error_msg}")
            self._send_result(ScrapeResult(
                success=False,
                message=error_msg
            ))
            return True
        
        if not os.path.isdir(config_lite_module.cfg.file_config.scan_dir):
            self._send_result(ScrapeResult(
                success=False,
                message=f'扫描目录不存在: {config_lite_module.cfg.file_config.scan_dir}'
            ))
            return True
        
        try:
            logger.info(f"🔍 开始扫描目录: {config_lite_module.cfg.file_config.scan_dir}")
            
            # 解析忽略文件夹列表
            ignore_folders = [
                f.strip() for f in config_lite_module.cfg.file_config.ignore_folder.split(';') 
                if f.strip()
            ]
            
            # 扫描影片文件（scan_movies 直接返回 Movie 对象列表）
            movies = scan_movies(
                config_lite_module.cfg.file_config.scan_dir,
                only_scan=True  # 只扫描不处理
            )
            
            # 过滤掉无效的影片
            valid_movies = []
            for movie in movies:
                if movie.dvdid or movie.cid:
                    # 确保类型已设置
                    if not movie.data_src and movie.dvdid:
                        movie.data_src = guess_av_type(movie.dvdid)
                    valid_movies.append(movie)
                else:
                    logger.warning(f"无法提取番号: {movie.files}")
            
            with self._lock:
                self._movies = valid_movies
                self._update_stats()
            
            # 返回扫描结果
            result_movies = []
            for i, m in enumerate(movies):
                result_movies.append({
                    'id': str(i),
                    'avid': m.dvdid or m.cid,
                    'movie_type': m.data_src,
                    'file_path': m.files[0] if m.files else '',
                    'status': 'pending',
                    'progress': 0.0
                })
            
            self._send_result(ScrapeResult(
                success=True,
                message=f'扫描完成，找到 {len(movies)} 个影片',
                data={
                    'count': len(movies),
                    'movies': result_movies
                }
            ))
            
            logger.info(f"✅ 扫描完成: {len(movies)} 个影片")
            return True
            
        except Exception as e:
            logger.exception("扫描失败")
            self._send_result(ScrapeResult(
                success=False,
                message=f'扫描失败: {e}'
            ))
            return True
    
    def _cmd_start_scrape(self, movie_ids: List[str], thread_count: int = 4) -> bool:
        """开始刮削任务"""
        if self._is_running:
            self._send_result(ScrapeResult(
                success=False,
                message='刮削任务已在运行中'
            ))
            return True
        
        if not self._movies:
            self._send_result(ScrapeResult(
                success=False,
                message='没有可刮削的影片，请先扫描'
            ))
            return True
        
        # 确保爬虫模块已导入
        ensure_crawlers_imported()
        
        # 重置状态
        self._stop_event.clear()
        self._is_running = True
        
        # 如果没有指定影片 ID，则刮削所有待处理的影片
        if not movie_ids:
            target_movies = [(i, m) for i, m in enumerate(self._movies)]
        else:
            target_movies = [(int(idx), self._movies[int(idx)]) for idx in movie_ids]
        
        # 创建线程池
        max_workers = min(thread_count, len(target_movies))
        self._executor = ThreadPoolExecutor(max_workers=max_workers)
        
        logger.info(f"🚀 开始刮削任务: {len(target_movies)} 个影片, {max_workers} 个线程")
        
        # 启动后台线程执行刮削
        scrape_thread = threading.Thread(
            target=self._run_scraping_tasks,
            args=(target_movies,),
            daemon=True
        )
        scrape_thread.start()
        
        self._send_result(ScrapeResult(
            success=True,
            message=f'开始刮削 {len(target_movies)} 个影片 (线程数: {max_workers})',
            data={
                'total': len(target_movies),
                'thread_count': max_workers
            }
        ))
        
        return True
    
    def _run_scraping_tasks(self, target_movies: list):
        """在后台线程中执行刮削任务"""
        futures = {}
        
        for idx, movie in target_movies:
            if self._stop_event.is_set():
                break
            
            future = self._executor.submit(self._scrape_single_movie, idx, movie)
            futures[future] = (idx, movie)
        
        # 等待所有任务完成
        for future in as_completed(futures):
            idx, movie = futures[future]
            try:
                future.result()  # 获取结果或异常
            except Exception as e:
                logger.error(f"影片 {movie.dvdid or movie.cid} 刮削异常: {e}")
                self._send_progress(ScrapeProgress(
                    movie_id=str(idx),
                    avid=movie.dvdid or movie.cid,
                    status='failed',
                    error=str(e)
                ))
        
        # 任务完成
        with self._lock:
            self._is_running = False
            self._update_stats()
        
        logger.info("🏁 刮削任务完成")
        self._send_progress(ScrapeProgress(
            movie_id='',
            avid='',
            status='completed',
            progress=100.0,
            info={'stats': self._stats.copy()}
        ))
        self._send_result(ScrapeResult(
            success=True,
            message=f'刮削完成: {self._stats["success"]} 成功, {self._stats["failed"]} 失败',
            data=self._stats.copy()
        ))
    
    def _scrape_single_movie(self, idx: int, movie: Movie):
        """刮削单个影片（带超时保护 + 终态保证）"""
        movie_id = str(idx)
        avid = movie.dvdid or movie.cid
        
        self._send_progress(ScrapeProgress(
            movie_id=movie_id,
            avid=avid,
            status='scraping',
            progress=0.0
        ))
        
        final_status = 'failed'
        try:
            crawler_list = list(config_lite_module.cfg.crawler_select.get(movie.data_src, []))
            if not crawler_list:
                crawler_list = list(config_lite_module.cfg.crawler_select.get('normal', []))
            
            cookie = config_lite_module.cfg.crawler.javdb_cookie
            if not cookie or not cookie.strip():
                crawler_list = [c for c in crawler_list if c != 'javdb']
                if 'javdb' in config_lite_module.cfg.crawler_select.get(movie.data_src or 'normal', []):
                    logger.info(f"[{avid}] 未配置 javdb cookie，跳过 javdb")
            
            logger.info(f"[{avid}] 爬虫列表: {crawler_list}")
            
            info = None
            last_error = None
            
            per_crawler_timeout = getattr(config_lite_module.cfg.network, 'timeout', 30) * 2
            
            for crawler_name in crawler_list:
                if self._stop_event.is_set():
                    logger.info(f"[{avid}] 收到停止信号，终止")
                    return
                
                try:
                    logger.info(f"[{avid}] 尝试爬虫: {crawler_name}")
                    
                    self._send_progress(ScrapeProgress(
                        movie_id=movie_id,
                        avid=avid,
                        status='scraping',
                        progress=30.0,
                        crawler_name=crawler_name
                    ))
                    
                    mod_name = f'javsp_core.web.{crawler_name}'
                    mod = __import__(mod_name, fromlist=['parse_data'])
                    
                    info = MovieInfo(movie)
                    
                    def _run_crawler():
                        mod.parse_data(info)
                        return info
                    
                    executor = ThreadPoolExecutor(max_workers=1)
                    try:
                        future = executor.submit(_run_crawler)
                        info = future.result(timeout=per_crawler_timeout)
                    except FuturesTimeoutError:
                        executor.shutdown(wait=False, cancel_futures=True)
                        raise Exception(f'爬虫超时 ({per_crawler_timeout}s)')
                    finally:
                        executor.shutdown(wait=False)
                    
                    required_keys = config_lite_module.cfg.crawler.required_keys.split(',')
                    has_all_required = all(
                        getattr(info, key, None) for key in required_keys
                    )
                    
                    if has_all_required:
                        logger.info(f"[{avid}] ✅ 爬虫成功: {crawler_name}")
                        
                        if config_lite_module.cfg.translate.translate_title or config_lite_module.cfg.translate.translate_plot:
                            try:
                                self._translate_info(info)
                            except Exception as trans_e:
                                logger.warning(f"[{avid}] ⚠️ 翻译失败（不影响刮削结果）: {trans_e}")
                        
                        movie.info = info
                        
                        self._send_progress(ScrapeProgress(
                            movie_id=movie_id,
                            avid=avid,
                            status='success',
                            progress=100.0,
                            crawler_name=crawler_name,
                            info=info.to_dict()
                        ))
                        
                        final_status = 'success'
                        
                        _output_organized_files(movie, info)
                        movie._status = 'success'
                        with self._lock:
                            self._update_stats()
                        return
                    else:
                        logger.warning(f"[{avid}] ⚠️ 数据不完整，尝试下一个爬虫")
                        
                except Exception as e:
                    last_error = str(e)
                    import traceback
                    err_detail = traceback.format_exc()
                    logger.warning(f"[{avid}] ❌ 爬虫 {crawler_name} 失败: {e}")
                    logger.warning(f"[{avid}] 详细错误:\n{err_detail[-500:]}")
                    continue
            
            raise Exception(f"所有爬虫均失败: {last_error or '未知错误'}")
            
        except Exception as e:
            logger.error(f"[{avid}] ❌ 刮削最终失败: {e}")
            final_status = 'failed'
            movie._status = 'failed'
            self._send_progress(ScrapeProgress(
                movie_id=movie_id,
                avid=avid,
                status='failed',
                progress=0.0,
                error=str(e)
            ))
            with self._lock:
                self._update_stats()
    
    def _translate_info(self, info: MovieInfo):
        """翻译影片信息（如果配置了翻译引擎）"""
        if not config_lite_module.cfg.translate.engine:
            return
        
        try:
            from javsp_core.web.translate import translate_movie_info
            translate_movie_info(info, config_lite_module.cfg.translate)
            logger.info(f"[{info.dvdid or info.cid}] ✅ 翻译完成")
        except Exception as e:
            logger.warning(f"[{info.dvdid or info.cid}] ⚠️ 翻译失败: {e}")
    
    def _cmd_stop_scrape(self) -> bool:
        """优雅停止刮削任务"""
        if not self._is_running:
            self._send_result(ScrapeResult(
                success=True,
                message='没有正在运行的刮削任务'
            ))
            return True
        
        logger.info("⏹️ 收到停止请求，等待当前任务完成后停止...")
        self._stop_event.set()
        
        self._send_result(ScrapeResult(
            success=True,
            message='已发送停止信号，正在等待当前任务完成...'
        ))
        return True
    
    def _update_stats(self):
        """更新统计信息"""
        pending = sum(1 for m in self._movies if not hasattr(m, '_status') or m._status == 'pending')
        scraping = sum(1 for m in self._movies if getattr(m, '_status', '') == 'scraping')
        success = sum(1 for m in self._movies if getattr(m, '_status', '') == 'success')
        failed = sum(1 for m in self._movies if getattr(m, '_status', '') == 'failed')
        
        self._stats = {
            'total': len(self._movies),
            'pending': pending,
            'scraping': scraping,
            'success': success,
            'failed': failed
        }
    
    def _cleanup(self):
        """清理资源"""
        if self._executor:
            self._executor.shutdown(wait=False)
        self._is_running = False


def main():
    """主函数"""
    logger.info("=" * 60)
    logger.info("JavSP 刮削服务启动")
    logger.info("=" * 60)
    
    server = ScraperRPCServer()
    
    try:
        # 从 stdin 循环读取命令
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            
            try:
                command = json.loads(line)
            except json.JSONDecodeError as e:
                logger.error(f"JSON 解析失败: {e}")
                server._send_error(f"无效的 JSON: {e}")
                continue
            
            should_continue = server.handle_command(command)
            if not should_continue:
                break
                
    except KeyboardInterrupt:
        logger.info("收到中断信号，退出")
    except Exception as e:
        logger.exception("发生致命错误")
    finally:
        server._cleanup()
        logger.info("JavSP 刮削服务已停止")


if __name__ == '__main__':
    main()
