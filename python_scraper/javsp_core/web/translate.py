"""影片信息翻译模块 - 使用 Google Translate 免费接口"""
import logging
import json


logger = logging.getLogger(__name__)

def translate_movie_info(info, translate_config):
    """翻译影片的标题和剧情简介（根据配置开关决定是否翻译）"""
    engine = getattr(translate_config, 'engine', '') or 'google'
    
    if engine == 'baidu':
        _translate_baidu(info, translate_config)
    else:
        _translate_google_free(info, translate_config)


def _google_translate(text, src='ja', dst='zh-cn'):
    """调用 Google Translate 免费接口"""
    if not text or not text.strip():
        return text
    try:
        import urllib.request
        import urllib.parse
        
        base_url = 'https://translate.googleapis.com/translate_a/single'
        params = urllib.parse.urlencode({
            'client': 'gtx',
            'sl': src,
            'tl': dst,
            'dt': 't',
            'q': text
        })
        url = f'{base_url}?{params}'
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if data and len(data) > 0:
                translated = ''.join(item[0] for item in data[0] if item[0])
                return translated
    except Exception as e:
        logger.debug(f"[translate] Google 接口请求失败: {e}")
    return None


def _translate_google_free(info, cfg):
    """使用 Google Translate 免费接口（根据配置开关决定是否翻译）"""
    
    do_title = getattr(cfg, 'translate_title', False)
    do_plot = getattr(cfg, 'translate_plot', False)
    
    if info.title and do_title:
        result = _google_translate(info.title)
        if result and result != info.title:
            info.ori_title = info.title
            info.title = result
            logger.info(f"[translate] 标题已翻译: {info.title[:50]}")
    
    if info.plot and do_plot:
        result = _google_translate(info.plot)
        if result and result != info.plot:
            info.plot = result
            logger.info(f"[translate] 剧情简介已翻译")


def _translate_baidu(info, cfg):
    """使用百度翻译 API（根据配置开关决定是否翻译）"""
    appid = getattr(cfg, 'baidu_appid', '') or ''
    key = getattr(cfg, 'baidu_key', '') or ''
    
    if not appid or not key:
        logger.warning("[translate] 百度翻译未配置 appid/key")
        return
    
    import hashlib
    import random
    import requests
    from urllib.parse import quote
    
    def _baidu_translate(text, src='jp', dst='zh'):
        salt = str(random.randint(32768, 65536))
        sign_str = appid + text + salt + key
        sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()
        url = f'http://api.fanyi.baidu.com/api/trans/vip/translate?q={quote(text)}&from={src}&to={dst}&appid={appid}&salt={salt}&sign={sign}'
        resp = requests.get(url, timeout=5)
        data = resp.json()
        if 'trans_result' in data:
            return ''.join(item['dst'] for item in data['trans_result'])
        return None
    
    do_title = getattr(cfg, 'translate_title', False)
    do_plot = getattr(cfg, 'translate_plot', False)
    
    if info.title and do_title:
        try:
            result = _baidu_translate(info.title)
            if result:
                info.ori_title = info.title
                info.title = result
        except Exception as e:
            logger.warning(f"[translate] 百度标题翻译失败: {e}")
    
    if info.plot and do_plot:
        try:
            result = _baidu_translate(info.plot)
            if result:
                info.plot = result
        except Exception as e:
            logger.warning(f"[translate] 百度剧情简介翻译失败: {e}")