import { afterEach, describe, expect, it, vi } from 'vitest'
import { ApiError, createGate, createProvider, loginGoogleReader, normalizeServer } from './index'

const response = (value: unknown, init?: ResponseInit) =>
  new Response(JSON.stringify(value), {
    ...init,
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  })
const entry = (id: number) => ({
  id,
  feed_id: 1,
  title: 'Album',
  author: 'Artist',
  url: 'https://example.com/post',
  content: '<img src="/cover.jpg">',
  published_at: '2026-10-15T00:00:00Z',
  status: 'unread',
  starred: false,
})
// 测试里不等待请求间隔
const gate = () => createGate({ interval: 0 })

afterEach(() => {
  vi.useRealTimers()
})

describe('Miniflux', () => {
  it('preserves subpaths and pages one scope at a time with an ID cursor', async () => {
    const calls: URL[] = []
    const fetcher = vi.fn<typeof fetch>(async (url, init) => {
      const path = new URL(String(url))
      calls.push(path)
      expect(init?.credentials).toBe('omit')
      expect(init?.redirect).toBe('error')
      expect(init?.headers).toMatchObject({ 'X-Auth-Token': 'secret' })
      if (path.pathname.endsWith('/me')) return response({ username: 'reader' })
      if (path.pathname.endsWith('/feeds'))
        return response([
          { id: 1, title: 'Photos', site_url: 'https://example.com', category: { id: 2 } },
        ])
      if (path.pathname.endsWith('/categories')) return response([{ id: 2, title: 'Art' }])
      const before = path.searchParams.get('before_entry_id')
      return response({
        entries: before === null ? [entry(3), entry(2)] : before === '2' ? [entry(1)] : [],
      })
    })
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://rss.example.com/rss/',
      token: 'secret',
      fetch: fetcher,
      gate: gate(),
    })
    expect(await provider.authenticate()).toBe('reader')
    const { feeds, folders } = await provider.subscriptions()
    expect(feeds[0]?.folderIds).toEqual(['2'])
    expect(folders).toEqual([{ id: '2', title: 'Art' }])
    const first = await provider.entries({}, null, 2)
    expect(first.entries.map((e) => e.id)).toEqual(['3', '2'])
    expect(first.cursor).toBe('2')
    const last = await provider.entries({}, first.cursor, 2)
    expect(last).toMatchObject({ entries: [{ id: '1' }], cursor: null })
    const pages = calls.filter((url) => url.pathname.endsWith('/v1/entries'))
    expect(pages).toHaveLength(2)
    expect(pages[0]?.searchParams.getAll('status')).toEqual(['read', 'unread'])
    expect(pages[0]?.searchParams.get('limit')).toBe('2')
    expect(calls.every((url) => url.href.startsWith('https://rss.example.com/rss/v1/'))).toBe(true)
  })

  it('maps scopes to the feed, category, unread and starred queries', async () => {
    const calls: URL[] = []
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      gate: gate(),
      fetch: async (url) => {
        calls.push(new URL(String(url)))
        return response({ entries: [] })
      },
    })
    await provider.entries({ feedId: '7', unread: true }, null, 100)
    await provider.entries({ folderId: '3' }, '50', 100)
    await provider.entries({ starred: true }, null, 100)
    expect(calls.map((url) => url.pathname)).toEqual([
      '/v1/feeds/7/entries',
      '/v1/categories/3/entries',
      '/v1/entries',
    ])
    expect(calls[0]?.searchParams.getAll('status')).toEqual(['unread'])
    expect(calls[1]?.searchParams.get('before_entry_id')).toBe('50')
    expect(calls[2]?.searchParams.get('starred')).toBe('true')
  })

  it('reads unread counters and treats a missing counter endpoint as unsupported', async () => {
    const provider = (status: number) =>
      createProvider({
        service: 'miniflux',
        server: 'https://example.com',
        token: 'secret',
        gate: gate(),
        fetch: async () =>
          status === 200
            ? response({ reads: { 1: 4 }, unreads: { 1: 2, 5: 9 } })
            : new Response('', { status }),
      })
    expect(await provider(200).unreadCounts()).toEqual({ 1: 2, 5: 9 })
    expect(await provider(404).unreadCounts()).toBeNull()
    await expect(provider(401).unreadCounts()).rejects.toMatchObject({ status: 401 })
  })

  it('writes read state to the bulk endpoint and makes bookmarking idempotent', async () => {
    let starred = false
    const writes: { url: string; body: unknown }[] = []
    const fetcher = vi.fn<typeof fetch>(async (url, init) => {
      if (init?.method === 'PUT') {
        writes.push({ url: String(url), body: init.body ? JSON.parse(String(init.body)) : null })
        if (String(url).endsWith('/bookmark')) starred = !starred
        return new Response(null, { status: 204 })
      }
      return response({ ...entry(1), starred })
    })
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      fetch: fetcher,
      gate: gate(),
    })
    await provider.setRead(['1', '2'], true)
    await provider.setStarred('1', true)
    await provider.setStarred('1', true)
    expect(writes).toEqual([
      { url: 'https://example.com/v1/entries', body: { entry_ids: [1, 2], status: 'read' } },
      { url: 'https://example.com/v1/entries/1/bookmark', body: null },
    ])
  })

  it('reports HTTP authentication errors without exposing response bodies', async () => {
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      gate: gate(),
      fetch: async () => new Response('private data', { status: 401 }),
    })
    const error = await provider.authenticate().catch((e: unknown) => e)
    expect(error).toMatchObject({ status: 401 })
    expect(String((error as Error).message)).not.toContain('private data')
  })

  it('stops if the service repeats a page', async () => {
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      gate: gate(),
      fetch: async () => response({ entries: [entry(2), entry(1)] }),
    })
    const first = await provider.entries({}, null, 2)
    await expect(provider.entries({}, first.cursor, 2)).rejects.toThrow('分页')
  })
})

describe('rate limiting', () => {
  it('backs off on 429 using Retry-After and pauses the whole queue', async () => {
    vi.useFakeTimers()
    let calls = 0
    const started: number[] = []
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      gate: gate(),
      fetch: async (url) => {
        started.push(Date.now())
        if (String(url).endsWith('/me') && calls++ === 0)
          return new Response('', { status: 429, headers: { 'Retry-After': '2' } })
        return response(String(url).endsWith('/me') ? { username: 'reader' } : [])
      },
    })
    const auth = provider.authenticate()
    await vi.advanceTimersByTimeAsync(0)
    const feeds = provider.subscriptions()
    await vi.advanceTimersByTimeAsync(1999)
    expect(started).toHaveLength(1)
    await vi.advanceTimersByTimeAsync(1)
    expect(await auth).toBe('reader')
    await feeds
    expect(started.slice(1).every((time) => time - started[0]! >= 2000)).toBe(true)
  })

  it('gives up with a clear message when the service asks to wait too long', async () => {
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      gate: gate(),
      fetch: async () => new Response('', { status: 429, headers: { 'Retry-After': '120' } }),
    })
    await expect(provider.authenticate()).rejects.toThrow('约 120 秒后')
  })

  it('limits concurrency and spaces out request starts', async () => {
    vi.useFakeTimers()
    const limited = createGate({ concurrency: 2, interval: 100 })
    const starts: number[] = []
    let active = 0
    let peak = 0
    const task = () =>
      limited.run(async () => {
        starts.push(Date.now())
        peak = Math.max(peak, ++active)
        await new Promise((resolve) => setTimeout(resolve, 500))
        active--
      })
    const all = Promise.all([task(), task(), task(), task()])
    await vi.advanceTimersByTimeAsync(5000)
    await all
    expect(peak).toBe(2)
    starts.forEach((time, i) => i > 0 && expect(time - starts[i - 1]!).toBeGreaterThanOrEqual(100))
  })
})

describe('Google Reader', () => {
  it('exchanges a password for a token using form encoding', async () => {
    const fetcher = vi.fn<typeof fetch>(async (url, init) => {
      expect(String(url)).toBe('https://example.com/api/greader.php/accounts/ClientLogin')
      expect(String(init?.body)).toBe('Email=user&Passwd=p%26ss')
      return new Response('SID=x\nAuth=access-token\n')
    })
    expect(
      await loginGoogleReader('https://example.com/api/greader.php/', 'user', 'p&ss', fetcher),
    ).toBe('access-token')
  })

  it('preserves 64-bit string IDs and follows continuation cursors', async () => {
    const id = 'tag:google.com,2005:reader/item/ffffffffffffffff'
    const provider = createProvider({
      service: 'greader',
      server: 'https://example.com',
      token: 'token',
      gate: gate(),
      fetch: async (url) => {
        const path = new URL(String(url))
        if (path.searchParams.get('c')) return response({ items: [] })
        return response({
          continuation: 'next+/=',
          items: [
            {
              id,
              origin: { streamId: 'feed/1' },
              categories: ['user/1/state/com.google/starred'],
              summary: { content: '<p>Photo</p>' },
            },
          ],
        })
      },
    })
    const first = await provider.entries({}, null, 100)
    expect(first.entries[0]).toMatchObject({ id, feedId: 'feed/1', starred: true })
    expect(first.cursor).toBe('next+/=')
    expect(await provider.entries({}, first.cursor, 100)).toEqual({ entries: [], cursor: null })
  })

  it('reads feeds, labels, starred and unread items from their own streams', async () => {
    const calls: URL[] = []
    const provider = createProvider({
      service: 'greader',
      server: 'https://example.com/api/greader.php',
      token: 'token',
      gate: gate(),
      fetch: async (url) => {
        calls.push(new URL(String(url)))
        return response({ items: [] })
      },
    })
    await provider.entries({ feedId: 'feed/1', unread: true }, null, 50)
    await provider.entries({ folderId: 'user/-/label/插画 Art' }, 'c1', 50)
    await provider.entries({ starred: true }, null, 50)
    expect(calls.map((url) => decodeURIComponent(url.pathname))).toEqual([
      '/api/greader.php/reader/api/0/stream/contents/feed/1',
      '/api/greader.php/reader/api/0/stream/contents/user/-/label/插画 Art',
      '/api/greader.php/reader/api/0/stream/contents/user/-/state/com.google/starred',
    ])
    expect(calls[0]?.searchParams.get('xt')).toBe('user/-/state/com.google/read')
    expect(calls[1]?.searchParams.get('c')).toBe('c1')
    expect(calls[2]?.searchParams.get('n')).toBe('50')
  })

  it('reads per-feed unread counts and tolerates services without them', async () => {
    const provider = (body: unknown, status = 200) =>
      createProvider({
        service: 'greader',
        server: 'https://example.com',
        token: 'token',
        gate: gate(),
        fetch: async () => (status === 200 ? response(body) : new Response('', { status })),
      })
    expect(
      await provider({
        unreadcounts: [
          { id: 'feed/1', count: 3 },
          { id: 'user/-/label/Art', count: 3 },
          { id: 'user/-/state/com.google/reading-list', count: 3 },
        ],
      }).unreadCounts(),
    ).toEqual({ 'feed/1': 3 })
    expect(await provider(null, 404).unreadCounts()).toBeNull()
  })

  it('uses desired state tags with a fresh write token', async () => {
    const fetcher = vi.fn<typeof fetch>(async (url, init) => {
      if (String(url).endsWith('/token')) return new Response('csrf')
      const body = new URLSearchParams(String(init?.body))
      expect(body.get('T')).toBe('csrf')
      expect(body.get('r')).toBe('user/-/state/com.google/starred')
      expect(body.get('i')).toBe('tag:google.com,2005:reader/item/ffffffffffffffff')
      return new Response('OK')
    })
    await createProvider({
      service: 'greader',
      server: 'https://example.com',
      token: 'token',
      fetch: fetcher,
      gate: gate(),
    }).setStarred('tag:google.com,2005:reader/item/ffffffffffffffff', false)
  })
})

describe('server addresses', () => {
  it('rejects embedded credentials and unsafe schemes', () => {
    expect(() => normalizeServer('https://user:password@example.com')).toThrow(ApiError)
    expect(() => normalizeServer('javascript:alert(1)')).toThrow(ApiError)
    expect(normalizeServer('https://example.com/rss/?q=1#hash')).toBe('https://example.com/rss')
  })
})
