# -*- coding: utf-8 -*-
"""把游戏里的固定台词烘焙成配音文件。

用法：
    python tools/bake_voice.py                # 用默认音色（xiaoyi）烤
    python tools/bake_voice.py yunxia         # 换音色重烤（见 VOICES）
    python tools/bake_voice.py --list         # 列出可用中文音色

产物：
    assets/voice/<voice>/<sha256前16位>.mp3
    assets/voice/<voice>/manifest.json     ← 哈希 → 原文，方便查/校对

为什么是"烘焙"而不是运行时调 TTS：
    台词是固定的一张表（184 条），烤一次就永久可用 —— 不联网、不卡顿、
    音质比 Windows 自带的 SAPI 好一个数量级。游戏里没烤到的句子
    （比如接了真模型之后它现编的话）会自动回落到系统 TTS。

游戏侧查找逻辑在 scripts/audio/bj_voice.gd，哈希算法必须两边一致：
    sha256(utf-8 原文).hexdigest()[:16]
"""
import asyncio
import hashlib
import json
import os
import sys

try:
    import edge_tts
except ImportError:
    print("缺少 edge-tts：pip install edge-tts")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Windows 控制台默认是 GBK，打印台词里的 ♡/… 会直接崩 —— 强制 UTF-8 输出
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:                                          # noqa: BLE001
    pass

LINES_FILE = os.path.join(ROOT, "tools", "voice_lines.json")
OUT_ROOT = os.path.join(ROOT, "assets", "voice")

# 音色表：挑的都是中文女声，气质各不同
VOICES = {
    "xiaoyi": {
        "voice": "zh-CN-XiaoyiNeural",   # 活泼/卡通 —— 默认，最贴"嘴欠鲸鱼娘"
        "rate": "+10%",
        "pitch": "+3Hz",
        "note": "活泼少女，略带得意",
    },
    "xiaoxiao": {
        "voice": "zh-CN-XiaoxiaoNeural",  # 温柔/自然 —— 备选，稳一点
        "rate": "+6%",
        "pitch": "+0Hz",
        "note": "温柔自然，没那么欠",
    },
    "xiaobei": {
        "voice": "zh-CN-liaoning-XiaobeiNeural",  # 东北话，幽默
        "rate": "+6%",
        "pitch": "+0Hz",
        "note": "东北腔，喜剧效果",
    },
}

# 纯标点/拟声的句子不烤（TTS 念出来是噪音）
SKIP_CHARS = set("…。，、？！～~♡ \t")


def text_hash(text: str) -> str:
    """必须和 GDScript 侧一致：sha256 的十六进制前 16 位。"""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def is_speakable(text: str) -> bool:
    return any(ch not in SKIP_CHARS for ch in text)


async def bake_one(text: str, voice_cfg: dict, out_dir: str, index: int, total: int,
                   sem: asyncio.Semaphore) -> tuple:
    path = os.path.join(out_dir, text_hash(text) + ".mp3")
    if os.path.exists(path) and os.path.getsize(path) > 512:
        return ("skip", text)
    async with sem:
        for attempt in range(3):
            try:
                comm = edge_tts.Communicate(
                    text, voice_cfg["voice"],
                    rate=voice_cfg["rate"], pitch=voice_cfg["pitch"])
                await comm.save(path)
                if os.path.getsize(path) > 512:
                    print("  [%3d/%3d] %s" % (index, total, text))
                    return ("ok", text)
            except Exception as exc:                       # noqa: BLE001
                print("  [%3d/%3d] 重试 %d: %s (%s)" % (index, total, attempt + 1, text, exc))
                await asyncio.sleep(1.0 + attempt)
        return ("fail", text)


async def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        voices = await edge_tts.list_voices()
        for v in voices:
            if v["Locale"].startswith("zh-"):
                print("%-34s %-8s %s" % (v["ShortName"], v["Gender"], v.get("VoiceTag", {})))
        return 0

    name = args[0] if args else "xiaoyi"
    if name not in VOICES:
        print("未知音色 %s，可选：%s" % (name, ", ".join(VOICES)))
        return 1
    voice_cfg = VOICES[name]
    out_dir = os.path.join(OUT_ROOT, name)
    os.makedirs(out_dir, exist_ok=True)

    # utf-8-sig：这个清单有可能被 PowerShell 之流写出 BOM，别为这个翻车
    with open(LINES_FILE, encoding="utf-8-sig") as fh:
        lines = json.load(fh)["lines"]
    speakable = [t for t in lines if is_speakable(t)]
    print("台词 %d 条，其中可念的 %d 条；音色 %s（%s）"
          % (len(lines), len(speakable), voice_cfg["voice"], voice_cfg["note"]))

    sem = asyncio.Semaphore(4)
    tasks = [bake_one(t, voice_cfg, out_dir, i + 1, len(speakable), sem)
             for i, t in enumerate(speakable)]
    results = await asyncio.gather(*tasks)
    ok = sum(1 for kind, _ in results if kind in ("ok", "skip"))
    failed = [t for kind, t in results if kind == "fail"]

    manifest = {text_hash(t): t for t in speakable}
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump({"voice": voice_cfg["voice"], "rate": voice_cfg["rate"],
                   "pitch": voice_cfg["pitch"], "count": len(manifest),
                   "clips": manifest}, fh, ensure_ascii=False, indent=2)

    print("\n完成：%d/%d 条，失败 %d 条" % (ok, len(speakable), len(failed)))
    for t in failed:
        print("  失败：%s" % t)
    print("输出目录：%s" % out_dir)
    return 0 if not failed else 2


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
