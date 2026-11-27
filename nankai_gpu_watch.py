"""南开 HPC GPU 分区监控。运行 python nankai_gpu_watch.py，按 Ctrl+C 停止。"""
import queue
import re
import threading
import tkinter as tk
import time
from datetime import datetime
from pathlib import Path

from lxml import html
from playwright.sync_api import Error as BrowserError, sync_playwright

URL = "https://hpc.nankai.edu.cn/hpc/partition-detail"
PROFILE = Path.home() / ".nankai-hpc-monitor"
INTERVAL = 900


def available(markup):
    nodes = {}
    card_rows = 0
    for row in html.fromstring(markup).xpath("//li | //*[@role='listitem']"):
        text = " ".join(row.itertext())
        count = re.search(r"(\d+)\s*卡\s*/\s*(\d+)\s*卡", text)
        name = re.search(r"(?<![A-Za-z0-9_])gpu\s*(\d+)(?![A-Za-z0-9_])", text, re.I)
        if not name and not count:
            continue
        if count:
            card_rows += 1
        if not name:
            raise ValueError(f"已找到卡数，但未识别节点名。行文本：{text.strip()[:120]}")
        node = "gpu" + name[1]
        dot = row.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' MuiBadge-dot ')]")
        if len(dot) != 1 or not count:
            raise ValueError(f"{node} 的状态或卡数无法识别")
        used, total = map(int, count.groups())
        if used > total:
            raise ValueError(f"{node} 的已用卡数超过总数")
        healthy = "MuiBadge-invisible" in dot[0].get("class", "").split()
        nodes[node] = total - used if healthy else 0
    if not nodes:
        raise ValueError(f"未读取到 GPU 节点（含卡数的列表行：{card_rows}）")
    return {name: free for name, free in nodes.items() if free}


def check(page):
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    gpu = page.get_by_role("button", name="gpu", exact=True)
    try:
        gpu.wait_for(state="visible", timeout=10000)
    except BrowserTimeout:
        print("GPU 按钮等待 10 秒后仍未出现。如页面要求登录，请完成登录。", flush=True)
        gpu.wait_for(state="visible", timeout=295000)
    if "MuiButton-containedPrimary" not in (gpu.get_attribute("class") or "").split():
        gpu.click()
    page.locator("button.MuiButton-containedPrimary").filter(has_text=re.compile("^gpu$", re.I)).wait_for()
    deadline = time.monotonic() + 30
    while True:
        try:
            return available(page.content())
        except ValueError:
            if time.monotonic() >= deadline:
                raise
            page.wait_for_timeout(500)



def monitor(updates):
    with sync_playwright() as pw:
        context = pw.chromium.launch_persistent_context(str(PROFILE), headless=False)
        page = context.pages[0] if context.pages else context.new_page()
        try:
            while not page.is_closed():
                start = time.monotonic()
                stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                try:
                    free = check(page)
                except (BrowserError, ValueError) as err:
                    print(stamp, "本轮检查失败：", err, flush=True)
                    updates.put((None, "本轮检查失败，当前余量未知。", stamp))
                else:
                    message = "，".join(f"{name}：{n} 张" for name, n in free.items())
                    print(stamp, message or "无可提醒的空闲 GPU", flush=True)
                    updates.put((bool(free), message or "当前无可用空卡。", stamp))
                    if free:
                        try:
                            with (PROFILE / "gpu-alerts.log").open("a", encoding="utf-8") as log:
                                print(stamp, message, file=log)
                        except OSError as err:
                            print("提醒记录写入失败：", err, flush=True)
                if not page.is_closed():
                    time.sleep(max(0, INTERVAL - (time.monotonic() - start)))
        finally:
            context.close()


def main():
    root = tk.Tk()
    root.withdraw()
    root.title("南开 HPC · GPU 空卡提醒")
    root.attributes("-topmost", True)
    details = tk.StringVar(root)
    tk.Label(root, textvariable=details, justify="left", wraplength=480,
             padx=24, pady=20, font=("Microsoft YaHei UI", 12)).pack()
    tk.Button(root, text="关闭本次提醒", command=root.withdraw).pack(pady=(0, 16))
    root.protocol("WM_DELETE_WINDOW", root.withdraw)
    updates = queue.Queue()
    worker = threading.Thread(target=monitor, args=(updates,), daemon=True)
    worker.start()

    def refresh():
        while not updates.empty():
            has_free, message, stamp = updates.get_nowait()
            if has_free is False:
                root.withdraw()
            elif has_free or root.state() != "withdrawn":
                details.set(f"{stamp} 检查结果\n\n{message}")
                if has_free and root.state() == "withdrawn":
                    root.deiconify()
                    root.lift()
        if not worker.is_alive() and root.state() == "withdrawn":
            root.quit()
            return
        root.after(250, refresh)

    root.after(0, refresh)
    try:
        root.mainloop()
    finally:
        root.destroy()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
