/* 页面状态与服务操作；演示分支保留独立的模拟数据。 */
import type { EntryPage, RemoteEntry } from '@album-rss/core'
import {
  ApiError,
  createGate,
  createProvider,
  loginGoogleReader,
  normalizeServer,
  type Provider,
} from '@album-rss/providers'
import { showToast, toastStore, type ToastAction } from '../components/ui/toast'
import { createStore } from '../lib/createStore'
import { endpointLabel } from '../lib/endpoint'
import { configureLatency, openImage } from '../lib/imageSource'
import { parseEntry } from '../lib/parseEntry'
import { createDemoData, demoBlocksDownload } from './demoData'
import type {
  DownloadState,
  Endpoint,
  Entry,
  Feed,
  Folder,
  ImageAsset,
  ListQuery,
  ScopeState,
  ServiceKind,
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
  /** 正在使用的端点 */
  endpoint: Endpoint | null
  /** 已添加的端点，不含演示数据 */
  endpoints: Endpoint[]
  loaded: boolean
  settings: Settings
  folders: Folder[]
  feeds: Feed[]
  entries: Record<string, Entry>
  /** 已读取的全部文章 ID，新的在前 */
  order: string[]
  /** 各列表在服务端的分页进度，键见 scopeKey；只读用户看到的部分，滚到底再读下一页 */
  scopes: Record<string, ScopeState>
  /** 服务端的未读计数（订阅 ID → 篇数）；服务不提供时为 null，改按已读取的文章统计 */
  unread: Record<string, number> | null
  sync: SyncState
  /** 列表快照版本：显式刷新或应用新内容时递增，各列表据此重新取数 */
  listVersion: number
  downloads: Record<string, DownloadState>
  refreshingFeeds: Record<string, boolean>
  /** 当前查看器的翻页顺序，取自打开它的那个列表 */
  viewerSequence: string[] | null
}

const SETTINGS_KEY = 'album-rss:settings'
const ENDPOINTS_KEY = 'album-rss:endpoints'
const ACTIVE_KEY = 'album-rss:active'
/** 旧版本把当前连接单独保存在这里，读取后迁移到端点列表 */
const LEGACY_SESSION_KEY = 'album-rss:session'

/** 每页文章数。切换或添加端点时只读第一页，列表滚到底再读下一页 */
export const PAGE_SIZE = 100
/** 切回已缓存的端点时，距上次同步超过这个时间才在后台检查新内容 */
const STALE_MS = 60_000

const DEMO_ENDPOINT: Endpoint = {
  id: 'demo',
  kind: 'demo',
  service: 'miniflux',
  server: 'demo.album-rss.local',
  username: 'demo',
  remember: true,
}

const DEFAULT_SETTINGS: Settings = {
  videoEndBehavior: 'pause',
  videoAutoplay: false,
  videoAutoplayCellular: false,
  autoRead: true,
  downloadRead: true,
  showImageless: false,
  defaultStatus: 'unread',
  density: 'standard',
  theme: 'system',
  simulateLatency: true,
}

function readItem(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function readJson<T>(key: string): T | null {
  try {
    const raw = readItem(key)
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

function persistEndpoints(endpoints: Endpoint[]) {
  localStorage.setItem(
    ENDPOINTS_KEY,
    JSON.stringify(endpoints.filter((endpoint) => endpoint.remember)),
  )
}

/** 读取保存的端点，并迁移旧版本单独保存的连接 */
function restoreEndpoints(): { endpoints: Endpoint[]; activeId: string | null } {
  const endpoints = (readJson<Endpoint[]>(ENDPOINTS_KEY) ?? []).filter(
    (endpoint) => endpoint?.kind === 'connected' && endpoint.token,
  )
  endpoints.forEach((endpoint) => (endpoint.id ??= newEndpointId()))
  let activeId = readItem(ACTIVE_KEY)
  const legacy = readJson<Partial<Endpoint>>(LEGACY_SESSION_KEY)
  if (legacy) {
    if (legacy.kind === 'demo') activeId ??= DEMO_ENDPOINT.id
    else if (legacy.kind === 'connected' && legacy.token && legacy.remember) {
      const id = legacy.id ?? newEndpointId()
      if (!endpoints.some((endpoint) => endpoint.id === id))
        endpoints.push({ ...legacy, id } as Endpoint)
      activeId ??= id
    }
    localStorage.removeItem(LEGACY_SESSION_KEY)
    persistEndpoints(endpoints)
    if (activeId) localStorage.setItem(ACTIVE_KEY, activeId)
  }
  return { endpoints, activeId }
}

function demoContent(now: number) {
  const demo = createDemoData(now)
  arrivals = demo.arrivals
  return {
    folders: demo.folders,
    feeds: demo.feeds,
    entries: Object.fromEntries(demo.entries.map((entry) => [entry.id, entry])),
    order: demo.entries.map((entry) => entry.id),
  }
}

function initialState(): AppState {
  const now = Date.now()
  const { endpoints, activeId } = restoreEndpoints()
  const endpoint =
    activeId === DEMO_ENDPOINT.id
      ? DEMO_ENDPOINT
      : (endpoints.find((item) => item.id === activeId) ?? null)
  const connected = endpoint?.kind === 'connected'
  const demo = demoContent(now)
  return {
    endpoint,
    endpoints,
    loaded: !connected,
    settings: { ...DEFAULT_SETTINGS, ...readJson<Partial<Settings>>(SETTINGS_KEY) },
    ...(connected ? { folders: [], feeds: [], entries: {}, order: [] } : demo),
    scopes: {},
    unread: null,
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

/** 列表在 store 里的键 */
export function scopeKey(query: ListQuery): string {
  return JSON.stringify([query.status, query.feedId ?? null, query.folderId ?? null])
}

export function queryOfKey(key: string): ListQuery {
  const [status, feedId, folderId] = JSON.parse(key) as [ListQuery['status'], string?, string?]
  return { status, feedId: feedId ?? undefined, folderId: folderId ?? undefined }
}

function entryScope(query: ListQuery) {
  return {
    feedId: query.feedId,
    folderId: query.folderId,
    unread: query.status === 'unread' || undefined,
    starred: query.status === 'starred' || undefined,
  }
}

/** 正在显示的列表：同步时只刷新它们，其余列表等再次打开时读取 */
const mounted = new Map<string, { query: ListQuery; count: number }>()

export function retainScope(query: ListQuery): () => void {
  const key = scopeKey(query)
  const item = mounted.get(key) ?? { query, count: 0 }
  item.count++
  mounted.set(key, item)
  return () => {
    item.count--
    if (item.count <= 0 && mounted.get(key) === item) mounted.delete(key)
  }
}

const defaultQuery = (): ListQuery => ({ status: appStore.get().settings.defaultStatus })

function uniqueQueries(queries: ListQuery[]): ListQuery[] {
  return [...new Map(queries.map((query) => [scopeKey(query), query])).values()]
}

let scopeToken = 0

function freshScope(query: ListQuery, page: EntryPage): ScopeState {
  return {
    query,
    ids: [...new Set(page.entries.map((entry) => entry.id))],
    cursor: page.cursor,
    done: page.cursor === null,
    loading: false,
    token: ++scopeToken,
  }
}

function sortOrder(entries: Record<string, Entry>): string[] {
  return Object.values(entries)
    .sort((a, b) => b.publishedAt - a.publishedAt)
    .map((entry) => entry.id)
}

type EntryData = Pick<AppState, 'entries' | 'unread'>

/** 改动文章；已读状态变化时一并调整未读计数 */
function patchData<T extends EntryData>(
  data: T,
  ids: readonly string[],
  patch: (entry: Entry) => Entry,
): T {
  let entries: Record<string, Entry> | null = null
  let unread: Record<string, number> | null = null
  for (const id of ids) {
    const entry = data.entries[id]
    if (!entry) continue
    const next = patch(entry)
    if (next === entry) continue
    entries ??= { ...data.entries }
    entries[id] = next
    if (data.unread && next.read !== entry.read) {
      unread ??= { ...data.unread }
      unread[entry.feedId] = Math.max(0, (unread[entry.feedId] ?? 0) + (next.read ? -1 : 1))
    }
  }
  return entries ? { ...data, entries, unread: unread ?? data.unread } : data
}

function patchEntries(ids: readonly string[], patch: (entry: Entry) => Entry) {
  appStore.set((state) => patchData(state, ids, patch))
}

/** 每个端点缓存最后一次的数据，切回时立即显示 */
type EndpointData = Pick<
  AppState,
  'folders' | 'feeds' | 'entries' | 'order' | 'scopes' | 'unread'
> & { lastSyncedAt: number }
const cache = new Map<string, EndpointData>()

function stash(state: AppState) {
  const endpoint = state.endpoint
  if (endpoint?.kind !== 'connected' || !state.loaded) return
  if (!state.endpoints.some((item) => item.id === endpoint.id)) return
  cache.set(endpoint.id, {
    folders: state.folders,
    feeds: state.feeds,
    entries: state.entries,
    order: state.order,
    scopes: Object.fromEntries(
      Object.entries(state.scopes).map(([key, scope]) => [
        key,
        scope.loading ? { ...scope, loading: false } : scope,
      ]),
    ),
    unread: state.unread,
    lastSyncedAt: state.sync.lastSyncedAt,
  })
}

/** 改动某个端点的文章：正在使用时改页面状态，否则改它的缓存 */
function patchEndpoint(endpointId: string, ids: readonly string[], patch: (entry: Entry) => Entry) {
  if (appStore.get().endpoint?.id === endpointId) patchEntries(ids, patch)
  else {
    const data = cache.get(endpointId)
    if (data) cache.set(endpointId, patchData(data, ids, patch))
  }
}

let generation = 0
let connectionAttempt = 0
let mutationTail = Promise.resolve()
let revision = 0
/** 未确认的已读、收藏改动，键为 端点\n文章\n字段 */
const changes = new Map<string, { revision: number; value: boolean }>()
const confirmed = new Map<string, boolean>()
const lastChanges = new Map<string, number>()
/** 后台同步读到的新一页，点“有新图集”时替换对应列表 */
let pending: { generation: number; scopes: Record<string, ScopeState> } | null = null

const track = (endpointId: string, entryId: string, field: 'read' | 'starred') =>
  `${endpointId}\n${entryId}\n${field}`

function forgetTracking(endpointId: string) {
  for (const map of [changes, confirmed, lastChanges]) {
    for (const key of map.keys()) if (key.startsWith(`${endpointId}\n`)) map.delete(key)
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '请求失败，请稍后重试'
}

/** 每个端点一个适配器，同一端点的请求共用一个队列 */
const providers = new Map<string, { key: string; provider: Provider }>()

function providerFor(endpoint: Endpoint): Provider {
  const key = [endpoint.service, endpoint.server, endpoint.token].join('\n')
  const cached = providers.get(endpoint.id)
  if (cached?.key === key) return cached.provider
  const provider = createProvider({
    service: endpoint.service,
    server: endpoint.server,
    token: endpoint.token ?? '',
    gate: createGate(),
  })
  providers.set(endpoint.id, { key, provider })
  return provider
}

/** 合并服务端返回的文章；本地还没确认的已读、收藏改动优先 */
function mergeEntries(
  current: Record<string, Entry>,
  endpoint: Endpoint,
  remote: readonly RemoteEntry[],
  since: number,
): Record<string, Entry> {
  const entries = { ...current }
  for (const item of remote) {
    const entry = parseEntry(item, endpoint.server, endpoint.mediaOrigin)
    for (const field of ['read', 'starred'] as const) {
      const key = track(endpoint.id, entry.id, field)
      if (changes.has(key) || (lastChanges.get(key) ?? 0) > since)
        entry[field] = current[entry.id]?.[field] ?? entry[field]
    }
    entries[entry.id] = entry
  }
  return entries
}

/** 读取端点的订阅、未读计数和指定列表的第一页 */
async function loadEndpoint(
  endpoint: Endpoint,
  provider: Provider,
  queries: ListQuery[],
): Promise<EndpointData> {
  const since = revision
  const [pages, subscriptions, unread] = await Promise.all([
    // 文章页最大，先排进请求队列
    Promise.all(queries.map((query) => provider.entries(entryScope(query), null, PAGE_SIZE))),
    provider.subscriptions(),
    provider.unreadCounts(),
  ])
  const entries = mergeEntries(
    {},
    endpoint,
    pages.flatMap((page) => page.entries),
    since,
  )
  return {
    ...subscriptions,
    entries,
    order: sortOrder(entries),
    scopes: Object.fromEntries(
      queries.map((query, i) => [scopeKey(query), freshScope(query, pages[i]!)]),
    ),
    unread,
    lastSyncedAt: Date.now(),
  }
}

/** 切换到端点：先缓存当前端点的数据，再换上新数据 */
function activate(endpoint: Endpoint, data: EndpointData) {
  const state = appStore.get()
  if (state.endpoint?.id !== endpoint.id) stash(state)
  cache.delete(endpoint.id)
  generation++
  pending = null
  toastStore.set(() => [])
  const endpoints = state.endpoints.some((item) => item.id === endpoint.id)
    ? state.endpoints.map((item) => (item.id === endpoint.id ? endpoint : item))
    : [...state.endpoints, endpoint]
  persistEndpoints(endpoints)
  localStorage.setItem(ACTIVE_KEY, endpoint.id)
  appStore.set((current) => ({
    ...current,
    endpoint,
    endpoints,
    loaded: true,
    folders: data.folders,
    feeds: data.feeds,
    entries: data.entries,
    order: data.order,
    scopes: data.scopes,
    unread: data.unread,
    sync: { status: 'idle', lastSyncedAt: data.lastSyncedAt, pendingIds: [] },
    downloads: {},
    refreshingFeeds: {},
    viewerSequence: null,
    listVersion: current.listVersion + 1,
  }))
}

/** 不再使用任何端点，回到连接页 */
function deactivate() {
  connectionAttempt++
  generation++
  pending = null
  toastStore.set(() => [])
  localStorage.removeItem(ACTIVE_KEY)
  const demo = demoContent(Date.now())
  appStore.set((state) => ({
    ...state,
    endpoint: null,
    loaded: true,
    ...demo,
    scopes: {},
    unread: null,
    downloads: {},
    refreshingFeeds: {},
    viewerSequence: null,
    sync: { status: 'idle', lastSyncedAt: 0, pendingIds: [] },
    listVersion: state.listVersion + 1,
  }))
}

function mutate(ids: readonly string[], field: 'read' | 'starred', value: boolean) {
  const { endpoint, entries } = appStore.get()
  const apply = (entry: Entry) => (entry[field] === value ? entry : { ...entry, [field]: value })
  if (!endpoint || endpoint.kind === 'demo') {
    patchEntries(ids, apply)
    return
  }
  const serial = ++revision
  ids.forEach((id) => {
    const key = track(endpoint.id, id, field)
    if (!changes.has(key)) confirmed.set(key, entries[id]?.[field] ?? false)
    changes.set(key, { revision: serial, value })
    lastChanges.set(key, serial)
  })
  patchEntries(ids, apply)
  mutationTail = mutationTail.then(async () => {
    try {
      // 写入属于发起操作的端点：切换端点后照常发送，端点被删除时放弃
      const target = appStore.get().endpoints.find((item) => item.id === endpoint.id)
      if (!target) return
      const provider = providerFor(target)
      if (field === 'read') await provider.setRead(ids, value)
      else for (const id of ids) await provider.setStarred(id, value)
      ids.forEach((id) => confirmed.set(track(endpoint.id, id, field), value))
    } catch (error) {
      patchEndpoint(endpoint.id, ids, (entry) => {
        const key = track(endpoint.id, entry.id, field)
        const old = confirmed.get(key)
        return changes.get(key)?.revision === serial && old !== undefined && entry[field] !== old
          ? { ...entry, [field]: old }
          : entry
      })
      const active = appStore.get().endpoint?.id === endpoint.id
      if (active) appStore.set((state) => ({ ...state, listVersion: state.listVersion + 1 }))
      showToast({
        message: active ? '状态未能保存到服务器' : `「${endpointLabel(endpoint)}」的状态未能保存`,
        detail: errorMessage(error),
        tone: 'warning',
        action: active ? { label: '重试', run: () => mutate(ids, field, value) } : undefined,
      })
    } finally {
      ids.forEach((id) => {
        const key = track(endpoint.id, id, field)
        if (changes.get(key)?.revision === serial) {
          changes.delete(key)
          confirmed.delete(key)
        }
      })
    }
  })
}

/** 同步时要刷新的列表：显式同步刷新正在显示的列表，后台同步只检查浏览页 */
function syncQueries(state: AppState, explicit: boolean): ListQuery[] {
  if (!state.loaded) return [defaultQuery()]
  const valid = (query: ListQuery) =>
    (!query.feedId || state.feeds.some((feed) => feed.id === query.feedId)) &&
    (!query.folderId || state.folders.some((folder) => folder.id === query.folderId))
  const shown = [...mounted.values()].map((item) => item.query).filter(valid)
  if (explicit) return uniqueQueries(shown.length > 0 ? shown : [defaultQuery()])
  const browse = shown.filter((query) => !query.feedId && query.status !== 'starred')
  return uniqueQueries(browse.length > 0 ? browse : [defaultQuery()]).filter(
    (query) => state.scopes[scopeKey(query)],
  )
}

export const actions = {
  enterDemo() {
    connectionAttempt++
    const state = appStore.get()
    stash(state)
    generation++
    pending = null
    toastStore.set(() => [])
    localStorage.setItem(ACTIVE_KEY, DEMO_ENDPOINT.id)
    appStore.set(() => ({
      ...initialState(),
      endpoints: state.endpoints,
      endpoint: DEMO_ENDPOINT,
      loaded: true,
      listVersion: state.listVersion + 1,
    }))
  },

  exitDemo() {
    deactivate()
  },

  /** 添加或编辑端点：验证凭据、读取第一页，然后切换过去 */
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
    const endpoint: Endpoint = {
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
    const provider = providerFor(endpoint)
    const username = await provider.authenticate()
    if (username) endpoint.username = username
    input.onStep?.(2)
    const data = await loadEndpoint(endpoint, provider, [defaultQuery()])
    if (attempt !== connectionAttempt) throw new ApiError('连接已取消')
    activate(endpoint, data)
  },

  /** 放弃进行中的连接；迟到的结果不会切换端点 */
  cancelConnect() {
    connectionAttempt++
  },

  /** 切换端点。访问过的端点直接用缓存，必要时在后台检查新内容 */
  async switchEndpoint(id: string) {
    const state = appStore.get()
    const endpoint = state.endpoints.find((item) => item.id === id)
    if (!endpoint || endpoint.id === state.endpoint?.id) return
    const attempt = ++connectionAttempt
    const cached = cache.get(id)
    if (cached) {
      activate(endpoint, cached)
      if (Date.now() - cached.lastSyncedAt > STALE_MS) void actions.sync({ explicit: false })
      return
    }
    const data = await loadEndpoint(endpoint, providerFor(endpoint), [defaultQuery()])
    if (attempt !== connectionAttempt) throw new ApiError('连接已取消')
    activate(endpoint, data)
  },

  /** 删除端点及其保存的凭据；删除正在使用的端点时切到下一个，没有了就回到连接页 */
  async removeEndpoint(id: string) {
    const state = appStore.get()
    const endpoints = state.endpoints.filter((endpoint) => endpoint.id !== id)
    cache.delete(id)
    providers.delete(id)
    forgetTracking(id)
    persistEndpoints(endpoints)
    appStore.set((current) => ({ ...current, endpoints }))
    if (state.endpoint?.id !== id) return
    const next = endpoints[0]
    if (next) {
      try {
        await actions.switchEndpoint(next.id)
        return
      } catch (error) {
        showToast({
          message: `无法连接「${endpointLabel(next)}」`,
          detail: errorMessage(error),
          tone: 'warning',
        })
      }
    }
    deactivate()
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

  /** 订阅的全部未读：先向服务端取齐未读文章（含还没加载的），再标为已读，可撤销 */
  async markFeedRead(feed: Feed) {
    const state = appStore.get()
    const endpoint = state.endpoint
    const label = `「${feed.author}」`
    if (endpoint?.kind !== 'connected') {
      actions.markAllRead(
        state.order.filter((id) => state.entries[id]?.feedId === feed.id),
        label,
      )
      return
    }
    const epoch = generation
    try {
      const provider = providerFor(endpoint)
      const ids: string[] = []
      let cursor: string | null = null
      do {
        const since = revision
        const page: EntryPage = await provider.entries(
          { feedId: feed.id, unread: true },
          cursor,
          500,
        )
        if (epoch !== generation) return
        appStore.set((current) => {
          const entries = mergeEntries(current.entries, endpoint, page.entries, since)
          return { ...current, entries, order: sortOrder(entries) }
        })
        ids.push(...page.entries.map((entry) => entry.id))
        cursor = page.cursor
      } while (cursor)
      if (ids.length === 0) showToast({ message: `${label}没有未读的图集`, tone: 'success' })
      else actions.markAllRead(ids, label)
    } catch (error) {
      if (epoch === generation)
        showToast({ message: '标为已读失败', detail: errorMessage(error), tone: 'warning' })
    }
  },

  /** 读取列表的下一页（还没读过时读第一页） */
  async loadMore(query: ListQuery) {
    const key = scopeKey(query)
    const state = appStore.get()
    const endpoint = state.endpoint
    const scope = state.scopes[key]
    if (endpoint?.kind !== 'connected' || !state.loaded || scope?.loading || scope?.done) return
    const epoch = generation
    const token = scope?.token ?? ++scopeToken
    const since = revision
    const setScope = (update: (scope: ScopeState) => ScopeState, merge?: RemoteEntry[]) =>
      appStore.set((current) => {
        const existing = current.scopes[key]
        if (existing && existing.token !== token) return current
        const next = update(
          existing ?? { query, ids: [], cursor: null, done: false, loading: false, token },
        )
        if (!merge) return { ...current, scopes: { ...current.scopes, [key]: next } }
        const entries = mergeEntries(current.entries, endpoint, merge, since)
        return {
          ...current,
          entries,
          order: sortOrder(entries),
          scopes: { ...current.scopes, [key]: next },
        }
      })
    setScope((current) => ({ ...current, loading: true, error: undefined }))
    try {
      const page = await providerFor(endpoint).entries(
        entryScope(query),
        scope?.cursor ?? null,
        PAGE_SIZE,
      )
      if (epoch !== generation) return
      setScope((current) => {
        const ids = new Set(current.ids)
        page.entries.forEach((entry) => ids.add(entry.id))
        return {
          ...current,
          ids: [...ids],
          cursor: page.cursor,
          done: page.cursor === null,
          loading: false,
        }
      }, page.entries)
    } catch (error) {
      if (epoch !== generation) return
      setScope((current) => ({ ...current, loading: false, error: errorMessage(error) }))
    }
  },

  /**
   * 同步。explicit 为用户主动刷新：重新读取正在显示的列表，新内容直接进入列表；
   * 否则（回到前台等）只记下数量，由用户决定何时放进列表。
   */
  async sync({ explicit }: { explicit: boolean }) {
    if (appStore.get().sync.status === 'syncing') return
    const epoch = generation
    appStore.set((state) => ({ ...state, sync: { ...state.sync, status: 'syncing' } }))
    const endpoint = appStore.get().endpoint
    if (endpoint?.kind === 'connected') {
      try {
        await mutationTail
        const since = revision
        const queries = syncQueries(appStore.get(), explicit)
        const provider = providerFor(endpoint)
        const [pages, subscriptions, unread] = await Promise.all([
          // 文章页最大，先排进请求队列
          Promise.all(queries.map((query) => provider.entries(entryScope(query), null, PAGE_SIZE))),
          provider.subscriptions(),
          provider.unreadCounts(),
        ])
        if (epoch !== generation) return
        const scopes = Object.fromEntries(
          queries.map((query, i) => [scopeKey(query), freshScope(query, pages[i]!)]),
        )
        const state = appStore.get()
        const replace = explicit || !state.loaded
        // 后台同步：新文章只计数，点“有新图集”时再换上这一页
        const pendingIds = replace
          ? []
          : [
              ...new Set(
                Object.entries(scopes).flatMap(([key, scope]) => {
                  const known = new Set(state.scopes[key]?.ids)
                  return scope.ids.filter((id) => !known.has(id))
                }),
              ),
            ]
        pending = pendingIds.length > 0 ? { generation, scopes } : null
        const entries = mergeEntries(
          state.entries,
          endpoint,
          pages.flatMap((page) => page.entries),
          since,
        )
        appStore.set((current) => ({
          ...current,
          loaded: true,
          ...subscriptions,
          entries,
          order: sortOrder(entries),
          unread,
          scopes: replace ? scopes : current.scopes,
          sync: { status: 'idle', lastSyncedAt: Date.now(), pendingIds },
          listVersion: replace ? current.listVersion + 1 : current.listVersion,
        }))
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

  /** 把后台同步到的新内容放进列表 */
  applyPending() {
    const scopes = pending?.generation === generation ? pending.scopes : null
    pending = null
    appStore.set((state) => ({
      ...state,
      scopes: scopes ?? state.scopes,
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
    const endpoint = appStore.get().endpoint
    if (endpoint?.kind === 'connected') {
      try {
        const provider = providerFor(endpoint)
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
    images = images.filter((image) => image.kind !== 'video')
    if (!images.length) return
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
    if (appStore.get().endpoint?.kind === 'connected') {
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
    const { endpoint, endpoints, listVersion } = appStore.get()
    appStore.set(() => ({ ...initialState(), endpoint, endpoints, listVersion: listVersion + 1 }))
  },
}
