"""把生成的 2048×2048 头像处理成游戏能用的图标。

为什么要分三种裁切（这不是玄学，是"32px 还能不能认出来"的实测结论）：
  原图很满、细节很多，直接整体缩放的话，在任务栏的 32×32 上只剩一团深蓝。
  所以：
    · **ico（exe / 任务栏）** 用最紧的裁切 —— 只留脸 + 筹码，主角占满画面，
      24×24 也认得出"蓝头发的女孩拿着一摞金筹码"；
    · **icon.png（游戏运行时窗口图标）** 用中等裁切，保留完整剪影（裙子、鲸尾）；
    · **封面** 不裁，原图直接放进 docs/（当 GitHub 头像/README 大图）。

用法：python tools/make_icon.py <源图.png>
"""
import os
import sys

from PIL import Image, ImageFilter

RESAMPLE = Image.LANCZOS

# (左, 上, 右, 下) —— 相对于原图的比例
CROP_ICO = (0.16, 0.10, 0.84, 0.78)     # 脸 + 筹码，最大可辨识度
CROP_PNG = (0.10, 0.06, 0.92, 0.88)     # 保留裙子与鲸尾的完整剪影

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
DOCS = os.path.join(ROOT, "docs")


def crop_by(im: Image.Image, box) -> Image.Image:
    w, h = im.size
    x0, y0, x1, y1 = box
    return im.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(DOCS, "00-cover.png")
    if not os.path.exists(src):
        print("用法：python tools/make_icon.py <源图.png>")
        return 1

    im = Image.open(src).convert("RGB")
    print("源图 %dx%d" % im.size)

    # ① 窗口图标 / GitHub 头像：保留完整剪影
    png = crop_by(im, CROP_PNG).resize((512, 512), RESAMPLE)
    png_path = os.path.join(GAME, "icon.png")
    png.save(png_path, "PNG", optimize=True)
    print("  icon.png  %d KB (512, 完整剪影)" % (os.path.getsize(png_path) // 1024))

    # ② exe / 任务栏：最紧裁切 + 轻微锐化，救 16~32px
    tight = crop_by(im, CROP_ICO)
    sharp = tight.resize((256, 256), RESAMPLE).filter(
        ImageFilter.UnsharpMask(radius=1.2, percent=110, threshold=3)
    )
    ico_path = os.path.join(GAME, "icon.ico")
    sharp.save(ico_path, format="ICO",
               sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("  icon.ico  %d KB (16~256 多尺寸)" % (os.path.getsize(ico_path) // 1024))

    # ③ 小尺寸预览图：放大 6 倍看像素，肉眼确认可辨识度
    for size in (24, 32, 48, 64):
        preview = tight.resize((size, size), RESAMPLE)
        preview = preview.resize((size * 6, size * 6), Image.NEAREST)
        preview.save(os.path.join(DOCS, "_icon-preview-%d.png" % size), "PNG")
    print("  预览图 docs/_icon-preview-{24,32,48,64}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
