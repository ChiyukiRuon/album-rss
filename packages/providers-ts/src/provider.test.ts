import { describe, expect, it, vi } from 'vitest'
import { ApiError, createProvider, loginGoogleReader, normalizeServer } from './index'

const response = (value: unknown) =>
  new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } })
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

describe('Miniflux', () => {
  it('preserves subpaths and paginates past the first hundred articles', async () => {
    const calls: string[] = []
    const fetcher = vi.fn<typeof fetch>(async (url, init) => {
      calls.push(String(url))
      expect(init?.credentials).toBe('omit')
      expect(init?.redirect).toBe('error')
      expect(init?.headers).toMatchObject({ 'X-Auth-Token': 'secret' })
      const path = new URL(String(url))
      if (path.pathname.endsWith('/me')) return response({ username: 'reader' })
      if (path.pathname.endsWith('/feeds'))
        return response([
          { id: 1, title: 'Photos', site_url: 'https://example.com', category: { id: 2 } },
        ])
      if (path.pathname.endsWith('/categories')) return response([{ id: 2, title: 'Art' }])
      expect(path.searchParams.getAll('status')).toEqual(['read', 'unread'])
      const before = path.searchParams.get('before_entry_id')
      return response({
        entries:
          before === null
            ? Array.from({ length: 100 }, (_, i) => entry(101 - i))
            : before === '2'
              ? [entry(1)]
              : [],
      })
    })
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://rss.example.com/rss/',
      token: 'secret',
      fetch: fetcher,
    })
    expect(await provider.authenticate()).toBe('reader')
    const snapshot = await provider.snapshot()
    expect(snapshot.entries).toHaveLength(101)
    expect(snapshot.entries.at(-1)?.id).toBe('1')
    expect(snapshot.feeds[0]?.folderIds).toEqual(['2'])
    expect(snapshot.folders).toEqual([{ id: '2', title: 'Art' }])
    expect(calls.every((url) => url.startsWith('https://rss.example.com/rss/v1/'))).toBe(true)
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
      fetch: async () => new Response('private data', { status: 401 }),
    })
    await expect(provider.authenticate()).rejects.toMatchObject({ status: 401 })
  })

  it('stops if the service repeats a page', async () => {
    const provider = createProvider({
      service: 'miniflux',
      server: 'https://example.com',
      token: 'secret',
      fetch: async (url) =>
        response(
          String(url).includes('/feeds') || String(url).includes('/categories')
            ? []
            : { entries: [entry(1)] },
        ),
    })
    await expect(provider.snapshot()).rejects.toThrow('分页')
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

  it('preserves 64-bit string IDs, continuation cursors and old starred articles', async () => {
    const id = 'tag:google.com,2005:reader/item/ffffffffffffffff'
    const fetcher = vi.fn<typeof fetch>(async (url) => {
      const path = new URL(String(url))
      if (path.pathname.includes('/subscription/list'))
        return response({
          subscriptions: [
            {
              id: 'feed/1',
              title: 'Photos',
              categories: [{ id: 'user/1/label/art', label: 'Art' }],
            },
          ],
        })
      const starred = path.pathname.endsWith('/starred')
      if (path.searchParams.get('c')) return response({ items: [] })
      return response({
        continuation: 'next+/=',
        items: [
          {
            id: starred ? 'old-starred' : id,
            origin: { streamId: 'feed/1' },
            categories: starred ? ['user/1/state/com.google/starred'] : [],
            summary: { content: '<p>Photo</p>' },
          },
        ],
      })
    })
    const provider = createProvider({
      service: 'greader',
      server: 'https://example.com',
      token: 'token',
      fetch: fetcher,
    })
    const snapshot = await provider.snapshot()
    expect(snapshot.entries.map((e) => e.id)).toEqual([id, 'old-starred'])
    expect(snapshot.entries[1]?.starred).toBe(true)
    expect(snapshot.folders).toEqual([{ id: 'user/1/label/art', title: 'Art' }])
    expect(
      fetcher.mock.calls.some(([url]) => new URL(String(url)).searchParams.get('c') === 'next+/='),
    ).toBe(true)
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
