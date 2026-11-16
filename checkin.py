import os
import sys
import time
from datetime import datetime
from pathlib import Path

from patchright.sync_api import sync_playwright  # 接口与 Playwright 一致

BOARD = "https://www.nodeseek.com/board"
HERE = Path(__file__).resolve().parent
SHOT = HERE / "fail.png"
BUTTONS = {"random": "试试手气", "fixed": "鸡腿 x 5"}
CHALLENGE_WAIT = 60  # 等待 Cloudflare 验证页消失的最长秒数
SW_WAIT = 15         # 等待 Service Worker 接管页面的最长秒数


def log(*args):
    print(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), *args, flush=True)


def load_dotenv(path):
    """读取 .env；已存在的环境变量优先（方便 Docker 用 -e 传入）。"""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())


def parse_cookies(raw):
    cookies = []
    for pair in raw.split(";"):
        pair = pair.strip()
        if not pair or "=" not in pair:
            continue
        name, value = pair.split("=", 1)
        cookies.append({"name": name, "value": value, "url": "https://www.nodeseek.com"})
    return cookies


def challenge_present(page):
    """页面是否还停留在 Cloudflare 的验证页。"""
    try:
        title = page.title()
        text = page.inner_text("body")[:300]
    except Exception:
        return True  # 页面正在跳转，按"还在验证"处理
    return ("Just a moment" in title) or ("请稍候" in title) or ("正在进行安全验证" in text)


def wait_challenge_clear(page, timeout_s):
    """等验证页消失，返回等待的秒数；超时返回 None。"""
    for i in range(timeout_s):
        if not challenge_present(page):
            return i
        page.wait_for_timeout(1000)
    return None


def is_controlled(page):
    try:
        return page.evaluate("!!(navigator.serviceWorker && navigator.serviceWorker.controller)")
    except Exception:
        return False


def ensure_sw_control(page):
    """等 Service Worker 接管页面；不行就刷新一次再等。返回是否已接管。"""
    for round_no in range(2):
        for _ in range(SW_WAIT):
            if is_controlled(page):
                return True
            page.wait_for_timeout(1000)
        if round_no == 0:
            page.reload(wait_until="domcontentloaded")
            if wait_challenge_clear(page, CHALLENGE_WAIT) is None:
                return False
            page.wait_for_timeout(3000)
    return False


def already_signed(page):
    body = page.inner_text("body")
    if "今日签到获得" in body:
        i = body.index("今日签到获得")
        return body[i:i + 30].replace("\n", " ")
    return None


def attempt(cookies, mode):
    """跑一次，返回 ("ok" 或 "fail", 说明)。"""
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=False,  # 有界面模式，Linux 服务器上由 xvfb 提供虚拟屏幕
            channel="chrome",
            args=["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"],
        )
        page = None
        try:
            context = browser.new_context(viewport={"width": 1280, "height": 900}, locale="zh-CN")
            context.add_cookies(cookies)
            page = context.new_page()

            page.goto(BOARD, wait_until="domcontentloaded", timeout=60000)
            if wait_challenge_clear(page, CHALLENGE_WAIT) is None:
                page.screenshot(path=str(SHOT))
                return "fail", "Cloudflare 验证页一直没有通过（见 fail.png）"
            page.wait_for_timeout(5000)

            text = already_signed(page)
            if text:
                return "ok", "今天已签到：" + text

            if not ensure_sw_control(page):
                page.screenshot(path=str(SHOT))
                return "fail", "Service Worker 没有接管页面，无法正常签到（见 fail.png）"

            text = already_signed(page)
            if text:
                return "ok", "今天已签到：" + text

            button = page.get_by_text(BUTTONS[mode], exact=True)
            if button.count() == 0:
                page.screenshot(path=str(SHOT))
                return "fail", "没找到签到按钮：Cookie 可能失效，或页面改版了（见 fail.png）"

            def is_attendance(r):
                return "/api/attendance" in r.url and "/board" not in r.url

            with page.expect_response(is_attendance, timeout=30000) as info:
                button.click()
            resp = info.value
            try:
                data = resp.json()
            except Exception:
                page.screenshot(path=str(SHOT))
                return "fail", f"接口返回的不是 JSON：HTTP {resp.status}"
            if data.get("success"):
                return "ok", f"签到成功：{data}"
            return "fail", f"接口返回失败：{data}"
        except Exception as e:
            if page is not None:
                try:
                    page.screenshot(path=str(SHOT))
                except Exception:
                    pass
            return "fail", f"出错：{e}"
        finally:
            browser.close()


def main():
    load_dotenv(HERE / ".env")

    if sys.platform.startswith("linux") and not os.environ.get("DISPLAY"):
        log("未检测到 DISPLAY：请用 xvfb-run -a python checkin.py 运行（或通过 run.sh）")
        return 1

    raw = os.environ.get("NS_COOKIE", "").strip()
    if not raw:
        log("未设置 NS_COOKIE，请检查 .env")
        return 1

    mode = os.environ.get("NS_MODE", "random").strip().lower()
    if mode not in BUTTONS:
        log(f"NS_MODE 只能是 random 或 fixed，当前是：{mode}")
        return 1

    retries = int(os.environ.get("RETRIES", "3"))
    wait = int(os.environ.get("RETRY_WAIT", "60"))
    cookies = parse_cookies(raw)

    for i in range(1, retries + 1):
        status, msg = attempt(cookies, mode)
        log(f"第 {i}/{retries} 次：{msg}")
        if status == "ok":
            return 0
        if i < retries:
            time.sleep(wait)
    log("最终失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())
