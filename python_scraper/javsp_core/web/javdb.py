"""从JavDB抓取数据（使用依赖注入的上下文管理器）"""
import os
import re
import sys
import logging
from typing import Dict, Optional, Tuple

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
from web.base import Request, resp2html
from web.crawler_context import CrawlerContext, get_global_context
from web.exceptions import *
from core.func import *
from core.avid import guess_av_type
from core.config import cfg
from core.datatype import MovieInfo, GenreMap
from core.chromium import get_browsers_cookies


logger = logging.getLogger(__name__)
genre_map = GenreMap('data/genre_javdb.csv')
permanent_url = 'https://javdb.com'

if cfg.Network.proxy:
    base_url = permanent_url
else:
    base_url = cfg.ProxyFree.javdb


def parse_cookie_string(cookie_str: str) -> Dict[str, str]:
    """
    将Cookie字符串解析为字典（工具函数，消除代码重复）
    
    Args:
        cookie_str: 分号分隔的Cookie字符串 (如 "name1=value1; name2=value2")
        
    Returns:
        Dict[str, str]: Cookie字典 {name: value}
        
    Example:
        >>> parse_cookie_string("session=abc123; token=xyz789")
        {'session': 'abc123', 'token': 'xyz789'}
    """
    cookies = {}
    if not cookie_str:
        return cookies
        
    for item in cookie_str.split(';'):
        item = item.strip()
        if '=' in item:
            key, value = item.split('=', 1)
            key = key.strip()
            value = value.strip()
            if key:  # 忽略空键名
                cookies[key] = value
                
    return cookies


# 初始化全局上下文和Request实例（向后兼容）
_ctx: Optional[CrawlerContext] = None

def _get_or_create_context() -> CrawlerContext:
    """获取或创建JavDB专用的上下文"""
    global _ctx
    
    if _ctx is None:
        logger.info("[JavDB] 初始化爬虫上下文")
        _ctx = CrawlerContext.create_for_crawler(
            crawler_name='javdb',
            use_scraper=True
        )
        
        # 设置语言偏好
        _ctx.update_headers({
            'Accept-Language': 'zh-CN,zh;q=0.9,zh-TW;q=0.8,en-US;q=0.7,en;q=0.6,ja;q=0.5'
        })
        
        # 从配置文件加载Cookies
        _load_config_cookies(_ctx)
        
    return _ctx


def _load_config_cookies(ctx: CrawlerContext) -> None:
    """从配置文件加载JavDB Cookies到上下文"""
    if hasattr(cfg.Crawler, 'javdb_cookie') and cfg.Crawler.javdb_cookie:
        cookie_dict = parse_cookie_string(cfg.Crawler.javdb_cookie)
        
        if cookie_dict:
            ctx.set_cookies(cookie_dict)
            
            ctx.add_to_cookies_pool({
                'profile': 'config',
                'site': 'javdb.com',
                'cookies': cookie_dict
            })
            
            logger.info(
                f"[JavDB] ✅ 已从配置文件加载Cookie "
                f"({len(cookie_dict)}个字段)"
            )


def _initialize_cookies_pool(ctx: CrawlerContext) -> None:
    """
    初始化浏览器Cookies池
    
    从浏览器读取可用的登录凭据，并添加配置的备用Cookie
    """
    try:
        browser_cookies = get_browsers_cookies()
        
        if browser_cookies:
            for cookie_info in browser_cookies:
                ctx.add_to_cookies_pool(cookie_info)
                
            logger.info(
                f"[JavDB] ✅ 成功从浏览器获取 "
                f"{len(browser_cookies)} 组Cookies"
            )
        else:
            logger.warning("[JavDB] ⚠️  未从浏览器获取到任何Cookies")
            
    except PermissionError as e:
        logger.warning(
            f"[JavDB] ⚠️  无法访问浏览器Cookies文件 "
            f"(权限不足): {e}",
            exc_info=True
        )
    except OSError as e:
        logger.warning(
            f"[JavDB] ⚠️  无法读取浏览器Cookies "
            f"(可能被安全软件保护): {e}",
            exc_info=True
        )
    except Exception as e:
        logger.warning(
            f"[JavDB] ⚠️  获取浏览器Cookies时出错 "
            f"(可能使用了非标准浏览器): {e}",
            exc_info=True
        )
    
    # 确保至少有配置的Cookie作为后备
    if hasattr(cfg.Crawler, 'javdb_cookie') and cfg.Crawler.javdb_cookie:
        config_cookies = parse_cookie_string(cfg.Crawler.javdb_cookie)
        if config_cookies:
            ctx.add_to_cookies_pool({
                'profile': 'config',
                'site': 'javdb.com',
                'cookies': config_cookies
            })


def get_html_wrapper(url: str):
    """
    包装HTTP请求并处理认证、重定向等问题
    
    使用上下文管理器自动处理：
    - Cookie失效时的自动切换
    - 登录检测和重定向
    - VIP权限检查
    
    Args:
        url: 要请求的URL
        
    Returns:
        lxml.HtmlElement: 解析后的HTML文档
        
    Raises:
        CredentialError: 所有Cookies都无效时
        SitePermissionError: 需要VIP权限时
        SiteBlocked: 被站点封锁时
        WebsiteError: 其他HTTP错误时
    """
    ctx = _get_or_create_context()
    request_obj = ctx.request
    
    logger.debug(f"[JavDB] 请求URL: '{url[:80]}...'")
    
    try:
        r = request_obj.get(url, delay_raise=True)
    except Exception as e:
        logger.error(f"[JavDB] ❌ 请求失败: {e}", exc_info=True)
        raise
    
    if r.status_code == 200:
        return _handle_successful_response(r, url, ctx)
    elif r.status_code in (403, 503):
        return _handle_blocked_response(r, url)
    else:
        raise WebsiteError(f'JavDB: {r.status_code} 非预期状态码: {url}')


def _handle_successful_response(response, url: str, ctx: CrawlerContext):
    """处理成功的HTTP响应（200 OK）"""
    if response.history and '/login' in response.url:
        logger.warning(
            f"[JavDB] ⚠️  检测到重定向到登录页，"
            f"尝试更换Cookies..."
        )
        return _handle_login_redirect(url, ctx)
        
    elif response.history and 'pay' in response.url.split('/')[-1]:
        original_url = response.history[0].url
        raise SitePermissionError(
            f"JavDB: 此资源被限制为仅VIP可见: '{original_url}'"
        )
        
    else:
        html = resp2html(response)
        logger.debug(f"[JavDB] ✅ 成功获取页面内容 (URL: '{url[:60]}...')")
        return html


def _handle_login_redirect(url: str, ctx: CrawlerContext):
    """处理需要登录的重定向"""
    _initialize_cookies_pool(ctx)
    
    next_cookies = ctx.get_next_cookies()
    
    if next_cookies is None:
        logger.error("[JavDB] ❌ 所有Cookies均已过期或不可用")
        raise CredentialError('JavDB: 所有浏览器Cookies均已过期')
    
    logger.info(
        f"[JavDB] 🔄 切换到新的Cookies (剩余: {len(ctx._cookies_pool)}组)"
    )
    
    ctx.reset_request(use_scraper=True)
    ctx.set_cookies(next_cookies)
    
    return get_html_wrapper(url)


def _handle_blocked_response(response, url: str):
    """处理被封锁的响应（403/503）"""
    html = resp2html(response)
    code_tag = html.xpath("//span[@class='code-label']/span")
    error_code = code_tag[0].text if code_tag else None
    
    if error_code == '1020':
        block_msg = (
            f'JavDB: {response.status_code} 禁止访问: '
            f'站点屏蔽了来自日本地区的IP地址，请使用其他地区的代理服务器'
        )
    elif error_code:
        block_msg = (
            f'JavDB: {response.status_code} 禁止访问: '
            f'{url} (Error code: {error_code})'
        )
    else:
        block_msg = f'JavDB: {response.status_code} 禁止访问: {url}'
    
    logger.error(f"[JavDB] 🚫 访问被阻止: {block_msg}")
    raise SiteBlocked(block_msg)


def get_user_info(site: str, cookies: Dict[str, str]) -> Optional[Tuple[str, str]]:
    """
    获取Cookies对应的用户信息（验证Cookies有效性）
    
    Args:
        site: 站点域名
        cookies: 要验证的Cookie字典
        
    Returns:
        Tuple[str, str] or None: (email, username) 或 None（如果无效）
    """
    ctx = _get_or_create_context()
    
    try:
        ctx.set_cookies(cookies)
        html = ctx.request.get_html(f'https://{site}/users/profile')
        
        if 'JavDB' in html.text:
            email = html.xpath(
                "//div[@class='user-profile']/ul/li[1]/span/following-sibling::text()"
            )[0].strip()
            username = html.xpath(
                "//div[@class='user-profile']/ul/li[2]/span/following-sibling::text()"
            )[0].strip()
            
            logger.debug(f"[JavDB] ✅ Cookies有效: 用户='{username}', Email='{email}'")
            return (email, username)
        else:
            logger.debug(f"[JavDB] ⚠️  域名可能已失效: '{site}'")
            return None
            
    except Exception as e:
        logger.debug(f"[JavDB] 获取用户信息时出错: {e}")
        return None


def get_valid_cookies() -> Optional[Dict[str, str]]:
    """
    扫描浏览器，获取一个有效的Cookies
    
    Returns:
        Dict[str, str] or None: 有效的Cookie字典
    """
    ctx = _get_or_create_context()
    _initialize_cookies_pool(ctx)
    
    while True:
        cookie_info_dict = ctx._cookies_pool.pop(0) if ctx._cookies_pool else None
        
        if cookie_info_dict is None:
            logger.error("[JavDB] 没有更多可用的Cookies可供尝试")
            return None
            
        cookies = cookie_info_dict['cookies']
        site = cookie_info_dict['site']
        profile = cookie_info_dict['profile']
        
        user_info = get_user_info(site, cookies)
        
        if user_info:
            logger.info(
                f"[JavDB] ✅ 找到有效Cookies: "
                f"source='{profile}', user='{user_info[1]}'"
            )
            return cookies
        else:
            logger.debug(
                f"[JavDB] ⚠️  Cookies无效 (source='{profile}', site='{site}')"
            )


def parse_data(movie: MovieInfo) -> None:
    """
    从网页抓取并解析指定番号的数据
    
    Args:
        movie (MovieInfo): 要解析的影片信息，解析后的信息直接更新到此变量内
    """
    ctx = _get_or_create_context()
    
    search_url = f'{base_url}/search?q={movie.dvdid}'
    logger.info(f"[JavDB] 开始搜索番号: '{movie.dvdid}'")
    
    html = get_html_wrapper(search_url)
    
    ids = list(map(str.lower, html.xpath("//div[@class='video-title']/strong/text()")))
    movie_urls = html.xpath("//a[@class='box']/@href")
    
    match_count = len([i for i in ids if i == movie.dvdid.lower()])
    
    if match_count == 0:
        logger.warning(f"[JavDB] 未找到影片: '{movie.dvdid}' (搜索结果: {ids[:5]}...) ")
        raise MovieNotFoundError(__name__, movie.dvdid, ids)
        
    elif match_count > 1:
        logger.error(f"[JavDB] 发现重复结果: '{movie.dvdid}' ({match_count}个匹配)")
        raise MovieDuplicateError(__name__, movie.dvdid, match_count)
    
    index = ids.index(movie.dvdid.lower())
    new_url = movie_urls[index]
    
    try:
        html2 = get_html_wrapper(new_url)
    except (SitePermissionError, CredentialError) as e:
        logger.warning(f"[JavDB] 无法访问详情页，尝试从搜索结果提取基本信息: {e}")
        _extract_partial_data(html, index, movie, new_url)
        return
    
    _parse_full_data(html2, movie, new_url)


def _extract_partial_data(html, index: int, movie: MovieInfo, url: str) -> None:
    """当无法访问详情页时，从搜索结果中提取部分数据"""
    box = html.xpath("//a[@class='box']")[index]
    
    movie.url = url
    movie.title = box.get('title')
    movie.cover = box.xpath("div/img/@src")[0]
    
    score_str = box.xpath("div[@class='score']/span/span")[0].tail
    score_match = re.search(r'([\d.]+)分', score_str)
    
    if score_match:
        movie.score = "{:.2f}".format(float(score_match.group(1)) * 2)
        
    publish_date = box.xpath("div[@class='meta']/text()")[0].strip()
    if publish_date != '0000-00-00':
        movie.publish_date = publish_date
        
    logger.info(f"[JavDB] 从搜索结果提取部分数据: title='{movie.title[:30]}...'")


def _parse_full_data(html, movie: MovieInfo, url: str) -> None:
    """解析完整的影片详情页面"""
    container = html.xpath("/html/body/section/div/div[@class='video-detail']")[0]
    info = container.xpath("//nav[@class='panel movie-panel-info']")[0]
    
    title = container.xpath("h2/strong[@class='current-title']/text()")[0]
    
    show_orig_title = container.xpath(
        "//a[contains(@class, 'meta-link') and not(contains(@style, 'display none'))]"
    )
    if show_orig_title:
        ori_title_el = container.xpath("h2/span[@class='origin-title']/text()")
        if ori_title_el:
            movie.ori_title = ori_title_el[0]
    
    cover = container.xpath("//img[@class='video-cover']/@src")[0]
    preview_pics = container.xpath(
        "//a[@class='tile-item'][@data-fancybox='gallery']/@href"
    )
    
    preview_video_tags = container.xpath("//video[@id='preview-video']/source/@src")
    if preview_video_tags:
        preview_video = preview_video_tags[0]
        if preview_video.startswith('//'):
            preview_video = 'https:' + preview_video
        movie.preview_video = preview_video
    
    dvdid = info.xpath("div/span")[0].text_content()
    publish_date = info.xpath("div/strong[text()='日期:']")[0].getnext().text
    duration_raw = info.xpath("div/strong[text()='時長:']")[0].getnext().text.replace('分鍾', '').strip()
    
    director_tag = info.xpath("div/strong[text()='導演:']")
    if director_tag:
        movie.director = director_tag[0].getnext().text_content().strip()
    
    av_type = guess_av_type(movie.dvdid)
    if av_type != 'fc2':
        producer_tag = info.xpath("div/strong[text()='片商:']")
    else:
        producer_tag = info.xpath("div/strong[text()='賣家:']")
        
    if producer_tag:
        movie.producer = producer_tag[0].getnext().text_content().strip()
    
    publisher_tag = info.xpath("div/strong[text()='發行:']")
    if publisher_tag:
        movie.publisher = publisher_tag[0].getnext().text_content().strip()
    
    serial_tag = info.xpath("div/strong[text()='系列:']")
    if serial_tag:
        movie.serial = serial_tag[0].getnext().text
    
    score_tag = info.xpath("//span[@class='score-stars']")
    if score_tag:
        score_str = score_tag[0].tail
        score_match = re.search(r'([\d.]+)分', score_str)
        if score_match:
            movie.score = "{:.2f}".format(float(score_match.group(1)) * 2)
    
    genre_tags = info.xpath("//strong[text()='類別:']/../span/a")
    genre, genre_id = [], []
    for tag in genre_tags:
        pre_id = tag.get('href').split('/')[-1]
        genre.append(tag.text)
        genre_id.append(pre_id)
        
        subsite = pre_id.split('?')[0]
        movie.uncensored = {'uncensored': True, 'tags': False}.get(subsite, movie.uncensored)
    
    actors_tag = info.xpath("//strong[text()='演員:']/../span")[0]
    all_actors = actors_tag.xpath("a/text()")
    genders = actors_tag.xpath("strong/text()")
    actress = [i for i in all_actors if genders[all_actors.index(i)] == '♀']
    
    magnet = container.xpath("//div[@class='magnet-name column is-four-fifths']/a/@href")
    
    movie.dvdid = dvdid
    movie.url = url.replace(base_url, permanent_url)
    movie.title = title.replace(dvdid, '').strip()
    movie.cover = cover
    movie.preview_pics = preview_pics
    movie.publish_date = publish_date
    movie.duration = duration_raw
    movie.genre = genre
    movie.genre_id = genre_id
    movie.actress = actress
    movie.magnet = [i.replace('[javdb.com]', '') for i in magnet]
    
    logger.info(
        f"[JavDB] ✅ 数据解析完成: "
        f"title='{title[:30]}...', actress={len(actress)}人, "
        f"genre={len(genre)}个"
    )


def parse_clean_data(movie: MovieInfo) -> None:
    """
    解析指定番号的影片数据并进行清洗
    
    包括：数据抓取 → 封面有效性验证 → Genre映射转换
    """
    try:
        parse_data(movie)
        
        if movie.cover is not None:
            ctx = _get_or_create_context()
            try:
                r = ctx.request.head(movie.cover)
                if r.status_code != 200:
                    logger.warning(
                        f"[JavDB] ⚠️  封面URL无效 (status={r.status_code}): "
                        f"'{movie.cover[:60]}...'"
                    )
                    movie.cover = None
            except Exception as e:
                logger.debug(f"[JavDB] 封面验证时出错: {e}")
                
    except SiteBlocked:
        raise
    except Exception as e:
        logger.error(f'[JavDB] 可能触发了反爬虫机制: {e}', exc_info=True)
        raise
    
    if movie.genre_id and (not movie.genre_id[0].startswith('fc2?')):
        movie.genre_norm = genre_map.map(movie.genre_id)
        movie.genre_id = None
        logger.debug(f"[JavDB] Genre映射完成: {len(movie.genre_norm or [])}个")


def collect_actress_alias(type: int = 0, use_original: bool = True) -> None:
    """
    收集女优的别名（批量任务）
    
    Args:
        type: 类型 (0-有码, 1-无码, 2-欧美)
        use_original: 是否使用原名
    """
    import json
    import time
    import random
    
    ctx = _get_or_create_context()
    actressAliasMap = {}
    actressAliasFilePath = "data/actress_alias.json"
    
    if not os.path.exists(actressAliasFilePath):
        with open(actressAliasFilePath, "w", encoding="utf-8") as file:
            json.dump({}, file)
    
    typeList = ["censored", "uncensored", "western"]
    page_url = f"{base_url}/actors/{typeList[type]}"
    
    logger.info(f"[JavDB] 开始收集女优别名 (type={typeList[type]})")
    
    while True:
        try:
            html = get_html_wrapper(page_url)
            actors = html.xpath("//div[@class='box actor-box']/a")
            
            count = 0
            for actor in actors:
                count += 1
                actor_name = actor.xpath("strong/text()")[0].strip()
                actor_url = actor.xpath("@href")[0]
                
                actor_html = get_html_wrapper(actor_url)
                names_span = actor_html.xpath("//span[@class='actor-section-name']")[0]
                aliases_span_list = actor_html.xpath("//span[@class='section-meta']")
                
                names_list = [name.strip() for name in names_span.text.split(",")]
                
                if len(aliases_span_list) > 1:
                    aliases_list = [
                        alias.strip() for alias in aliases_span_list[0].text.split(",")
                    ]
                else:
                    aliases_list = []
                
                actressAliasMap[names_list[-1 if use_original else 0]] = (
                    names_list + aliases_list
                )
                
                name_key = names_list[-1 if use_original else 0]
                print(f"{count} --- {name_key}: {names_list + aliases_list}")
                
                if count % 10 == 0:
                    _save_intermediate_results(actressAliasFilePath, actressAliasMap)
                    actressAliasMap = {}
                    
                delay = max(1, 10 * random.random())
                time.sleep(delay)
            
            next_page_link = html.xpath(
                "//a[@rel='next' and @class='pagination-next']/@href"
            )
            if not next_page_link:
                break
            page_url = next_page_link[0]
            
        except SiteBlocked:
            raise
            
    _save_final_results(actressAliasFilePath, actressAliasMap, count)
    print(f"已爬取 {count} 个女优，数据已更新并写回文件:", actressAliasFilePath)


def _save_intermediate_results(filepath: str, data: dict) -> None:
    """保存中间结果到文件"""
    with open(filepath, "r", encoding="utf-8") as file:
        existing_data = json.load(file)
    
    existing_data.update(data)
    
    with open(filepath, "w", encoding="utf-8") as file:
        json.dump(existing_data, file, ensure_ascii=False, indent=2)
    
    logger.info(f"[JavDB] 中间结果已保存 ({len(data)}条记录)")


def _save_final_results(filepath: str, data: dict, total_count: int) -> None:
    """保存最终结果"""
    with open(filepath, "r", encoding="utf-8") as file:
        existing_data = json.load(file)
    
    existing_data.update(data)
    
    with open(filepath, "w", encoding="utf-8") as file:
        json.dump(existing_data, file, ensure_ascii=False, indent=2)
    
    logger.info(f"[JavDB] ✅ 收集完成: 共{total_count}个女优")


if __name__ == "__main__":
    import pretty_errors
    pretty_errors.configure(display_link=True)
    logger.root.handlers[1].level = logging.DEBUG
    
    movie = MovieInfo('FC2-2735981')
    try:
        parse_clean_data(movie)
        print(movie)
    except CrawlerError as e:
        logger.error(e, exc_info=1)
