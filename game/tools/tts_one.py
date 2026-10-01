# -*- coding: utf-8 -*-
"""给**一句话**做配音（游戏运行时调用）。

用法（由 bj_voice.gd 通过 OS.create_process 拉起）：
    python tools/tts_one.py <文本文件路径> <输出目录> [音色key]

- 文本从**文件**读，不走命令行参数 —— 台词里有引号、换行、♡，命令行转义太容易翻车。
- 输出 `<输出目录>/<sha256前16位>.mp3`，哈希算法和 GDScript 侧一致：
      sha256(utf-8 原文).hexdigest()[:16]
  所以游戏里存过的句子下次直接命中，不再合成。
- **已经存在就直接退出**（0），让游戏侧看到文件就够了。

为什么要"运行时合成"：接了真模型之后它现编的台词是无限的，烤不完。
用同一个音色现烤现用，才不会出现"一句小鱼一句机器人"的两种声线。
"""
import asyncio
import hashlib
import os
import sys

VOICES = {
    "xiaoyi": ("zh-CN-XiaoyiNeural", "+10%", "+3Hz"),
    "xiaoxiao": ("zh-CN-XiaoxiaoNeural", "+6%", "+0Hz"),
    "xiaobei": ("zh-CN-liaoning-XiaobeiNeural", "+6%", "+0Hz"),
}
DEFAULT_VOICE = "xiaoyi"


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: tts_one.py <text_file> <out_dir> [voice]", file=sys.stderr)
        return 2
    text_file, out_dir = sys.argv[1], sys.argv[2]
    voice_key = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_VOICE
    try:
        with open(text_file, encoding="utf-8-sig") as fh:
            text = fh.read().strip()
    except OSError as exc:
        print("读不到文本：%s" % exc, file=sys.stderr)
        return 3
    if not text:
        return 0

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, hashlib.sha256(text.encode("utf-8")).hexdigest()[:16] + ".mp3")
    if os.path.exists(out_path) and os.path.getsize(out_path) > 512:
        return 0

    voice, rate, pitch = VOICES.get(voice_key, VOICES[DEFAULT_VOICE])
    try:
        import edge_tts
    except ImportError:
        print("没装 edge-tts（pip install edge-tts）", file=sys.stderr)
        return 4

    async def run() -> None:
        comm = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        await comm.save(out_path)

    try:
        asyncio.run(run())
    except Exception as exc:                                   # noqa: BLE001
        print("合成失败：%s" % exc, file=sys.stderr)
        return 5
    return 0 if os.path.exists(out_path) else 6


if __name__ == "__main__":
    raise SystemExit(main())
