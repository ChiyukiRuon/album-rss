import { CORE_PACKAGE, httpUrl } from '@album-rss/core'
import type { Feed, Folder, RemoteEntry, ServiceKind, Snapshot } from '@album-rss/core'

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

export interface ProviderOptions {
  service: ServiceKind
  server: string
  token: string
  fetch?: typeof fetch
}

export interface Provider {
  authenticate(): Promise<string>
  snapshot(): Promise<Snapshot>
  setRead(ids: readonly string[], read: boolean): Promise<void>
  setStarred(id: string, starred: boolean): Promise<void>
  refreshFeed?: (id: string) => Promise<void>
}

function transport(server: string, fetcher: typeof fetch = fetch) {
  return async (path: string, init: RequestInit = {}) => {
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
    if (!response.ok) {
      throw new ApiError(
        response.status === 401 || response.status === 403
          ? '登录信息无效或已过期，请重新连接服务'
          : `服务返回 HTTP ${response.status}，请稍后重试`,
        response.status,
      )
    }
    return response
  }
}

async function json<T>(response: Response): Promise<T> {
  try {
    return (await response.json()) as T
  } catch {
    throw new ApiError('服务没有返回有效的 JSON 数据，请检查服务类型和 API 地址')
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
  if (!Number.isSafeInteger(value) || value <= 0) throw new ApiError('服务返回了不支持的文章 ID')
  return value
}

export function createProvider(options: ProviderOptions): Provider {
  const request = transport(normalizeServer(options.server), options.fetch)
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
        throw new ApiError('服务类型不匹配：未返回 Miniflux 账号')
      return me.username
    },
    async snapshot() {
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
      const entries = new Map<string, RemoteEntry>()
      // 使用 ID 游标，避免分页期间的新文章导致 offset 偏移。
      let before = ''
      for (;;) {
        const params = new URLSearchParams({ limit: '100', order: 'id', direction: 'desc' })
        params.append('status', 'read')
        params.append('status', 'unread')
        if (before) params.set('before_entry_id', before)
        const page = await get<{ entries: MinifluxEntry[] | null }>(`/v1/entries?${params}`)
        const items = page.entries ?? []
        if (!items.length) break
        for (const e of items) {
          const id = String(numericId(String(e.id)))
          entries.set(id, {
            id,
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
          })
        }
        const next = String(Math.min(...items.map((e) => numericId(String(e.id)))))
        if (before && BigInt(next) >= BigInt(before)) throw new ApiError('服务未正确推进文章分页')
        before = next
      }
      return {
        feeds,
        folders: categories.map((c) => ({ id: String(c.id), title: c.title })),
        entries: [...entries.values()],
      }
    },
    async setRead(ids, read) {
      for (let offset = 0; offset < ids.length; offset += 100) {
        await put('/v1/entries', {
          entry_ids: ids.slice(offset, offset + 100).map(numericId),
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
    async snapshot() {
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
      const entries = new Map<string, RemoteEntry>()
      const readStream = async (stream: string) => {
        let cursor = ''
        const seen = new Set<string>()
        for (;;) {
          const params = new URLSearchParams({ output: 'json', n: '100' })
          if (cursor) params.set('c', cursor)
          const page = await get<{ items: ReaderItem[]; continuation?: string }>(
            `stream/contents/${stream}?${params}`,
          )
          if (!Array.isArray(page.items)) throw new ApiError('服务未返回有效的文章列表')
          for (const e of page.items) {
            if (typeof e.id !== 'string') throw new ApiError('服务返回了不安全的 Google Reader ID')
            const categories = e.categories ?? []
            entries.set(e.id, {
              id: e.id,
              feedId: e.origin?.streamId ?? '',
              title: e.title ?? '',
              author: e.author ?? '',
              url: httpUrl(e.canonical?.[0]?.href ?? e.alternate?.[0]?.href ?? ''),
              publishedAt: (e.published ?? 0) * 1000,
              content: e.content?.content ?? e.summary?.content ?? '',
              tags: categories
                .filter((c) => c.includes('/label/'))
                .map((c) => c.split('/label/')[1] ?? c),
              read: categories.some((c) => c.endsWith('/state/com.google/read')),
              starred: categories.some((c) => c.endsWith('/state/com.google/starred')),
              enclosures: (e.enclosure ?? []).map((a) => ({ url: a.href, mimeType: a.type })),
            })
          }
          if (!page.continuation) break
          if (seen.has(page.continuation)) throw new ApiError('服务未正确推进文章分页')
          cursor = page.continuation
          seen.add(cursor)
        }
      }
      await readStream('user/-/state/com.google/reading-list')
      await readStream('user/-/state/com.google/starred')
      return { feeds, folders: [...folders.values()], entries: [...entries.values()] }
    },
    setRead: (ids, read) => edit(ids, 'read', read),
    setStarred: (id, starred) => edit([id], 'starred', starred),
  }
}
