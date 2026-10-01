# -*- coding: utf-8 -*-
"""把"外援立绘"转成游戏要的标准格式。

游戏里鲸鱼娘的每个情绪都是：**一帧 48×57，同一情绪的所有帧横向排开、无间隙、透明背景**。
AI 生成的外援立绘往往不是这个规格（尺寸是 4 倍、带一块纯色底），这个脚本负责规整：

    python tools/prepare_whale_extra.py <源图> <输出png> <帧数> [底色hex]

例：
    python tools/prepare_whale_extra.py heihua_angry_x4.png assets/whale/black.png 4

做的事：
  1. 按**纯色底**抠掉背景（底色默认从四角取样），带一点过渡带避免锯齿硬边；
  2. 横向等分成 <帧数> 格，每格按**最近邻**缩到 48×57（外援图通常是 4 倍整，最近邻正好无损）；
  3. 输出 48×帧数 × 57 的横排 sheet。

为什么不直接在游戏里做：一次性规整好，运行时零开销，而且换素材重跑一遍就行。
"""
import os
import sys

from PIL import Image

# Windows 控制台默认 GBK，打印中文会崩 —— 强制 UTF-8
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:                                          # noqa: BLE001
    pass

FRAME_W, FRAME_H = 48, 57
EDGE_SOFT = 10      # 与底色的切比雪夫距离 ≤ 这个值 → 完全透明
EDGE_HARD = 26      # ≥ 这个值 → 完全不透明，中间线性过渡


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    src_path, out_path, frames = sys.argv[1], sys.argv[2], int(sys.argv[3])
    src = Image.open(src_path).convert("RGBA")
    w, h = src.size

    if len(sys.argv) > 4:
        hex_color = sys.argv[4].lstrip("#")
        bg = tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    else:
        # 四角取样当底色（AI 图基本都是纯色底）
        corners = [src.getpixel(xy)[:3] for xy in
                   [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
        bg = tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))
    print("底色 = %s" % (bg,))

    # 1) 抠底
    keyed = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src_px = src.load()
    out_px = keyed.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = src_px[x, y]
            dist = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            if dist <= EDGE_SOFT:
                continue
            alpha = 255 if dist >= EDGE_HARD else int(
                255.0 * (dist - EDGE_SOFT) / float(EDGE_HARD - EDGE_SOFT))
            out_px[x, y] = (r, g, b, min(a, alpha))

    # 2) 等分 + 最近邻缩到 48×57
    cell_w = w // frames
    sheet = Image.new("RGBA", (FRAME_W * frames, FRAME_H), (0, 0, 0, 0))
    for i in range(frames):
        cell = keyed.crop((i * cell_w, 0, (i + 1) * cell_w, h))
        sheet.paste(cell.resize((FRAME_W, FRAME_H), Image.NEAREST), (i * FRAME_W, 0))

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    sheet.save(out_path)
    total = FRAME_W * frames * FRAME_H
    hist = sheet.getchannel("A").histogram()
    transparent = sum(hist[:10])
    print("输出 %s  %dx%d（%d 帧）透明占比 %.1f%%"
          % (out_path, sheet.width, sheet.height, frames, 100.0 * transparent / total))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
