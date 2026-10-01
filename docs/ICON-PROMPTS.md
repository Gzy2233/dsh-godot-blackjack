# 🎨 游戏头像 / 图标 生成提示词

游戏现在用的还是 **Godot 默认的那个机器人图标**（`game/icon.svg`），
导出的 exe、窗口、GitHub 仓库都缺一个属于自己的脸。这份文档是给**图像模型**的提示词。

---

## 先记住三个约束（决定了图标好不好用）

| 约束 | 为什么 |
|---|---|
| **必须在小尺寸下能认出来** | 它会被缩到 **32×32**（任务栏）、**48×48**（文件列表）、**500×500**（GitHub 头像）。细节全会在 32px 时消失 —— 所以**主体只能有一个**，不要塞三个人 |
| **配色要和游戏一致** | 配色抄下面这张表，别让图标是紫色而游戏是墨绿 |
| **方图、四周留白** | 各平台都会裁成圆形或圆角方块，主体别顶到边 |

### 游戏的真实配色（写进提示词里）

| 用途 | 色值 |
|---|---|
| 赌桌绿呢 | `#1b6b46` 深、`#2a8a5c` 亮 |
| 主强调（筹码/金币/高亮） | `#f0b429`，暗部 `#b8821a`，亮部 `#ffc94d` |
| 角色蓝（头发/眼睛/鲸尾） | `#7fb4ff`，暗部 `#0f2f7a`，最深 `#061b6e` |
| 危险红 | `#d9483f` |
| 文字米白 | `#f2f6f3` |
| 底/面板墨绿黑 | `#0f1a14`、`#12261c` |

### 角色设定（照这个描述，别自由发挥）

> 鲸鱼娘：**深蓝色过腰长发**，头顶有一撮**像鲸鱼喷水一样卷起来的呆毛**，
> **白底蓝色滚边的连衣裙**，身后拖着一条**蓝色鲸鱼尾巴**，蓝色眼睛。
> 她是这个 21 点赌桌上的**对家**，气质是"端庄但会翻脸"。

---

## ⭐ 主提示词（方形游戏图标，直接用这个）

```
Game icon, square, 1:1. A chibi anime whale girl: long dark-blue hair,
a water-spout curl on top of her head like a whale's blowhole spray,
white dress with blue sailor trim, a blue whale tail behind her, blue eyes.
She leans on a stack of golden poker chips with one hand; a fanned pair of
playing cards (an Ace and a black ten, minimal pip detail) sits beside the chips.
Background: dark green casino felt with a subtle radial vignette and a thin
golden rim light. Limited palette only: deep green #0f1a14 / #1b6b46,
gold #f0b429 / #ffc94d, character blue #7fb4ff / #061b6e, cream #f2f6f3.
Bold clean shapes, strong silhouette, high contrast, no text, no letters,
no numbers. The whole subject fits inside the central 70% with even margins.
Crisp vector-clean edges, poster-like, readable at 32x32 pixels.
```

**中文对照**（如果你用的模型中文更好）：
```
游戏图标，正方形 1:1。Q 版动漫鲸鱼娘：深蓝过腰长发，头顶一撮像鲸鱼喷水般卷起的呆毛，
白底蓝色水手滚边的连衣裙，身后一条蓝色鲸鱼尾，蓝眼睛。她一只手搭在一摞金色筹码上，
旁边斜靠两张展开的扑克牌（A 和黑色十点，点数简化成符号即可）。
背景：深绿赌桌呢面 + 柔和暗角 + 一圈金色轮廓光。
只用这套配色：墨绿 #0f1a14 / #1b6b46，金 #f0b429 / #ffc94d，
角色蓝 #7fb4ff / #061b6e，米白 #f2f6f3。
造型概括有力、剪影清晰、对比强烈，**不要任何文字与数字**。
主体占画面中间 70%，四周留均匀空白。边缘干净锐利，海报感，缩到 32×32 仍能认出来。
```

---

## 🕹 变体 B：像素风版本（和游戏内精灵最搭）

游戏里的她是 **48×57 的像素图**，如果你想要图标和游戏画面**完全同一种质感**，用这个：

```
Pixel art game icon, 64x64 logical pixels (output 512x512 with hard pixel edges,
NO anti-aliasing, NO gradients, NO blur). Chibi whale girl seen front-on:
long dark-blue hair, a curled water-spout tuft on top, white dress with blue trim,
a blue whale tail visible behind her. Behind her, a simplified golden poker chip
and one playing card at an angle. Dark green felt background block.
Strict limited palette (max 12 colors): #0f1a14 #12261c #1b6b46 #2a8a5c
#061b6e #0f2f7a #7fb4ff #f0b429 #ffc94d #b8821a #f2f6f3 #d9483f.
Every pixel is a hard square, no dithering haze. Silhouette must read at 32x32.
No text, no letters, no numbers, no logo.
```

> ⚠️ 像素风一定要写 **"hard pixel edges / no anti-aliasing"**，
> 否则模型会给你一张"看起来像像素的模糊图"，缩到 32px 会糊成一团。

---

## 🖼 变体 C：GitHub 社交预览图（16:9，README 顶部大图）

```
Wide cinematic key art, 16:9. A dim cabaret casino room: deep green felt table,
red velvet curtain, a single warm hanging lamp casting a pool of light.
On the left, a whale girl with long dark-blue hair, a curled water-spout tuft,
white dress with blue trim and a blue whale tail, leaning on the table looking
up with a cool confident half-smile. On the right, the viewer's point of view:
two face-up playing cards and a stack of golden chips, lit from above.
Scattered chips and a couple of cards mid-air for motion. Moody rim lighting,
limited palette (deep green #0f1a14 / #1b6b46, gold #f0b429, blue #7fb4ff /
#061b6e, cream #f2f6f3, accent red #d9483f). Semi-realistic anime illustration,
painterly but clean. Leave the top-left third relatively empty for a title.
No text, no watermark.
```

---

## 🚫 负面提示词（每个都加上）

```
text, letters, numbers, watermark, signature, logo, UI screenshot,
harsh neon colors, purple or pink dominant, rainbow, busy background,
cluttered composition, multiple characters, extra fingers, deformed hands,
photo-realism, 3D render, blurry, low contrast, subject touching the edges
```

---

## ✅ 拿到图之后：放到哪里

| 用途 | 放哪 | 尺寸 |
|---|---|---|
| **游戏窗口图标 + exe 图标** | `game/icon.png`（替换掉默认的 `icon.svg`） | 512×512 或 256×256 |
| **Windows exe 文件图标** | `game/icon.ico`（多尺寸 ico：16/32/48/64/128/256） | — |
| **GitHub 仓库头像** | GitHub → Settings → 仓库头像上传 | 500×500 或更大 |
| **README 顶部大图** | `docs/00-cover.png`（替换 README 第一张图） | 1600×900 |
| **DSH 面板里的按钮图标**（可选） | `plugin/lib/client.js` 里把 `🐋` 换成 `<img>` | 128×128 透明 PNG |

改完图标后要**重新导出**才生效：

```powershell
# ① 编辑 game/export_presets.cfg，把 application/icon 指到 icon.ico
#    （这一步只影响 exe 在资源管理器里的图标）
# ② 重新打包 + 自动冒烟测试
powershell -ExecutionPolicy Bypass -File tools\build-release.ps1
```

> 现在的 `export_presets.cfg` 里 `application/icon=""`，所以 exe 显示的是 Godot 默认图标。
> 把 `icon.ico` 生成好之后，那一行改成 `application/icon="res://icon.ico"` 即可。
> `game/icon.svg` / `icon.png` 则决定游戏**运行时的窗口图标**。

---

## 💡 挑图时的小抄

- 缩到 **32×32** 再看一眼：还能看出"有个蓝头发角色 + 金色筹码"就算合格；
  如果只剩一坨颜色，让模型"主体再放大、细节再砍"。
- 想要更"图标感"，可以把提示词里的 `chibi anime` 换成 `flat vector mascot`，
  背景直接给纯色 `#0f1a14`。
- 一次生成 4 张挑，比反复微调一张快得多。
