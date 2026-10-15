/* 页面状态与服务操作；演示分支保留独立的模拟数据。 */
import { showToast, toastStore, type ToastAction } from '../components/ui/toast'
import { createStore } from '../lib/createStore'
import { configureLatency, openImage } from '../lib/imageSource'
import { createDemoData, demoBlocksDownload } from './demoData'
import { ApiError, createProvider, loginGoogleReader, normalizeServer } from '@album-rss/providers'
import { parseEntry } from '../lib/parseEntry'
import type {
  DownloadState,
  Entry,
  Feed,
  Folder,
  ImageAsset,
  ServiceKind,
  Session,
  Settings,
} from './types'

export interface SyncState {
  status: 'idle' | 'syncing'
  lastSyncedAt: number
  /** 后台同步拿到、还没放进列表的新文章；点“有新图集”后才出现，列表不会自己跳动 */
  pendingIds: string[]
  error?: string
}

export interface AppState {
  session: Session | null
  endpoints: Session[]
  loaded: boolean
  settings: Settings
  folders: Folder[]
  feeds: Feed[]
  entries: Record<string, Entry>
  /** 全部文章 ID，新的在前 */
  order: string[]
  sync: SyncState
  /** 列表快照版本：显式刷新或应用新内容时递增，各列表据此重新取数 */
  listVersion: number
  downloads: Record<string, DownloadState>
  refreshingFeeds: Record<string, boolean>
  /** 当前查看器的翻页顺序，取自打开它的那个列表 */
  viewerSequence: string[] | null
}

const SETTINGS_KEY = 'album-rss:settings'
const SESSION_KEY = 'album-rss:session'
const ENDPOINTS_KEY = 'album-rss:endpoints'

const DEFAULT_SETTINGS: Settings = {
  autoRead: true,
  downloadRead: true,
  showImageless: false,
  defaultStatus: 'unread',
  density: 'standard',
  theme: 'system',
  simulateLatency: true,
}

function readJson<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key)
    return raw ? (JSON.parse(raw) as T) : null
  } catch {
    return null
  }
}

let arrivals: Entry[] = []

function newEndpointId() {
  return (
    globalThis.crypto?.randomUUID?.() ??
    `endpoint-${Date.now()}-${Math.random().toString(36).slice(2)}`
  )
}

function initialState(): AppState {
  const now = Date.now()
  const saved = readJson<Session>(SESSION_KEY)
  const session =
    saved?.kind === 'demo' || (saved?.kind === 'connected' && saved.token && saved.remember)
      ? saved
      : null
  const endpoints = readJson<Session[]>(ENDPOINTS_KEY) ?? []
  if (session?.kind === 'connected') {
    session.id ??= newEndpointId()
    if (!endpoints.some((endpoint) => endpoint.id === session.id)) endpoints.push(session)
    localStorage.setItem(SESSION_KEY, JSON.stringify(session))
    persistEndpoints(endpoints)
  }
  const demo = createDemoData(now)
  arrivals = demo.arrivals
  const entries: Record<string, Entry> = {}
  for (const entry of demo.entries) entries[entry.id] = entry
  return {
    session,
    endpoints,
    loaded: session?.kind !== 'connected',
    settings: { ...DEFAULT_SETTINGS, ...readJson<Partial<Settings>>(SETTINGS_KEY) },
    folders: session?.kind === 'connected' ? [] : demo.folders,
    feeds: session?.kind === 'connected' ? [] : demo.feeds,
    entries: session?.kind === 'connected' ? {} : entries,
    order: session?.kind === 'connected' ? [] : demo.entries.map((e) => e.id),
    sync: { status: 'idle', lastSyncedAt: now - 4 * 60_000, pendingIds: [] },
    listVersion: 0,
    downloads: {},
    refreshingFeeds: {},
    viewerSequence: null,
  }
}

export const appStore = createStore<AppState>(initialState())
export const useApp = appStore.use

configureLatency(() => appStore.get().settings.simulateLatency)

const delay = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms))

function patchEntries(ids: readonly string[], patch: (entry: Entry) => Entry) {
  appStore.set((state) => {
    let changed = false
    const entries = { ...state.entries }
    for (const id of ids) {
      const entry = entries[id]
      if (!entry) continue
      const next = patch(entry)
      if (next !== entry) {
        entries[id] = next
        changed = true
      }
    }
    return changed ? { ...state, entries } : state
  })
}

let generation = 0
let connectionAttempt = 0
let mutationTail = Promise.resolve()
let revision = 0
const changes = new Map<string, { revision: number; value: boolean }>()
const confirmed = new Map<string, boolean>()
const lastChanges = new Map<string, number>()

function persistEndpoints(endpoints: Session[]) {
  localStorage.setItem(
    ENDPOINTS_KEY,
    JSON.stringify(endpoints.filter((endpoint) => endpoint.remember)),
  )
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '请求失败，请稍后重试'
}

function providerFor(session: Session) {
  return createProvider({
    service: session.service,
    server: session.server,
    token: session.token ?? '',
  })
}

function mutate(ids: readonly string[], field: 'read' | 'starred', value: boolean) {
  const session = appStore.get().session
  if (!session || session.kind === 'demo') {
    patchEntries(ids, (entry) => (entry[field] === value ? entry : { ...entry, [field]: value }))
    return
  }
  const epoch = generation
  const serial = ++revision
  ids.forEach((id) => {
    const key = `${id}:${field}`
    if (!changes.has(key)) confirmed.set(key, appStore.get().entries[id]?.[field] ?? false)
    changes.set(key, { revision: serial, value })
    lastChanges.set(key, serial)
  })
  patchEntries(ids, (entry) => ({ ...entry, [field]: value }))
  mutationTail = mutationTail.then(async () => {
    if (epoch !== generation) return
    try {
      const provider = providerFor(session)
      if (field === 'read') await provider.setRead(ids, value)
      else for (const id of ids) await provider.setStarred(id, value)
      if (epoch === generation) ids.forEach((id) => confirmed.set(`${id}:${field}`, value))
    } catch (error) {
      if (epoch !== generation) return
      patchEntries(ids, (entry) => {
        const old = confirmed.get(`${entry.id}:${field}`)
        return changes.get(`${entry.id}:${field}`)?.revision === serial && old !== undefined
          ? { ...entry, [field]: old }
          : entry
      })
      appStore.set((state) => ({ ...state, listVersion: state.listVersion + 1 }))
      showToast({
        message: '状态未能保存到服务器',
        detail: errorMessage(error),
        tone: 'warning',
        action: { label: '重试', run: () => mutate(ids, field, value) },
      })
    } finally {
      if (epoch === generation)
        ids.forEach((id) => {
          if (changes.get(`${id}:${field}`)?.revision === serial) {
            changes.delete(`${id}:${field}`)
            confirmed.delete(`${id}:${field}`)
          }
        })
    }
  })
}

export const actions = {
  enterDemo() {
    connectionAttempt++
    const endpoints = appStore.get().endpoints
    const session: Session = {
      kind: 'demo',
      service: 'miniflux',
      server: 'demo.album-rss.local',
      username: 'demo',
      remember: true,
    }
    localStorage.setItem(SESSION_KEY, JSON.stringify(session))
    generation++
    toastStore.set(() => [])
    changes.clear()
    confirmed.clear()
    lastChanges.clear()
    mutationTail = Promise.resolve()
    appStore.set(() => ({ ...initialState(), endpoints, session, loaded: true }))
  },

  async connect(input: {
    id?: string
    name?: string
    token?: string
    service: ServiceKind
    server: string
    username: string
    remember: boolean
    apiKey: string
    password: string
    mediaOrigin?: string
    onStep?: (step: number) => void
  }) {
    const server = normalizeServer(input.server)
    const attempt = ++connectionAttempt
    input.onStep?.(0)
    const token =
      input.service === 'miniflux'
        ? input.apiKey.trim()
        : input.token || (await loginGoogleReader(server, input.username.trim(), input.password))
    const session: Session = {
      id: input.id ?? newEndpointId(),
      name: input.name?.trim() || undefined,
      kind: 'connected',
      service: input.service,
      server,
      username: input.username.trim(),
      remember: input.remember,
      token,
      mediaOrigin: input.mediaOrigin ? normalizeServer(input.mediaOrigin) : undefined,
    }
    input.onStep?.(1)
    const provider = providerFor(session)
    const username = await provider.authenticate()
    if (username) session.username = username
    input.onStep?.(2)
    const snapshot = await provider.snapshot()
    const entries = Object.fromEntries(
      snapshot.entries.map((e) => [e.id, parseEntry(e, server, session.mediaOrigin)]),
    )
    if (attempt !== connectionAttempt) throw new ApiError('连接已取消')
    generation++
    toastStore.set(() => [])
    if (input.remember) localStorage.setItem(SESSION_KEY, JSON.stringify(session))
    else localStorage.removeItem(SESSION_KEY)
    const endpoints = appStore.get().endpoints.filter((endpoint) => endpoint.id !== session.id)
    endpoints.push(session)
    persistEndpoints(endpoints)
    changes.clear()
    confirmed.clear()
    lastChanges.clear()
    mutationTail = Promise.resolve()
    appStore.set((state) => ({
      ...state,
      session,
      endpoints,
      loaded: true,
      folders: snapshot.folders,
      feeds: snapshot.feeds,
      entries,
      order: Object.values(entries)
        .sort((a, b) => b.publishedAt - a.publishedAt)
        .map((e) => e.id),
      sync: { status: 'idle', lastSyncedAt: Date.now(), pendingIds: [] },
      downloads: {},
      refreshingFeeds: {},
      viewerSequence: null,
      listVersion: state.listVersion + 1,
    }))
  },

  signOut() {
    connectionAttempt++
    generation++
    toastStore.set(() => [])
    changes.clear()
    confirmed.clear()
    lastChanges.clear()
    mutationTail = Promise.resolve()
    localStorage.removeItem(SESSION_KEY)
    localStorage.removeItem(ENDPOINTS_KEY)
    appStore.set((state) => ({
      ...state,
      session: null,
      endpoints: [],
      loaded: true,
      folders: [],
      feeds: [],
      entries: {},
      order: [],
      downloads: {},
      refreshingFeeds: {},
      viewerSequence: null,
      sync: { status: 'idle', lastSyncedAt: 0, pendingIds: [] },
      listVersion: state.listVersion + 1,
    }))
  },

  async switchEndpoint(id: string) {
    const endpoint = appStore.get().endpoints.find((item) => item.id === id)
    if (!endpoint || endpoint.id === appStore.get().session?.id) return
    await actions.connect({
      ...endpoint,
      apiKey: endpoint.token ?? '',
      password: '',
    })
  },

  removeEndpoint(id: string) {
    if (appStore.get().session?.id === id) return
    const endpoints = appStore.get().endpoints.filter((endpoint) => endpoint.id !== id)
    persistEndpoints(endpoints)
    appStore.set((state) => ({ ...state, endpoints }))
  },

  updateSettings(patch: Partial<Settings>) {
    appStore.set((state) => {
      const settings = { ...state.settings, ...patch }
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
      return { ...state, settings }
    })
  },

  setRead(ids: readonly string[], read: boolean) {
    mutate(ids, 'read', read)
  },

  setStarred(id: string, starred: boolean) {
    mutate([id], 'starred', starred)
  },

  /** 批量标为已读，并提供撤销 */
  markAllRead(ids: readonly string[], scopeLabel: string) {
    const entries = appStore.get().entries
    const targets = ids.filter((id) => entries[id] && !entries[id].read)
    if (targets.length === 0) return
    actions.setRead(targets, true)
    showToast({
      message: `已将${scopeLabel}的 ${targets.length} 个图集标为已读`,
      tone: 'success',
      action: { label: '撤销', run: () => actions.setRead(targets, false) },
    })
  },

  /**
   * 同步。explicit 为用户主动刷新：新内容直接进入列表；
   * 否则（回到前台等）只记下数量，由用户决定何时放进列表。
   */
  async sync({ explicit }: { explicit: boolean }) {
    if (appStore.get().sync.status === 'syncing') return
    const epoch = generation
    appStore.set((state) => ({ ...state, sync: { ...state.sync, status: 'syncing' } }))
    const session = appStore.get().session
    if (session?.kind === 'connected') {
      try {
        await mutationTail
        const startRevision = revision
        const snapshot = await providerFor(session).snapshot()
        if (epoch !== generation) return
        const entries = Object.fromEntries(
          snapshot.entries.map((e) => [e.id, parseEntry(e, session.server, session.mediaOrigin)]),
        )
        appStore.set((state) => {
          for (const entry of Object.values(entries)) {
            for (const field of ['read', 'starred'] as const) {
              if (
                changes.has(`${entry.id}:${field}`) ||
                (lastChanges.get(`${entry.id}:${field}`) ?? 0) > startRevision
              ) {
                entry[field] = state.entries[entry.id]?.[field] ?? entry[field]
              }
            }
          }
          const fresh = Object.keys(entries).filter((id) => !state.entries[id])
          return {
            ...state,
            loaded: true,
            entries,
            folders: snapshot.folders,
            feeds: snapshot.feeds,
            order: Object.values(entries)
              .sort((a, b) => b.publishedAt - a.publishedAt)
              .map((e) => e.id),
            sync: {
              status: 'idle',
              lastSyncedAt: Date.now(),
              pendingIds: explicit
                ? []
                : [...new Set([...state.sync.pendingIds, ...fresh])].filter((id) => entries[id]),
            },
            listVersion: explicit || !state.loaded ? state.listVersion + 1 : state.listVersion,
          }
        })
        if (explicit) showToast({ message: '同步完成', tone: 'success' })
      } catch (error) {
        if (epoch !== generation) return
        appStore.set((state) => ({
          ...state,
          loaded: true,
          sync: { ...state.sync, status: 'idle', error: errorMessage(error) },
        }))
        showToast({ message: '同步失败', detail: errorMessage(error), tone: 'warning' })
      }
      return
    }
    await delay(explicit ? 900 : 600)
    if (epoch !== generation) return
    const now = Date.now()
    const take = arrivals.slice(0, explicit ? 2 : 3)
    arrivals = arrivals.slice(take.length)
    const fresh = take.map((entry, i) => ({ ...entry, publishedAt: now - i * 90_000 }))
    appStore.set((state) => {
      const entries = { ...state.entries }
      for (const entry of fresh) entries[entry.id] = entry
      const ids = fresh.map((e) => e.id)
      return {
        ...state,
        entries,
        order: [...ids, ...state.order],
        sync: {
          status: 'idle',
          lastSyncedAt: now,
          pendingIds: explicit ? [] : [...ids, ...state.sync.pendingIds],
        },
        listVersion: explicit ? state.listVersion + 1 : state.listVersion,
      }
    })
    if (explicit) {
      showToast({
        message:
          fresh.length > 0 ? `同步完成，新增 ${fresh.length} 个图集` : '同步完成，没有新的图集',
        tone: 'success',
      })
    }
  },

  applyPending() {
    appStore.set((state) => ({
      ...state,
      sync: { ...state.sync, pendingIds: [] },
      listVersion: state.listVersion + 1,
    }))
  },

  async refreshFeed(feedId: string) {
    if (appStore.get().refreshingFeeds[feedId]) return
    const epoch = generation
    const setRefreshing = (value: boolean) =>
      appStore.set((state) => ({
        ...state,
        refreshingFeeds: { ...state.refreshingFeeds, [feedId]: value },
      }))
    setRefreshing(true)
    const session = appStore.get().session
    if (session?.kind === 'connected') {
      try {
        const provider = providerFor(session)
        if (!provider.refreshFeed)
          throw new ApiError('当前服务不支持手动抓取，请在 RSS 服务中刷新后同步')
        await provider.refreshFeed(feedId)
        if (epoch !== generation) return
        showToast({ message: '已提交抓取请求，服务完成抓取后请再次同步', tone: 'success' })
        await actions.sync({ explicit: true })
      } catch (error) {
        if (epoch === generation)
          showToast({ message: '刷新失败', detail: errorMessage(error), tone: 'warning' })
      } finally {
        if (epoch === generation) setRefreshing(false)
      }
      return
    }
    await delay(1200)
    if (epoch !== generation) return
    setRefreshing(false)
    const feed = appStore.get().feeds.find((f) => f.id === feedId)
    if (!feed) return
    if (feed.parsingError) {
      appStore.set((state) => ({
        ...state,
        feeds: state.feeds.map((f) =>
          f.id === feedId ? { ...f, parsingErrorCount: f.parsingErrorCount + 1 } : f,
        ),
      }))
      showToast({ message: `刷新失败：${feed.parsingError}`, tone: 'warning' })
      return
    }
    appStore.set((state) => ({
      ...state,
      feeds: state.feeds.map((f) => (f.id === feedId ? { ...f, checkedAt: Date.now() } : f)),
    }))
    showToast({ message: `已刷新「${feed.author}」，没有新的图集`, tone: 'success' })
  },

  setViewerSequence(ids: string[] | null) {
    appStore.set((state) => ({ ...state, viewerSequence: ids }))
  },

  /**
   * 下载即存入设备。真实情况按资源实测：图源允许脚本读取（CORS）时直接保存；
   * 否则引导用户在图片上右键 / 长按，由浏览器保存。演示里 Bilibili 经代理的图片不可读，与本地实测一致。
   * fallback 是读取被拒时提示里的操作，默认打开原图。
   */
  async download(key: string, entry: Entry, images: ImageAsset[], fallback?: ToastAction) {
    const epoch = generation
    const current = appStore.get().downloads[key]
    if (current?.status === 'running') return
    const setState = (value: DownloadState | null) =>
      appStore.set((state) => {
        if (epoch !== generation) return state
        const downloads = { ...state.downloads }
        if (value) downloads[key] = value
        else delete downloads[key]
        return { ...state, downloads }
      })
    const total = images.length
    if (total === 0) return
    setState({ status: 'running', done: 0, total })
    if (appStore.get().session?.kind === 'connected') {
      let done = 0
      try {
        for (const image of images) {
          const response = await fetch(image.url, {
            credentials: 'omit',
            referrerPolicy: 'no-referrer',
            signal: AbortSignal.timeout(30_000),
          })
          if (!response.ok) throw new Error('图片请求失败')
          const blob = await response.blob()
          if (!blob.type.startsWith('image/')) throw new Error('来源没有返回图片')
          if (epoch !== generation) return
          const url = URL.createObjectURL(blob)
          const anchor = document.createElement('a')
          anchor.href = url
          const extension = blob.type.split('/')[1]?.split('+')[0] || 'img'
          anchor.download = `album-${entry.id.replace(/[^a-z0-9-]/gi, '_')}-${done + 1}.${extension}`
          anchor.click()
          window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
          done++
          setState({ status: done === total ? 'done' : 'running', done, total })
        }
        if (epoch !== generation) return
        if (appStore.get().settings.downloadRead) actions.setRead([entry.id], true)
        showToast({ message: `已下载 ${done} 张图片`, tone: 'success' })
      } catch {
        if (epoch !== generation) return
        setState({ status: 'blocked', done, total })
        showToast({
          message: done ? `已下载 ${done} 张，其余图片无法直接下载` : '图片无法直接下载',
          detail: '可能是网络或跨域限制。可打开原图后右键或长按保存。',
          tone: 'warning',
          action:
            fallback ??
            (images[done]
              ? { label: '打开原图', run: () => void openImage(images[done]!.url) }
              : undefined),
        })
      }
      window.setTimeout(() => {
        if (epoch === generation) setState(null)
      }, 4000)
      return
    }
    const readable =
      !demoBlocksDownload(entry.feedId) && !images.some((i) => i.url.startsWith('demo:broken'))
    if (!readable) {
      await delay(700)
      if (epoch !== generation) return
      setState({ status: 'blocked', done: 0, total })
      const first = images[0]
      showToast({
        message:
          images.length > 1
            ? '这些图片的来源不允许网页直接下载'
            : '这张图片的来源不允许网页直接下载',
        detail: '在图片上右键选择另存为；手机上长按图片保存。',
        tone: 'warning',
        action:
          fallback ??
          (first ? { label: '打开原图', run: () => void openImage(first.url) } : undefined),
      })
      window.setTimeout(() => setState(null), 4000)
      return
    }
    for (let done = 1; done <= total; done++) {
      await delay(220 + Math.random() * 260)
      if (epoch !== generation) return
      setState({ status: done === total ? 'done' : 'running', done, total })
    }
    if (appStore.get().settings.downloadRead) actions.setRead([entry.id], true)
    showToast({
      message: total > 1 ? `已下载 ${total} 张图片` : '已下载图片',
      detail: '演示数据，没有写入文件。',
      tone: 'success',
    })
    window.setTimeout(() => setState(null), 2600)
  },

  resetDemo() {
    localStorage.removeItem(SETTINGS_KEY)
    const { session, endpoints } = appStore.get()
    appStore.set(() => ({ ...initialState(), session, endpoints }))
  },
}
