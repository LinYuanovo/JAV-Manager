"""从jav321抓取数据"""
import os
import re
import sys
import logging


sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
from web.base import post_html
from web.exceptions import *
from core.datatype import MovieInfo


logger = logging.getLogger(__name__)
base_url = 'https://www.jav321.com'


def str2sec(time_str: str) -> str:
    """
    将时长字符串转换为秒数
    
    Args:
        time_str: 时长字符串 (如 "120分", "1時間30分")
        
    Returns:
        str: 秒数（字符串格式）
    """
    if not time_str:
        return '0'
    
    total_seconds = 0
    
    # 匹配 "X時間" 或 "X小时" 格式
    hour_match = re.search(r'(\d+)\s*[小時时间]', time_str)
    if hour_match:
        total_seconds += int(hour_match.group(1)) * 3600
        
    # 匹配 "X分" 格式
    minute_match = re.search(r'(\d+)\s*分', time_str)
    if minute_match:
        total_seconds += int(minute_match.group(1)) * 60
        
    # 如果没有匹配到任何格式，尝试直接解析为纯数字
    if total_seconds == 0:
        num_match = re.search(r'(\d+)', time_str)
        if num_match:
            total_seconds = int(num_match.group(1)) * 60  # 假设单位是分钟
            
    return str(total_seconds)


def parse_data(movie: MovieInfo):
    """解析指定番号的影片数据"""
    logger.info(f"[jav321] 开始搜索番号: '{movie.dvdid}'")
    
    try:
        html = post_html(f'{base_url}/search', data={'sn': movie.dvdid})
    except Exception as e:
        logger.error(f"[jav321] ❌ 搜索请求失败: {type(e).__name__}: {str(e)[:150]}")
        raise NetworkTransientError(
            f"jav321 搜索失败: {movie.dvdid}",
            original_error=e
        )
    
    page_urls = html.xpath("//ul[@class='dropdown-menu']/li/a/@href")
    
    if not page_urls:
        logger.warning(f"[jav321] 未找到影片页面链接: '{movie.dvdid}'")
        raise MovieNotFoundError(__name__, movie.dvdid)
        
    page_url = page_urls[0]
    
    cid = page_url.split('/')[-1]   # /video/ipx00177
    # 如果从URL匹配到的cid是'search'，说明还停留在搜索页面，找不到这部影片
    if cid == 'search':
        raise MovieNotFoundError(__name__, movie.dvdid)
    
    title_tags = html.xpath("//div[@class='panel-heading']/h3/text()")
    if not title_tags:
        logger.warning(f"[jav321] 未找到标题: '{movie.dvdid}'")
        raise MovieNotFoundError(__name__, movie.dvdid)
        
    title = title_tags[0]
    
    info_panels = html.xpath("//div[@class='col-md-9']")
    if not info_panels:
        logger.warning(f"[jav321] 未找到信息面板: '{movie.dvdid}'")
        raise WebsiteError(f"jav321: 页面结构异常 - {movie.dvdid}")
        
    info = info_panels[0]
    # jav321的不同信息字段间没有明显分隔，只能通过url来匹配目标标签
    company_tags = info.xpath("a[contains(@href,'/company/')]/text()")
    if company_tags:
        movie.producer = company_tags[0]
    # actress, actress_pics
    # jav321现在连女优信息都没有了，首页通过女优栏跳转过去也全是空白
    actress, actress_pics = [], {}
    actress_tags = html.xpath("//div[@class='thumbnail']/a[contains(@href,'/star/')]/img")
    for tag in actress_tags:
        name = tag.tail.strip()
        pic_url = tag.get('src')
        actress.append(name)
        # jav321的女优头像完全是应付了事：即使女优实际没有头像，也会有一个看起来像模像样的url，
        # 因而无法通过url判断女优头像图片是否有效。有其他选择时最好不要使用jav321的女优头像数据
        actress_pics[name] = pic_url
    # genre, genre_id
    genre_tags = info.xpath("a[contains(@href,'/genre/')]")
    genre, genre_id = [], []
    for tag in genre_tags:
        genre.append(tag.text)
        genre_id.append(tag.get('href').split('/')[-2]) # genre/4025/1
    # 修复索引越界问题：先检查 XPath 结果是否为空
    dvdid_tag = info.xpath("b[text()='品番']")
    if not dvdid_tag:
        raise WebsiteError(f"jav321: 页面缺少品番信息 - {movie.dvdid}")
    dvdid = dvdid_tag[0].tail.replace(': ', '').upper()
    
    publish_date_tag = info.xpath("b[text()='配信開始日']")
    if not publish_date_tag:
        raise WebsiteError(f"jav321: 页面缺少配信開始日信息 - {movie.dvdid}")
    publish_date = publish_date_tag[0].tail.replace(': ', '')
    
    # 修复索引越界问题：增加空值检查
    duration_element = info.xpath("b[text()='収録時間']")
    if duration_element:
        duration_str = duration_element[0].tail
        if duration_str and duration_str.strip():
            movie.duration = str2sec(duration_str.strip())
        else:
            logger.warning(f"[jav321] 未找到有效时长信息: '{movie.dvdid}'")
    else:
        logger.warning(f"[jav321] 未找到时长字段: '{movie.dvdid}'")
    # 仅部分影片有评分且评分只能粗略到星级而没有分数，要通过星级的图片来判断，如'/img/35.gif'表示3.5星
    score_tag = info.xpath("//b[text()='平均評価']/following-sibling::img/@data-original")
    if score_tag:
        score = int(score_tag[0][5:7])/5   # /10*2
        movie.score = str(score)
    serial_tag = info.xpath("a[contains(@href,'/series/')]/text()")
    if serial_tag:
        movie.serial = serial_tag[0]
    preview_video_tag = info.xpath("//video/source/@src")
    if preview_video_tag:
        movie.preview_video = preview_video_tag[0]
    plot_tag = info.xpath("//div[@class='panel-body']/div[@class='row']/div[@class='col-md-12']/text()")
    if plot_tag:
        movie.plot = plot_tag[0]
    preview_pics = html.xpath("//div[@class='col-xs-12 col-md-12']/p/a/img[@class='img-responsive']/@src")
    if len(preview_pics) == 0:
        # 尝试搜索另一种布局下的封面，需要使用onerror过滤掉明明没有封面时网站往里面塞的默认URL
        preview_pics = html.xpath("//div/div/div[@class='col-md-3']/img[@onerror and @class='img-responsive']/@src")
    # 有的图片链接里有多个//，网站质量堪忧……
    preview_pics = [i[:8] + i[8:].replace('//', '/') for i in preview_pics]
    # 磁力和ed2k链接是依赖js脚本加载的，无法通过静态网页来解析

    movie.url = page_url
    movie.cid = cid
    movie.dvdid = dvdid
    movie.title = title
    movie.actress = actress
    movie.actress_pics = actress_pics
    movie.genre = genre
    movie.genre_id = genre_id
    movie.publish_date = publish_date
    # preview_pics的第一张图始终是封面，剩下的才是预览图
    if len(preview_pics) > 0:
        movie.cover = preview_pics[0]
        movie.preview_pics = preview_pics[1:]


if __name__ == "__main__":
    import pretty_errors
    pretty_errors.configure(display_link=True)
    logger.root.handlers[1].level = logging.DEBUG

    movie = MovieInfo('SCUTE-1177')
    try:
        parse_data(movie)
        print(movie)
    except CrawlerError as e:
        logger.error(e, exc_info=1)
