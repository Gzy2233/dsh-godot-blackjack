#!/usr/bin/env pwsh
# 鲸鱼娘 21 点 · DSH 插件一键安装 / 卸载
#
# 设计原则：**只动该动的地方，动之前先备份，任何一步失败都明确告诉你。**
#   - 插件本体复制到  %DSH_HOME%\plugins\dsh-godot-blackjack\
#   - 在 desktop profile 的 package.json 里
#       ① dependencies 加一条   "dsh-godot-blackjack": "link:<插件目录>"
#       ② dsh.profile.bundles 追加 "dsh-godot-blackjack"
#     （少了 ② 插件就**根本不会被加载** —— 这是最常见的"装完没反应"原因）
#
# 为什么不用 `dsh plugin --profile desktop add`：那条命令会被硬拒绝
# （desktop profile 归 Electron 独占，见 @deepseek-ai/dsh/lib/bin.js）。
[CmdletBinding()]
param(
  [string]$GodotExe = '',
  [string]$ProjectDir = '',
  [switch]$Uninstall,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PluginName = 'dsh-godot-blackjack'
$RepoRoot   = $PSScriptRoot
$PluginSrc  = Join-Path $RepoRoot 'plugin'

function Say($msg)  { Write-Host "  $msg" }
function Ok($msg)   { Write-Host "  [OK] $msg"   -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!]  $msg"   -ForegroundColor Yellow }
function Die($msg)  { Write-Host "  [X]  $msg"   -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=== 鲸鱼娘 21 点 · DSH 插件安装器 ===" -ForegroundColor Cyan

# ---------------------------------------------------------------- 0. 找 DSH
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
if (-not (Test-Path $DshHome)) { Die "找不到 DSH 目录：$DshHome（先运行一次 DeepSeek Harness）" }
$ProfileName = if ($env:DSH_PROFILE) { $env:DSH_PROFILE } else { 'desktop' }
$ProfileDir  = Join-Path $DshHome "profiles\$ProfileName"
$ProfileJson = Join-Path $ProfileDir 'package.json'
$PluginsDir  = Join-Path $DshHome 'plugins'
$PluginDst   = Join-Path $PluginsDir $PluginName

Say "DSH_HOME   = $DshHome"
Say "profile    = $ProfileName"
if (-not (Test-Path $ProfileJson)) { Die "找不到 profile 的 package.json：$ProfileJson" }

# ---------------------------------------------------------------- 1. 卸载分支
if ($Uninstall) {
  Write-Host "`n-- 卸载 --" -ForegroundColor Cyan
  if (Test-Path $PluginDst) { if ($DryRun) { Say "将删除 $PluginDst" } else { Remove-Item $PluginDst -Recurse -Force; Ok "已删除 $PluginDst" } }
  $raw = Get-Content $ProfileJson -Raw -Encoding UTF8
  $json = $raw | ConvertFrom-Json
  if ($json.dependencies.PSObject.Properties.Name -contains $PluginName) {
    if (-not $DryRun) {
      Copy-Item $ProfileJson "$ProfileJson.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
      Say "剩余步骤：请到 DSH 的 Plugins 页里删掉它，或手工从 package.json 移除："
    }
    Say "  dependencies['$PluginName'] 与 dsh.profile.bundles 里的 '$PluginName'"
  }
  Write-Host "`n卸载需要重启 DSH 才完全生效。" -ForegroundColor Yellow
  exit 0
}

# ---------------------------------------------------------------- 2. 找 Godot
Write-Host "`n-- 1/4 定位 Godot --" -ForegroundColor Cyan
if (-not $GodotExe) {
  # 只查**已知的几个安装位置**，每个最多下探 2 层。
  # （早先版本对 C:\Program Files 做 -Recurse，要跑好几分钟 —— 那是错的。）
  $GodotExe = $env:GODOT_EXE
  if (-not $GodotExe) {
    $roots = @(
      "$env:ProgramFiles\Godot", "${env:ProgramFiles(x86)}\Godot",
      'C:\Godot', 'D:\Godot', 'E:\Godot',
      "$env:ProgramFiles\Godot Engine", "${env:ProgramFiles(x86)}\Godot Engine",
      "$env:LOCALAPPDATA\Programs\Godot",
      'E:\Program Files (x86)\Godot', 'D:\Program Files\Godot'
    )
    $found = foreach ($root in $roots) {
      if (Test-Path $root) {
        Get-ChildItem $root -Filter 'Godot*.exe' -File -Depth 2 -ErrorAction SilentlyContinue |
          Select-Object -ExpandProperty FullName
      }
    }
    $onPath = (Get-Command godot -ErrorAction SilentlyContinue).Source
    $GodotExe = @($onPath) + @($found) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  }
}
if (-not $GodotExe -or -not (Test-Path $GodotExe)) {
  Warn "没探测到 Godot 可执行文件（也可以设环境变量 GODOT_EXE 指定）。"
  Say "请装一个 Godot 4.7（https://godotengine.org/download），或用 -GodotExe <路径> 指定。"
  Say "装好后改 $PluginDst\cordis.patch.yml 里的 config.godotExe 即可（热生效，不用重启）。"
} else {
  Ok "Godot = $GodotExe"
}

# ---------------------------------------------------------------- 3. 游戏目录
Write-Host "`n-- 2/4 游戏工程 --" -ForegroundColor Cyan
if (-not $ProjectDir) { $ProjectDir = Join-Path $RepoRoot 'game' }
if (-not (Test-Path (Join-Path $ProjectDir 'project.godot'))) {
  Die "目录里没有 project.godot：$ProjectDir"
}
$ProjectDir = (Resolve-Path $ProjectDir).Path
Ok "projectDir = $ProjectDir"

# 首次运行前必须让 Godot 生成 .godot/（全局类表 + 资源导入）。
# 少了这一步，直接跑游戏会满屏 `Parse Error: Identifier "BjTheme" not declared`，
# 然后白屏 —— 看起来像插件坏了，其实是工程从没被编辑器导入过。
if (-not $DryRun -and $GodotExe -and (Test-Path $GodotExe)) {
  $cache = Join-Path $ProjectDir '.godot\global_script_class_cache.cfg'
  if (Test-Path $cache) {
    Ok "Godot 导入缓存已存在（跳过）"
  } else {
    Say "生成 Godot 导入缓存（约 6 秒，只做一次）…"
    & $GodotExe --headless --import --path $ProjectDir *> $null
    if (Test-Path $cache) { Ok "导入完成" }
    else { Warn "导入没成功；插件第一次启动时会自己再试一次" }
  }
}

# ---------------------------------------------------------------- 4. 复制插件
Write-Host "`n-- 3/4 安装插件本体 --" -ForegroundColor Cyan
if ($DryRun) {
  Say "将复制 $PluginSrc -> $PluginDst"
} else {
  if (Test-Path $PluginDst) { Remove-Item $PluginDst -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $PluginDst | Out-Null
  Copy-Item "$PluginSrc\*" $PluginDst -Recurse -Force
  Ok "已复制到 $PluginDst"
}

# 把探测到的路径写进插件的配置
$PatchFile = Join-Path $PluginDst 'cordis.patch.yml'
if (-not $DryRun -and (Test-Path $PatchFile)) {
  $patch = Get-Content $PatchFile -Raw -Encoding UTF8
  if ($GodotExe -and (Test-Path $GodotExe)) {
    $patch = [regex]::Replace($patch, "(?m)^(\s*godotExe:\s*).*$", "`${1}'" + ($GodotExe -replace '\\','\\') + "'")
  }
  $patch = [regex]::Replace($patch, "(?m)^(\s*projectDir:\s*).*$", "`${1}'" + ($ProjectDir -replace '\\','\\') + "'")
  [System.IO.File]::WriteAllText($PatchFile, $patch, (New-Object System.Text.UTF8Encoding($false)))
  Ok "已把路径写入 cordis.patch.yml"
}

# 顺带把本地已构建的独立版 exe 预放进下载缓存 ——
# 这样**作者自己**装完是秒开；普通玩家没有这个文件，插件会从 GitHub Release 下载。
if (-not $DryRun) {
  $localExe = Join-Path $RepoRoot 'dist\BlackjackWhale.exe'
  $cacheDir = Join-Path $env:LOCALAPPDATA 'dsh-godot-blackjack'
  $cacheExe = Join-Path $cacheDir 'BlackjackWhale.exe'
  if ((Test-Path $localExe) -and -not (Test-Path $cacheExe)) {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    Copy-Item $localExe $cacheExe -Force
    Ok ("已把本地独立版放进缓存（" + [math]::Round((Get-Item $cacheExe).Length/1MB,1) + " MB）→ 首次启动不用下载")
  } elseif (Test-Path $cacheExe) {
    Ok "独立版已在缓存里（首次启动不用下载）"
  } else {
    Say "本地没有独立版 exe —— 首次点按钮时会从 GitHub Release 下载（约 108MB）"
  }
}

# ---------------------------------------------------------------- 5. 注册 bundle
Write-Host "`n-- 4/4 注册到 profile --" -ForegroundColor Cyan
$raw = Get-Content $ProfileJson -Raw -Encoding UTF8
$json = $raw | ConvertFrom-Json

$alreadyDep    = $json.dependencies.PSObject.Properties.Name -contains $PluginName
$bundles       = @()
if ($json.dsh -and $json.dsh.profile -and $json.dsh.profile.bundles) { $bundles = @($json.dsh.profile.bundles) }
$alreadyBundle = $bundles -contains $PluginName

if ($alreadyDep -and $alreadyBundle) {
  Ok "已经在 profile 里注册过了（跳过）"
} elseif ($DryRun) {
  Say "将在 dependencies 加 link:$PluginDst，并在 dsh.profile.bundles 末尾追加 $PluginName"
} else {
  $backup = "$ProfileJson.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Copy-Item $ProfileJson $backup -Force
  Ok "已备份 -> $backup"

  # 用文本插入而不是 ConvertTo-Json 回写：后者会把整个文件重新格式化，
  # 可能打乱 DSH 自己维护的字段顺序（也会把中文转义），风险不值得冒。
  $linkPath = ($PluginDst -replace '\\','/')
  if (-not $alreadyDep) {
    $anchor = [regex]::Match($raw, '(?m)^(\s*)"dependencies"\s*:\s*\{\s*$')
    if (-not $anchor.Success) { Die "package.json 结构不认识（找不到 dependencies 块），请手工按 INSTALL.md 添加" }
    $insertAt = $anchor.Index + $anchor.Length
    $raw = $raw.Insert($insertAt, "`r`n    `"$PluginName`": `"link:$linkPath`",")
    Ok "dependencies += $PluginName"
  }
  if (-not $alreadyBundle) {
    $m = [regex]::Match($raw, '(?s)"bundles"\s*:\s*\[(.*?)\]')
    if (-not $m.Success) { Die "package.json 里找不到 dsh.profile.bundles 数组，请手工按 INSTALL.md 添加" }
    $inner = $m.Groups[1].Value
    $trimmed = $inner.TrimEnd()
    $newInner = if ($trimmed -eq '') { "`r`n        `"$PluginName`"`r`n      " } else { "$trimmed,`r`n        `"$PluginName`"`r`n      " }
    $raw = $raw.Remove($m.Groups[1].Index, $m.Groups[1].Length).Insert($m.Groups[1].Index, $newInner)
    Ok "dsh.profile.bundles += $PluginName （放在末尾，配置优先级最低最安全）"
  }
  [System.IO.File]::WriteAllText($ProfileJson, $raw, (New-Object System.Text.UTF8Encoding($false)))
  # 立刻校验一遍：写坏了要马上发现
  try { $null = Get-Content $ProfileJson -Raw -Encoding UTF8 | ConvertFrom-Json; Ok "package.json 语法校验通过" }
  catch { Copy-Item $backup $ProfileJson -Force; Die "写坏了 package.json，已自动回滚。请把 $backup 手工恢复并反馈。" }
}

# ---------------------------------------------------------------- 完成
Write-Host ""
Write-Host "=== 完成 ===" -ForegroundColor Green
Write-Host "  下一步：**重启一次 DSH**（插件 JS 只有重启才会加载）。" -ForegroundColor Yellow
Write-Host "  重启后界面右下角会出现「🐋 鲸鱼娘 21 点」，点它就开始玩。"
Write-Host "  游戏里的 DeepSeek 凭据由本插件自动注入，**不需要填 API Key**。"
Write-Host ""
Write-Host "  万一没反应，按顺序查：" -ForegroundColor DarkGray
Write-Host "    1) $PluginName 是否在 $ProfileJson 的 dsh.profile.bundles 里" -ForegroundColor DarkGray
Write-Host "    2) DSH 日志里有没有 [$PluginName] 开头的行" -ForegroundColor DarkGray
Write-Host "    3) Godot 路径对不对：$PluginDst\cordis.patch.yml" -ForegroundColor DarkGray
Write-Host ""
