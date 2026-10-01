# 怎么把它发到 GitHub（作者向）

**结论：不是「拖个文件夹上去」就行。** 有三件事会挡住你：

| 坑 | 说明 |
|---|---|
| **GitHub 网页拖拽一次最多 100 个文件** | 这个仓库有 **520+ 个文件**（光 `game/assets/` 就 424 个），网页上传得分 6+ 次，容易漏 |
| **网页上传不看 `.gitignore`** | 会把 `game/.godot/`（Godot 导入缓存，600+ 个文件、含你机器的绝对路径）一起传上去 |
| **独立版 exe 有 108MB** | 超过 GitHub **单文件 100MB 限制**，**不能**提交进 git —— 必须放到 **Release** 里 |

所以：**代码用 git 推，exe 用 Release 传。**

---

## 第 1 步：构建独立版 exe

```powershell
cd E:\我要赚钱啊啊啊啊\agent\突发奇想\dsh-godot-blackjack
powershell -ExecutionPolicy Bypass -File tools\build-release.ps1
```

它会：同步开发工程 → 清掉 MCP 开发依赖 → 生成导入缓存 → 导出
`dist\BlackjackWhale.exe` → **自己启动一次做冒烟测试**（检查 stderr 为空、自动连接生效）。

> 需要 Godot 4.7 的**导出模板**（编辑器 → 编辑器 → 管理导出模板 → 下载）。
> 国内直连 GitHub 只有 0.2MB/s（要 4 小时），走镜像几十秒就够：
>
> ```powershell
> curl.exe -L -o "$env:TEMP\t.zip" 'https://gh-proxy.com/https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz'
> Expand-Archive "$env:TEMP\t.zip" "$env:TEMP\tpl" -Force
> New-Item -ItemType Directory -Force "$env:APPDATA\Godot\export_templates\4.7.1.stable" | Out-Null
> Copy-Item "$env:TEMP\tpl\templates\*" "$env:APPDATA\Godot\export_templates\4.7.1.stable\" -Recurse -Force
> ```

## 第 2 步：把 exe 传成 Release

1. 打开 `https://github.com/<你的用户名>/<仓库名>/releases/new`
2. Tag 随便写（如 `v1.0.0`），标题写「鲸鱼娘 21 点 v1.0.0」
3. **附件上传 `dist\BlackjackWhale.exe`** —— 名字必须一模一样
4. 发布

插件的下载地址是 `.../releases/latest/download/BlackjackWhale.exe`，
所以**附件名**和 **`plugin/package.json` 里的 `repository.url`** 这两处必须对。

> 想放别处（自己的服务器、国内网盘直链）也行：在 `cordis.patch.yml` 里填 `config.downloadURL`。
> 国内用户下 Release 直链可能很慢，这是目前体验上最需要你自己权衡的一点。

## 第 3 步：推代码

先在 GitHub 上新建一个**空仓库**（不要勾 README / .gitignore / license），然后：

```powershell
cd E:\我要赚钱啊啊啊啊\agent\突发奇想\dsh-godot-blackjack
Remove-Item game\.godot -Recurse -Force -ErrorAction SilentlyContinue   # 保险
git init
git add .
git status                 # ← 看一眼：不该出现 .godot/ 或 dist/*.exe
git commit -m "鲸鱼娘 21 点：Godot 游戏 + DSH 插件（独立版 + 自动连接 DeepSeek）"
git branch -M main
git remote add origin https://github.com/<你的用户名>/dsh-godot-blackjack.git
git push -u origin main
```

`dist/` 已被 `.gitignore` 排除，所以那个 108MB 的 exe 不会被误提交。

---

## 发布前自检清单

- [ ] `Test-Path game\.godot` → `False`
- [ ] `git status` 里没有 `dist/` 下的东西
- [ ] `node plugin/test/host-smoke.mjs` → 「全部通过 ✓」（它会真的启动一次游戏）
- [ ] `plugin/package.json` 的 `repository.url` 是你的仓库
- [ ] Release 里那个附件叫 `BlackjackWhale.exe`
- [ ] README 里的 `git clone` 那行改成了你的仓库地址
- [ ] 确认 `LICENSE` 署名是你想要的

## 别人装的时候会遇到什么

| 情况 | 结果 |
|---|---|
| **只有 DSH，没有任何开发环境** | ✅ **主路径**：点按钮 → 自动下载独立版 → 开玩 |
| 有 Godot | ✅ 也支持：插件优先跑 `game/` 工程（改代码即时生效，开发方便） |
| DSH 里没配 DeepSeek 凭据 | ⚠️ 游戏还能玩，但对手退回本地策略大脑（界面显示"本地 AI"） |
| 下载慢 / 被墙 | ⚠️ 用 `config.downloadURL` 指到国内可访问的直链 |
| DSH 版本 < 0.1.5 | ⚠️ 未验证。凭据服务取不到时插件会退回直接读 `.credentials.yaml` |
