// dsh-godot-blackjack —— Host 半身（跑在 DSH 宿主进程里）
//
// 它做三件事：
//   1. **读 DSH 自己正在用的 DeepSeek 凭据**（`ctx.credentials.resolve`，
//      读不到就退回直接解析 `$DSH_HOME/.credentials.yaml`）；
//   2. **把凭据通过环境变量注入游戏进程**并启动 Godot —— 玩家因此不用填 key；
//   3. 暴露 `/dsh-blackjack-api/{launch,status}` 给浏览器那一半调用。
//
// ───────────────────────────────────────────────────────────────────────────
// 这份代码里有 4 个"踩过才知道"的地方，改动前请先读：
//
// ① **不要用 `ctx.subprocess` 起游戏。** dsh-subprocess-local 在 Windows 上
//    "non-terminal children start with their windows hidden" —— 而 Godot 是 GUI，
//    走它大概率只闻其声不见其窗。用裸 `node:child_process` + `windowsHide: false`。
//    （另外 `ctx.subprocess` 还会清洗子进程环境，凭据必须显式再传一遍。）
//
// ② **不要用 `connection.rpc.handle()` 做前后端通信。** 它在 desktop profile 上
//    会抛 `cannot get property "webServer" without inject`。唯一可靠通道是
//    自己在 `ctx.webServer` 上注册路由，前端同源 fetch。
//
// ③ **`inject` 里只放"一定存在"的服务。** 老宿主上缺一个服务，插件就永远不 apply。
//    可选服务一律用 `ctx.get('x')`。
//
// ④ **key 绝不落盘、绝不进日志。** 只放进子进程环境变量。
//    游戏侧同理（见 scripts/game/bj_game.gd 的 `_read_dsh_env`）。
// ───────────────────────────────────────────────────────────────────────────
import { spawn, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-godot-blackjack'

// 只声明一定存在的服务；credentials 用 ctx.get() 取（可选）。
export const inject = ['webServer']

const PLUGIN_ID = 'dsh-godot-blackjack'
const API_PREFIX = '/dsh-blackjack-api'   // 刻意避开宿主保留的 /api 与 /plugins
const CREDENTIAL_KEY = 'DEEPSEEK_API_KEY'

// 本插件包根目录（lib/ 的上一级 = plugin/）。package.json 就在这儿。
const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
// 仓库根目录（plugin/ 的上一级）。**只在"直接从仓库里用插件"时有意义**：
// game/、dist/BlackjackWhale.exe 都在这一层。
// 插件被 install.ps1 复制进 ~/.dsh/plugins/ 之后，这里指向的就不是仓库了 ——
// 所以那两个路径只是"顺手能找到就用"，找不到就走自动探测 / 下载。
const REPO_ROOT = path.resolve(PACKAGE_ROOT, '..')
const BUNDLED_GAME_DIR = path.join(REPO_ROOT, 'game')

// 独立版可执行文件的名字（Godot 导出产物；由 install.ps1 从 GitHub Release 下载，
// 或玩家自己放进这个目录）。
const STANDALONE_EXE_NAME = 'BlackjackWhale.exe'
// 下载缓存目录：用户可写、不进仓库、不进 plugins 目录。
const CACHE_DIR = path.join(
  process.env.LOCALAPPDATA || os.tmpdir(),
  'dsh-godot-blackjack',
)

function log(...args) {
  console.log(`[${PLUGIN_ID}]`, ...args)
}

function warn(...args) {
  console.warn(`[${PLUGIN_ID}]`, ...args)
}

// ────────────────────────────────────────────────────────────── 独立版定位

/** 本地已经有的独立版 exe（按优先级）。 */
function standaloneCandidates() {
  const extra = process.env.DSH_BLACKJACK_EXE
  return [
    extra,
    path.join(CACHE_DIR, STANDALONE_EXE_NAME),          // 插件下载的缓存
    path.join(BUNDLED_GAME_DIR, STANDALONE_EXE_NAME),   // 仓库布局：game/ 里
    path.join(REPO_ROOT, 'dist', STANDALONE_EXE_NAME),  // 仓库布局：dist/ 里（构建产物）
  ].filter(Boolean)
}

function findStandaloneExe() {
  for (const candidate of standaloneCandidates()) {
    try {
      if (fs.existsSync(candidate)) return candidate
    } catch { /* 忽略 */ }
  }
  return ''
}

/**
 * 从**本仓库的 GitHub Release** 推下载地址。
 *
 * 不写死 URL：插件就在仓库里，所以 package.json 的 `repository` 字段
 * 就是它自己的出处 —— 换成任何人的 fork 都能自动对上，作者的仓库改名也不用改代码。
 * 想在别处托管 exe，就在 cordis.patch.yml 里填 config.downloadURL。
 */
function releaseAssetUrl() {
  const repo = readRepositoryUrl()
  if (!repo) return ''
  return `${repo}/releases/latest/download/${STANDALONE_EXE_NAME}`
}

function readRepositoryUrl() {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(PACKAGE_ROOT, 'package.json'), 'utf8'))
    const raw = typeof pkg.repository === 'string' ? pkg.repository : pkg.repository?.url
    if (!raw) return ''
    const url = String(raw)
      .replace(/^git\+/, '')
      .replace(/\.git$/, '')
      .replace(/\/$/, '')
    // 还没填自己的仓库（模板里的占位符）→ 当作没配置，
    // 免得去请求一个不存在的地址、报一堆看不懂的 404。
    if (/\bOWNER\/REPO\b/i.test(url)) return ''
    if (!/^https?:\/\/github\.com\/[^/<>]+\/[^/<>]+$/.test(url)) return ''
    return url
  } catch {
    return ''
  }
}

/** 下载独立版 exe 到缓存目录。返回路径。 */
async function downloadStandaloneExe(url) {
  fs.mkdirSync(CACHE_DIR, { recursive: true })
  const target = path.join(CACHE_DIR, STANDALONE_EXE_NAME)
  const partial = `${target}.part`
  log(`正在下载独立版游戏（约 90MB，只下一次）：${url}`)

  const response = await fetch(url, { redirect: 'follow' })
  if (!response.ok) {
    throw new Error(`下载失败 HTTP ${response.status}（Release 里有没有 ${STANDALONE_EXE_NAME}？）`)
  }
  const total = Number(response.headers.get('content-length') || 0)
  const chunks = []
  let received = 0
  let lastLog = 0
  for await (const chunk of response.body) {
    chunks.push(chunk)
    received += chunk.length
    const percent = total ? Math.floor((received / total) * 100) : 0
    if (percent >= lastLog + 20) {
      lastLog = percent
      log(`下载中 ${percent}%（${Math.round(received / 1048576)}MB）`)
    }
  }
  fs.writeFileSync(partial, Buffer.concat(chunks))
  fs.renameSync(partial, target)
  log(`下载完成：${target}（${Math.round(received / 1048576)}MB）`)
  return target
}

// ────────────────────────────────────────────────────────────── 自动探测

/** 在常见安装位置里找 Godot 可执行文件（每个目录最多下探 2 层，不递归全盘）。 */
function findGodotExe() {
  const fromEnv = process.env.GODOT_EXE
  if (fromEnv && fs.existsSync(fromEnv)) return fromEnv

  const roots = [
    process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Godot'),
    process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'Godot'),
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Programs', 'Godot'),
    'C:\\Godot', 'D:\\Godot', 'E:\\Godot',
  ].filter(Boolean)

  const hits = []
  for (const root of roots) {
    let entries = []
    try {
      entries = fs.readdirSync(root)
    } catch {
      continue
    }
    for (const entry of entries) {
      const full = path.join(root, entry)
      let stat = null
      try {
        stat = fs.statSync(full)
      } catch {
        continue
      }
      if (stat.isFile() && /^Godot.*\.exe$/i.test(entry)) hits.push(full)
      else if (stat.isDirectory()) {
        // 再下一层（有些安装包会多套一层版本目录）
        try {
          for (const inner of fs.readdirSync(full)) {
            if (/^Godot.*\.exe$/i.test(inner)) hits.push(path.join(full, inner))
          }
        } catch { /* 没权限就算了 */ }
      }
    }
  }
  return hits[0] ?? ''
}

/** 用哪个游戏目录：配置优先，其次插件旁边的 game/（仓库布局）。 */
function resolveProjectDir(configured) {
  const trimmed = String(configured || '').trim()
  if (trimmed && fs.existsSync(path.join(trimmed, 'project.godot'))) return trimmed
  if (fs.existsSync(path.join(BUNDLED_GAME_DIR, 'project.godot'))) return BUNDLED_GAME_DIR
  return trimmed || BUNDLED_GAME_DIR
}

// ────────────────────────────────────────────────────────────── 凭据读取

/** 项目的 class_name 全类表在不在。 */
function classCacheReady(projectDir) {
  return fs.existsSync(path.join(projectDir, '.godot', 'global_script_class_cache.cfg'))
}

/**
 * 第一次运行前必须让 Godot 生成 `.godot/`（全局类表 + 资源导入）。
 *
 * ⚠️ 这是**必须的**，不是优化：Godot 的 `class_name` 解析依赖
 * `.godot/global_script_class_cache.cfg`，而这个文件只在编辑器扫描时生成。
 * 直接 `godot --path <dir>` 跑一个刚 clone 下来、从没被编辑器打开过的工程，
 * 会得到满屏 `Parse Error: Identifier "BjTheme" not declared in the current scope`，
 * 然后游戏白屏 —— 看起来像"插件坏了"，其实是工程没被导入过。
 *
 * ⚠️ 而且要**跑两遍**：全新工程上第一次 `--import` 只扫资源，
 * 第二次才把 class_name 注册进类表（实测）。所以这里循环两次、每次都检查结果。
 */
function ensureImported(godotExe, projectDir) {
  if (classCacheReady(projectDir)) return true
  for (let pass = 1; pass <= 2; pass += 1) {
    log(`首次运行：正在生成 Godot 导入缓存（第 ${pass} 遍，约 6 秒）…`)
    try {
      const result = spawnSync(godotExe, ['--headless', '--import', '--path', projectDir], {
        cwd: projectDir,
        stdio: 'ignore',
        windowsHide: true,
        timeout: 180000,
      })
      if (result.error) {
        warn('导入失败：' + (result.error.message ?? String(result.error)))
        return false
      }
    } catch (err) {
      warn('导入失败：' + (err?.message ?? String(err)))
      return false
    }
    if (classCacheReady(projectDir)) break
  }
  const ok = classCacheReady(projectDir)
  if (ok) log('导入完成，继续启动。')
  else warn('两遍导入之后类表还是没生成，游戏可能会有解析错误。')
  return ok
}

/** 从 `$DSH_HOME/.credentials.yaml` 里直接抠出 key（credentials 服务不可用时的退路）。 */
function readKeyFromFile() {
  const home = process.env.DSH_HOME || path.join(os.homedir(), '.dsh')
  const file = path.join(home, '.credentials.yaml')
  let text = ''
  try {
    text = fs.readFileSync(file, 'utf8')
  } catch {
    return null
  }
  // 文件形如：
  //   version: 1
  //   refs:
  //     DEEPSEEK_API_KEY: sk-xxxxxxxx
  // 只需要这一行，不引入 yaml 依赖（插件只允许 node: 内置模块）。
  const match = text.match(new RegExp(`^\\s*${CREDENTIAL_KEY}\\s*:\\s*(\\S+)\\s*$`, 'm'))
  return match ? match[1] : null
}

/** 先走官方凭据服务，失败再读文件。返回 { key, source } 或 null。 */
async function resolveKey(ctx) {
  const service = ctx.get('credentials')
  if (service && typeof service.resolve === 'function') {
    try {
      // 品牌只是编译期装饰（dsh-brand 的 brandString 运行期是恒等函数），
      // 所以这里传纯字符串完全等价，插件无需依赖任何 @deepseek-ai 包。
      const hit = await service.resolve(CREDENTIAL_KEY)
      const value = hit && typeof hit.value === 'string' ? hit.value.trim() : ''
      if (value) return { key: value, source: 'credentials-service' }
    } catch (err) {
      warn('凭据服务读取失败，改用文件退路：' + (err?.message ?? String(err)))
    }
  }
  const fromFile = readKeyFromFile()
  if (fromFile) return { key: fromFile.trim(), source: 'credentials-file' }
  return null
}

// ────────────────────────────────────────────────────────────── 启动游戏

export function apply(ctx, config = {}) {
  // 配置里留空 = 自动探测。这样**手动装**（DSH 的 Plugins 页）也能直接用，
  // 不用先去改 cordis.patch.yml。
  const projectDir = resolveProjectDir(config.projectDir)
  const godotExe = String(config.godotExe || '').trim() || findGodotExe()
  const baseURL = String(config.baseURL || '').trim()
  const model = String(config.model || '').trim()

  let child = null
  let startedAt = 0
  let preparing = ''      // 非空 = 正在做耗时准备（下载），前端可以提示
  const launchLog = []

  function running() {
    return !!(child && child.exitCode === null && !child.killed)
  }

  function status() {
    return {
      ok: true,
      running: running(),
      pid: running() ? child.pid : null,
      startedAt: running() ? startedAt : 0,
      godotExe,
      projectDir,
      standalone: findStandaloneExe(),
      preparing: !!preparing,
      history: launchLog.slice(-5),
    }
  }

  /**
   * 决定"用什么跑游戏"。优先级：
   *   ① 本地已有的独立版 exe（install.ps1 下过 / 玩家自己放的）—— **不需要 Godot**
   *   ② 从本仓库的 GitHub Release 下载独立版（一次，约 90MB）—— **不需要 Godot**
   *   ③ 退回：有 Godot 就跑工程目录（作者/开发者用）
   * 这样"只有 DSH 的人"也能点一下就玩。
   */
  async function resolveRunner() {
    const local = findStandaloneExe()
    if (local) return { kind: 'exe', path: local }

    const url = String(config.downloadURL || '').trim() || releaseAssetUrl()
    if (url) {
      preparing = '下载独立版游戏'
      try {
        const downloaded = await downloadStandaloneExe(url)
        preparing = ''
        return { kind: 'exe', path: downloaded }
      } catch (err) {
        preparing = ''
        warn('独立版下载失败：' + (err?.message ?? String(err)))
        // 不直接失败：如果本机有 Godot，还能退回跑工程
      }
    }

    if (godotExe && fs.existsSync(godotExe) && fs.existsSync(path.join(projectDir, 'project.godot'))) {
      return { kind: 'project' }
    }
    return null
  }

  async function launch() {
    if (running()) return { ok: true, already: true, pid: child.pid }

    const runner = await resolveRunner()
    if (!runner) {
      return {
        ok: false,
        error: '既没有独立版游戏、本机也没有 Godot。'
          + `请确认仓库 Release 里有 ${STANDALONE_EXE_NAME}，`
          + '或装一个 Godot 4.7（https://godotengine.org/download）。',
      }
    }

    if (runner.kind === 'project' && !ensureImported(godotExe, projectDir)) {
      // 刚 clone 下来、从没被编辑器打开过的工程要先无窗口导入一次（见函数注释）
      return { ok: false, error: 'Godot 导入失败，无法启动。请用编辑器打开一次 game/ 目录，或看 DSH 日志。' }
    }

    const found = await resolveKey(ctx)
    if (!found) {
      return {
        ok: false,
        error: 'DSH 里没有配置 DeepSeek 凭据。请在 DSH 设置里填一次 API Key（之后本插件就都能用了）。',
      }
    }
    if (config.logCredentialLength === true) {
      log(`凭据来源=${found.source}，长度=${found.key.length}（内容不打印）`)
    }

    // 只传游戏真正需要的几个变量。**key 不进日志、不落盘。**
    const env = {
      ...process.env,
      [CREDENTIAL_KEY]: found.key,
    }
    if (baseURL) env.DEEPSEEK_BASE_URL = baseURL
    if (model) env.DEEPSEEK_MODEL = model

    // 排障开关：把游戏自己的 stdout 转发到 DSH 日志。
    // 游戏启动时会打印 "[blackjack] 已自动连接 DSH…" —— 用它一眼确认凭据送到了。
    const captureOutput = config.logGameOutput === true

    const argv = runner.kind === 'exe' ? [] : ['--path', projectDir.replace(/\\/g, '/')]
    const executable = runner.kind === 'exe' ? runner.path : godotExe

    try {
      child = spawn(executable, argv, {
        cwd: runner.kind === 'exe' ? path.dirname(runner.path) : projectDir,
        detached: true,      // 脱离 DSH：关掉 DSH 不会把游戏一起带走
        stdio: captureOutput ? ['ignore', 'pipe', 'pipe'] : 'ignore',
        windowsHide: false,  // ★ 关键：显式要求显示窗口
        env,
      })
    } catch (err) {
      return { ok: false, error: '启动失败：' + (err?.message ?? String(err)) }
    }

    if (captureOutput && child.stdout) {
      const forward = (stream, tag) => {
        let buffer = ''
        stream.setEncoding('utf8')
        stream.on('data', (chunk) => {
          buffer += chunk
          const lines = buffer.split(/\r?\n/)
          buffer = lines.pop() ?? ''
          for (const line of lines) if (line.trim()) log(`${tag} ${line}`)
        })
      }
      forward(child.stdout, '[game]')
      forward(child.stderr, '[game:err]')
    }

    child.on('error', (err) => warn('游戏进程出错：' + (err?.message ?? String(err))))
    child.on('exit', (code, signal) => log(`游戏已退出 code=${code} signal=${signal ?? '-'}`))
    child.unref()

    startedAt = Date.now()
    launchLog.push({ at: startedAt, pid: child.pid, source: found.source })
    log(`已启动鲸鱼娘 21 点（pid=${child.pid}，凭据来源=${found.source}）`)
    return { ok: true, pid: child.pid, startedAt, source: found.source }
  }

  // ──────────────────────────────────────── 浏览器 ↔ 宿主 的 HTTP 通道
  ctx.effect(() => {
    const ops = {
      launch,
      status,
      // 让前端能提示"DSH 里配没配 key"，但不泄露 key 本身
      credential: async () => {
        const found = await resolveKey(ctx)
        return { ok: true, configured: !!found, source: found?.source ?? null }
      },
    }

    const handler = async (req, res) => {
      const reply = (code, body) => {
        res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' })
        res.end(JSON.stringify(body))
      }
      // 同源 fetch 自带签名 cookie；这里再挡一层跨站请求
      if (String(req.headers['sec-fetch-site'] || '') === 'cross-site') {
        return reply(403, { ok: false, error: 'forbidden' })
      }
      const op = String(req.url || '')
        .replace(new RegExp(`^${API_PREFIX}/?`), '')
        .split('?')[0]
      const fn = ops[op]
      if (!fn) return reply(404, { ok: false, error: 'unknown op: ' + op })
      try {
        return reply(200, await fn())
      } catch (err) {
        return reply(500, { ok: false, error: String(err?.message ?? err) })
      }
    }

    const dispose = ctx.webServer.register({ kind: 'prefix', path: API_PREFIX, handler })
    log(`已注册路由 ${API_PREFIX}/{launch,status,credential}`)
    return () => {
      try {
        dispose()
      } catch {
        // 宿主退出时的清理失败无所谓
      }
    }
  }, `${PLUGIN_ID}: api`)

  log('已加载。点界面右下角的「🃏 黑杰克」即可开始。')

  if (config.autoLaunch === true) {
    launch().catch((err) => warn('自动启动失败：' + (err?.message ?? String(err))))
  }
}
