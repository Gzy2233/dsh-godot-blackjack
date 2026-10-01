// 插件 Host 半身的**离线冒烟测试**（不装进 DSH，不碰任何用户配置）。
//
// 它用一个假的 `ctx` 调 `apply()`，把真实链路整条跑一遍：
//   假的凭据服务 → 插件读 key → spawn 真实 Godot → 游戏打印"已自动连接 DSH"
//   → 插件转发的日志里出现这一行 → 假的 webServer 路由能正确应答
//
// 用法（在仓库根目录）：
//   node plugin/test/host-smoke.mjs
//
// 退出码 0 = 通过。
import path from 'node:path'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { apply } from '../lib/index.js'

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, '..', '..')
const gameDir = path.join(repoRoot, 'game')

// 允许用环境变量覆盖，方便在别的机器上跑
const godotExe = process.env.SMOKE_GODOT || ''
const standaloneExe = path.join(repoRoot, 'dist', 'BlackjackWhale.exe')
const hasStandalone = fs.existsSync(standaloneExe)
const FAKE_KEY = 'sk-smoke-test-key-not-real'

let failures = 0
function check(name, ok, extra = '') {
  console.log(`${ok ? '  [OK]' : '  [X] '} ${name}${extra ? '  ' + extra : ''}`)
  if (!ok) failures += 1
}

// ── 假的 ctx：只提供插件真正会用到的东西 ─────────────────────────────
let registered = null
const lines = []
const ctx = {
  get: (name) => (name === 'credentials'
    ? { resolve: async () => ({ value: FAKE_KEY, source: 'smoke' }) }
    : undefined),
  webServer: {
    register: (route) => {
      registered = route
      return () => { registered = null }
    },
  },
  effect: (fn) => { fn(); return () => {} },
}
// 让插件内部的 log 走我们这里，方便断言
const realLog = console.log
console.log = (...args) => { lines.push(args.join(' ')); realLog(...args) }

console.log('\n=== 插件 Host 冒烟测试 ===\n')
console.log(hasStandalone
  ? '  模式：独立版 exe（不依赖 Godot）\n'
  : '  模式：Godot 工程（dist/BlackjackWhale.exe 不存在）\n')

// 刻意**不传** godotExe / projectDir：
// 独立版存在时必须自己找到 dist/BlackjackWhale.exe（这才是"只有 DSH 的人"的路径）
apply(ctx, {
  godotExe,
  baseURL: 'https://api.deepseek.com',
  model: 'deepseek-chat',
  autoLaunch: false,
  logGameOutput: true,   // 关键：转发游戏 stdout，才能看到"已自动连接 DSH"
})

check('注册了 webServer 路由', !!registered && registered.path === '/dsh-blackjack-api',
  registered ? registered.path : '(没注册)')

// ── 调 /launch ───────────────────────────────────────────────────────
function fakeRes() {
  return {
    code: 0, body: '',
    writeHead(code) { this.code = code; return this },
    end(body) { this.body = body ?? ''; return this },
  }
}

const res = fakeRes()
await registered.handler({ url: '/dsh-blackjack-api/launch', headers: {} }, res)
let payload = {}
try { payload = JSON.parse(res.body) } catch { /* 保持空对象 */ }

check('HTTP 200', res.code === 200, `code=${res.code}`)
check('launch 返回 ok', payload.ok === true, JSON.stringify(payload).slice(0, 200))
check('拿到了 pid', Number.isInteger(payload.pid) && payload.pid > 0, `pid=${payload.pid}`)
check('凭据来源是 credentials 服务', payload.source === 'credentials-service', String(payload.source))

// ── 等游戏启动并打印那一行 ──────────────────────────────────────────
const deadline = Date.now() + 20000
let sawAutoConnect = false
while (Date.now() < deadline && !sawAutoConnect) {
  await new Promise((r) => setTimeout(r, 400))
  if (lines.some((l) => l.includes('已自动连接 DSH'))) sawAutoConnect = true
}
const gameLine = lines.find((l) => l.includes('已自动连接 DSH'))
check('游戏确认「已自动连接 DSH」', sawAutoConnect, gameLine ? gameLine.trim() : '(20 秒内没看到)')

// ── /status 与跨站拦截 ──────────────────────────────────────────────
const res2 = fakeRes()
await registered.handler({ url: '/dsh-blackjack-api/status', headers: {} }, res2)
const status = JSON.parse(res2.body)
check('status 说游戏在跑', status.running === true, `pid=${status.pid}`)

const res3 = fakeRes()
await registered.handler({ url: '/dsh-blackjack-api/status', headers: { 'sec-fetch-site': 'cross-site' } }, res3)
check('跨站请求被拒（403）', res3.code === 403, `code=${res3.code}`)

const res4 = fakeRes()
await registered.handler({ url: '/dsh-blackjack-api/nope', headers: {} }, res4)
check('未知 op 返回 404', res4.code === 404, `code=${res4.code}`)

const res5 = fakeRes()
await registered.handler({ url: '/dsh-blackjack-api/credential', headers: {} }, res5)
const cred = JSON.parse(res5.body)
check('credential 只说配没配，不泄露 key',
  cred.configured === true && !res5.body.includes(FAKE_KEY), res5.body)

console.log(`\n=== ${failures === 0 ? '全部通过 ✓' : failures + ' 项失败 ✗'} ===\n`)
console.log = realLog
process.exit(failures === 0 ? 0 : 1)
