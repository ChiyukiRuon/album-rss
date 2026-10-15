// Exercise the actual Vite application in a disposable Edge profile. Never log credentials.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { readFile, mkdir, mkdtemp, writeFile } from 'node:fs/promises'
import { resolve, join } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'

const base = 'http://localhost:8880'
const web = 'http://localhost:5173'
const writeMode = process.argv.includes('--allow-write')
const config = await readFile(
  'D:/CodeProject/Develop Environment/miniflux/docker-compose.yaml',
  'utf8',
)
function setting(name) {
  const value = config.match(new RegExp(`^\\s+${name}:\\s*(.*?)\\s*$`, 'm'))?.[1]
  assert(value, `Missing configuration: ${name}`)
  return value.startsWith('"') ? JSON.parse(value) : value.replace(/^'|'$/g, '')
}
const basic = `Basic ${Buffer.from(`${setting('ADMIN_USERNAME')}:${setting('ADMIN_PASSWORD')}`).toString('base64')}`
async function api(path, init = {}, token) {
  const response = await fetch(base + path, {
    ...init,
    headers: {
      ...(token ? { 'X-Auth-Token': token } : { Authorization: basic }),
      'Content-Type': 'application/json',
      ...init.headers,
    },
    signal: AbortSignal.timeout(30_000),
  })
  assert(response.ok, `Local API returned HTTP ${response.status}`)
  return response.status === 204 ? null : response.json()
}
const key = await api('/v1/api-keys', {
  method: 'POST',
  body: JSON.stringify({ description: `album-web-check-${Date.now()}` }),
})
let browser
let ws
let original
let targetId
const report = { mode: writeMode ? 'single-entry-roundtrip' : 'read-only', checks: [] }
try {
  await mkdir('.local-check', { recursive: true })
  const profile = await mkdtemp(resolve('.local-check/web-api-'))
  browser = spawn(
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    [
      '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--no-default-browser-check',
      '--no-proxy-server',
      '--disable-extensions',
      '--disable-background-networking',
      '--remote-debugging-port=0',
      `--user-data-dir=${profile}`,
      'about:blank',
    ],
    { stdio: 'ignore', windowsHide: true },
  )
  let launchError
  browser.on('error', (error) => {
    launchError = error
  })
  let port
  for (let i = 0; i < 100; i++) {
    if (launchError) throw new Error(`Browser launch failed: ${launchError.code}`)
    try {
      port = (await readFile(join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]
      break
    } catch {
      await delay(100)
    }
  }
  assert(port, 'Browser did not start its debugging endpoint')
  const pages = await (await fetch(`http://localhost:${port}/json/list`)).json()
  ws = new WebSocket(pages.find((page) => page.type === 'page').webSocketDebuggerUrl)
  await new Promise((accept, reject) => {
    ws.addEventListener('open', accept, { once: true })
    ws.addEventListener('error', reject, { once: true })
  })
  const pending = new Map()
  let nextId = 0
  ws.addEventListener('message', ({ data }) => {
    const result = JSON.parse(data)
    if (!result.id) return
    const task = pending.get(result.id)
    pending.delete(result.id)
    if (result.error) task?.reject(new Error('Browser protocol error'))
    else task?.accept(result.result)
  })
  async function command(method, params = {}) {
    const id = ++nextId
    return new Promise((accept, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id)
        reject(new Error(`Browser command timed out: ${method}`))
      }, 60_000)
      pending.set(id, {
        accept: (value) => {
          clearTimeout(timer)
          accept(value)
        },
        reject,
      })
      ws.send(JSON.stringify({ id, method, params }))
    })
  }
  async function evaluate(expression) {
    expression = expression.replaceAll(
      "import('/src/prototype/store.ts')",
      "import(performance.getEntriesByType('resource').filter(r => new URL(r.name).pathname === '/src/prototype/store.ts').at(-1)?.name ?? '/src/prototype/store.ts')",
    )
    const result = await command('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
    })
    if (result.exceptionDetails)
      throw new Error(
        `Browser assertion failed: ${result.exceptionDetails.exception?.description?.split('\n')[0] ?? 'unknown'}`,
      )
    return result.result.value
  }
  async function waitFor(expression) {
    for (let i = 0; i < 150; i++) {
      if (await evaluate(expression)) return
      await delay(200)
    }
    throw new Error('Browser condition timed out')
  }
  const apiRequests = () =>
    evaluate(
      `performance.getEntriesByType('resource').filter(r => r.name.startsWith(${JSON.stringify(base + '/v1/')})).length`,
    )
  const fill = (label, value, root = 'document') => `(() => {
    const input = [...${root}.querySelectorAll('input')].find(i => [...i.labels].some(l => l.textContent === ${JSON.stringify(label)}));
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, ${JSON.stringify(value)});
    input.dispatchEvent(new Event('input', { bubbles: true }));
  })()`
  const scope = (key) => `(async () => {
    const { appStore } = await import('/src/prototype/store.ts');
    const scope = appStore.get().scopes[${JSON.stringify(key)}];
    return scope ? { ids: scope.ids.length, done: scope.done } : null;
  })()`
  await command('Page.navigate', { url: web + '/connect' })
  await waitFor(`!!document.querySelector('form')`)
  await evaluate(`(async () => {
    const { actions } = await import('/src/prototype/store.ts');
    actions.updateSettings({ autoRead: false, simulateLatency: false, defaultStatus: 'unread' });
  })()`)
  await evaluate(fill('服务地址', base))
  await evaluate(fill('API 密钥', key.token))
  await evaluate(fill('服务公开地址（可选）', setting('BASE_URL')))
  await evaluate(`document.querySelector('input[type=checkbox]').click()`)
  await evaluate(`document.querySelector('form').requestSubmit()`)
  await waitFor(`location.pathname === '/' && !!document.querySelector('nav')`)
  const summary = await evaluate(`(async () => {
    const { appStore } = await import('/src/prototype/store.ts');
    const s = appStore.get();
    return { feeds: s.feeds.length, entries: s.order.length,
      images: Object.values(s.entries).reduce((n, e) => n + e.images.length, 0),
      demoImages: Object.values(s.entries).some(e => e.images.some(i => i.url.startsWith('demo:'))),
      counts: s.unread !== null,
      tokenSaved: !!JSON.parse(localStorage.getItem('album-rss:endpoints'))[0]?.token };
  })()`)
  summary.connectRequests = await apiRequests()
  assert(summary.feeds > 0 && summary.entries > 0 && summary.entries <= 100 && summary.images > 0)
  assert.equal(summary.demoImages, false)
  assert.equal(summary.tokenSaved, true)
  assert.equal(summary.counts, true)
  // /v1/me、/v1/feeds、/v1/categories、/v1/feeds/counters 与第一页文章
  assert(summary.connectRequests <= 5, `Connect made ${summary.connectRequests} API requests`)
  report.summary = summary
  report.checks.push(
    'form connect reads subscriptions, counters and one page only, real image extraction, remembered token',
  )

  await evaluate(`(async () => {
    const { parseEntry } = await import('/src/lib/parseEntry.ts');
    const e = parseEntry({ id: 'fixture', feedId: '1', title: '', author: '', url: 'https://example.com/post',
      publishedAt: 0, tags: [], read: false, starred: false,
      content: '<script>window.__articleExecuted=true</script><p>Hello<br>world</p><img src="javascript:alert(1)"><img src="/pixel" width="1" height="1"><picture><source srcset="/small.jpg 100w, /large.jpg 1000w"><img alt="Art"></picture><img data-src="/lazy.jpg"><img src="/large.jpg"><img>',
      enclosures: [{ url: '/attached.png', mimeType: 'image/png' }, { url: '/movie.mp4', mimeType: 'video/mp4' }],
    }, 'http://localhost:8880');
    if (e.images.length !== 3 || !e.images[0].url.endsWith('/large.jpg') || e.paragraphs.join(' ') !== 'Hello world' || window.__articleExecuted) throw new Error('Image parsing fixture failed');
  })()`)
  report.checks.push(
    'safe HTML parsing, picture/srcset, lazy images, attachment deduplication, tracker filtering',
  )

  // “全部”列表：先读第一页，滚到底再读下一页
  await evaluate(
    `document.querySelectorAll('[role=radiogroup][aria-label="显示范围"] [role=radio]')[1].click()`,
  )
  const allKey = JSON.stringify(['all', null, null])
  await waitFor(`(async () => (await ${scope(allKey)})?.ids > 0)()`)
  const firstPage = await evaluate(scope(allKey))
  let paged = firstPage
  // 卡片测量完尺寸才会放进瀑布流；无法访问的图片要等到超时，这里留足时间
  const deadline = Date.now() + 120_000
  while (Date.now() < deadline && !paged.done && paged.ids === firstPage.ids) {
    await evaluate(`window.scrollTo(0, document.documentElement.scrollHeight)`)
    await delay(250)
    paged = await evaluate(scope(allKey))
  }
  assert(firstPage.done || paged.ids > firstPage.ids, 'Scrolling did not load the next page')
  report.paging = { firstPage: firstPage.ids, afterScroll: paged.ids }
  report.checks.push('older articles load page by page when the list reaches the end')

  await command('Page.reload')
  await waitFor(`!!document.querySelector('nav') && location.pathname === '/'`)
  await waitFor(`document.querySelectorAll('article[data-card-key]').length > 0`)
  const screenshot = await command('Page.captureScreenshot', { format: 'png' })
  await writeFile('.local-check/web-api.png', Buffer.from(screenshot.data, 'base64'))
  report.checks.push(
    'reload restores the remembered endpoint and refetches the first page, wall renders',
  )
  await evaluate(`document.querySelector('a[href="/feeds"]').click()`)
  await waitFor(`location.pathname === '/feeds'`)
  await evaluate(`document.querySelector('a[href^="/feeds/"]').click()`)
  await waitFor(`location.pathname.startsWith('/feeds/') && !!document.querySelector('h1')`)
  await waitFor(`document.querySelectorAll('article[data-card-key]').length > 0`)
  await evaluate(`document.querySelector('article[data-card-key] a').click()`)
  await waitFor(`!!document.querySelector('[data-viewer-root]')`)
  await evaluate(`history.back()`)
  await waitFor(`!document.querySelector('[data-viewer-root]')`)
  report.checks.push('subscription page reads its own list, album viewer opens')

  // 通过左下角菜单的弹窗添加第二个端点，再切回第一个：访问过的端点直接用缓存
  await evaluate(`document.querySelector('button[aria-haspopup="menu"]').click()`)
  await waitFor(`!!document.querySelector('[role=menu]')`)
  await evaluate(
    `[...document.querySelectorAll('[role=menuitem]')].find(b => b.textContent.includes('添加 API 端点')).click()`,
  )
  await waitFor(`!!document.querySelector('dialog[open] form')`)
  const dialog = `document.querySelector('dialog[open]')`
  await evaluate(fill('服务地址', base, dialog))
  await evaluate(fill('API 密钥', key.token, dialog))
  await evaluate(fill('端点名称（可选）', 'check-second', dialog))
  await evaluate(`${dialog}.querySelector('form').requestSubmit()`)
  await waitFor(`(async () => {
    const { appStore } = await import('/src/prototype/store.ts');
    return !document.querySelector('dialog[open]') && appStore.get().endpoint?.name === 'check-second';
  })()`)
  const beforeSwitch = await apiRequests()
  await evaluate(`document.querySelector('button[aria-haspopup="menu"]').click()`)
  await waitFor(`!!document.querySelector('[role=menu]')`)
  await evaluate(`document.querySelector('[role=menuitemradio][aria-checked=false]').click()`)
  await waitFor(`(async () => {
    const { appStore } = await import('/src/prototype/store.ts');
    return appStore.get().endpoint?.name !== 'check-second' && !document.querySelector('[role=menu]');
  })()`)
  report.switchRequests = (await apiRequests()) - beforeSwitch
  assert.equal(report.switchRequests, 0, 'Switching back to a cached endpoint made API requests')
  report.checks.push('add endpoint in the dialog, switch back from cache without API requests')

  if (writeMode) {
    const { entries } = await api('/v1/entries?limit=1&order=id&direction=asc', {}, key.token)
    original = entries[0]
    assert(original)
    targetId = String(original.id)
    const desiredRead = original.status !== 'read'
    const desiredStarred = !original.starred
    await evaluate(`(async () => {
      const { actions } = await import('/src/prototype/store.ts');
      actions.setRead([${JSON.stringify(targetId)}], ${desiredRead});
      actions.setStarred(${JSON.stringify(targetId)}, ${desiredStarred});
    })()`)
    let saved = false
    for (let i = 0; i < 60; i++) {
      const entry = await api(`/v1/entries/${targetId}`, {}, key.token)
      if ((entry.status === 'read') === desiredRead && entry.starred === desiredStarred) {
        saved = true
        break
      }
      await delay(200)
    }
    assert(saved, 'Read and starred state were not saved')
    await evaluate(`(async () => {
      const { actions } = await import('/src/prototype/store.ts');
      actions.setRead([${JSON.stringify(targetId)}], ${original.status === 'read'});
      actions.setStarred(${JSON.stringify(targetId)}, ${original.starred});
      await actions.sync({ explicit: true });
    })()`)
    const restored = await api(`/v1/entries/${targetId}`, {}, key.token)
    assert.equal(restored.status, original.status)
    assert.equal(restored.starred, original.starred)
    report.checks.push('single-entry read/starred writes verified remotely and restored')
    original = undefined
  }
  await evaluate(`(async () => {
    const { actions, appStore } = await import('/src/prototype/store.ts');
    for (const endpoint of appStore.get().endpoints) await actions.removeEndpoint(endpoint.id);
    if (appStore.get().endpoint || JSON.parse(localStorage.getItem('album-rss:endpoints')).length || localStorage.getItem('album-rss:active')) throw new Error('Endpoint cleanup failed');
    actions.enterDemo();
    if (!Object.values(appStore.get().entries).some(e => e.images.some(i => i.url.startsWith('demo:')))) throw new Error('Demo isolation failed');
    actions.exitDemo();
  })()`)
  report.checks.push('endpoint removal clears saved credentials, demo isolation')
  console.log(JSON.stringify(report, null, 2))
} finally {
  try {
    if (original) {
      await api(
        '/v1/entries',
        {
          method: 'PUT',
          body: JSON.stringify({ entry_ids: [original.id], status: original.status }),
        },
        key.token,
      )
      const current = await api(`/v1/entries/${targetId}`, {}, key.token)
      if (current.starred !== original.starred)
        await api(`/v1/entries/${targetId}/bookmark`, { method: 'PUT' }, key.token)
      const restored = await api(`/v1/entries/${targetId}`, {}, key.token)
      assert(
        restored.status === original.status && restored.starred === original.starred,
        'Manual state restoration required',
      )
    }
  } finally {
    ws?.close()
    if (browser?.pid) {
      const killer = spawn('taskkill', ['/pid', String(browser.pid), '/t', '/f'], {
        stdio: 'ignore',
        windowsHide: true,
      })
      await new Promise((accept) => killer.on('exit', accept))
    }
    await api(`/v1/api-keys/${key.id}`, { method: 'DELETE' })
  }
}
