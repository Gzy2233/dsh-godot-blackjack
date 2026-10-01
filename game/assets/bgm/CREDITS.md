# BGM 候选素材 — 授权与来源记录

用途：像素风 21 点单挑游戏（深海赌桌 + 鲸鱼娘）BGM 候选。
下载时间：本次会话；全部文件已通过「大小 + 文件头」双重验证（见下方 Bytes / Magic 列）。

| 文件 | 字节数 | 文件头 | 曲名 | 作者 | 授权 |
|---|---|---|---|---|---|
| `Joth-8bit Bossa Nova.mp3` | 1,196,325 | `ID3` | 8bit Bossa Nova | Joth | CC0 1.0 |
| `KevinMacLeod-I Knew a Guy.mp3` | 6,044,335 | `ID3` | I Knew a Guy | Kevin MacLeod | CC BY 4.0 |
| `isaiah658-Underwater Ambient Pad.ogg` | 705,155 | `OggS` | Underwater Ambient Pad | isaiah658 | CC0 1.0 |
| `omfgdude-Lofi Loop.ogg` | 1,430,666 | `OggS` | Lofi Hip Hop Loop | omfgdude (OMF-Games) | CC0 1.0 |

---

## 1. Joth — 8bit Bossa Nova

- 来源页面: https://opengameart.org/content/bossa-nova
- 直链: https://opengameart.org/sites/default/files/8bit%20Bossa.mp3
- 授权: CC0 1.0 (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/
- 风格: 8-bit / chiptune 音色的 bossa nova，慵懒、电梯感、赌场 lounge
- 标签: loop, Jazz, calm, elevator, bossa nova, 129bpm
- 署名: 不需要。作者 Joth 原话「纯 bossa nova 兴趣 + 游戏音色混合」，页面标注 CC0。
- 备注: 时长约 1 分钟（ID3 tag 后按 160kbps 估算），短循环、体积小，最省事的一首。

## 2. Kevin MacLeod — I Knew a Guy

- 来源页面: https://incompetech.com/music/royalty-free/index.html?keywords=I+Knew+a+Guy&Search=Search
  （站点索引页 https://incompetech.com/music/royalty-free/music.html）
- 直链: https://incompetech.com/music/royalty-free/mp3-royaltyfree/I%20Knew%20a%20Guy.mp3
- 授权: Creative Commons Attribution 4.0 (CC BY 4.0) — https://creativecommons.org/licenses/by/4.0/
  （依据 https://incompetech.com/music/royalty-free/faq.html ：incompetech 全部曲目按 CC BY 4.0 提供，必须署名）
- 文件内嵌 ID3 已核对: TIT2=`I Knew a Guy` / TPE1=`Kevin MacLeod` / TALB=`Scoring: Noire` / COMM=`incompetech.com`
- 风格: 慵懒 noir jazz（低音贝斯 + 铃声 + 鼓），慢速、不激昂、无人声
- 时长: 约 2:47
- **必须署名**。官方要求的署名文本（把 Title 换成曲名）：

  ```
  "I Knew a Guy" Kevin MacLeod (incompetech.com)
  Licensed under Creative Commons: By Attribution 4.0
  https://creativecommons.org/licenses/by/4.0/
  ```

- 备注: 曲末为完整收尾而非无缝接缝，Godot 里直接 loop 可能会有轻微断点；建议在 Godot 的
  AudioStreamPlayer 里配合淡入淡出，或把它当作「每局开始时播放一次」的曲子。

## 3. isaiah658 — Underwater Ambient Pad

- 来源页面: https://opengameart.org/content/underwater-ambient-pad
- 直链: https://opengameart.org/sites/default/files/Underwater-Ambient-Pad-isaiah658_0.ogg
- 授权: CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/
- 作者声明: "Attribution not required. Credit isaiah658 if you want to."
- 风格: 深海 / 水下氛围 pad，梦幻、无节奏、无人声
- 时长: 约 16.5 秒的 loop（Ogg 末页 granule 735232 / 44100）
- 备注: 极短，适合做底噪式环境层，叠在爵士 BGM 下面；不适合单独当主体 BGM。

## 4. omfgdude (OMF-Games) — Lofi Hip Hop Loop

- 来源页面: https://opengameart.org/content/lofi-hip-hop-loop
- 直链: https://opengameart.org/sites/default/files/LofiLoop_2.ogg
- 授权: CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/
- 风格: lofi hip hop / chiptune 循环，柔和、chill
- 时长: 约 2:08
- 署名: 不需要（作者在评论区明确表示无需署名；如想署名可用 "OMF-Games"）

---

## 已考察但未保留的候选（需要可自行下载）

- Kevin MacLeod — Airport Lounge（CC BY 4.0，直链
  https://incompetech.com/music/royalty-free/mp3-royaltyfree/Airport%20Lounge.mp3 ），
  赌场 lounge 感最正，但 12,309,016 字节（约 5:07 @320kbps），超过 8MB 参考线，故未保留。
- Kevin MacLeod — Backbay Lounge / Bossa Antigua / Cool Vibes / Smooth Lovin 同样 > 8MB。
- 小于 8MB 的备选（均已实测可下载）：Off to Osaka (4.0MB)、Hard Boiled (5.8MB)、
  I Knew a Guy (6.0MB)、Cuban Sandwich (6.2MB)、Sidewalk Shade (6.3MB)、Bass Walker (6.5MB)。

## 下载与验证方法

```powershell
Invoke-WebRequest -Uri <直链> -OutFile <文件名> -UserAgent "Mozilla/5.0" -UseBasicParsing
Get-Item <文件名> | Select-Object Name,Length      # 均 > 100KB
# 文件头：ogg = 4F 67 67 53 ("OggS")，mp3 = 49 44 33 ("ID3")
```

四首文件头实测：
- `isaiah658-Underwater Ambient Pad.ogg` → `4F 67 67 53 00 02 ...` = **OggS** ✓
- `Joth-8bit Bossa Nova.mp3` → `49 44 33 02 00 ...` = **ID3** ✓
- `KevinMacLeod-I Knew a Guy.mp3` → `49 44 33 02 00 ...` = **ID3** ✓
- `omfgdude-Lofi Loop.ogg` → `4F 67 67 53 00 02 ...` = **OggS** ✓

Godot 4 原生支持 `.ogg`（AudioStreamOggVorbis）与 `.mp3`（AudioStreamMP3），导入后
勾选 loop 即可（ogg 循环点最干净）。
