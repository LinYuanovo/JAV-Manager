"""轻量级配置模块 - 从 JSON 读取配置"""
import json
import os
import re
import logging
from dataclasses import dataclass, field, asdict
from typing import List, Optional

logger = logging.getLogger(__name__)


@dataclass
class NetworkConfig:
    use_proxy: bool = False
    proxy: str = ""
    retry: int = 3
    timeout: int = 10


@dataclass
class CrawlerConfig:
    required_keys: str = "cover,title"
    javdb_cookie: str = ""
    hardworking_mode: bool = True
    respect_site_avid: bool = True
    title_remove_actor: bool = True
    title_chinese_first: bool = True
    sleep_after_scraping: int = 1
    ignore_javdb_cover: str = "auto"
    unify_actress_name: bool = True


@dataclass
class TranslateConfig:
    engine: str = "google"
    translate_title: bool = True
    translate_plot: bool = True
    baidu_appid: str = ""
    baidu_key: str = ""
    bing_key: str = ""
    claude_key: str = ""
    groq_key: str = ""


@dataclass
class FileConfig:
    scan_dir: str = ""
    media_ext: str = "3gp;avi;f4v;flv;iso;m2ts;m4v;mkv;mov;mp4;mpeg;rm;rmvb;ts;vob;webm;wmv;strm;mpg"
    ignore_folder: str = "#recycle;#整理完成;不要扫描;UnSub;Watched"
    ignore_video_file_less_than: int = 232
    enable_file_move: bool = False


# ============================================================
# JavSP 兼容性配置类（原始 JavSP 代码的 config.ini 对应项）
# ============================================================

@dataclass
class ProxyFreeConfig:
    """代理/直连 URL 配置"""
    javdb: str = "https://javdb368.com"
    javbus: str = "https://www.seedmm.bond"

@dataclass
class MovieIDConfig:
    """番号识别配置"""
    ignore_whole_word: str = "144P;240P;360P;480P;720P;1080P;2K;4K"
    ignore_regex: str = r"\w+2048\.com;Carib(beancom)?;[^a-z\d](f?hd|lt)[^a-z\d]"
    ignore_pattern: 're.Pattern' = field(default_factory=lambda: re.compile(
        r'\d{3,4}x\d{3,4}|'  # 分辨率
        r'[\w-]*\.(com|net|app|xyz)|'  # 域名
        r'Carib(beancom)?|'  # 加勒比
        r'[^a-z\d](f?hd|lt)[^a-z\d]',  # HD/LT 标记
        flags=re.I | re.A
    ))


@dataclass
class NamingRuleConfig:
    """命名规则配置"""
    calc_path_len_by_byte: str = "auto"
    max_path_len: int = 250
    max_actress_count: int = 10
    media_servers: str = ""
    output_folder: str = ""
    save_dir: str = ""
    filename: str = "{avid}"
    nfo_title: str = "{title}"
    text_for_censored: str = "有码"
    text_for_uncensored: str = "无码"
    text_for_unknown_censorship: str = "打码情况未知"
    null_for_title: str = "#未知标题"
    null_for_actress: str = "#未知女优"
    null_for_serial: str = "#未知系列"
    null_for_director: str = "#未知导演"
    null_for_producer: str = "#未知制作商"
    null_for_publisher: str = "#未知发行商"
    censorship_names: dict = field(default_factory=lambda: {
        False: "有码",
        True: "无码",
        None: "打码情况未知"
    })


@dataclass
class ScraperConfig:
    network: NetworkConfig = field(default_factory=NetworkConfig)
    crawler: CrawlerConfig = field(default_factory=CrawlerConfig)
    translate: TranslateConfig = field(default_factory=TranslateConfig)
    file_config: FileConfig = field(default_factory=FileConfig)
    movie_id: MovieIDConfig = field(default_factory=MovieIDConfig)
    naming_rule: NamingRuleConfig = field(default_factory=NamingRuleConfig)
    proxy_free: ProxyFreeConfig = field(default_factory=ProxyFreeConfig)
    
    # 爬虫选择列表（精简版）
    crawler_select: dict = field(default_factory=lambda: {
        'normal': ['javbus', 'jav321', 'javdb'],
        'fc2': ['fc2', 'javmenu', 'fc2ppvdb', 'javdb'],
        'cid': ['fanza'],
        'getchu': ['dl_getchu'],
        'gyutto': ['gyutto']
    })
    
    max_workers: int = 4
    
    @property
    def File(self):
        """兼容性属性 - 提供对 file_config 的 File 风格访问"""
        return self.file_config
    
    @property
    def Network(self):
        """兼容性属性 - 提供对 network 的 Network 风格访问"""
        return self.network
    
    @property
    def MovieID(self):
        """兼容性属性 - 番号识别配置"""
        return self.movie_id
    
    @property
    def NamingRule(self):
        """兼容性属性 - 命名规则配置"""
        return self.naming_rule
    
    @property
    def ProxyFree(self):
        """兼容性属性 - 代理/直连 URL 配置"""
        return self.proxy_free
    
    @property
    def Crawler(self):
        """兼容性属性 - 提供对 crawler 的 Crawler 风格访问"""
        return self.crawler
    
    @classmethod
    def from_json(cls, json_str: str) -> 'ScraperConfig':
        from json import loads
        data = loads(json_str)
        
        config = cls()
        
        if 'network' in data:
            for k, v in data['network'].items():
                if hasattr(config.network, k):
                    setattr(config.network, k, v)
        
        if 'crawler' in data:
            for k, v in data['crawler'].items():
                if hasattr(config.crawler, k):
                    setattr(config.crawler, k, v)
        
        if 'translate' in data:
            for k, v in data['translate'].items():
                if hasattr(config.translate, k):
                    setattr(config.translate, k, v)
        
        if 'file_config' in data:
            for k, v in data['file_config'].items():
                if hasattr(config.file_config, k):
                    setattr(config.file_config, k, v)
        
        if 'crawler_select' in data:
            config.crawler_select = data['crawler_select']
        
        if 'max_workers' in data:
            config.max_workers = data['max_workers']
        
        return config
    
    def to_dict(self) -> dict:
        return {
            'network': asdict(self.network),
            'crawler': asdict(self.crawler),
            'translate': asdict(self.translate),
            'file_config': asdict(self.file_config),
            'crawler_select': self.crawler_select,
            'max_workers': self.max_workers
        }


# 全局配置实例（兼容 JavSP 原有代码）
cfg = None


def init_config(config_data: dict):
    """初始化全局配置"""
    global cfg
    import json
    cfg = ScraperConfig.from_json(json.dumps(config_data))
    logger.info(f"配置已初始化: scan_dir={cfg.file_config.scan_dir}, max_workers={cfg.max_workers}")
