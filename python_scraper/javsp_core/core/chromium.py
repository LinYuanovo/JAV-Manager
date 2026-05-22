"""解析Chromium系浏览器Cookies的相关函数"""
import os
import sys
import json
import base64
import sqlite3
import logging
from glob import glob
from shutil import copyfile
from datetime import datetime

__all__ = ['get_browsers_cookies']

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from Crypto.Cipher import AES
    _crypto_available = True
except ImportError:
    _crypto_available = False

logger = logging.getLogger(__name__)


class Decrypter():
    def __init__(self, key):
        self.key = key
    def decrypt(self, encrypted_value):
        nonce = encrypted_value[3:3+12]
        ciphertext = encrypted_value[3+12:-16]
        tag = encrypted_value[-16:]
        cipher = AES.new(self.key, AES.MODE_GCM, nonce=nonce)
        plaintext = cipher.decrypt_and_verify(ciphertext, tag).decode('utf-8')
        return plaintext


def get_browsers_cookies():
    """获取系统上的所有Chromium系浏览器的JavDB的Cookies
    
    注意：如果未安装 cryptography 和 pycryptodome 库，
    此函数将返回空列表。建议用户在设置页面手动输入 Cookie。
    """
    if not _crypto_available:
        logger.warning("cryptography 或 pycryptodome 库未安装，无法自动获取浏览器 Cookie")
        logger.warning("请在设置页面手动输入 JavDB Cookie")
        return []
    
    # 不予支持: Opera, 360安全&极速, 搜狗使用非标的用户目录或数据格式; QQ浏览器屏蔽站点
    user_data_dirs = {
        'Chrome':        '/Google/Chrome/User Data',
        'Chrome Beta':   '/Google/Chrome Beta/User Data',
        'Chrome Canary': '/Google/Chrome SxS/User Data',
        'Chromium':      '/Google/Chromium/User Data',
        'Edge':          '/Microsoft/Edge/User Data',
        'Vivaldi':       '/Vivaldi/User Data'
    }
    LocalAppDataDir = os.getenv('LOCALAPPDATA')
    if not LocalAppDataDir:
        return []
    
    all_browser_cookies = []
    exceptions = []
    for brw, path in user_data_dirs.items():
        user_dir = LocalAppDataDir + path
        cookies_files = glob(user_dir+'/*/Cookies') + glob(user_dir+'/*/Network/Cookies')
        local_state = user_dir+'/Local State'
        if os.path.exists(local_state):
            try:
                key = decrypt_key(local_state)
                decrypter = Decrypter(key)
            except Exception as e:
                logger.debug(f"无法解密密钥: {e}")
                continue
                
            for file in cookies_files:
                profile = brw + ": " + file.split('User Data')[1].split(os.sep)[1]
                file = os.path.normpath(file)
                try:
                    records = get_cookies(file, decrypter)
                    if records:
                        for site, cookies in records.items():
                            entry = {'profile': profile, 'site': site, 'cookies': cookies}
                            all_browser_cookies.append(entry)
                except Exception as e:
                    exceptions.append(e)
                    logger.debug(f"无法解析Cookies文件({e}): {file}", exc_info=True)
    
    if len(all_browser_cookies) == 0 and len(exceptions) > 0:
        raise exceptions[0]
    return all_browser_cookies


def convert_chrome_utc(chrome_utc):
    """将Chrome存储的UTC时间转换为UNIX的UTC时间格式"""
    second = int(chrome_utc / 1e6)
    if second > 0:
        second = second - 11644473600
    unix_utc = datetime.fromtimestamp(second)
    return unix_utc


def decrypt_key_win(local_state):
    """从Local State文件中提取并解密出Cookies文件的密钥"""
    import win32crypt
    with open(local_state, 'rt', encoding='utf-8') as file:
        encrypted_key = json.loads(file.read())['os_crypt']['encrypted_key']
    encrypted_key = base64.b64decode(encrypted_key)
    encrypted_key = encrypted_key[5:]
    decrypted_key = win32crypt.CryptUnprotectData(encrypted_key, None, None, None, 0)[1]
    return decrypted_key


def decrypt_key_linux(local_state):
    """从Local State文件中提取并解密出Cookies的密钥，适用于Linux"""
    with open(local_state, 'rt', encoding='utf-8') as file:
        encrypted_key = json.loads(file.read())['os_crypt']['encrypted_key']
    encrypted_key = base64.b64decode(encrypted_key)
    encrypted_key = encrypted_key[5:]
    key = encrypted_key
    nonce = b' ' * 12
    aesgcm = AESGCM(key)
    decrypted_key = aesgcm.decrypt(nonce, encrypted_key, None)
    return decrypted_key


decrypt_key = decrypt_key_win if sys.platform == 'win32' else decrypt_key_linux


def get_cookies(cookies_file, decrypter, host_pattern='javdb%.com'):
    """从cookies_file文件中查找指定站点的所有Cookies"""
    temp_dir = os.getenv('TMPDIR', os.getenv('TEMP', os.getenv('TMP', '.')))
    temp_cookie = os.path.join(temp_dir, 'Cookies')
    copyfile(cookies_file, temp_cookie)
    conn = sqlite3.connect(temp_cookie)
    cursor = conn.cursor()
    cursor.execute(f'SELECT host_key, name, encrypted_value, expires_utc FROM cookies WHERE host_key LIKE "{host_pattern}"')
    now = datetime.now()
    records = {}
    for host_key, name, encrypted_value, expires_utc in cursor.fetchall():
        d = records.setdefault(host_key, {})
        expires = convert_chrome_utc(expires_utc)
        if expires > now:
            d[name] = decrypter.decrypt(encrypted_value)
    valid_records = {k: v for k, v in records.items() if '_jdb_session' in v}
    conn.close()
    os.remove(temp_cookie)
    return valid_records


if __name__ == "__main__":
    all_cookies = get_browsers_cookies()
    for d in all_cookies:
        print('{:<20}{}'.format(d['profile'], d['site']))
