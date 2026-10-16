import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { EntryPage, RemoteEntry } from '@album-rss/core'

const mocks = vi.hoisted(() => ({
  authenticate: vi.fn(),
  subscriptions: vi.fn(),
  unreadCounts: vi.fn(),
  entries: vi.fn(),
  setRead: vi.fn(),
  setStarred: vi.fn(),
}))
vi.mock('@album-rss/providers', async (load) => ({
  ...(await load<typeof import('@album-rss/providers')>()),
  createProvider: () => mocks,
}))
vi.mock('../lib/parseEntry', () => ({
  parseEntry: (entry: RemoteEntry) => ({
    ...entry,
    images: [],
    paragraphs: [],
    parseState: 'none',
  }),
}))

function remote(id: string, patch: Partial<RemoteEntry> = {}): RemoteEntry {
  return {
    id,
    feedId: '2',
    title: 'Article',
    author: '',
    url: 'https://example.com/post',
    publishedAt: Number(id),
    content: '',
    enclosures: [],
    tags: [],
    read: false,
    starred: false,
    ...patch,
  }
}
const page = (entries: RemoteEntry[], cursor: string | null = null): EntryPage => ({
  entries,
  cursor,
})
function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: Error) => void
  const promise = new Promise<T>((yes, no) => {
    resolve = yes
    reject = no
  })
  return { promise, resolve, reject }
}
const input = {
  service: 'miniflux' as const,
  server: 'https://example.com/rss/',
  username: '',
  remember: false,
  apiKey: 'token',
  password: 'never-persist-this',
}
const unread = { status: 'unread' as const }

beforeEach(() => {
  vi.resetModules()
  vi.resetAllMocks()
  vi.useFakeTimers()
  const saved = new Map<string, string>()
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => saved.get(key) ?? null,
    setItem: (key: string, value: string) => saved.set(key, value),
    removeItem: (key: string) => saved.delete(key),
  })
  vi.stubGlobal('window', { setTimeout })
  mocks.authenticate.mockResolvedValue('reader')
  mocks.subscriptions.mockResolvedValue({
    feeds: [
      {
        id: '2',
        title: 'Photos',
        author: 'Photos',
        siteUrl: '',
        iconUrl: '',
        folderIds: [],
        checkedAt: 0,
        parsingErrorCount: 0,
      },
    ],
    folders: [],
  })
  mocks.unreadCounts.mockResolvedValue({ 2: 1 })
  mocks.entries.mockImplementation(async () => page([remote('1')]))
  mocks.setRead.mockResolvedValue(undefined)
  mocks.setStarred.mockResolvedValue(undefined)
})
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('endpoints', () => {
  it('adds, edits, switches and removes endpoints while persisting only remembered credentials', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect({ ...input, remember: true, name: 'First' })
    const first = appStore.get().endpoint!
    actions.setRead(['1'], true)
    await actions.connect({ ...input, server: 'https://second.example.com', name: 'Second' })
    const second = appStore.get().endpoint!
    expect(appStore.get().endpoints).toHaveLength(2)
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(JSON.parse(localStorage.getItem('album-rss:endpoints')!)).toHaveLength(1)
    await actions.connect({ ...input, id: second.id, name: 'Edited' })
    expect(appStore.get().endpoints).toHaveLength(2)
    expect(appStore.get().endpoint?.name).toBe('Edited')
    await actions.switchEndpoint(first.id)
    expect(appStore.get().endpoint?.id).toBe(first.id)
    expect(appStore.get().entries['1']?.read).toBe(true)
    expect(appStore.get().viewerSequence).toBeNull()
    await actions.removeEndpoint(second.id)
    expect(appStore.get().endpoints).toHaveLength(1)
    await actions.removeEndpoint(first.id)
    expect(appStore.get().endpoint).toBeNull()
    expect(localStorage.getItem('album-rss:active')).toBeNull()
    expect(JSON.parse(localStorage.getItem('album-rss:endpoints')!)).toEqual([])
  })

  it('reads only subscriptions, counts and the first page when connecting', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    expect(mocks.authenticate).toHaveBeenCalledTimes(1)
    expect(mocks.subscriptions).toHaveBeenCalledTimes(1)
    expect(mocks.unreadCounts).toHaveBeenCalledTimes(1)
    expect(mocks.entries).toHaveBeenCalledTimes(1)
    expect(mocks.entries).toHaveBeenCalledWith(expect.objectContaining({ unread: true }), null, 100)
    expect(appStore.get().order).toEqual(['1'])
    expect(appStore.get().unread).toEqual({ 2: 1 })
  })

  it('switches back to a visited endpoint from its cache without requests', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect({ ...input, name: 'A' })
    const a = appStore.get().endpoint!
    mocks.entries.mockImplementation(async () => page([remote('7')]))
    await actions.connect({ ...input, server: 'https://b.example.com', name: 'B' })
    const b = appStore.get().endpoint!
    vi.clearAllMocks()
    await actions.switchEndpoint(a.id)
    expect(appStore.get().order).toEqual(['1'])
    expect(mocks.entries).not.toHaveBeenCalled()
    expect(mocks.subscriptions).not.toHaveBeenCalled()
    // 缓存放久了：切回时立即显示，同时在后台检查新内容
    vi.setSystemTime(Date.now() + 61_000)
    await actions.switchEndpoint(b.id)
    expect(appStore.get().order).toEqual(['7'])
    await vi.waitFor(() => expect(mocks.subscriptions).toHaveBeenCalledTimes(1))
  })

  it('keeps the active endpoint and pending writes intact when adding another fails', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const original = appStore.get().endpoint
    const writing = deferred<void>()
    mocks.setRead.mockReturnValueOnce(writing.promise)
    actions.setRead(['1'], true)
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(1))
    mocks.entries.mockRejectedValueOnce(new Error('offline'))
    await expect(
      actions.connect({ ...input, server: 'https://offline.example.com' }),
    ).rejects.toThrow('offline')
    expect(appStore.get().endpoint).toBe(original)
    expect(appStore.get().endpoints).toHaveLength(1)
    writing.reject(new Error('write failed'))
    await vi.waitFor(() => expect(appStore.get().entries['1']?.read).toBe(false))
  })

  it('still sends writes after switching and rolls failures back into the cached endpoint', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect({ ...input, name: 'A' })
    const a = appStore.get().endpoint!
    const writing = deferred<void>()
    mocks.setRead.mockReturnValueOnce(writing.promise)
    actions.setRead(['1'], true)
    expect(appStore.get().unread).toEqual({ 2: 0 })
    await actions.connect({ ...input, server: 'https://b.example.com', name: 'B' })
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledWith(['1'], true))
    writing.reject(new Error('write failed'))
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(1))
    await Promise.resolve()
    expect(appStore.get().entries['1']?.read).toBe(false)
    await actions.switchEndpoint(a.id)
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(appStore.get().unread).toEqual({ 2: 1 })
  })

  it('switches to the next endpoint when the active one is removed', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect({ ...input, name: 'A' })
    const a = appStore.get().endpoint!
    await actions.connect({ ...input, server: 'https://b.example.com', name: 'B' })
    const b = appStore.get().endpoint!
    await actions.removeEndpoint(b.id)
    expect(appStore.get().endpoint?.id).toBe(a.id)
    expect(appStore.get().endpoints.map((endpoint) => endpoint.id)).toEqual([a.id])
  })

  it('migrates a remembered legacy connection and restores multiple endpoints on reload', async () => {
    localStorage.setItem(
      'album-rss:session',
      JSON.stringify({ kind: 'connected', ...input, token: input.apiKey, remember: true }),
    )
    const { actions, appStore } = await import('./store')
    const firstId = appStore.get().endpoint?.id
    expect(firstId).toBeTruthy()
    expect(localStorage.getItem('album-rss:session')).toBeNull()
    await actions.connect({ ...input, remember: true, server: 'https://second.example.com' })
    vi.resetModules()
    const restored = await import('./store')
    expect(restored.appStore.get().endpoints).toHaveLength(2)
    expect(restored.appStore.get().endpoints[0]?.id).toBe(firstId)
    expect(restored.appStore.get().endpoint?.server).toBe('https://second.example.com')
    expect(restored.appStore.get().loaded).toBe(false)
  })

  it('persists only the explicitly remembered token and never the password', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    expect(JSON.parse(localStorage.getItem('album-rss:endpoints')!)).toEqual([])
    await actions.connect({ ...input, remember: true })
    const saved = localStorage.getItem('album-rss:endpoints')!
    expect(JSON.parse(saved)[0]).toMatchObject({
      token: 'token',
      server: 'https://example.com/rss',
      username: 'reader',
    })
    expect(saved).not.toContain(input.password)
    vi.resetModules()
    const restored = await import('./store')
    expect(restored.appStore.get().endpoints).toHaveLength(1)
    await restored.actions.removeEndpoint(appStore.get().endpoint!.id)
    expect(restored.appStore.get().endpoint).toBeNull()
    restored.actions.enterDemo()
    expect(restored.appStore.get().order.length).toBeGreaterThan(1)
  })

  it('does not establish an endpoint after a failed initial read', async () => {
    const { actions, appStore } = await import('./store')
    mocks.entries.mockRejectedValueOnce(new Error('offline'))
    await expect(actions.connect(input)).rejects.toThrow('offline')
    expect(appStore.get().endpoint).toBeNull()
    expect(localStorage.getItem('album-rss:active')).toBeNull()
  })
})

describe('lists', () => {
  it('reads older pages only when a list asks for them', async () => {
    const { actions, appStore, scopeKey } = await import('./store')
    mocks.entries.mockResolvedValueOnce(page([remote('3'), remote('2')], '2'))
    await actions.connect(input)
    expect(appStore.get().scopes[scopeKey(unread)]).toMatchObject({ ids: ['3', '2'], done: false })
    mocks.entries.mockResolvedValueOnce(page([remote('1')]))
    await actions.loadMore(unread)
    expect(mocks.entries).toHaveBeenLastCalledWith(
      expect.objectContaining({ unread: true }),
      '2',
      100,
    )
    expect(appStore.get().scopes[scopeKey(unread)]).toMatchObject({
      ids: ['3', '2', '1'],
      done: true,
    })
    await actions.loadMore(unread)
    expect(mocks.entries).toHaveBeenCalledTimes(2)
    await actions.loadMore({ status: 'all', feedId: '2' })
    expect(mocks.entries).toHaveBeenLastCalledWith(
      expect.objectContaining({ feedId: '2', unread: undefined }),
      null,
      100,
    )
  })

  it('drops a page that arrives after the list was refreshed', async () => {
    const { actions, appStore, scopeKey } = await import('./store')
    mocks.entries.mockResolvedValueOnce(page([remote('3')], '3'))
    await actions.connect(input)
    const older = deferred<EntryPage>()
    mocks.entries.mockReturnValueOnce(older.promise)
    const loading = actions.loadMore(unread)
    mocks.entries.mockResolvedValueOnce(page([remote('4'), remote('3')], '3'))
    await actions.sync({ explicit: true })
    older.resolve(page([remote('2')]))
    await loading
    expect(appStore.get().scopes[scopeKey(unread)]?.ids).toEqual(['4', '3'])
  })

  it('counts new articles in the background until they are applied', async () => {
    const { actions, appStore, scopeKey } = await import('./store')
    await actions.connect(input)
    mocks.entries.mockResolvedValueOnce(page([remote('9'), remote('1')]))
    await actions.sync({ explicit: false })
    expect(appStore.get().sync.pendingIds).toEqual(['9'])
    expect(appStore.get().scopes[scopeKey(unread)]?.ids).toEqual(['1'])
    actions.applyPending()
    expect(appStore.get().sync.pendingIds).toEqual([])
    expect(appStore.get().scopes[scopeKey(unread)]?.ids).toEqual(['9', '1'])
  })

  it('marks every unread article of a feed, including unloaded ones, with undo', async () => {
    const { actions, appStore } = await import('./store')
    const { toastStore } = await import('../components/ui/toast')
    mocks.unreadCounts.mockResolvedValue({ 2: 3 })
    await actions.connect(input)
    mocks.entries
      .mockResolvedValueOnce(page([remote('1'), remote('5')], '5'))
      .mockResolvedValueOnce(page([remote('6')]))
    await actions.markFeedRead(appStore.get().feeds[0]!)
    expect(mocks.entries).toHaveBeenCalledWith({ feedId: '2', unread: true }, '5', 500)
    expect(appStore.get().unread).toEqual({ 2: 0 })
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledWith(['1', '5', '6'], true))
    toastStore.get().at(-1)?.action?.run()
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledWith(['1', '5', '6'], false))
    expect(appStore.get().unread).toEqual({ 2: 3 })
  })
})

describe('sync', () => {
  it('ignores a previous endpoint response even when both services use the same article IDs', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const reading = deferred<EntryPage>()
    mocks.entries.mockReturnValueOnce(reading.promise)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.entries).toHaveBeenCalledTimes(2))
    await actions.connect({ ...input, server: 'https://second.example.com' })
    reading.resolve(page([remote('1', { read: true })]))
    await syncing
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(appStore.get().sync.status).toBe('idle')
  })

  it('serializes rapid writes and rolls back consecutive failures to confirmed state', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const first = deferred<void>()
    const second = deferred<void>()
    mocks.setRead.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise)
    actions.setRead(['1'], true)
    actions.setRead(['1'], false)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(1))
    first.reject(new Error('offline'))
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(2))
    second.reject(new Error('offline'))
    mocks.entries.mockImplementationOnce(async () => {
      expect(appStore.get().entries['1']?.read).toBe(false)
      return page([remote('1')])
    })
    await syncing
    expect(appStore.get().entries['1']?.read).toBe(false)
  })

  it('keeps a local change made while a sync is in flight', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const reading = deferred<EntryPage>()
    mocks.entries.mockReturnValueOnce(reading.promise)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.entries).toHaveBeenCalledTimes(2))
    actions.setStarred('1', true)
    await vi.waitFor(() => expect(mocks.setStarred).toHaveBeenCalledTimes(1))
    reading.resolve(page([remote('1')]))
    await syncing
    expect(appStore.get().entries['1']?.starred).toBe(true)
  })

  it('ignores stale sync responses after the endpoint is removed', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const reading = deferred<EntryPage>()
    mocks.entries.mockReturnValueOnce(reading.promise)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.entries).toHaveBeenCalledTimes(2))
    await actions.removeEndpoint(appStore.get().endpoint!.id)
    reading.resolve(page([remote('8')]))
    await syncing
    expect(appStore.get().endpoint).toBeNull()
    expect(appStore.get().entries['8']).toBeUndefined()
  })

  it('retains earlier data when sync fails and clears the error on retry', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    mocks.entries.mockRejectedValueOnce(new Error('offline'))
    await actions.sync({ explicit: true })
    expect(appStore.get().order).toEqual(['1'])
    expect(appStore.get().sync.error).toBe('offline')
    await actions.sync({ explicit: true })
    expect(appStore.get().sync.error).toBeUndefined()
  })

  it('does not mix a pending demo sync into a newly connected endpoint', async () => {
    const { actions, appStore } = await import('./store')
    actions.enterDemo()
    const syncing = actions.sync({ explicit: true })
    await actions.connect(input)
    await vi.advanceTimersByTimeAsync(1000)
    await syncing
    expect(appStore.get().order).toEqual(['1'])
    expect(appStore.get().endpoint?.kind).toBe('connected')
  })
})

describe('download read setting', () => {
  async function setup() {
    const store = await import('./store')
    await store.actions.connect(input)
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockImplementation(async () => new Response(new Blob(['image'], { type: 'image/png' }))),
    )
    vi.stubGlobal('document', { createElement: () => ({ click: vi.fn() }) })
    return {
      ...store,
      entry: store.appStore.get().entries['1']!,
      images: [{ key: 'image', url: 'https://example.com/image.png' }],
    }
  }

  it('defaults to marking successful downloads read and writes the state to the provider', async () => {
    const { actions, appStore, entry, images } = await setup()
    expect(appStore.get().settings.downloadRead).toBe(true)
    await actions.download('download', entry, images)
    expect(appStore.get().entries['1']?.read).toBe(true)
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledWith(['1'], true))
  })

  it('excludes videos from image downloads and does not mark video-only requests read', async () => {
    const { actions, appStore, entry, images } = await setup()
    const video = { key: 'video', url: 'https://example.com/video.mp4', kind: 'video' as const }
    await actions.download('video', entry, [video])
    expect(fetch).not.toHaveBeenCalled()
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(appStore.get().downloads.video).toBeUndefined()
    await actions.download('mixed', entry, [...images, video])
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(appStore.get().downloads.mixed).toMatchObject({ total: 1, done: 1 })
  })

  it('persists the disabled preference and leaves successful downloads unread', async () => {
    const { actions, appStore, entry, images } = await setup()
    actions.updateSettings({ downloadRead: false })
    await actions.download('download', entry, images)
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(mocks.setRead).not.toHaveBeenCalled()
    expect(JSON.parse(localStorage.getItem('album-rss:settings')!).downloadRead).toBe(false)
  })

  it('leaves partial, failed and empty downloads unread', async () => {
    const { actions, appStore, entry, images } = await setup()
    vi.mocked(fetch).mockRejectedValueOnce(new Error('offline'))
    await actions.download('failed', entry, images)
    expect(appStore.get().downloads.failed?.status).toBe('blocked')
    vi.mocked(fetch)
      .mockResolvedValueOnce(new Response(new Blob(['image'], { type: 'image/png' })))
      .mockRejectedValueOnce(new Error('offline'))
    await actions.download('partial', entry, [...images, ...images])
    expect(appStore.get().downloads.partial).toMatchObject({ status: 'blocked', done: 1 })
    await actions.download('empty', entry, [])
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(mocks.setRead).not.toHaveBeenCalled()
  })

  it('does not mark the new endpoint read when an old download finishes', async () => {
    const { actions, appStore, entry, images } = await setup()
    const response = deferred<Response>()
    vi.mocked(fetch).mockReturnValueOnce(response.promise)
    const downloading = actions.download('old', entry, images)
    await actions.connect({ ...input, server: 'https://second.example.com' })
    response.resolve(new Response(new Blob(['image'], { type: 'image/png' })))
    await downloading
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(appStore.get().downloads).toEqual({})
    expect(mocks.setRead).not.toHaveBeenCalled()
  })
})
