import { CORE_PACKAGE, httpUrl } from '@album-rss/core'
import type {
  EntryPage,
  EntryScope,
  Feed,
  Folder,
  RemoteEntry,
  ServiceKind,
  Subscriptions,
} from '@album-rss/core'

export const PROVIDERS_PACKAGE = '@album-rss/providers'
export const PROVIDERS_DEPENDS_ON = [CORE_PACKAGE] as const

export class ApiError extends Error {
  status: number
  constructor(message: string, status = 0) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

export function normalizeServer(value: string): string {
  const url = httpUrl(value.trim())
  if (!url) throw new ApiError('请输入不含用户名和密码的 HTTP 或 HTTPS 服务地址')
  const parsed = new URL(url)
  parsed.search = ''
  parsed.hash = ''
  return parsed.href.replace(/\/+$/, '')
}

/**
 * 同一服务的请求排队：同时最多 concurrency 个，相邻两次开始至少间隔 interval 毫秒。
 * 服务限流时整体暂停，避免连续请求触发服务或前置代理的风控。
 */
export interface RequestGate {
  run<T>(task: () => Promise<T>): Promise<T>
  /** ms 毫秒内不再开始新的请求 */
  pause(ms: number): void
}

export function createGate({ concurrency = 2, interval = 150 } = {}): RequestGate {
  const queue: (() => void)[] = []
  let active = 0
  let readyAt = 0
  let timer: ReturnType<typeof setTimeout> | undefined
  const pump = () => {
    timer = undefined
    while (active < concurrency && queue.length > 0) {
      const wait = readyAt - Date.now()
      if (wait > 0) {
        timer = setTimeout(pump, wait)
        return
      }
      readyAt = Date.now() + interval
      active++
      queue.shift()?.()
    }
  }
  return {
    run(task) {
      return new Promise((resolve, reject) => {
        queue.push(() => {
          void task()
            .then(resolve, reject)
            .finally(() => {
              active--
              if (!timer) pump()
            })
        })
        if (!timer) pump()
      })
    },
    pause(ms) {
      readyAt = Math.max(readyAt, Date.now() + ms)
    },
  }
}

export interface ProviderOptions {
  service: ServiceKind
  server: string
  token: string
  fetch?: typeof fetch
  /** 同一端点的请求共用一个队列；不传时每个适配器单独排队 */
  gate?: RequestGate
}

export interface Provider {
  authenticate(): Promise<string>
  subscriptions(): Promise<Subscriptions>
  /** 各订阅的未读文章数，键为订阅 ID；服务不提供计数接口时为 null */
  unreadCounts(): Promise<Record<string, number> | null>
  /** 按范围分页读取文章，新的在前；cursor 来自上一页 */
  entries(scope: EntryScope, cursor: string | null, limit: number): Promise<EntryPage>
  setRead(ids: readonly string[], read: boolean): Promise<void>
  setStarred(id: string, starred: boolean): Promise<void>
  refreshFeed?: (id: string) => Promise<void>
}

/** 限流或网关暂时不可用时重试；超过这个等待时间就直接报错，交给用户稍后再试 */
const RETRY_STATUS = new Set([429, 502, 503, 504])
const MAX_RETRIES = 3
const MAX_RETRY_WAIT_MS = 30_000

function retryDelay(response: Response, attempt: number): number {
  const header = response.headers.get('Retry-After')?.trim()
  if (header) {
    const seconds = Number(header)
    if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000)
    const date = Date.parse(header)
    if (!Number.isNaN(date)) return Math.max(0, date - Date.now())
  }
  return 1000 * 2 ** attempt
}

function transport(server: string, fetcher: typeof fetch = fetch, gate = createGate()) {
  return (path: string, init: RequestInit = {}) =>
    gate.run(async () => {
      for (let attempt = 0; ; attempt++) {
        let response: Response
        try {
          response = await fetcher(server + path, {
            ...init,
            credentials: 'omit',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
            signal: AbortSignal.timeout(30_000),
          })
        } catch {
          throw new ApiError('请求未完成，请检查网络、服务证书和跨域（CORS）配置后重试')
        }
        if (response.ok) return response
        const wait = retryDelay(response, attempt)
        if (
          RETRY_STATUS.has(response.status) &&
          attempt < MAX_RETRIES &&
          wait <= MAX_RETRY_WAIT_MS
        ) {
          void response.body?.cancel()
          gate.pause(wait)
          await new Promise((resolve) => setTimeout(resolve, wait))
          continue
        }
        throw new ApiError(
          response.status === 401 || response.status === 403
            ? '凭据无效或已过期，请编辑这个端点后重新连接'
            : response.status === 429
              ? `服务限制了请求频率，请${wait > MAX_RETRY_WAIT_MS ? `约 ${Math.ceil(wait / 1000)} 秒后` : '稍后'}再试`
              : `服务返回 HTTP ${response.status}，请稍后重试`,
          response.status,
        )
      }
    })
}

async function json<T>(response: Response): Promise<T> {
  try {
    return (await response.json()) as T
  } catch {
    throw new ApiError('服务没有返回有效的 JSON 数据，请检查服务类型和 API 地址')
  }
}

/** 可选接口：服务没有实现时返回 null，认证和网络错误照常抛出 */
async function optional<T>(read: () => Promise<T | null>): Promise<T | null> {
  try {
    return await read()
  } catch (error) {
    if (error instanceof ApiError && [400, 404, 405, 501].includes(error.status)) return null
    throw error
  }
}

interface MinifluxFeed {
  id: number
  title: string
  site_url: string
  feed_url: string
  category?: { id: number; title: string }
  checked_at: string
  parsing_error_count: number
  parsing_error_message?: string
}

interface MinifluxEntry {
  id: number
  feed_id: number
  title: string
  author: string
  url: string
  content: string
  published_at: string
  status: string
  starred: boolean
  enclosures?: { url: string; mime_type: string }[] | null
}

function numericId(id: string): number {
  const value = Number(id)
  if (!Number.isSafeInteger(value) || value <= 0) throw new ApiError('服务返回了不支持的 ID')
  return value
}

function minifluxEntry(e: MinifluxEntry): RemoteEntry {
  return {
    id: String(numericId(String(e.id))),
    feedId: String(e.feed_id),
    title: e.title,
    author: e.author,
    url: httpUrl(e.url),
    publishedAt: Date.parse(e.published_at) || 0,
    content: e.content || '',
    tags: [],
    read: e.status === 'read',
    starred: e.starred,
    enclosures: (e.enclosures ?? []).map((a) => ({ url: a.url, mimeType: a.mime_type })),
  }
}

export function createProvider(options: ProviderOptions): Provider {
  const request = transport(normalizeServer(options.server), options.fetch, options.gate)
  if (options.service === 'greader') return googleReader(request, options.token)
  const headers = { 'X-Auth-Token': options.token }
  const get = async <T>(path: string) => json<T>(await request(path, { headers }))
  const put = async (path: string, body?: unknown) => {
    await request(path, {
      method: 'PUT',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  }
  return {
    async authenticate() {
      const me = await get<{ username: string }>('/v1/me')
      if (typeof me.username !== 'string')
        throw new ApiError('服务类型不匹配：未返回 Miniflux 用户信息')
      return me.username
    },
    async subscriptions() {
      const [rawFeeds, categories] = await Promise.all([
        get<MinifluxFeed[]>('/v1/feeds'),
        get<{ id: number; title: string }[]>('/v1/categories'),
      ])
      const feeds: Feed[] = rawFeeds.map((f) => ({
        id: String(f.id),
        title: f.title,
        author: f.title,
        siteUrl: httpUrl(f.site_url),
        iconUrl: '',
        folderIds: f.category ? [String(f.category.id)] : [],
        checkedAt: Date.parse(f.checked_at) || 0,
        parsingErrorCount: f.parsing_error_count || 0,
        parsingError: f.parsing_error_message || undefined,
      }))
      return { feeds, folders: categories.map((c) => ({ id: String(c.id), title: c.title })) }
    },
    unreadCounts: () =>
      optional(async () => {
        const counters = await get<{ unreads?: Record<string, number> }>('/v1/feeds/counters')
        if (!counters || typeof counters !== 'object') return null
        return Object.fromEntries(
          Object.entries(counters.unreads ?? {}).map(([id, count]) => [id, Number(count) || 0]),
        )
      }),
    async entries(scope, cursor, limit) {
      // 使用 ID 游标，避免翻页期间新增或读完的文章导致 offset 偏移。
      const params = new URLSearchParams({ limit: String(limit), order: 'id', direction: 'desc' })
      if (scope.unread) params.append('status', 'unread')
      else {
        params.append('status', 'read')
        params.append('status', 'unread')
      }
      if (scope.starred) params.set('starred', 'true')
      if (cursor) params.set('before_entry_id', cursor)
      const path = scope.feedId
        ? `/v1/feeds/${numericId(scope.feedId)}/entries`
        : scope.folderId
          ? `/v1/categories/${numericId(scope.folderId)}/entries`
          : '/v1/entries'
      const page = await get<{ entries: MinifluxEntry[] | null }>(`${path}?${params}`)
      const entries = (page.entries ?? []).map(minifluxEntry)
      if (entries.length < limit) return { entries, cursor: null }
      const next = String(Math.min(...entries.map((e) => Number(e.id))))
      if (cursor && BigInt(next) >= BigInt(cursor)) throw new ApiError('服务未正确推进文章分页')
      return { entries, cursor: next }
    },
    async setRead(ids, read) {
      for (let offset = 0; offset < ids.length; offset += 250) {
        await put('/v1/entries', {
          entry_ids: ids.slice(offset, offset + 250).map(numericId),
          status: read ? 'read' : 'unread',
        })
      }
    },
    async setStarred(id, starred) {
      // 旧版 Miniflux 只有切换接口，先读取再写入期望状态。
      const entry = await get<MinifluxEntry>(`/v1/entries/${numericId(id)}`)
      if (entry.starred !== starred) await put(`/v1/entries/${numericId(id)}/bookmark`)
      const verified = await get<MinifluxEntry>(`/v1/entries/${numericId(id)}`)
      if (verified.starred !== starred) throw new ApiError('收藏状态校验失败，请同步后重试')
    },
    refreshFeed: (id) => put(`/v1/feeds/${numericId(id)}/refresh`),
  }
}

export async function loginGoogleReader(
  server: string,
  username: string,
  password: string,
  fetcher?: typeof fetch,
): Promise<string> {
  const response = await transport(normalizeServer(server), fetcher)('/accounts/ClientLogin', {
    method: 'POST',
    body: new URLSearchParams({ Email: username, Passwd: password }),
  })
  const token = (await response.text()).match(/^Auth=(.+)$/m)?.[1]?.trim()
  if (!token) throw new ApiError('登录失败：服务未返回 Google Reader 访问令牌')
  return token
}

interface ReaderItem {
  id: string
  title?: string
  author?: string
  published?: number
  categories?: string[]
  origin?: { streamId: string; title?: string; htmlUrl?: string }
  canonical?: { href: string }[]
  alternate?: { href: string }[]
  summary?: { content: string }
  content?: { content: string }
  enclosure?: { href: string; type: string }[]
}

const READING_LIST = 'user/-/state/com.google/reading-list'
const STARRED = 'user/-/state/com.google/starred'
const READ = 'user/-/state/com.google/read'

/** 流 ID 放在路径里：保留分隔的斜杠，其余字符（如标签里的空格、中文）逐段编码 */
function streamPath(stream: string): string {
  return stream.split('/').map(encodeURIComponent).join('/')
}

function readerEntry(e: ReaderItem): RemoteEntry {
  if (typeof e.id !== 'string') throw new ApiError('服务返回了不安全的 Google Reader ID')
  const categories = e.categories ?? []
  return {
    id: e.id,
    feedId: e.origin?.streamId ?? '',
    title: e.title ?? '',
    author: e.author ?? '',
    url: httpUrl(e.canonical?.[0]?.href ?? e.alternate?.[0]?.href ?? ''),
    publishedAt: (e.published ?? 0) * 1000,
    content: e.content?.content ?? e.summary?.content ?? '',
    tags: categories.filter((c) => c.includes('/label/')).map((c) => c.split('/label/')[1] ?? c),
    read: categories.some((c) => c.endsWith('/state/com.google/read')),
    starred: categories.some((c) => c.endsWith('/state/com.google/starred')),
    enclosures: (e.enclosure ?? []).map((a) => ({ url: a.href, mimeType: a.type })),
  }
}

function googleReader(request: ReturnType<typeof transport>, token: string): Provider {
  const headers = { Authorization: `GoogleLogin auth=${token}` }
  const get = async <T>(path: string) =>
    json<T>(await request(`/reader/api/0/${path}`, { headers }))
  const edit = async (ids: readonly string[], tag: string, value: boolean) => {
    const csrf = (await (await request('/reader/api/0/token', { headers })).text()).trim()
    if (!csrf || csrf.startsWith('<')) throw new ApiError('服务未返回有效的写入令牌')
    for (let offset = 0; offset < ids.length; offset += 100) {
      const body = new URLSearchParams({
        T: csrf,
        [value ? 'a' : 'r']: `user/-/state/com.google/${tag}`,
      })
      ids.slice(offset, offset + 100).forEach((id) => body.append('i', id))
      const response = await request('/reader/api/0/edit-tag', { method: 'POST', headers, body })
      if ((await response.text()).trim() !== 'OK') throw new ApiError('服务没有确认状态写入成功')
    }
  }
  return {
    async authenticate() {
      const data = await get<{ subscriptions: unknown[] }>('subscription/list?output=json')
      if (!Array.isArray(data.subscriptions)) throw new ApiError('服务类型不匹配：未返回订阅列表')
      return ''
    },
    async subscriptions() {
      const { subscriptions } = await get<{
        subscriptions: {
          id: string
          title: string
          htmlUrl?: string
          url?: string
          iconUrl?: string
          categories?: { id: string; label: string }[]
        }[]
      }>('subscription/list?output=json')
      if (!Array.isArray(subscriptions)) throw new ApiError('服务类型不匹配：未返回订阅列表')
      const folders = new Map<string, Folder>()
      const feeds: Feed[] = subscriptions.map((s) => {
        for (const c of s.categories ?? []) folders.set(c.id, { id: c.id, title: c.label })
        return {
          id: s.id,
          title: s.title,
          author: s.title,
          siteUrl: httpUrl(s.htmlUrl ?? ''),
          iconUrl: httpUrl(s.iconUrl ?? ''),
          folderIds: (s.categories ?? []).map((c) => c.id),
          checkedAt: 0,
          parsingErrorCount: 0,
        }
      })
      return { feeds, folders: [...folders.values()] }
    },
    unreadCounts: () =>
      optional(async () => {
        const data = await get<{ unreadcounts?: { id?: unknown; count?: unknown }[] }>(
          'unread-count?output=json',
        )
        if (!Array.isArray(data?.unreadcounts)) return null
        const counts: Record<string, number> = {}
        for (const item of data.unreadcounts) {
          if (typeof item?.id === 'string' && item.id.startsWith('feed/'))
            counts[item.id] = Number(item.count) || 0
        }
        return counts
      }),
    async entries(scope, cursor, limit) {
      const stream = scope.feedId ?? scope.folderId ?? (scope.starred ? STARRED : READING_LIST)
      const params = new URLSearchParams({ output: 'json', n: String(limit) })
      if (scope.unread) params.set('xt', READ)
      if (cursor) params.set('c', cursor)
      const page = await get<{ items: ReaderItem[]; continuation?: string }>(
        `stream/contents/${streamPath(stream)}?${params}`,
      )
      if (!Array.isArray(page.items)) throw new ApiError('服务未返回有效的文章列表')
      const next = page.continuation || null
      if (next && next === cursor) throw new ApiError('服务未正确推进文章分页')
      return { entries: page.items.map(readerEntry), cursor: next }
    },
    setRead: (ids, read) => edit(ids, 'read', read),
    setStarred: (id, starred) => edit([id], 'starred', starred),
  }
}
