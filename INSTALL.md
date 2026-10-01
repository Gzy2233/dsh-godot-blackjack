# 鲸鱼娘 21 点 · DSH 插件（一键安装脚本）

把 `plugin/` 装进 DSH 的 desktop profile，并把 `game/` 的路径写进插件配置。
**只碰这两个地方**，且都会先备份：

1. `%DSH_HOME%\plugins\dsh-godot-blackjack\` ← 复制插件本体
2. `%DSH_HOME%\profiles\desktop\package.json` ← 加一行依赖 + 一行 bundle 名（改动前备份）

> ⚠️ 为什么必须手工改 `package.json`：**desktop profile 不能用 CLI 安装**
> （`dsh plugin --profile desktop` 会被 `bin.js` 硬拒绝，desktop 归 Electron 独占）。
> 图形界面里也可以用侧边栏的 **Plugins** 页装，效果一样。

用法：

```powershell
# 在仓库根目录
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

可选参数：

| 参数 | 说明 |
|---|---|
| `-GodotExe <路径>` | 指定 Godot 可执行文件；不给就自动探测 |
| `-ProjectDir <路径>` | 指定游戏工程目录；默认用仓库里的 `game\` |
| `-Uninstall` | 卸载（移出 plugins 目录 + 从 package.json 里删掉那两行） |
| `-DryRun` | 只打印将要做什么，不落盘 |

装完 **需要重启一次 DSH** —— 插件的 JS 代码只有重启才会加载
（`cordis.patch.yml` 是热生效的，但 `lib/index.js` 不是）。
