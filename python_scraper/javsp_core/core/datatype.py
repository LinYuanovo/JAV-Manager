"""定义数据类型和一些通用性的对数据类型操作，支持线程安全访问"""
import os
import csv
import sys
import json
import shutil
import logging
import threading
from functools import cached_property
from typing import Any, Dict, List, Optional, Union

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
from core.config import Config
from core.lib import mei_path, detect_special_attr


logger = logging.getLogger(__name__)
filemove_logger = logging.getLogger('filemove')


class ThreadSafeMovieInfo:
    """
    线程安全的影片信息类
    
    使用读写锁机制确保多线程并发访问时的数据一致性。
    所有属性的读取和写入都通过锁保护。
    
    Attributes:
        _lock: 线程锁对象，保护所有实例属性的访问
        _data: 存储实际数据的字典
    """
    
    # 定义所有可能的数据属性（用于兼容 dir() 和属性遍历）
    DATA_ATTRIBUTES = [
        'dvdid', 'cid', 'url', 'plot', 'cover', 'big_cover',
        'genre', 'genre_id', 'genre_norm', 'score', 'title',
        'ori_title', 'magnet', 'serial', 'actress', 'actress_pics',
        'director', 'duration', 'producer', 'publisher', 'uncensored',
        'publish_date', 'preview_pics', 'preview_video'
    ]
    
    __slots__ = ['_lock', '_data', '__weakref__']
    
    def __init__(self, dvdid: str = None, /, *, cid: str = None, from_file: Optional[str] = None):
        """
        初始化线程安全的影片信息对象
        
        Args:
            dvdid (str, optional): DVD番号
            cid (str, optional): DMM Content ID
            from_file (str, optional): 从JSON文件加载数据
            
        Raises:
            TypeError: 参数数量不正确或文件路径无效时抛出
        """
        arg_count = len([i for i in [dvdid, cid, from_file] if i])
        if arg_count != 1:
            raise TypeError(f'Require 1 parameter but {arg_count} given')
        
        self._lock = threading.RLock()  # 使用可重入锁，支持同一线程多次获取
        self._data = {}
        
        with self._lock:
            if isinstance(dvdid, Movie):
                self._data['dvdid'] = dvdid.dvdid
                self._data['cid'] = dvdid.cid
            else:
                self._data['dvdid'] = dvdid
                self._data['cid'] = cid
                
            self._init_default_attrs()
            
            if from_file:
                if os.path.isfile(from_file):
                    self.load(from_file)
                    logger.debug(f"成功从文件加载MovieInfo数据: '{from_file}'")
                else:
                    raise TypeError(f"Invalid file path: '{from_file}'")
    
    def _init_default_attrs(self) -> None:
        """初始化所有默认属性为None"""
        default_attrs = [
            'url', 'plot', 'cover', 'big_cover', 'genre', 'genre_id',
            'genre_norm', 'score', 'title', 'ori_title', 'magnet',
            'serial', 'actress', 'actress_pics', 'director', 'duration',
            'producer', 'publisher', 'uncensored', 'publish_date',
            'preview_pics', 'preview_video'
        ]
        for attr in default_attrs:
            self._data[attr] = None
    
    def __getattr__(self, name: str) -> Any:
        """线程安全的属性访问"""
        if name in ('_lock', '_data'):
            raise AttributeError(f"'{type(self).__name__}' object has no attribute '{name}'")
        
        if name.startswith('_'):
            raise AttributeError(f"'{type(self).__name__}' object has no attribute '{name}'")
        
        with self._lock:
            if name in self._data:
                return self._data[name]
            else:
                raise AttributeError(f"'{type(self).__name__}' object has no attribute '{name}'")
    
    def __setattr__(self, name: str, value: Any) -> None:
        """线程安全的属性设置"""
        if name in ('_lock', '_data'):
            super().__setattr__(name, value)
            return
        
        with self._lock:
            if hasattr(self, '_data') and name in self._data:
                old_value = self._data.get(name)
                self._data[name] = value
                logger.debug(f"MovieInfo属性更新: {name} = {repr(value)[:50]} (原值: {repr(old_value)[:50] if old_value is not None else 'None'})")
            elif not hasattr(self, '_data'):
                super().__setattr__(name, value)
            else:
                self._data[name] = value
                logger.debug(f"MovieInfo新增属性: {name} = {repr(value)[:50]}")
    
    def safe_set(self, name: str, value: Any) -> None:
        """
        线程安全的属性设置方法（显式调用版本）
        
        Args:
            name: 属性名
            value: 属性值
        """
        with self._lock:
            self._data[name] = value
            logger.debug(f"[ThreadSafe] 设置属性: {name}")
    
    def safe_get(self, name: str, default: Any = None) -> Any:
        """
        线程安全的属性获取方法（显式调用版本）
        
        Args:
            name: 属性名
            default: 属性不存在时的默认值
            
        Returns:
            属性值或默认值
        """
        with self._lock:
            return self._data.get(name, default)
    
    def safe_update(self, attrs_dict: Dict[str, Any]) -> None:
        """
        批量更新多个属性（原子操作）
        
        Args:
            attrs_dict: 要更新的属性字典 {属性名: 属性值}
        """
        with self._lock:
            updated_keys = []
            for key, value in attrs_dict.items():
                if key in self._data or key.startswith('_'):
                    self._data[key] = value
                    updated_keys.append(key)
            logger.debug(f"[ThreadSafe] 批量更新属性 ({len(updated_keys)}个): {updated_keys}")
    
    def to_dict(self) -> Dict[str, Any]:
        """
        获取所有数据的副本（线程安全快照）
        
        Returns:
            包含所有属性值的字典副本
        """
        with self._lock:
            return self._data.copy()
    
    def data_keys(self) -> List[str]:
        """
        获取所有数据属性的键名列表
        
        Returns:
            List[str]: 数据属性名称列表（如 ['dvdid', 'cid', 'title', ...]）
        """
        with self._lock:
            return list(self._data.keys())
    
    def __dir__(self) -> List[str]:
        """
        自定义 dir() 输出，包含数据属性和方法
        
        Returns:
            包含数据属性和方法的完整属性列表
        """
        # 返回数据属性 + 方法名
        attrs = list(self.DATA_ATTRIBUTES)
        attrs.extend([
            '__init__', '__getattr__', '__setattr__', '__str__', '__repr__',
            '__eq__', 'dump', 'load', 'get_info_dic', 'to_dict',
            'safe_set', 'safe_get', 'safe_update', 'data_keys'
        ])
        return sorted(attrs)
    
    def __str__(self) -> str:
        with self._lock:
            return json.dumps(self._data, indent=2, ensure_ascii=False)
    
    def __repr__(self) -> str:
        with self._lock:
            dvdid = self._data.get('dvdid')
            cid = self._data.get('cid')
            
        if dvdid:
            expression = f"('{dvdid}')"
        else:
            expression = f"('cid={cid}')"
        return __class__.__name__ + expression
    
    def __eq__(self, other) -> bool:
        if isinstance(other, ThreadSafeMovieInfo):
            with self._lock, other._lock:
                return self._data == other._data
        return False
    
    def dump(self, filepath: Optional[str] = None, crawler: Optional[str] = None) -> None:
        """
        将数据导出为JSON文件
        
        Args:
            filepath: 输出文件路径，为空时自动生成
            crawler: 数据来源爬虫名称
        """
        with self._lock:
            if not filepath:
                id_val = self._data['dvdid'] if self._data['dvdid'] else self._data['cid']
                if crawler:
                    filepath = f'../unittest/data/{id_val} ({crawler}).json'
                    filepath = os.path.join(os.path.dirname(__file__), filepath)
                else:
                    filepath = f'{id_val}.json'
            
            data_str = json.dumps(self._data, indent=2, ensure_ascii=False)
            
        with open(filepath, 'wt', encoding='utf-8') as f:
            f.write(data_str)
        logger.info(f"MovieInfo数据已导出到: '{filepath}'")
    
    def load(self, filepath: str) -> None:
        """
        从JSON文件加载数据
        
        Args:
            filepath: JSON文件路径
        """
        with open(filepath, 'rt', encoding='utf-8') as f:
            d = json.load(f)
        
        with self._lock:
            valid_attrs = set(self._data.keys())
            loaded_count = 0
            for k, v in d.items():
                if k in valid_attrs:
                    self._data[k] = v
                    loaded_count += 1
                else:
                    logger.warning(f"加载文件时发现未知属性: '{k}'，已忽略")
            logger.info(f"从文件加载MovieInfo数据: '{filepath}' (加载{loaded_count}/{len(d)}个属性)")
    
    def get_info_dic(self, cfg: Config) -> Dict[str, str]:
        """
        生成用来填充模板的字典（线程安全）
        
        Args:
            cfg: 配置对象
            
        Returns:
            用于模板填充的字典
        """
        with self._lock:
            info = self._data
            d = {
                'num': info.get('dvdid') or info.get('cid'),
                'title': info.get('title') or cfg.NamingRule.null_for_title,
                'rawtitle': info.get('ori_title') or (info.get('title') or cfg.NamingRule.null_for_title),
                'actress': ','.join(info.get('actress')) if info.get('actress') else cfg.NamingRule.null_for_actress,
                'score': info.get('score') or '0',
                'censor': cfg.NamingRule.censorship_names[info.get('uncensored')],
                'serial': info.get('serial') or cfg.NamingRule.null_for_serial,
                'director': info.get('director') or cfg.NamingRule.null_for_director,
                'producer': info.get('producer') or cfg.NamingRule.null_for_producer,
                'publisher': info.get('publisher') or cfg.NamingRule.null_for_publisher,
                'date': info.get('publish_date') or '0000-00-00',
            }
            d['year'] = d['date'].split('-')[0]
            
            num_items = d['num'].split('-')
            d['label'] = num_items[0] if len(num_items) > 1 else '---'
            
            genre_list = info.get('genre_norm') or info.get('genre') or []
            d['genre'] = ','.join(genre_list)
            
            return d


# 保持向后兼容的别名
MovieInfo = ThreadSafeMovieInfo


class Movie:
    """用于关联影片文件的类"""
    def __init__(self, dvdid=None, /, *, cid=None) -> None:
        arg_count = len([i for i in (dvdid, cid) if i])
        if arg_count != 1:
            raise TypeError(f'Require 1 parameter but {arg_count} given')
        # 创建类的默认属性
        self.dvdid = dvdid              # DVD ID，即通常的番号
        self.cid = cid                  # DMM Content ID
        self.files = []                 # 关联到此番号的所有影片文件的列表（用于管理带有多个分片的影片）
        self.data_src = 'normal'        # 数据源：不同的数据源将使用不同的爬虫
        self.info: MovieInfo = None     # 抓取到的影片信息
        self.save_dir = None            # 存放影片、封面、NFO的文件夹路径
        self.basename = None            # 按照命名模板生成的不包含路径和扩展名的basename
        self.nfo_file = None            # nfo文件的路径
        self.fanart_file = None         # fanart文件的路径
        self.poster_file = None         # poster文件的路径
        self.guid = None                # GUI使用的唯一标识，通过dvdid和files做md5生成

    @cached_property
    def hard_sub(self) -> bool:
        """影片文件带有内嵌字幕"""
        return 'C' in self.attr_str

    @cached_property
    def uncensored(self) -> bool:
        """影片文件是无码流出/无码破解版本（很多种子并不严格区分这两种，故这里也不进一步细分）"""
        return 'U' in self.attr_str

    @cached_property
    def attr_str(self) -> str:
        """用来标示影片文件的额外属性的字符串(空字符串/-U/-C/-UC)"""
        # 暂不支持多分片的影片
        if len(self.files) != 1:
            return ''
        r = detect_special_attr(self.files[0], self.dvdid)
        if r:
            r = '-' + r
        return r

    def __repr__(self) -> str:
        if self.cid and self.data_src == 'cid':
            expression = f"('cid={self.cid}')"
        else:
            expression = f"('{self.dvdid}')"
        return __class__.__name__ + expression

    def rename_files(self):
        """根据命名规则移动（重命名）影片文件"""
        def move_file(src:str, dst:str):
            """移动（重命名）文件并记录信息到日志"""
            abs_dst = os.path.abspath(dst)
            # shutil.move might overwrite dst file
            if os.path.exists(abs_dst):
                raise FileExistsError(f'File exists: {abs_dst}')
            shutil.move(src, abs_dst)
            src_rel = os.path.relpath(src)
            dst_name = os.path.basename(dst)
            logger.info(f"重命名文件: '{src_rel}' -> '...{os.sep}{dst_name}'")
            # 目前StreamHandler并未设置filter，为了避免显示中出现重复的日志，这里暂时只能用debug级别
            filemove_logger.debug(f'移动（重命名）文件: \n  原路径: "{src}"\n  新路径: "{abs_dst}"')

        new_paths = []
        dir = os.path.dirname(self.files[0])
        if len(self.files) == 1:
            fullpath = self.files[0]
            ext = os.path.splitext(fullpath)[1]
            newpath = os.path.join(self.save_dir, self.basename + ext)
            move_file(fullpath, newpath)
            new_paths.append(newpath)
        else:
            for i, fullpath in enumerate(self.files, start=1):
                ext = os.path.splitext(fullpath)[1]
                newpath = os.path.join(self.save_dir, self.basename + f'-CD{i}' + ext)
                move_file(fullpath, newpath)
                new_paths.append(newpath)
        self.new_paths = new_paths
        if len(os.listdir(dir)) == 0:
            #如果移动文件后目录为空则删除该目录
            os.rmdir(dir)


class GenreMap(dict):
    """genre的映射表"""
    def __init__(self, file):
        genres = {}
        with open(mei_path(file), newline='', encoding='utf-8-sig') as csvfile:
            reader = csv.DictReader(csvfile)
            try:
                for row in reader:
                    genres[row['id']] = row['translate']
            except UnicodeDecodeError:
                logger.error('CSV file must be saved as UTF-8-BOM to edit is in Excel')
            except KeyError:
                logger.error("The columns 'id' and 'translate' must exist in the csv file")
        self.update(genres)

    def map(self, ls):
        """将列表ls按照内置的映射进行替换：保留映射表中不存在的键，删除值为空的键"""
        mapped = [self.get(i, i) for i in ls]
        cleaned = [i for i in mapped if i]  # 译文为空表示此genre应当被删除
        return cleaned
