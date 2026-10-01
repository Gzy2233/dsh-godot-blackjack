#!/usr/bin/env pwsh
# 打包独立版游戏：同步开发工程 → 清理 → 导出 BlackjackWhale.exe
#
# 为什么需要它（而不是手敲几条命令）：
#   1. **每次同步都会把开发工程的 `project.godot` 覆盖回来**，而它里面有一个
#      `_mcp_game_helper` 自动加载项指向 MCP 插件（玩家没有那个插件）——
#      忘了清就会在玩家机器上刷 3 行 ERROR。这个脚本每次都清。
#   2. 同步必须排除 `.godot`（导入缓存）和 `addons`（开发依赖），
#      否则仓库会变脏、镜像也会变大。
#   3. 导出前必须先 `--headless --import`，否则 `class_name` 解析不了（白屏）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\build-release.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-release.ps1 -DevProject 'D:\其他\21'
[CmdletBinding()]
param(
  [string]$DevProject = 'C:\Users\Gzy2233\Documents\21',
  [string]$GodotExe = '',
  [switch]$SkipSync
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$GameDir  = Join-Path $RepoRoot 'game'
$DistDir  = Join-Path $RepoRoot 'dist'

function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Say($m)  { Write-Host "  $m" }
function Die($m)  { Write-Host "  [X] $m" -ForegroundColor Red; exit 1 }

Write-Host "`n=== 打包独立版 ===" -ForegroundColor Cyan

if (-not $GodotExe) {
  # 注意：PowerShell 5.1 里 `foreach (...) {...} | ...` 是非法的（"空管道元素"），
  # 必须先把结果收进数组，再管道。
  $roots = @("$env:ProgramFiles\Godot", "${env:ProgramFiles(x86)}\Godot", 'E:\Program Files (x86)\Godot', 'D:\Godot', 'C:\Godot')
  $found = @()
  foreach ($r in $roots) {
    if (Test-Path $r) {
      $found += Get-ChildItem $r -Filter 'Godot*.exe' -File -Depth 2 -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
    }
  }
  $GodotExe = $found | Select-Object -First 1
}
if (-not $GodotExe -or -not (Test-Path $GodotExe)) { Die "没找到 Godot（用 -GodotExe 指定）" }
Ok "Godot = $GodotExe"

# ── 1. 同步
if (-not $SkipSync) {
  if (-not (Test-Path (Join-Path $DevProject 'project.godot'))) { Die "开发工程不存在：$DevProject" }
  Say "同步 $DevProject → game/（排除 .godot / addons / docs / tests）"
  robocopy $DevProject $GameDir /E /XD .godot addons docs tests /NFL /NDL /NJH /NJS /NP | Out-Null
  Ok "已同步"
}
Remove-Item (Join-Path $GameDir '.godot') -Recurse -Force -EA SilentlyContinue

# ── 2. 清掉开发依赖（每次同步后都要做，见文件头注释）
$proj = Join-Path $GameDir 'project.godot'
$lines = Get-Content $proj -Encoding UTF8
$clean = $lines | Where-Object {
  $t = $_.Trim()
  -not ($t -like '_mcp_game_helper=*' -or $t -eq '[editor_plugins]' -or $t -like 'enabled=PackedStringArray("*godot_ai*')
}
if ($clean.Count -ne $lines.Count) {
  Set-Content -Path $proj -Value $clean -Encoding UTF8
  Ok "已移除 MCP 开发依赖（$($lines.Count - $clean.Count) 行）"
} else {
  Ok "project.godot 干净"
}

# ── 3. 导入（生成全局类表）
# **必须跑两遍**：Godot 在全新工程上第一次 --import 只扫资源，
# 第二次才把 class_name 注册进 .godot/global_script_class_cache.cfg（实测）。
# 只跑一遍就检查会误判成"导入失败"，然后导出一个白屏的游戏。
$cache = Join-Path $GameDir '.godot\global_script_class_cache.cfg'
foreach ($pass in 1..2) {
  Say "生成导入缓存（第 $pass 遍）…"
  & $GodotExe --headless --import --path $GameDir 2>&1 | Out-Null
  if (Test-Path $cache) { break }
}
if (-not (Test-Path $cache)) { Die "导入失败：两遍之后仍然没有 global_script_class_cache.cfg" }
Ok "导入完成（类表已生成）"

# ── 4. 导出
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
Remove-Item (Join-Path $DistDir 'BlackjackWhale.exe') -Force -EA SilentlyContinue
Say "导出 release 版…"
& $GodotExe --headless --export-release "Windows Desktop" --path $GameDir 2>&1 | Select-Object -Last 1 | Out-Null
$out = Join-Path $DistDir 'BlackjackWhale.exe'
if (-not (Test-Path $out)) { Die "导出失败（装了导出模板吗？编辑器 → 编辑器 → 管理导出模板）" }
Ok ("产物 " + [math]::Round((Get-Item $out).Length/1MB,1) + " MB → $out")

# ── 5. 冒烟：真跑一次，确认没有 stderr、且自动连接有效
Say "冒烟测试（启动 9 秒，检查 stderr 与自动连接）…"
$env:DEEPSEEK_API_KEY = 'sk-build-smoke'
$o = "$env:TEMP\_bj_build_out.txt"; $e = "$env:TEMP\_bj_build_err.txt"
$p = Start-Process -FilePath $out -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
Start-Sleep -Seconds 9
if (-not $p.HasExited) { $p.Kill() }
Start-Sleep -Milliseconds 800
Remove-Item Env:\DEEPSEEK_API_KEY
$errCount = (Get-Content $e -Encoding UTF8 -EA SilentlyContinue | Measure-Object).Count
$autoConnect = [bool](Get-Content $o -Encoding UTF8 -EA SilentlyContinue | Select-String '已自动连接 DSH')
if ($errCount -gt 0) { Get-Content $e -Encoding UTF8 | Select-Object -First 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkYellow } }
Ok "stderr 行数 = $errCount"
if ($errCount -eq 0 -and $autoConnect) { Ok "自动连接 = 生效" } else { Die "冒烟没过（stderr=$errCount, 自动连接=$autoConnect）" }

Write-Host "`n=== 打包完成 ===" -ForegroundColor Green
Write-Host "  下一步：把这个 exe 传到 GitHub Release（**不要提交进 git**，108MB 超了单文件限制）："
Write-Host "    https://github.com/<owner>/<repo>/releases/new"
Write-Host "    附件名必须是 BlackjackWhale.exe（插件按这个名字拼下载地址）"
Write-Host ""
