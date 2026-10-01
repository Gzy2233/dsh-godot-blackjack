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

      // 按钮上的小图标：把 PNG 以 base64 **内嵌**进来。
      // 客户端 bundle 跑在浏览器里，读不到本地文件；内嵌就完全不需要额外请求，
      // 也不怕宿主路由还没热加载好。
      var ICON = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAABIFBMVEVVYWZqmdkhW1ZcdJibo5rc4t1kXSnXsEyOq9AqNCre06k7Y6OMdykZMVL+0mEVLYO0z+yalGqahCn+xTlwhXSCfGG5wLZPjqspTTLLvpJGb8c+gZE6gn8FGm0OGRP0+PUAAAAaakUHGFMOJnARJlXm7OrttS8tRnISJy91qO+FufrY5esqR5DN1tYDCgcbNYj2xU7VpjAIFTMVVzYACVFtl9G4lCsQNiqNxf6puswnN1AjOXIADWV8svzGnCs5WI4iPYxSaZNGaa8QIxpUd60YZTpbh9G2xc0VSTKriyjnukvxyWYtRVWUp7MbcUbkrSoZM3Cut7Q0VqgBDDRzho/EysmIm7IzVW51krFGWY2MpctRecjb4dlria0aWVBXhbAOirZ9AAAAYHRSTlP//////////////////////////////////////////wD///////////////////////////////////////////////////////////////////////////////////+iPcs2AAAJBklEQVR42o2Yh3qqSheGB1FjSU7aPuUvyHYGpAioKPbeNRp7bDHe/12cGYotZmevJ/EBZF6/VWbNAPh5aiFiWsgPVgZlgNA3djYUXFCwgU1WlrNZ+WEVCv0+C1xi8s2tIIrioClLWaD9PgpccIQt0szh2kCSV78BCp2BDldpqeIcakJ2F/otO4IOl5rZ2lGERtH4RBT9eb8ofks6BWkguz9xRqsJOqdUY9iqVUUQxG9BznlDKp3crM8ExJzYvVIRRO1LEjhxbJBtHm7kGAYZCuTGCELosGIV4UtN56ClDcoXEAORwsEzTQQVzGtfgU5Opb1dAwVThvV3YdPldUlnIJHOk89jbOCJX0f/vgeFNJNjIRhbzycUUq6CLq+YHDz4ONwmmTKtw2sk8AXnzMxTykDOIRK+B13jWKZkjcN399x3IOHwq59ibLTl+uHLmPhrUF65xkEx8rkNxpRjmNCvQXXmqhiJUpxoH8Kk/wKkCdWrIERl65eh/yTpTFEl1r5kIESkTNGnJDL6lyBtWW1Th7spLEJBsc/OOiUGv1ZUj0nytIjMkKKSJE2pNqN89tSaNgVB+wKkDaaKLFeLseA9AUml7HZaL17J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'

      var btn = document.createElement('button')
      btn.style.cssText = [
        'display:flex',
        'align-items:center',
        'gap:8px',
        'font:600 13px/1 ui-sans-serif,system-ui',
        'padding:8px 14px 8px 8px',
        'cursor:pointer',
        'color:#0b1a3a',
        'background:linear-gradient(#f7dfa0,#e8bd52)',
        'border:1px solid #b8912f',
        'border-radius:12px',
        'box-shadow:0 3px 12px rgba(0,0,0,.35)',
        'transition:transform .08s ease, filter .15s ease',
      ].join(';')

      var icon = document.createElement('img')
      icon.alt = ''
      icon.src = ICON
      icon.style.cssText = 'width:26px;height:26px;border-radius:7px;display:block;flex:0 0 auto;box-shadow:0 1px 3px rgba(0,0,0,.3)'
      btn.appendChild(icon)

      var label = document.createElement('span')
      label.textContent = '鲸鱼娘 21 点'
      btn.appendChild(label)

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
