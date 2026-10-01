// dsh-godot-blackjack —— Client 半身（跑在浏览器里）
//
// ⚠️ 这个文件**必须手写**成 `window.__ModuleLoader__.load({id, factory})` 的形状：
//    DSH 的客户端 bundle 没有构建工具链帮你生成（见 dsh-client-modules 的 README）。
//
// ⚠️ 而且这里**故意一个 require 都不写**：
//    浏览器侧的 require 只认种子表（React / Cordis / 少量 UI 库），
//    require 一个不在表里的词 = 工厂直接抛错 = 整个客户端插件永远不可见。
//    只用原生 DOM + Shadow DOM，就完全没有这个风险，也不怕 DSH 的 CSS 影响。
window.__ModuleLoader__.load({
  id: 'dsh-godot-blackjack',
  factory: function () {
    var module = { exports: {} }

    var API = '/dsh-blackjack-api'
    var BTN_ID = 'dsh-godot-blackjack-launcher'

    function post(op) {
      // 同源请求，DSH 的签名 cookie 会自动带上，因此无需额外鉴权
      return fetch(API + '/' + op, { method: 'POST', credentials: 'same-origin' })
        .then(function (res) { return res.json() })
    }

    function mount() {
      if (document.getElementById(BTN_ID)) return
      if (!document.body) return

      var host = document.createElement('div')
      host.id = BTN_ID
      host.style.cssText = 'position:fixed;right:18px;bottom:18px;z-index:2147483000'
      var root = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host

      var wrap = document.createElement('div')
      wrap.style.cssText = 'display:flex;flex-direction:column;align-items:flex-end;gap:6px;' +
        'font:13px/1.4 ui-sans-serif,system-ui,"Segoe UI",sans-serif'

      var tip = document.createElement('div')
      tip.style.cssText = 'max-width:260px;padding:6px 10px;border-radius:8px;display:none;' +
        'background:rgba(12,18,32,.92);color:#cfd8ea;box-shadow:0 4px 16px rgba(0,0,0,.4);' +
        'white-space:pre-wrap;word-break:break-all'

      var btn = document.createElement('button')
      // 牌面画的是鲸鱼，所以这里也用它
      btn.textContent = '\uD83D\uDC0B 鲸鱼娘 21 点'
      btn.style.cssText = [
        'font:600 13px/1 ui-sans-serif,system-ui',
        'padding:10px 16px',
        'cursor:pointer',
        'color:#0b1a3a',
        'background:linear-gradient(#f7dfa0,#e8bd52)',
        'border:1px solid #b8912f',
        'border-radius:12px',
        'box-shadow:0 3px 12px rgba(0,0,0,.35)',
        'transition:transform .08s ease, filter .15s ease',
      ].join(';')

      btn.onmouseenter = function () { btn.style.filter = 'brightness(1.06)' }
      btn.onmouseleave = function () { btn.style.filter = '' }
      btn.onmousedown = function () { btn.style.transform = 'translateY(1px)' }
      btn.onmouseup = function () { btn.style.transform = '' }

      function say(text, ms) {
        tip.textContent = text
        tip.style.display = 'block'
        if (ms) setTimeout(function () { tip.style.display = 'none' }, ms)
      }

      btn.onclick = function () {
        btn.disabled = true
        btn.style.opacity = '0.6'
        say('正在启动游戏…')
        post('launch')
          .then(function (data) {
            if (data && data.ok) {
              say(data.already ? ('游戏已经在跑了（pid ' + data.pid + '）') : ('已启动，去玩吧（pid ' + data.pid + '）'), 4000)
            } else {
              say('启动失败：' + ((data && data.error) || '未知错误'), 12000)
            }
          })
          .catch(function (err) {
            say('请求失败：' + err + '\n（如果刚装完插件，请重启一次 DSH）', 9000)
          })
          .then(function () {
            setTimeout(function () {
              btn.disabled = false
              btn.style.opacity = ''
            }, 600)
          })
      }

      // 首次点击要下载独立版游戏（约 90MB），期间轮询状态给个进度提示 ——
      // 不然按钮点下去几十秒没反应，玩家会以为卡死了。
      var polling = null
      btn.addEventListener('click', function () {
        if (polling) return
        polling = setInterval(function () {
          fetch(API + '/status', { method: 'POST', credentials: 'same-origin' })
            .then(function (r) { return r.json() })
            .then(function (d) {
              if (d && d.preparing) {
                say('首次启动：正在下载独立版游戏…\n（约 90MB，只下一次，进度看 DSH 日志）')
              } else {
                clearInterval(polling)
                polling = null
              }
            })
            .catch(function () { clearInterval(polling); polling = null })
        }, 3000)
      })

      wrap.appendChild(tip)
      wrap.appendChild(btn)
      root.appendChild(wrap)
      document.body.appendChild(host)

      // 首次挂载时报一次"DSH 里配没配 key"，让玩家提前知道能不能直接玩
      post('credential')
        .then(function (data) {
          if (data && data.ok && !data.configured) {
            say('提示：DSH 里还没有 DeepSeek 凭据，先去「设置」填一次 Key。', 8000)
          }
        })
        .catch(function () { /* 路由还没热加载好，忽略 */ })
    }

    // apply 是插件生命周期的入口（此时 DOM 通常已就绪，但不保证）
    module.exports.apply = function apply() {
      if (document.body) mount()
      else document.addEventListener('DOMContentLoaded', mount, { once: true })
    }

    return module.exports
  },
})
