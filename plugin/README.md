# dsh-godot-blackjack

**鲸鱼娘 21 点** —— 一个 DeepSeek Harness（DSH）插件，点一下就在本地启动一个
单挑黑杰克小游戏（Godot 写的），并且**自动把 DSH 自己的 DeepSeek 凭据注入游戏进程**。

- ✅ **不需要填 API Key** —— 用 DSH 里已经配好的那把
- ✅ **不需要装 Godot** —— 游戏以独立 exe 分发，插件首次启动时自动下载（压缩后约 40MB）
- ✅ 鲸鱼娘的对手大脑是真的 DeepSeek：会看你点数、会跟注、会嘴硬、输急眼了会翻脸

## 安装

在 DSH 侧边栏的 **Plugins** 页里输入包名：

```
dsh-godot-blackjack
```

国内建议先让 pnpm 走镜像（否则拉包可能很慢）：

```powershell
npm config set registry https://registry.npmmirror.com
```

装完 **重启一次 DSH**，界面右下角会出现「🐋 鲸鱼娘 21 点」按钮。

> 也可以直接跑仓库里的 `install.ps1` 走本地链接安装（零下载）：
> https://github.com/Gzy2233/dsh-godot-blackjack

## 它是怎么工作的

```
DSH 宿主
  │ ctx.credentials.resolve('DEEPSEEK_API_KEY')     ← 读 DSH 自己那把 key
  ▼
本插件（Host 半身）
  │ spawn(独立版 exe, { env: { DEEPSEEK_API_KEY, … }, windowsHide: false })
  ▼
Godot 游戏进程
  │ OS.get_environment("DEEPSEEK_API_KEY")
  ▼
右上角显示「已自动连接 DSH」
```

浏览器那一半（`lib/client.js`）只做一件事：在右下角画一个按钮，
点它 `fetch` 本插件注册的 `/dsh-blackjack-api/launch` 路由。

## 配置（可选）

改 `~/.dsh/plugins/dsh-godot-blackjack/cordis.patch.yml`（**改完存盘即生效，不用重启**）：

| 键 | 说明 |
|---|---|
| `godotExe` | 本机装了 Godot 时填上 → 直接跑 `game/` 工程（开发方便）|
| `projectDir` | 游戏工程目录，留空自动找 |
| `downloadURL` | 独立版 exe 的下载基址，留空 = 从本仓库的 GitHub Release 下载 |
| `model` / `baseURL` | 传给游戏的模型名与端点 |
| `autoLaunch` | 启动 DSH 时直接拉起游戏（默认 false）|
| `logGameOutput` | 把游戏 stdout 转发到 DSH 日志（排障用，能看到「已自动连接 DSH」那行）|

## 安全

宿主注入的 key **只在内存里用**：不写存档、不进日志、不改你手填的那份设置。
DSH 里没配 key 时游戏照样能玩，只是对手会退回本地策略大脑。

## 许可

MIT。完整说明与截图见仓库：https://github.com/Gzy2233/dsh-godot-blackjack
